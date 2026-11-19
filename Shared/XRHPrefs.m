#import "XRHPrefs.h"
#import "XRHKeys.h"

// 偏好在很多高频路径里读（每次改透明度、每次触摸、每次排版），读的时候不加锁：
// reload 整体换一份新的不可变字典（atomic 属性保证换的那一下是完整的），读到的总是某一份完整快照。
@interface XRHPrefs ()
@property (atomic, copy) NSDictionary *values;
@end

@implementation XRHPrefs

+ (instancetype)shared {
    static XRHPrefs *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [XRHPrefs new]; });
    return instance;
}

- (void)reload {
    CFStringRef domain = (__bridge CFStringRef)XRH_PREFS_DOMAIN;
    CFPreferencesAppSynchronize(domain);

    NSDictionary *values = nil;
    CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        values = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    self.values = values ?: @{};
}

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback {
    id v = self.values[key];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}

- (double)doubleForKey:(NSString *)key fallback:(double)fallback {
    id v = self.values[key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
}

- (id)objectForKey:(NSString *)key {
    return self.values[key];
}

- (BOOL)enabled {
    return [self boolForKey:kXRHEnabled fallback:YES];
}

@end
