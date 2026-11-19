// xrhead：xrhea 的充电上限后台服务（root，LaunchDaemon 常驻）。
//
// 停充的做法（在 iOS 17.3.1 真机上验证过）：
//   对 AppleSmartBattery 调 IORegistryEntrySetCFProperties({IsCharging: YES, PredictiveChargingInhibit: YES})，约 30 秒后停充，
//   电池电流 0～1 mA（电源直接给手机供电）；PredictiveChargingInhibit 写回 NO 就恢复。要 powersource-write 权限（entitlements.plist）。
//   属性只在内存里，重启手机恢复默认；PredictiveChargingInhibit 读不回来，所以「是不是我们停的」自己记。
//
// 规则（只在打开「充电上限」时管，关着时一律不碰，系统的优化充电照常工作）：
//   - 接着电源、电量 ≥ 上限 → 停充
//   - 充得快（电流 > 300 mA）时提前到「上限 − 1%」就停：停充要约 30 秒才生效，这段时间还会多充进 0.5% 左右，
//     不提前的话会停在上限 +1%（实测设 85% 停在 86%）。宁可低一点，也不超过上限
//   - 电量 ≤ 恢复线（上限 − 回落）→ 恢复充电（避免在上限附近反复启停）
//   - 刚插上电源、电量 < 上限 → 恢复充电
//   - 停着的时候发现又在充（被系统改回去了）→ 隔 90 秒以上再停一次
//   - 上限调高了、或者功能关了 → 恢复充电
//   - 收到退出信号（卸载、关服务）→ 先恢复充电再退出；`xrhead reset` 只恢复充电（prerm 用）
//   - 「这次充满」（chargeLimitFullOnce，插电弹窗里点的，SpringBoard 写）：这次接着电源期间不管上限；拔线就作废
//   - 记下上次充满的时间（lastFull），插件用来做「每月充满一次」提醒；第一次运行时当作刚充满，免得一装上就催
//
// 状态写给设置页 / 插件看：/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist（{inhibited, max, resumeAt, time, lastFull}）
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <notify.h>
#import <signal.h>

#define XRH_DOMAIN       CFSTR("com.xyrith.xrhea")
#define XRH_NOTIFY       "com.xyrith.xrhea/prefschanged"
#define XRH_STATE_FILE   @"/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist"
#define XRH_LOG_FILE     @"/var/mobile/Library/Caches/com.xyrith.xrhea.daemon.log"

typedef mach_port_t xr_io_object_t;
static xr_io_object_t (*pIOServiceGetMatchingService)(mach_port_t, CFDictionaryRef);
static CFMutableDictionaryRef (*pIOServiceMatching)(const char *);
static CFTypeRef (*pIORegistryEntryCreateCFProperty)(xr_io_object_t, CFStringRef, CFAllocatorRef, uint32_t);
static kern_return_t (*pIORegistryEntrySetCFProperties)(xr_io_object_t, CFTypeRef);

static xr_io_object_t gBattery;
static BOOL gInhibited;            // 我们最近一次发的是「停充」
static int gInhibitMax;            // 停充时的上限（上限调高了要恢复）
static const double kXRHEarlyStopAmps = 300;   // 充电电流超过这个（mA）就提前 1% 停
static CFAbsoluteTime gLastCommand;
static double gLastFull;           // 上次充满（Unix 时间）
static BOOL gWasConnected;

#pragma mark - 日志（只在调试版）

static void XRHLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void XRHLog(NSString *format, ...) {
#if XRH_DEBUG
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm:ss";
    line = [NSString stringWithFormat:@"%@ %@\n", [f stringFromDate:[NSDate date]], line];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:XRH_LOG_FILE];
    if (!h) {
        [@"" writeToFile:XRH_LOG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:XRH_LOG_FILE];
    }
    // 超过 200KB 就从头写，免得一直长
    if ([h seekToEndOfFile] > 200 * 1024) [h truncateFileAtOffset:0];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
#endif
}

#pragma mark - 电池

