#import "XRHCommon.h"

#pragma mark - 窗口场景

UIWindowScene *XRHActiveWindowScene(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

#pragma mark - 充电上限的状态（xrhead 写）

NSDictionary *XRHLimitState(void) {
    return [NSDictionary dictionaryWithContentsOfFile:XRH_LIMIT_STATE_FILE];
}

// 是充电上限停着的（高温保护停的不算）
BOOL XRHLimitInhibited(void) {
    NSDictionary *s = XRHLimitState();
    return [s[@"inhibited"] boolValue] && ![s[@"thermalHot"] boolValue];
}

// 高温保护中（xrhead 写；停充 / 间歇充电都算）
BOOL XRHThermalHot(void) {
    return [XRHLimitState()[@"thermalHot"] boolValue];
}

#pragma mark - 刷新登记

// 每项：@[keys 或 NSNull, 上次的值（可变数组）, block]
static NSMutableArray<NSArray *> *gRefreshers;

static NSArray *XRHSnapshot(NSArray<NSString *> *keys) {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) [values addObject:[[XRHPrefs shared] objectForKey:key] ?: NSNull.null];
    return values;
}

void XRHAddRefresher(NSArray<NSString *> *keys, void (^refresher)(void)) {
    if (!refresher) return;
    if (!gRefreshers) gRefreshers = [NSMutableArray array];
    NSMutableArray *last = keys ? [XRHSnapshot(keys) mutableCopy] : [NSMutableArray array];
    [gRefreshers addObject:@[keys ?: (id)NSNull.null, last, [refresher copy]]];
}

void XRHRunRefreshers(void) {
    for (NSArray *entry in gRefreshers) {
        NSArray *keys = entry[0] == NSNull.null ? nil : entry[0];
        if (keys) {
            NSArray *now = XRHSnapshot(keys);
            NSMutableArray *last = entry[1];
            if ([now isEqualToArray:last]) continue;
            [last setArray:now];
        }
        ((void (^)(void))entry[2])();
    }
}
