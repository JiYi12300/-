#import "NSPHttpService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"
#import <UIKit/UIKit.h>

// JSON-escape a string for embedding inside a hand-written JSON template.
// Serializing @[string] yields ["<escaped>"]; strip the [" wrapper to get the
// escaped payload alone (quotes/backslashes/newlines handled by Foundation).
static NSString* NSPushHTTPJSONEscapedString(NSString* string) {
  if (![string isKindOfClass:NSString.class]) {
    string = [string description];
  }
  NSData* data =
      [NSJSONSerialization dataWithJSONObject:@[string ?: @""] options:0 error:nil];
  if (!data) {
    return @"";
  }
  NSString* wrapped =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (wrapped.length < 4) {
    return @"";
  }
  return [wrapped substringWithRange:NSMakeRange(2, wrapped.length - 4)];
}

// Percent-encode a value for a form body / query string template. Matches the
// sender's form encoding (space -> '+').
static NSString* NSPushHTTPFormEncodedString(NSString* string) {
  NSCharacterSet* allowed = [NSCharacterSet
      characterSetWithCharactersInString:
          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
  return [[(string ?: @"")
      stringByAddingPercentEncodingWithAllowedCharacters:allowed]
      stringByReplacingOccurrencesOfString:@"%20"
                                withString:@"+"];
}

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
    @"paramsTemplate" : XStrDefault(servicePrefs[@"paramsTemplate"], @""),
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

// Render the user's params template: replace [placeholder] tokens with the
// notification's data. Values are escaped according to the target format
// (JSON string escaping for json bodies, form percent-encoding for form
// bodies and query strings) so notification content can never break the
// surrounding template structure.
+ (NSString*)renderedTemplate:(NSString*)templateString
                     infoDict:(NSDictionary*)infoDict
                      authKey:(NSString*)authKey
                formEncoded:(BOOL)formEncoded {
  if (![templateString isKindOfClass:NSString.class] ||
      templateString.length == 0) {
    return @"";
  }

  // The shared builder stores image as UIImage (or @YES as a "has image"
  // marker); templates need the base64 text. @YES renders as an empty string.
  NSString* imageString = @"";
  id imageValue = infoDict[@"image"];
  if ([imageValue isKindOfClass:UIImage.class]) {
    imageString = [NSPushImage base64RepresentationForImage:imageValue];
  } else if ([imageValue isKindOfClass:NSString.class]) {
    imageString = imageValue;
  }

  NSDictionary* placeholders = @{
    @"[title]" : infoDict[@"title"],
    @"[sub]" : infoDict[@"subtitle"],
    @"[msg]" : infoDict[@"message"],
    @"[date]" : infoDict[@"date"],
    @"[app]" : infoDict[@"appName"],
    @"[appid]" : infoDict[@"appID"],
    @"[device]" : infoDict[@"deviceName"],
    @"[icon]" : infoDict[@"icon"],
    @"[image]" : imageString,
    @"[key]" : authKey
  };

  NSString* result = templateString;
  for (NSString* placeholder in placeholders) {
    id value = placeholders[placeholder];
    NSString* string = @"";
    if ([value isKindOfClass:NSString.class]) {
      string = (NSString*)value;
    } else if (value && ![value isKindOfClass:NSNumber.class] &&
               ![value isEqual:@YES]) {
      string = [value description];
    }
    if (formEncoded) {
      string = NSPushHTTPFormEncodedString(string);
    } else {
      string = NSPushHTTPJSONEscapedString(string);
    }
    result = [result stringByReplacingOccurrencesOfString:placeholder
                                                withString:string];
  }
  return result;
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

  NSString* method = XStrDefault(config.rawPrefs[@"method"], @"POST");
  NSString* bodyType = XStrDefault(config.rawPrefs[@"bodyType"], @"json");
  NSPushRequest* request =
      [NSPushRequest requestWithURLString:[self replacedKeyURLStringForConfig:config]
                                 headers:headers
                                infoDict:infoDict];
  request.method = method;
  request.bodyType = bodyType;

  // Params template: fully user-defined payload. The rendered string is sent
  // verbatim (body for POST-family methods, query string for GET/HEAD).
  // infoDict is cleared so the sender never mixes the template with the
  // default all-fields body, and its image-shrink retry path stays dormant.
  NSString* template = XStrDefault(config.rawPrefs[@"paramsTemplate"], @"");
  if (template.length > 0) {
    BOOL isGetOrHead =
        ([method caseInsensitiveCompare:@"GET"] == NSOrderedSame ||
         [method caseInsensitiveCompare:@"HEAD"] == NSOrderedSame);
    BOOL isForm =
        [bodyType caseInsensitiveCompare:@"form"] == NSOrderedSame;
    request.infoDict = @{};
    request.rawBodyString =
        [self renderedTemplate:template
                       infoDict:infoDict
                        authKey:XStrDefault(config.rawPrefs[@"key"], @"")
                   formEncoded:(isForm || isGetOrHead)];
    return request;
  }

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
