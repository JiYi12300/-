#import "../NSPushService.h"
#import <Foundation/Foundation.h>

#define PUSHER_SERVICE_WECHAT @"Wechat"
#define PUSHER_SERVICE_WECHAT_URL                                              \
  @"https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token="            \
  @"REPLACE_DYNAMIC_KEY"
// Group bot webhook: no access_token dance, the key rides in the URL query.
#define PUSHER_SERVICE_WECHAT_WEBHOOK_URL                                      \
  @"https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=REPLACE_KEY"

// pushMode: 0 = self-built app (corpid/corpsecret/agentID), 1 = group bot
// webhook.
#define PUSHER_WECHAT_PUSH_MODE_APP 0
#define PUSHER_WECHAT_PUSH_MODE_BOT 1

@interface NSPWechatService : NSPushServiceBase
@end
