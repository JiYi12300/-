#import "NSPHttpService.h"
#import "../../helpers.h"
#import "../NSPushConfig.h"
#import "../NSPushSupport.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// Ported from SmsForwarder WebhookUtils.kt (sendMsg), adapted to Pusher's
// service architecture (NSPushRequest built once, sent by the shared sender):
//
//   - Custom headers (one "Key: Value" per entry, separated by ';')
//   - Content-Type in headers selects the body format:
//       application/json  -> template rendered as a JSON body
//       text/*            -> template rendered as a raw text body
//       (no template)     -> default form body
//   - Basic auth embedded in the URL (http://user:pass@host/...)
//   - HmacSHA256 signing: sign = urlencode(base64(hmac_sha256(
//       "<timestamp>\n<secret>", key = secret)))
//   - GET: template (or defaults) goes into the query string
//   - POST/PUT/PATCH: template goes into the request body
//
// Placeholders (rendered per target format):
//   [title] [sub] [msg] [date] [app] [appid] [device]
//   [icon] [image] [key] [timestamp] [sign]
// ---------------------------------------------------------------------------

// JSON-escape a string for embedding inside a hand-written JSON template.
// Serializing @[string] yields ["<escaped>"]; strip the [" wrapper to get the
// escaped payload alone (quotes/backslashes/newlines handled by Foundation).
static NSString* NSPushHTTPJSONEscapedString(NSString* string) {
  if (![string isKindOfClass:NSString.class]) {
    string = [string description];
  }
  NSData* data = [NSJSONSerialization dataWithJSONObject:@[string ?: @""]
                                                 options:0
                                                   error:nil];
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

// HmacSHA256 sign, ported from SmsForwarder:
//   stringToSign = "<timestamp>\n<secret>"
//   sign = urlencode(base64(hmac_sha256(stringToSign, secret)))
static NSString* NSPushHTTPSign(NSString* secret, long long timestamp) {
  if (secret.length == 0) {
    return @"";
  }
  NSString* stringToSign = [NSString stringWithFormat:@"%lld\n%@", timestamp, secret];
  const char* keyBytes = [secret UTF8String];
  const char* dataBytes = [stringToSign UTF8String];
  unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, keyBytes, strlen(keyBytes), dataBytes,
         strlen(dataBytes), hmac);
  NSData* hmacData = [NSData dataWithBytes:hmac length:sizeof(hmac)];
  NSString* base64 =
      [hmacData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
  // SmsForwarder uses Base64.NO_WRAP (no line breaks); strip any that the
  // encoder may have produced, then URL-encode like it does.
  base64 = [base64 stringByReplacingOccurrencesOfString:@"\n" withString:@""];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"\r" withString:@""];
  return NSPushHTTPFormEncodedString(base64);
}

