#import "NSPServerChanService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"

// ServerChan (Server酱) Turbo edition. Posts a title + markdown body to
// sctapi.ftqq.com/<SendKey>.send; the response is JSON with code == 0 on
// success. The notification title maps to the message title, the message body
// to the markdown content (desp), with the subtitle prepended when present.
@implementation NSPServerChanService

+ (void)load {
  [NSPushServiceManager registerServiceClass:self forName:[self serviceName]];
}

+ (NSString*)serviceName {
  return PUSHER_SERVICE_SERVERCHAN;
}

+ (NSString*)urlForEventName:(NSString*)eventName
                      dbName:(NSString*)dbName
                   serverURL:(NSString*)serverURL {
  return PUSHER_SERVICE_SERVERCHAN_URL;
}

+ (NSPushRequest*)requestForBulletinContext:(NSPBulletinContext*)context
                                     config:(NSPushServiceConfig*)config {
  // Missing send key: the URL would become https://sctapi.ftqq.com/.send,
  // which can never succeed. Abort the same way Wechat does for missing
  // credentials; callers treat nil as "failed to build request".
  NSString* key = XStrDefault(config.rawPrefs[@"key"], @"");
  if (key.length == 0) {
    return nil;
  }

  NSString* title = context.title ?: @"";
  NSString* subtitle = context.subtitle ?: @"";
  NSString* message = context.message ?: @"";
  // desp is a markdown body; the title goes in the separate title field, so
  // only prepend the subtitle (as bold text) when the notification has one.
  NSString* desp = message;
  if (subtitle.length > 0) {
    desp = XStr(@"**%@**\n\n%@", subtitle, message);
  }

  NSDictionary* infoDict = @{@"title" : title, @"desp" : desp};
  NSPushRequest* request =
      [NSPushRequest requestWithURLString:[self replacedKeyURLStringForConfig:config]
                                 headers:nil
                                infoDict:infoDict];
  // The send API accepts JSON and form bodies; form matches the official
  // examples and avoids any encoding surprises with markdown content.
  request.bodyType = @"form";
  request.logInfoDict = [self logInfoDictForInfoDict:infoDict];

  // The API reports errors through a numeric code in a 200 response (e.g. a
  // bad send key). Surface those as failures instead of letting the sender's
  // generic "HTTP 200 = success" path log them as delivered. There is no
  // token to refresh, so no resend.
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
          @"ServerChan returned an invalid/non-JSON response";
      completion(nil, YES);
      return;
    }
    id codeValue = json[@"code"];
    if (![codeValue respondsToSelector:@selector(integerValue)]) {
      request.failureReason =
          @"ServerChan returned a response without a valid code";
      completion(nil, YES);
      return;
    }
    NSInteger code = [codeValue integerValue];
    if (code != 0) {
      NSString* message = XStrDefault(json[@"message"], @"");
      request.failureReason = XStr(
          @"ServerChan send failed (code=%ld, message=%@)", (long)code, message);
      completion(nil, YES);
      return;
    }
    completion(nil, NO);
  };
  return request;
}

@end
