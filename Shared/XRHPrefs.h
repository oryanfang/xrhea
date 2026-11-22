#import <Foundation/Foundation.h>

// 偏好域与通知名：设置面板写入这里，插件从这里读取
#define XRH_PREFS_DOMAIN   @"com.xyrith.xrhea"
#define XRH_PREFS_CHANGED  "com.xyrith.xrhea/prefschanged"
// 设置页「提示」页每条提醒后面的「预览」→ SpringBoard 用当前数据弹一次：com.xyrith.xrhea/try-alert-1 … -6（Alerts.m）

@interface XRHPrefs : NSObject

+ (instancetype)shared;

// 从 cfprefsd 重新读取全部偏好
- (void)reload;

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback;
- (double)doubleForKey:(NSString *)key fallback:(double)fallback;
- (id)objectForKey:(NSString *)key;

// 总开关（默认开启）
@property (nonatomic, readonly) BOOL enabled;

@end
