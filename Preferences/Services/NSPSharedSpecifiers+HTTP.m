#import "../NSPSharedSpecifiers.h"
#import "../NSPLocalization.h"
#import "../NSPushServicePrefs.h"
#import "../../Generated/BuiltinServices.generated.h"
#import "../../global.h"

@implementation NSPSharedSpecifiers (HTTP)

+ (NSArray*)http:(NSString*)appID {
  BOOL isCustomApp = appID != nil;

  PSSpecifier* includeIcon = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Include Icon", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSSwitchCell
                          edit:nil];
  [includeIcon setProperty:NSPPreferenceServiceIncludeIconKey forKey:@"key"];
  [includeIcon setProperty:@YES forKey:@"enabled"];
  [includeIcon setProperty:@NO forKey:@"default"];
  [includeIcon setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [includeIcon setProperty:PUSHER_SERVICE_HTTP forKey:@"service"];
  [includeIcon setProperty:@"includeIcon" forKey:@"customAppsPrefsKey"];

  PSSpecifier* includeImage = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Include Image", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSSwitchCell
                          edit:nil];
  [includeImage setProperty:NSPPreferenceServiceIncludeImageKey forKey:@"key"];
  [includeImage setProperty:@YES forKey:@"enabled"];
  [includeImage setProperty:@NO forKey:@"default"];
  [includeImage setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [includeImage setProperty:PUSHER_SERVICE_HTTP forKey:@"service"];
  [includeImage setProperty:@"includeImage" forKey:@"customAppsPrefsKey"];

  PSSpecifier* imageMaxWidth = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Maximum Image Width (pixels)", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSEditTextCell
                          edit:nil];
  [imageMaxWidth setProperty:NSPPreferenceServiceImageMaxWidthKey
                      forKey:@"key"];
  [imageMaxWidth setProperty:@YES forKey:@"enabled"];
  [imageMaxWidth setProperty:@YES forKey:@"isDecimalPad"];
  [imageMaxWidth setProperty:@(PUSHER_DEFAULT_MAX_WIDTH) forKey:@"default"];
  [imageMaxWidth setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [imageMaxWidth setProperty:PUSHER_SERVICE_HTTP forKey:@"service"];
  [imageMaxWidth setProperty:@"imageMaxWidth" forKey:@"customAppsPrefsKey"];

  PSSpecifier* imageMaxHeight = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Maximum Image Height (pixels)", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSEditTextCell
                          edit:nil];
  [imageMaxHeight setProperty:NSPPreferenceServiceImageMaxHeightKey
                       forKey:@"key"];
  [imageMaxHeight setProperty:@YES forKey:@"enabled"];
  [imageMaxHeight setProperty:@YES forKey:@"isDecimalPad"];
  [imageMaxHeight setProperty:@(PUSHER_DEFAULT_MAX_HEIGHT) forKey:@"default"];
  [imageMaxHeight setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [imageMaxHeight setProperty:PUSHER_SERVICE_HTTP forKey:@"service"];
  [imageMaxHeight setProperty:@"imageMaxHeight" forKey:@"customAppsPrefsKey"];

  PSSpecifier* imageShrinkFactor = [PSSpecifier
      preferenceSpecifierNamed:NSPLocalizedString(@"Image Shrink Factor Upon Retry", nil)
                        target:self
                           set:@selector(setPreferenceValue:
                                         forBuiltInServiceSpecifier:)
                           get:@selector(readBuiltInServicePreferenceValue:)
                        detail:nil
                          cell:PSEditTextCell
                          edit:nil];
  [imageShrinkFactor setProperty:NSPPreferenceServiceImageShrinkFactorKey
                          forKey:@"key"];
  [imageShrinkFactor setProperty:@YES forKey:@"enabled"];
  [imageShrinkFactor setProperty:@YES forKey:@"isDecimalPad"];
  [imageShrinkFactor setProperty:@(PUSHER_DEFAULT_SHRINK_FACTOR)
                          forKey:@"default"];
  [imageShrinkFactor setProperty:@(isCustomApp) forKey:@"isCustomApp"];
  [imageShrinkFactor setProperty:PUSHER_SERVICE_HTTP forKey:@"service"];
  [imageShrinkFactor setProperty:@"imageShrinkFactor"
                          forKey:@"customAppsPrefsKey"];

  if (isCustomApp) {
    [includeIcon setProperty:appID forKey:@"customAppID"];
    [includeImage setProperty:appID forKey:@"customAppID"];
    [imageMaxWidth setProperty:appID forKey:@"customAppID"];
    [imageMaxHeight setProperty:appID forKey:@"customAppID"];
    [imageShrinkFactor setProperty:appID forKey:@"customAppID"];
  }

  return @[
    includeIcon, includeImage, imageMaxWidth, imageMaxHeight, imageShrinkFactor
  ];
}

+ (void)load {
  [NSPushServicePrefsManager registerBuilder:^NSArray*(NSString* appID) {
    return [NSPSharedSpecifiers http:appID];
  } forService:PUSHER_SERVICE_HTTP];
}

@end
