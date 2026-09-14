#import "NSPQuickerService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"

// Quicker (getquicker.net) push service, V2 long-connection API:
//   POST https://push.getquicker.cn/to/quicker
//   JSON body: { toUser (account email), code (push verification code),
//                toDevice (optional), operation (default "paste"),
//                action (optional), data (content template),
//                wait / maxWaitMs / txt (optional) }
//
// The `data` field is a template rendered from the notification:
//   [title] [sub] [msg] [date] [app] [appid] [device] [key]
// Placeholders are substituted with the raw notification values; the whole
// payload is then serialized with NSJSONSerialization, which escapes quotes,
// backslashes, newlines and any nested-JSON-looking content correctly for the
// JSON body, so templates may embed JSON text safely.
@implementation NSPQuickerService

+ (void)load {
  [NSPushServiceManager registerServiceClass:self forName:[self serviceName]];
}

+ (NSString*)serviceName {
  return PUSHER_SERVICE_QUICKER;
}

+ (NSString*)urlForEventName:(NSString*)eventName
                      dbName:(NSString*)dbName
                   serverURL:(NSString*)serverURL {
  return PUSHER_SERVICE_QUICKER_URL;
}

+ (NSDictionary*)extraPrefsForName:(NSString*)name
                      servicePrefs:(NSDictionary*)servicePrefs {
  return @{
    @"toUser" : XStrDefault(servicePrefs[@"toUser"], @""),
    @"code" : XStrDefault(servicePrefs[@"code"], @""),
    @"toDevice" : XStrDefault(servicePrefs[@"toDevice"], @""),
    @"operation" : XStrDefault(servicePrefs[@"operation"], @"paste"),
    @"action" : XStrDefault(servicePrefs[@"action"], @""),
    @"data" : XStrDefault(servicePrefs[@"data"], @"[title]\n[msg]"),
    @"wait" : servicePrefs[@"wait"] ?: @NO,
    @"maxWaitMs" : XStrDefault(servicePrefs[@"maxWaitMs"], @""),
    @"txt" : servicePrefs[@"txt"] ?: @NO
  };
}

// Substitute the notification placeholders with their raw values. Escaping is
// left to NSJSONSerialization (see the class comment), so raw values can
// contain quotes / newlines / JSON text without breaking the request body.
+ (NSString*)renderedDataTemplate:(NSString*)templateString
                          context:(NSPBulletinContext*)context
                           config:(NSPushServiceConfig*)config {
  NSDictionary* infoDict =
      [self baseInfoDictForBulletinContext:context config:config];
  NSDictionary* placeholders = @{
    @"[title]" : infoDict[@"title"] ?: @"",
    @"[sub]" : infoDict[@"subtitle"] ?: @"",
    @"[msg]" : infoDict[@"message"] ?: @"",
    @"[date]" : infoDict[@"date"] ?: @"",
    @"[app]" : infoDict[@"appName"] ?: @"",
    @"[appid]" : infoDict[@"appID"] ?: @"",
    @"[device]" : infoDict[@"deviceName"] ?: @"",
    @"[key]" : XStrDefault(config.rawPrefs[@"key"], @"")
  };
  NSString* result = templateString;
  for (NSString* placeholder in placeholders) {
    id value = placeholders[placeholder];
    NSString* string = @"";
    if ([value isKindOfClass:NSString.class]) {
      string = (NSString*)value;
    } else if ([value isKindOfClass:NSNumber.class]) {
      string = [(NSNumber*)value stringValue];
    } else if (value) {
      string = [value description];
    }
    result = [result stringByReplacingOccurrencesOfString:placeholder
                                                withString:string];
  }
  return result;
}

+ (NSPushRequest*)requestForBulletinContext:(NSPBulletinContext*)context
                                     config:(NSPushServiceConfig*)config {
  NSString* toUser = XStrDefault(config.rawPrefs[@"toUser"], @"");
  NSString* code = XStrDefault(config.rawPrefs[@"code"], @"");
  // Missing account email or push code: the push can never succeed. Abort the
  // same way ServerChan does for a missing send key; callers treat nil as
  // "failed to build request".
  if (toUser.length == 0 || code.length == 0) {
    return nil;
  }

  NSString* dataTemplate =
      XStrDefault(config.rawPrefs[@"data"], @"[title]\n[msg]");
  if (dataTemplate.length == 0) {
    dataTemplate = @"[title]\n[msg]";
  }
  NSString* data = [self renderedDataTemplate:dataTemplate
                                      context:context
                                       config:config];

  NSMutableDictionary* payload = [@{
    @"toUser" : toUser,
    @"code" : code,
    @"operation" : XStrDefault(config.rawPrefs[@"operation"], @"paste"),
    @"data" : data
  } mutableCopy];
  NSString* toDevice = XStrDefault(config.rawPrefs[@"toDevice"], @"");
  if (toDevice.length > 0) {
    payload[@"toDevice"] = toDevice;
  }
  NSString* action = XStrDefault(config.rawPrefs[@"action"], @"");
  if (action.length > 0) {
    payload[@"action"] = action;
  }
  // wait / maxWaitMs / txt are documented but optional; only send them when
  // actually configured to keep the payload minimal.
  if (NSPushBoolValue(config.rawPrefs[@"wait"])) {
    payload[@"wait"] = @YES;
    NSString* maxWaitMs = XStrDefault(config.rawPrefs[@"maxWaitMs"], @"");
    if (maxWaitMs.length > 0) {
      payload[@"maxWaitMs"] = @(maxWaitMs.integerValue);
    }
  }
  if (NSPushBoolValue(config.rawPrefs[@"txt"])) {
    payload[@"txt"] = @YES;
  }

  NSData* bodyData = [NSJSONSerialization dataWithJSONObject:payload
                                                     options:0
                                                       error:nil];
  if (!bodyData) {
    return nil;
  }
  NSString* bodyString =
      [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];

  NSPushRequest* request =
      [NSPushRequest requestWithURLString:PUSHER_SERVICE_QUICKER_URL
                                 headers:nil
                                infoDict:@{}
                                  method:@"POST"];
  request.bodyType = @"json";
  request.rawBodyString = bodyString;
  request.logInfoDict = [self logInfoDictForInfoDict:payload];

  // The API reports failures through isSuccess in a 200 response (e.g. a bad
  // push code); surface those instead of the sender's generic "HTTP 200 =
  // success" path.
  request.resendHandler =
      ^(NSPushRequest* request, NSURLResponse* response, NSData* data,
        NSError* error, void (^completion)(NSPushRequest* request,
                                          BOOL shouldFail)) {
    if (error || !data) {
      completion(nil, NO);
      return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data
                                              options:0
                                                error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
      request.failureReason =
          @"Quicker returned an invalid/non-JSON response";
      completion(nil, YES);
      return;
    }
    if (!NSPushBoolResolved(json[@"isSuccess"], NO)) {
      NSString* errorMessage =
          XStrDefault(json[@"errorMessage"], @"unknown error");
      request.failureReason =
          XStr(@"Quicker push failed: %@", errorMessage);
      completion(nil, YES);
      return;
    }
    completion(nil, NO);
  };
  return request;
}

@end
