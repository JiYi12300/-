#import "NSPBarkService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"

@implementation NSPBarkService

+ (void)load {
  [NSPushServiceManager registerServiceClass:self forName:[self serviceName]];
}

+ (NSString*)serviceName {
  return PUSHER_SERVICE_BARK;
}

+ (void)requestForBulletinContext:(NSPBulletinContext*)context
                           config:(NSPushServiceConfig*)config
                         requests:(void (^)(NSArray<NSPushRequest*>* requests))requests {
  // Multi-target: push to every non-empty key (key/key2/key3 share the URL
  // template). Empty keys are treated as disabled and skipped.
  NSArray<NSString*>* keys = @[
    XStrDefault(config.rawPrefs[@"key"], @""),
    XStrDefault(config.rawPrefs[@"key2"], @""),
    XStrDefault(config.rawPrefs[@"key3"], @"")
  ];
  NSMutableArray* built = [NSMutableArray new];
  for (NSString* key in keys) {
    if (key.length == 0) {
      continue;
    }
    NSPushRequest* request =
        [self requestForBulletinContext:context config:config key:key];
    if (request) {
      [built addObject:request];
    }
  }
  requests(built);
}

+ (NSPushRequest*)requestForBulletinContext:(NSPBulletinContext*)context
                                     config:(NSPushServiceConfig*)config {
  return [self requestForBulletinContext:context
                                  config:config
                                     key:XStrDefault(config.rawPrefs[@"key"], @"")];
}

+ (NSPushRequest*)requestForBulletinContext:(NSPBulletinContext*)context
                                     config:(NSPushServiceConfig*)config
                                        key:(NSString*)key {
  NSMutableDictionary* infoDict =
      [@{ @"title" : context.title ?: @"", @"body" : context.message ?: @"" }
          mutableCopy];
  NSDictionary<NSString*, NSString*>* barkParams = @{
    NSPPreferenceBarkLevelKey : @"level",
    NSPPreferenceBarkVolumeKey : @"volume",
    NSPPreferenceBarkBadgeKey : @"badge",
    NSPPreferenceBarkCallKey : @"call",
    NSPPreferenceBarkAutoCopyKey : @"autoCopy",
    NSPPreferenceBarkSoundKey : @"sound",
    NSPPreferenceBarkImageKey : @"image",
    NSPPreferenceBarkGroupKey : @"group",
    NSPPreferenceBarkIsArchiveKey : @"isArchive",
    NSPPreferenceBarkTTLKey : @"ttl",
    NSPPreferenceBarkClickURLKey : @"url",
    NSPPreferenceBarkActionKey : @"action",
    NSPPreferenceBarkIDKey : @"id",
    NSPPreferenceBarkDeleteKey : @"delete"
  };
  for (NSString* prefKey in barkParams) {
    NSString* value = XStrDefault(config.rawPrefs[prefKey], @"");
    if (value.length > 0) {
      infoDict[barkParams[prefKey]] = value;
    }
  }
  if (infoDict[@"delete"] != nil && infoDict[@"id"] == nil) {
    [infoDict removeObjectForKey:@"delete"];
  }
  NSPushRequest* request =
      [NSPushRequest
          requestWithURLString:[self replacedKeyURLStringForConfig:config key:key]
                       headers:nil
                      infoDict:infoDict];
  request.logInfoDict = [self logInfoDictForInfoDict:infoDict];
  return request;
}

+ (NSString*)urlForEventName:(NSString*)eventName
                      dbName:(NSString*)dbName
                   serverURL:(NSString*)serverURL {
  NSString* finalURL = nil;
  if (serverURL && serverURL.length > 0) {
    if ([serverURL hasSuffix:@"/"]) {
      finalURL = [serverURL stringByAppendingString:@"REPLACE_KEY"];
    } else {
      finalURL = [serverURL stringByAppendingFormat:@"/REPLACE_KEY"];
    }
  } else {
    finalURL = PUSHER_SERVICE_BARK_URL;
  }
  return finalURL;
}

+ (NSDictionary*)extraPrefsForName:(NSString*)name
                      servicePrefs:(NSDictionary*)servicePrefs {
  return @{
    @"serverURL" : XStrDefault(servicePrefs[NSPPreferenceServiceServerURLKey],
                               @"https://api.day.app"),
    NSPPreferenceBarkLevelKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkLevelKey], @""),
    NSPPreferenceBarkVolumeKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkVolumeKey], @""),
    NSPPreferenceBarkBadgeKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkBadgeKey], @""),
    NSPPreferenceBarkCallKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkCallKey], @""),
    NSPPreferenceBarkAutoCopyKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkAutoCopyKey], @""),
    NSPPreferenceBarkSoundKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkSoundKey], @""),
    NSPPreferenceBarkImageKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkImageKey], @""),
    NSPPreferenceBarkGroupKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkGroupKey], @""),
    NSPPreferenceBarkIsArchiveKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkIsArchiveKey], @""),
    NSPPreferenceBarkTTLKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkTTLKey], @""),
    NSPPreferenceBarkClickURLKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkClickURLKey], @""),
    NSPPreferenceBarkActionKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkActionKey], @""),
    NSPPreferenceBarkIDKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkIDKey], @""),
    NSPPreferenceBarkDeleteKey :
        XStrDefault(servicePrefs[NSPPreferenceBarkDeleteKey], @"")
  };
}

+ (NSDictionary*)extraCustomAppPrefsForName:(NSString*)name
                                   appPrefs:(NSDictionary*)appPrefs {
  return @{
    NSPPreferenceBarkLevelKey :
        XStrDefault(appPrefs[NSPPreferenceBarkLevelKey], @""),
    NSPPreferenceBarkVolumeKey :
        XStrDefault(appPrefs[NSPPreferenceBarkVolumeKey], @""),
    NSPPreferenceBarkBadgeKey :
        XStrDefault(appPrefs[NSPPreferenceBarkBadgeKey], @""),
    NSPPreferenceBarkCallKey :
        XStrDefault(appPrefs[NSPPreferenceBarkCallKey], @""),
    NSPPreferenceBarkAutoCopyKey :
        XStrDefault(appPrefs[NSPPreferenceBarkAutoCopyKey], @""),
    NSPPreferenceBarkSoundKey :
        XStrDefault(appPrefs[NSPPreferenceBarkSoundKey], @""),
    NSPPreferenceBarkImageKey :
        XStrDefault(appPrefs[NSPPreferenceBarkImageKey], @""),
    NSPPreferenceBarkGroupKey :
        XStrDefault(appPrefs[NSPPreferenceBarkGroupKey], @""),
    NSPPreferenceBarkIsArchiveKey :
        XStrDefault(appPrefs[NSPPreferenceBarkIsArchiveKey], @""),
    NSPPreferenceBarkTTLKey :
        XStrDefault(appPrefs[NSPPreferenceBarkTTLKey], @""),
    NSPPreferenceBarkClickURLKey :
        XStrDefault(appPrefs[NSPPreferenceBarkClickURLKey], @""),
    NSPPreferenceBarkActionKey :
        XStrDefault(appPrefs[NSPPreferenceBarkActionKey], @""),
    NSPPreferenceBarkIDKey :
        XStrDefault(appPrefs[NSPPreferenceBarkIDKey], @""),
    NSPPreferenceBarkDeleteKey :
        XStrDefault(appPrefs[NSPPreferenceBarkDeleteKey], @"")
  };
}

@end
