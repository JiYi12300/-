#import "../NSPSharedSpecifiers.h"
#import "../NSPLocalization.h"
#import "../NSPushServicePrefs.h"
#import "../../Generated/BuiltinServices.generated.h"
#import "../../global.h"

@implementation NSPSharedSpecifiers (Wechat)

+ (NSArray*)wechat:(NSString*)appID {
  BOOL isCustomApp = appID != nil;

  PSSpecifier* touser = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Touser", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSEditTextCell
                          edit:nil];
  [touser setProperty:NSPPreferenceServiceTouserKey forKey:@"key"];
  [touser setProperty:@YES forKey:@"enabled"];
  [touser setProperty:@YES forKey:@"noAutoCorrect"];
  [touser setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [touser setProperty:PUSHER_SERVICE_WECHAT forKey:@"service"];
  [touser setProperty:@"touser" forKey:@"customAppsPrefsKey"];

  // Per-app bot webhook key override: when left empty the app inherits the
  // service-level key, so an override added just for filters doesn't break
  // webhook pushes.
  PSSpecifier* webhookKey = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Webhook Key", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSEditTextCell
                          edit:nil];
  [webhookKey setProperty:@"webhookKey" forKey:@"key"];
  [webhookKey setProperty:@YES forKey:@"enabled"];
  [webhookKey setProperty:@YES forKey:@"noAutoCorrect"];
  [webhookKey setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [webhookKey setProperty:PUSHER_SERVICE_WECHAT forKey:@"service"];
  [webhookKey setProperty:@"webhookKey" forKey:@"customAppsPrefsKey"];

  if (isCustomApp) {
    [touser setProperty:appID forKey:@"customAppID"];
    [webhookKey setProperty:appID forKey:@"customAppID"];
  }

  return @[ touser, webhookKey ];
}

+ (void)load {
  [NSPushServicePrefsManager registerBuilder:^NSArray*(NSString* appID) {
    return [NSPSharedSpecifiers wechat:appID];
  } forService:PUSHER_SERVICE_WECHAT];
}

@end
