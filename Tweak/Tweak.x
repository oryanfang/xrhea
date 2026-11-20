// 入口：读偏好、监听设置变化、按总开关初始化各功能。
// 每个功能一个文件，对外暴露 XRHInitXxx()（声明在 XRHCommon.h），
// 功能内部用 XRHAddRefresher(关心的偏好键, block) 登记"改设置后要刷新什么"，只有那几个键变了才跑。
#import "XRHCommon.h"
#import <notify.h>

static BOOL gModulesLoaded = NO;

static void XRHPrefsChanged(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[XRHPrefs shared] reload];
    if (!gModulesLoaded) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        XRHRunRefreshers();
    });
}

%ctor {
    @autoreleasepool {
        XRHPrefs *prefs = [XRHPrefs shared];
        [prefs reload];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        XRHPrefsChanged, CFSTR(XRH_PREFS_CHANGED), NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);

        XRHDebugReset();
        XRHDebugLog(@"xrhea loaded into %@ (pid %d) at %@, enabled=%d",
                    NSProcessInfo.processInfo.processName, getpid(), [NSDate date], prefs.enabled);

        // 保持高刷新率的开关传给 backboardd（总开关关着时传 0）
        XRHSyncHighRefresh();
        // 总开关关闭时不安装任何 hook（切换总开关需要注销生效）
        if (!prefs.enabled) return;

        XRHInitChargePrompt();
        XRHInitAlerts();
        XRHInitLowPower();
        gModulesLoaded = YES;

#if XRH_DEBUG
        // 调试版：启动 5 秒后读一次电池，确认共用的读数代码在这台手机上都读得到
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            XRHDebugLog(@"[Battery] %.0fmV %.0fmA %.2fW %.1f℃ full=%.0f design=%.0f health=%.1f%% cycles=%.0f remain=%.0fmin adapter=%.0fW charging=%d",
                        XRBatteryVoltage(), XRBatteryAmperage(), XRBatteryWatts(), XRBatteryTemperature(),
                        XRBatteryFullCapacity(), XRBatteryDesignCapacity(), XRBatteryHealth() * 100, XRBatteryCycleCount(),
                        XRBatteryTimeRemaining(), XRBatteryAdapterWatts(), XRBatteryIsCharging());        });
#endif
        XRHDebugStartCPUSampling();
    }
}
