#import "NSPQuickerService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"

// Quicker (getquicker.net) push service, V2 long-connection API:
//   POST https://push.getquicker.cn/to/quicker
//   JSON body: { toUser (account email), code (push verification code),
//                toDevice (optional), operation (default "paste"),
//                action (optional), data (content) }
// The notification text is pushed as `data`; by default it is pasted into the
// active window on the target PC (operation = "paste"). Success is reported in
// the JSON response field isSuccess.
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
    @"action" : XStrDefault(servicePrefs[@"action"], @"")
  };
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

  NSString* title = context.title ?: @"";
  NSString* message = context.message ?: @"";
  NSString* data =
      (title.length > 0 && message.length > 0)
          ? XStr(@"%@\n%@", title, message)
          : (title.length > 0 ? title : message);

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
