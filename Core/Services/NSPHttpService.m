#import "NSPHttpService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"

// Built-in generic HTTP service. Mirrors NSPCustomService's request shape
// (method / bodyType / auth / shared data dict) but lives in the built-in
// registry so it shows up alongside Bark / Wechat / ... without the user
// having to create a custom service by name. The endpoint is stored in the
// shared serverURL field and piped through urlForEventName: into
// rawPrefs[@"url"] by NSPushConfig.
@implementation NSPHttpService

+ (void)load {
  [NSPushServiceManager registerServiceClass:self forName:[self serviceName]];
}

+ (NSString*)serviceName {
  return PUSHER_SERVICE_HTTP;
}

// The endpoint is fully user-supplied: return serverURL verbatim so
// NSPushConfig stores it as rawPrefs[@"url"]. A blank endpoint yields an
// empty URL and the send is skipped downstream.
+ (NSString*)urlForEventName:(NSString*)eventName
                      dbName:(NSString*)dbName
                   serverURL:(NSString*)serverURL {
  return [serverURL ?: @"" copy];
}

+ (NSDictionary*)extraPrefsForName:(NSString*)name
                      servicePrefs:(NSDictionary*)servicePrefs {
  // Pass raw values through with defaults so numeric prefs keep their
  // original type (edit cells may store strings); the guarded accessors in
  // the sender / base class handle both NSString and NSNumber.
  return @{
    @"method" : XStrDefault(servicePrefs[@"method"], @"POST"),
    @"bodyType" : XStrDefault(servicePrefs[@"bodyType"], @"json"),
    @"authenticationMethod" :
        @(NSPushIntegerValue(servicePrefs[@"authenticationMethod"], 0)),
    @"paramName" : XStrDefault(servicePrefs[@"paramName"], @""),
    @"includeIcon" : servicePrefs[NSPPreferenceServiceIncludeIconKey] ?: @NO,
    @"includeImage" : servicePrefs[NSPPreferenceServiceIncludeImageKey] ?: @NO,
    @"imageMaxWidth" : servicePrefs[NSPPreferenceServiceImageMaxWidthKey]
        ?: @(PUSHER_DEFAULT_MAX_WIDTH),
    @"imageMaxHeight" : servicePrefs[NSPPreferenceServiceImageMaxHeightKey]
        ?: @(PUSHER_DEFAULT_MAX_HEIGHT),
    @"imageShrinkFactor" :
            servicePrefs[NSPPreferenceServiceImageShrinkFactorKey]
        ?: @(PUSHER_DEFAULT_SHRINK_FACTOR)
  };
}

+ (NSDictionary*)extraCustomAppPrefsForName:(NSString*)name
                                   appPrefs:(NSDictionary*)appPrefs {
  return @{
    @"includeIcon" : appPrefs[@"includeIcon"] ?: @NO,
    @"includeImage" : appPrefs[@"includeImage"] ?: @NO,
    @"imageMaxWidth" : appPrefs[@"imageMaxWidth"] ?: @(PUSHER_DEFAULT_MAX_WIDTH),
    @"imageMaxHeight" : appPrefs[@"imageMaxHeight"] ?: @(PUSHER_DEFAULT_MAX_HEIGHT),
    @"imageShrinkFactor" :
        appPrefs[@"imageShrinkFactor"] ?: @(PUSHER_DEFAULT_SHRINK_FACTOR)
  };
}

+ (NSPushRequest*)requestForBulletinContext:(NSPBulletinContext*)context
                                     config:(NSPushServiceConfig*)config {
  NSMutableDictionary* infoDict =
      [[self baseInfoDictForBulletinContext:context config:config] mutableCopy];

  NSInteger authMethod =
      NSPushIntegerValue(config.rawPrefs[@"authenticationMethod"], 0);
  // authMethod 2 = body auth: embed key inside the JSON payload instead.
  if (authMethod == 2) {
    NSString* paramName = XStrDefault(config.rawPrefs[@"paramName"], @"");
    if (paramName.length > 0) {
      infoDict[paramName] = XStrDefault(config.rawPrefs[@"key"], @"");
    } else {
      infoDict[@"key"] = XStrDefault(config.rawPrefs[@"key"], @"");
    }
  }

  NSDictionary* headers = @{};
  // authMethod 1 = header auth: send key as a custom HTTP header.
  if (authMethod == 1) {
    NSString* paramName = XStrDefault(config.rawPrefs[@"paramName"], @"");
    NSString* headerName =
        (paramName.length > 0) ? paramName : @"Access-Token";
    headers = @{headerName : XStrDefault(config.rawPrefs[@"key"], @"")};
  }

  NSPushRequest* request =
      [NSPushRequest requestWithURLString:[self replacedKeyURLStringForConfig:config]
                                 headers:headers
                                infoDict:infoDict];
  request.method = XStrDefault(config.rawPrefs[@"method"], @"POST");
  request.bodyType = XStrDefault(config.rawPrefs[@"bodyType"], @"json");
  request.logInfoDict = [self logInfoDictForInfoDict:infoDict];
  return request;
}

+ (BOOL)shouldIncludeIconForConfig:(NSPushServiceConfig*)config {
  return NSPushBoolValue(config.rawPrefs[@"includeIcon"]);
}

+ (BOOL)shouldIncludeImageForConfig:(NSPushServiceConfig*)config {
  return NSPushBoolValue(config.rawPrefs[@"includeImage"]);
}

@end