// Parse the user's headers preference. Accepted formats (SmsForwarder has a
// proper editor on Android; on iOS we keep a single-line field):
//   "Key: Value; Key2: Value2"  or  "Key:Value1,Value2"
static NSDictionary* NSPushHTTPParseHeaders(NSString* headersString) {
  NSMutableDictionary* headers = [NSMutableDictionary dictionary];
  if (![headersString isKindOfClass:NSString.class] ||
      headersString.length == 0) {
    return headers;
  }
  for (NSString* entry in [headersString componentsSeparatedByString:@";"]) {
    NSString* trimmed =
        [entry stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
      continue;
    }
    NSRange colon = [trimmed rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0 ||
        NSMaxRange(colon) >= trimmed.length) {
      continue;
    }
    NSString* name = [[trimmed substringToIndex:colon.location]
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString* value = [[trimmed substringFromIndex:NSMaxRange(colon)]
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length > 0 && value.length > 0) {
      headers[name] = value;
    }
  }
  return headers;
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
    @"headers" : XStrDefault(servicePrefs[@"headers"], @""),
    @"secret" : XStrDefault(servicePrefs[@"secret"], @""),
    @"paramsTemplate" : XStrDefault(servicePrefs[@"paramsTemplate"], @""),
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

// Render the user's params template: replace [placeholder] tokens with the
// notification's data. Values are escaped according to the target format
// (JSON string escaping for json/text bodies, form percent-encoding for form
// bodies and query strings) so notification content can never break the
// surrounding template structure.
+ (NSString*)renderedTemplate:(NSString*)templateString
                     infoDict:(NSDictionary*)infoDict
                      authKey:(NSString*)authKey
                    timestamp:(long long)timestamp
                          sign:(NSString*)sign
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
    @"[key]" : authKey,
    @"[timestamp]" : @(timestamp),
    @"[sign]" : sign ?: @""
  };

  NSString* result = templateString;
  for (NSString* placeholder in placeholders) {
    id value = placeholders[placeholder];
    NSString* string = @"";
    if ([value isKindOfClass:NSString.class]) {
      string = (NSString*)value;
    } else if ([value isKindOfClass:NSNumber.class]) {
      string = [(NSNumber*)value stringValue];
    } else if (value && ![value isEqual:@YES]) {
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

  NSString* authKey = XStrDefault(config.rawPrefs[@"key"], @"");

  // --- Headers (SmsForwarder: setting.headers) -----------------------------
  NSMutableDictionary* headers =
      [NSPushHTTPParseHeaders(
          XStrDefault(config.rawPrefs[@"headers"], @"")) mutableCopy];
  // authMethod 1 = header auth: send key as a custom HTTP header.
  if (authMethod == 1) {
    NSString* paramName = XStrDefault(config.rawPrefs[@"paramName"], @"");
    NSString* headerName =
        (paramName.length > 0) ? paramName : @"Access-Token";
    headers[headerName] = authKey;
  }

  // Content-Type in the user headers decides the body format, exactly like
  // SmsForwarder: application/json -> json template, text/* -> text template.
  BOOL isJson = NO;
  BOOL isText = NO;
  for (NSString* name in headers.allKeys) {
    if ([name caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame) {
      NSString* value = headers[name];
      if ([value.lowercaseString containsString:@"application/json"]) {
        isJson = YES;
      } else if ([value.lowercaseString hasPrefix:@"text/"]) {
        isText = YES;
      }
      break;
    }
  }

  // --- URL + Basic auth (SmsForwarder: user:pass@ stripped from the URL) ---
  NSString* urlString = XStrDefault(config.rawPrefs[@"url"], @"");
  static NSRegularExpression* basicAuthRegex = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    basicAuthRegex = [NSRegularExpression
        regularExpressionWithPattern:@"^(https?://)([^:@/]+):([^@]+)@(.+)"
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
  });
  NSString* basicAuthValue = @"";
  NSTextCheckingResult* match =
      [basicAuthRegex firstMatchInString:urlString
                                  options:0
                                    range:NSMakeRange(0, urlString.length)];
  if (match && match.numberOfRanges == 5) {
    NSString* scheme = [urlString substringWithRange:[match rangeAtIndex:1]];
    NSString* user = [urlString substringWithRange:[match rangeAtIndex:2]];
    NSString* password = [urlString substringWithRange:[match rangeAtIndex:3]];
    NSString* rest = [urlString substringWithRange:[match rangeAtIndex:4]];
    urlString = [scheme stringByAppendingString:rest];
    NSString* credentials = [NSString stringWithFormat:@"%@:%@", user, password];
    basicAuthValue = [NSString
        stringWithFormat:@"Basic %@",
                         [[credentials dataUsingEncoding:NSUTF8StringEncoding]
                             base64EncodedStringWithOptions:0]];
    headers[@"Authorization"] = basicAuthValue;
  }

  // --- Signing (SmsForwarder: HmacSHA256 over "timestamp\nsecret") ---------
  NSString* secret = XStrDefault(config.rawPrefs[@"secret"], @"");
  long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
  NSString* sign = @"";
  if (secret.length > 0) {
    sign = NSPushHTTPSign(secret, timestamp);
  }

  NSString* method =
      [XStrDefault(config.rawPrefs[@"method"], @"POST") uppercaseString];
  BOOL isGet = [method isEqualToString:@"GET"];
  NSString* template = XStrDefault(config.rawPrefs[@"paramsTemplate"], @""];

  NSPushRequest* request =
      [NSPushRequest requestWithURLString:urlString
                                  headers:headers
                                 infoDict:infoDict
                                   method:method];

  // --- GET: everything goes into the query string --------------------------
  if (isGet) {
    NSString* queryString = @"";
    if (template.length > 0) {
      // User template: percent-encode the values, append verbatim. A leading
      // '/' means "path-style" (SmsForwarder behaviour).
      queryString = [self renderedTemplate:template
                                   infoDict:infoDict
                                    authKey:authKey
                                  timestamp:timestamp
                                        sign:sign
                               formEncoded:YES];
      if (![queryString hasPrefix:@"/"]) {
        NSString* separator = [urlString containsString:@"?"] ? @"&" : @"?";
        queryString =
            [separator stringByAppendingString:queryString];
      }
    } else {
      // No template: push the core fields, like SmsForwarder's default
      // "from/content/timestamp/sign" query.
      queryString = [NSString
          stringWithFormat:@"%@title=%@&message=%@&timestamp=%lld",
                           ([urlString containsString:@"?"] ? @"&" : @"?"),
                           NSPushHTTPFormEncodedString(
                               XStrDefault(infoDict[@"title"], @"")),
                           NSPushHTTPFormEncodedString(
                               XStrDefault(infoDict[@"message"], @"")),
                           timestamp];
      if (sign.length > 0) {
        queryString =
            [queryString stringByAppendingString:@"&sign="];
        queryString =
            [queryString stringByAppendingString:sign];
      }
    }
    request.infoDict = @{};
    request.rawBodyString = queryString;
    return request;
  }

  // --- POST/PUT/PATCH/...: body ---------------------------------------------
  BOOL templateIsJsonObject =
      [template hasPrefix:@"{"] || [template hasSuffix:@"}"];
  if (template.length > 0 && (isJson || isText || templateIsJsonObject)) {
    // JSON / text body: render with JSON escaping, send verbatim. The
    // Content-Type header from the user's headers wins (the sender only sets
    // it when the user didn't provide one).
    request.infoDict = @{};
    request.bodyType = @"json";
    request.rawBodyString =
        [self renderedTemplate:template
                       infoDict:infoDict
                        authKey:authKey
                      timestamp:timestamp
                            sign:sign
                   formEncoded:NO];
  } else {
    // Form body. No template -> SmsForwarder's default form payload.
    NSString* formTemplate = template;
    if (formTemplate.length == 0) {
      formTemplate = @"title=[title]&message=[msg]&timestamp=[timestamp]";
      if (sign.length > 0) {
        formTemplate = [formTemplate stringByAppendingString:@"&sign=[sign]"];
      }
    }
    request.infoDict = @{};
    request.bodyType = @"form";
    request.rawBodyString =
        [self renderedTemplate:formTemplate
                       infoDict:infoDict
                        authKey:authKey
                      timestamp:timestamp
                            sign:sign
                   formEncoded:YES];
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