static BOOL XRHOpenBattery(void) {
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!h) return NO;
    pIOServiceGetMatchingService = dlsym(h, "IOServiceGetMatchingService");
    pIOServiceMatching = dlsym(h, "IOServiceMatching");
    pIORegistryEntryCreateCFProperty = dlsym(h, "IORegistryEntryCreateCFProperty");
    pIORegistryEntrySetCFProperties = dlsym(h, "IORegistryEntrySetCFProperties");
    if (!pIOServiceGetMatchingService || !pIOServiceMatching || !pIORegistryEntryCreateCFProperty || !pIORegistryEntrySetCFProperties) return NO;
    gBattery = pIOServiceGetMatchingService(0, pIOServiceMatching("AppleSmartBattery"));
    return gBattery != 0;
}

static double XRHBatteryNumber(NSString *key, double fallback) {
    id v = (__bridge_transfer id)pIORegistryEntryCreateCFProperty(gBattery, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : fallback;
}

static void XRHWriteState(int max, int resumeAt) {
    NSDictionary *state = @{@"inhibited": @(gInhibited), @"max": @(max), @"resumeAt": @(resumeAt),
                            @"time": @([NSDate date].timeIntervalSince1970), @"lastFull": @(gLastFull)};
    [state writeToFile:XRH_STATE_FILE atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:XRH_STATE_FILE error:nil];
}

static void XRHSetInhibit(BOOL inhibit, int max, int resumeAt, NSString *why) {
    NSDictionary *props = @{@"IsCharging": @YES, @"PredictiveChargingInhibit": @(inhibit)};
    kern_return_t kr = pIORegistryEntrySetCFProperties(gBattery, (__bridge CFTypeRef)props);
    gInhibited = inhibit;
    gInhibitMax = inhibit ? max : 0;
    gLastCommand = CFAbsoluteTimeGetCurrent();
    XRHWriteState(max, resumeAt);
    XRHLog(@"%@ (%@) kr=0x%x", inhibit ? @"停充" : @"恢复充电", why, kr);
}

#pragma mark - 偏好（读 mobile 用户的，插件和设置页写在那里）

static id XRHPref(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyValue((__bridge CFStringRef)key, XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
}

static BOOL XRHPrefBool(NSString *key, BOOL fallback) {
    id v = XRHPref(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}

static int XRHPrefInt(NSString *key, int fallback, int lo, int hi) {
    id v = XRHPref(key);
    int i = [v respondsToSelector:@selector(intValue)] ? [v intValue] : fallback;
    return MAX(lo, MIN(hi, i));
}

#pragma mark - 判断

static void XRHTick(NSString *reason) {
    CFPreferencesSynchronize(XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL enabled = XRHPrefBool(@"enabled", YES) && XRHPrefBool(@"chargeLimit", NO);
    int max = XRHPrefInt(@"chargeLimitMax", 80, 50, 100);
    int resumeAt = max - XRHPrefInt(@"chargeLimitGap", 5, 1, 40);

    BOOL connected = XRHBatteryNumber(@"ExternalConnected", 0) > 0;
    BOOL charging = XRHBatteryNumber(@"IsCharging", 0) > 0;
    double level = XRHBatteryNumber(@"CurrentCapacity", NAN);
    double amps = XRHBatteryNumber(@"InstantAmperage", 0);
    BOOL newPlug = connected && !gWasConnected;
    BOOL unplugged = !connected && gWasConnected;
    gWasConnected = connected;
    if (isnan(level)) return;

    // 充满了：记一下时间（每月充满提醒用）。每 6 小时最多写一次
    if ((level >= 100 || XRHBatteryNumber(@"FullyCharged", 0) > 0) && [NSDate date].timeIntervalSince1970 - gLastFull > 6 * 3600) {
        gLastFull = [NSDate date].timeIntervalSince1970;
        XRHWriteState(max, resumeAt);
        XRHLog(@"充满了，记下时间");
    }
    // 拔线：「这次充满」作废（SpringBoard 也会清，这里兜底，防止它没在跑）
    if (unplugged && XRHPrefBool(@"chargeLimitFullOnce", NO)) {
        CFPreferencesSetValue(CFSTR("chargeLimitFullOnce"), NULL, XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
        CFPreferencesSynchronize(XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
        XRHLog(@"拔线，「这次充满」作废");
    }

    if (!enabled) {
        if (gInhibited) XRHSetInhibit(NO, max, resumeAt, @"功能关了");
        return;
    }
    if (!connected) return;   // 没接电源时不用管，插上再说

    // 这次充满：不管上限
    if (XRHPrefBool(@"chargeLimitFullOnce", NO)) {
        if (gInhibited) XRHSetInhibit(NO, max, resumeAt, @"这次充满");
        return;
    }

    CFAbsoluteTime since = CFAbsoluteTimeGetCurrent() - gLastCommand;
    // 停充的线：充得快时提前 1%（见文件开头）
    int stopAt = (charging && amps > kXRHEarlyStopAmps) ? max - 1 : max;
    if (level >= stopAt) {
        if (!gInhibited) XRHSetInhibit(YES, max, resumeAt, [NSString stringWithFormat:@"电量 %.0f%% ≥ 停充线 %d%%（上限 %d%%，电流 %.0f mA）", level, stopAt, max, amps]);
        else if (charging && since > 90) XRHSetInhibit(YES, max, resumeAt, @"停着却又在充，再停一次");
    } else if (gInhibited) {
        if (level <= resumeAt) XRHSetInhibit(NO, max, resumeAt, [NSString stringWithFormat:@"电量 %.0f%% ≤ 恢复线 %d%%", level, resumeAt]);
        else if (max > gInhibitMax) XRHSetInhibit(NO, max, resumeAt, @"上限调高了");
        else if (newPlug) XRHSetInhibit(NO, max, resumeAt, @"重新插上电源");
    }
    (void)reason;
}

#pragma mark - 入口

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (!XRHOpenBattery()) {
            XRHLog(@"找不到 AppleSmartBattery，退出");
            return 1;
        }
        // prerm（卸载 / 升级前）调用：只恢复充电
        if (argc > 1 && strcmp(argv[1], "reset") == 0) {
            XRHSetInhibit(NO, 0, 0, @"reset 命令");
            return 0;
        }

        // 服务重启前我们是不是停着（属性在内存里，重启服务不会丢）
        NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:XRH_STATE_FILE];
        gInhibited = [old[@"inhibited"] boolValue];
        gInhibitMax = [old[@"max"] intValue];
        gLastFull = [old[@"lastFull"] doubleValue];
        if (gLastFull <= 0) gLastFull = [NSDate date].timeIntervalSince1970;   // 第一次运行：当作刚充满
        gWasConnected = XRHBatteryNumber(@"ExternalConnected", 0) > 0;
        XRHLog(@"启动 pid=%d，之前停充=%d", getpid(), gInhibited);
        {   // 启动时先写一份状态（带上 lastFull），插件读得到
            CFPreferencesSynchronize(XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
            int max = XRHPrefInt(@"chargeLimitMax", 80, 50, 100);
            XRHWriteState(max, max - XRHPrefInt(@"chargeLimitGap", 5, 1, 40));
        }

        // 退出信号：先恢复充电（卸载时 launchctl unload 会发 SIGTERM）
        signal(SIGTERM, SIG_IGN);
        dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(term, ^{
            if (gInhibited) XRHSetInhibit(NO, 0, 0, @"服务退出");
            XRHLog(@"退出");
            exit(0);
        });
        dispatch_resume(term);

        // 改设置、插拔电源时马上判断一次；平时每 20 秒看一次（只读几个属性）
        int token;
        notify_register_dispatch(XRH_NOTIFY, &token, dispatch_get_main_queue(), ^(int t) { XRHTick(@"改了设置"); });
        notify_register_dispatch("com.apple.system.powersources.source", &token, dispatch_get_main_queue(), ^(int t) { XRHTick(@"电源变了"); });
        notify_register_dispatch("com.apple.system.powersources.percent", &token, dispatch_get_main_queue(), ^(int t) { XRHTick(@"电量变了"); });
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 20 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ XRHTick(@"定时"); });
        dispatch_resume(timer);

        dispatch_main();
    }
}
