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
//   - 定时充满（chargeSchedule + chargeScheduleTime，几点几分换成一天里的第几分钟）：离充满时间不到 12 小时插着线时，
//     先按上限停着；到「充满时间 − 从上限充到 100% 要多久 − 15 分钟」开始充，之后这次插着线期间都不管上限（到点还没满也不会又停回上限），
//     拔线作废。要多久按插件记下的这个充电头的实际速度（rates.plist 的 tail，没有就用 fast × 0.35，再没有按每分钟 0.4%）
//
//   - 高温保护（thermalGuard）：充电时电池到 thermalTemp（无线充电用 thermalTempWireless，默认 37℃）就停充或间歇充电，降 3℃ 后恢复；优先于下面所有规则
//   - 边充边玩直充（bypassCharge）：接着电源、电量 ≥ 20%，整机功耗（PowerTelemetryData.SystemLoad）最近 1 分钟平均高于 bypassWatts（默认 4 W）
//     就停充，由电源直接供电；平均低于「设定值 − 1 W」1 分钟后恢复。上限已经停着时不用管
//
// 状态写给设置页 / 插件看：/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist
//   {inhibited, max, resumeAt, time, lastFull, schedStart, schedFull, schedActive, thermalHot, thermalStop, bypass, bypassStop}
//   （定时充满的开始 / 充满时间是 Unix 时间，不在时段里是 0；bypass = 正在直充，bypassStop = 这次停充是直充发的）
//
// 顺带记电量曲线（设置页「日志」画 24 小时曲线）：/var/mobile/Library/Caches/com.xyrith.xrhea.levels.plist，{levels: [[Unix 秒, 电量 %, 标记]…]}，
//   标记 1 接着电源 / 2 在充 / 4 灭屏。电量、标记变了记一笔，没变化时最多 10 分钟补一笔；保留 8 天。总开关关着时不记
//
// 耗电排行（设置页「日志 › 耗电排行」）：设置页发 com.xyrith.xrhea/drain-refresh 时，只读查一次系统的电池记录
//   /var/containers/Shared/SystemGroup/<UUID>/Library/BatteryLife/CurrentPowerlog.PLSQL（powerlogd 写，「设置 › 电池」用的同一份；2026-11-21 真机探测）：
//   - PLAccountingOperator_Aggregate_RootNodeEnergy：每小时一桶（timestamp 起、timeInterval 3600），每个 NodeID 在每个硬件（RootNodeID）上的耗电
//   - PLAccountingOperator_EventNone_Nodes：NodeID → 名字（App 的 bundle ID、系统进程名）；硬件本身（CPU、Display…）也是节点，排行里去掉
//   - PLDisplayAgent_EventPoint_Display（Block = Backlight，Active 0/1）：屏幕开关，用来挑出「锁屏时」的整小时（屏幕开着不到两成）
//   算最近 24 小时的总排行和锁屏时排行，写 /var/mobile/Library/Caches/com.xyrith.xrhea.drain.plist，
//   {time, all: [[名字, 耗电]…], locked: [[名字, 耗电]…], lockedHours}（耗电是系统的原始单位，设置页只按比例显示），然后发 com.xyrith.xrhea/drain-updated。
//   只读打开（SQLITE_OPEN_READONLY），每分钟最多查一次；表名、字段对不上就写一份空的（设置页隐藏这一项）
//   后台耗电提醒（bgDrainAlert，「优化」页）开着时每小时自己查一次：最近 3 个锁屏小时里，同一个第三方 App 每小时都占锁屏耗电的
//   bgDrainShare%（默认 30）以上，就在结果里带上 alert = {name, share, time}，并发 com.xyrith.xrhea/drain-alert（SpringBoard 弹提醒）
//   顺带：push = 最近 24 小时每小时推送重连次数（PLPushAgent_EventPoint_APSDConnectedEvent，pushFrom = 第一个小时的开始），
//   wakes = 最近 24 小时网络唤醒次数（PLNetworkAgent_EventPoint_Wake）。推送连接被代理 / VPN 掐断时会每小时重连几十次（2026-11-21 真机：平时 5～8 次）
//
// 每周小结（「提示」页「每周」）：SpringBoard 发 week-ask（上一周）/ week-preview（最近 7 天），算好写 week.plist 再发 week-done：
//   {mode: week / preview, from, to, charges（充电次数，来自 charges.plist）, standby（锁屏时每小时掉几 %，来自电量曲线）,
//    top: [耗电最多的几个名字]（系统电池记录）, pushBadDays（推送重连偏多的天数：一天里连续 3 小时每小时 > 15 次）}
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <notify.h>
#import <signal.h>
#import <sqlite3.h>

#define XRH_DOMAIN       CFSTR("com.xyrith.xrhea")
#define XRH_NOTIFY       "com.xyrith.xrhea/prefschanged"
#define XRH_STATE_FILE   @"/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist"
#define XRH_LOG_FILE     @"/var/mobile/Library/Caches/com.xyrith.xrhea.daemon.log"
#define XRH_RATES_FILE   @"/var/mobile/Library/Caches/com.xyrith.xrhea.rates.plist"   // 插件记下的实际充电速度（同 Shared/XRHKeys.h）
#define XRH_LEVELS_FILE  @"/var/mobile/Library/Caches/com.xyrith.xrhea.levels.plist"  // 电量曲线（同 Shared/XRHKeys.h），见 XRHLevelSample
#define XRH_DRAIN_FILE   @"/var/mobile/Library/Caches/com.xyrith.xrhea.drain.plist"   // 耗电排行（同 Shared/XRHKeys.h），见 XRHDrainRefresh
#define XRH_DRAIN_ASK    "com.xyrith.xrhea/drain-refresh"   // 设置页打开「日志」时发：重新算一次耗电排行
#define XRH_DRAIN_DONE   "com.xyrith.xrhea/drain-updated"   // 算完了，设置页重新读
#define XRH_DRAIN_ALERT  "com.xyrith.xrhea/drain-alert"     // 有 App 锁屏时耗电过多（SpringBoard 读 drain.plist 的 alert 弹提醒）
#define XRH_WEEK_FILE    @"/var/mobile/Library/Caches/com.xyrith.xrhea.week.plist"   // 每周小结（同 Shared/XRHKeys.h），见 XRHWeekQuery
#define XRH_WEEK_ASK     "com.xyrith.xrhea/week-ask"        // SpringBoard：算上一周（周一 0 点到这周一 0 点）
#define XRH_WEEK_PREVIEW "com.xyrith.xrhea/week-preview"    // SpringBoard「预览」：算最近 7 天
#define XRH_WEEK_DONE    "com.xyrith.xrhea/week-done"       // 算完了

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
static BOOL gSchedActive;          // 定时充满：已经到点开始充了（这次插着线期间不管上限）
static double gSchedStart, gSchedFull;   // 定时充满：算出来的开始充 / 充满时间（Unix 时间；不在时段里是 0）
static const double kXRHSchedBuffer = 15 * 60;   // 提前多开始充，宁可早满一点
// 高温保护（thermalGuard）：充电时电池 ≥ thermalTemp 就进入保护，降到 thermalTemp − 3 ℃ 以下解除。
// thermalMode 0 = 停充；1 = 间歇充电（默认；停 3 分钟、充 3 分钟交替，先停）。优先于充电上限 / 这次充满 / 定时充满
static BOOL gThermalHot;           // 在保护中（拔线清掉）
static BOOL gThermalInhibit;       // 当前这次停充是高温保护发的（解除时要恢复）
static double gThermalSince;       // 进入保护的时间（间歇充电按它算周期）
static const double kXRHThermalGap = 3, kXRHPulseSeconds = 180;
static BOOL gBypass;               // 边充边玩直充：正在直充
static BOOL gBypassInhibit;        // 当前这次停充是直充发的（结束时要恢复）
static NSMutableArray<NSArray *> *gLoads;   // 最近 1 分钟的整机功耗 [[时间, W]…]
static const double kXRHBypassWindow = 60, kXRHBypassGap = 1, kXRHBypassMinLevel = 20;

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

static id XRHBatteryObject(NSString *key) {
    return (__bridge_transfer id)pIORegistryEntryCreateCFProperty(gBattery, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
}

static BOOL XRHAdapterWireless(void) {
    NSDictionary *a = XRHBatteryObject(@"AdapterDetails");
    return [a isKindOfClass:[NSDictionary class]] && [a[@"IsWireless"] boolValue];
}

// 整机功耗 W（PowerTelemetryData.SystemLoad，mW）；读不到 NAN
static double XRHSystemLoad(void) {
    NSDictionary *t = XRHBatteryObject(@"PowerTelemetryData");
    id v = [t isKindOfClass:[NSDictionary class]] ? t[@"SystemLoad"] : nil;
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] / 1000 : NAN;
}

static void XRHWriteState(int max, int resumeAt) {
    NSDictionary *state = @{@"inhibited": @(gInhibited), @"max": @(max), @"resumeAt": @(resumeAt),
                            @"time": @([NSDate date].timeIntervalSince1970), @"lastFull": @(gLastFull),
                            @"schedStart": @(gSchedStart), @"schedFull": @(gSchedFull), @"schedActive": @(gSchedActive),
                            @"thermalHot": @(gThermalHot), @"thermalStop": @(gThermalInhibit),
                            @"bypass": @(gBypass), @"bypassStop": @(gBypassInhibit)};
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

static double XRHPrefDouble(NSString *key, double fallback, double lo, double hi) {
    id v = XRHPref(key);
    double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
    return MAX(lo, MIN(hi, d));
}

#pragma mark - 定时充满

// 从 from% 充到 100% 要几分钟：按插件记下的这个充电头 80% 后的速度
static double XRHMinutesToFull(double from) {
    NSDictionary *details = (__bridge_transfer id)pIORegistryEntryCreateCFProperty(gBattery, CFSTR("AdapterDetails"), kCFAllocatorDefault, 0);
    double tail = 0;
    if ([details isKindOfClass:[NSDictionary class]]) {
        double w = [details[@"Watts"] doubleValue];
        NSString *key = [NSString stringWithFormat:[details[@"IsWireless"] boolValue] ? @"无线%.0fW" : @"%.0fW", w];
        NSDictionary *r = [NSDictionary dictionaryWithContentsOfFile:XRH_RATES_FILE][key];
        if ([r isKindOfClass:[NSDictionary class]]) tail = [r[@"tail"] doubleValue] ?: [r[@"fast"] doubleValue] * 0.35;
    }
    if (tail <= 0) tail = 0.4;
    return MAX(0, 100 - from) / tail;
}

// 下一个「几点几分」（今天还没到就是今天，过了就是明天）
static NSDate *XRHNextTime(int minuteOfDay) {
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *now = [NSDate date];
    NSDate *t = [cal dateBySettingHour:minuteOfDay / 60 minute:minuteOfDay % 60 second:0 ofDate:now options:0];
    return [t compare:now] == NSOrderedDescending ? t : [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:t options:0];
}

// 定时充满：算开始 / 充满时间，到点了就标记成「这次不管上限」。返回 YES = 现在该放开充
static BOOL XRHScheduleTick(BOOL connected, double level, int max, int resumeAt) {
    double start = 0, full = 0;
    if (!connected) gSchedActive = NO;
    if (connected && XRHPrefBool(@"chargeSchedule", NO) && !gSchedActive) {
        NSDate *next = XRHNextTime(XRHPrefInt(@"chargeScheduleTime", 7 * 60, 0, 24 * 60 - 1));
        double now = [NSDate date].timeIntervalSince1970, fullAt = next.timeIntervalSince1970;
        if (fullAt - now <= 12 * 3600) {
            full = fullAt;
            start = fullAt - XRHMinutesToFull(MAX(level, max)) * 60 - kXRHSchedBuffer;
            if (now >= start) {
                gSchedActive = YES;
                gSchedStart = start;   // 到点这一刻按新算的写一次（插件靠 schedActive 判断已经开始充）
                gSchedFull = full;
                XRHWriteState(max, resumeAt);
                XRHLog(@"定时充满：到点开始充（%.0f%%，%@ 前充满）", level, next);
            }
        }
    }
    if (gSchedActive) { start = gSchedStart; full = gSchedFull; }
    if (fabs(start - gSchedStart) > 30 || fabs(full - gSchedFull) > 30) {   // 变了才写状态（开始时间会随电量微调）
        gSchedStart = start;
        gSchedFull = full;
        XRHWriteState(max, resumeAt);
    }
    return gSchedActive;
}

#pragma mark - 高温保护

// 返回 YES = 现在因为高温该停着
static BOOL XRHThermalTick(BOOL connected, double temp, int max, int resumeAt) {
    BOOL wasHot = gThermalHot;
    if (!connected || !XRHPrefBool(@"enabled", YES) || !XRHPrefBool(@"thermalGuard", NO) || isnan(temp)) gThermalHot = NO;
    else {
        int limit = XRHAdapterWireless() ? XRHPrefInt(@"thermalTempWireless", 37, 30, 50) : XRHPrefInt(@"thermalTemp", 40, 30, 50);
        if (!gThermalHot && temp >= limit) {
            gThermalHot = YES;
            gThermalSince = [NSDate date].timeIntervalSince1970;
            XRHLog(@"高温保护：%.1f℃ ≥ %d℃，%@", temp, limit, XRHPrefInt(@"thermalMode", 1, 0, 1) ? @"间歇充电" : @"停充");
        } else if (gThermalHot && temp <= limit - kXRHThermalGap) {
            gThermalHot = NO;
            XRHLog(@"高温保护解除：%.1f℃", temp);
        }
    }
    if (wasHot != gThermalHot) XRHWriteState(max, resumeAt);
    if (!gThermalHot) return NO;
    if (XRHPrefInt(@"thermalMode", 1, 0, 1) == 0) return YES;
    long phase = (long)(([NSDate date].timeIntervalSince1970 - gThermalSince) / kXRHPulseSeconds);
    return phase % 2 == 0;   // 偶数段停、奇数段充
}

#pragma mark - 边充边玩直充

// 返回 YES = 现在该直充（停止给电池充电，电源直接供电）。用最近 1 分钟的平均功耗判断，免得游戏里忽高忽低来回切
static BOOL XRHBypassTick(BOOL connected, double level, int max, int resumeAt) {
    BOOL was = gBypass;
    double now = [NSDate date].timeIntervalSince1970;
    if (!gLoads) gLoads = [NSMutableArray array];
    if (!connected || !XRHPrefBool(@"enabled", YES) || !XRHPrefBool(@"bypassCharge", NO) || isnan(level) || (!gBypass && level < kXRHBypassMinLevel)) {
        gBypass = NO;
        [gLoads removeAllObjects];
    } else {
        double load = XRHSystemLoad();
        if (!isnan(load)) [gLoads addObject:@[@(now), @(load)]];
        while (gLoads.count && now - [gLoads.firstObject[0] doubleValue] > kXRHBypassWindow + 15) [gLoads removeObjectAtIndex:0];
        // 攒够 1 分钟的读数才判断（每 20 秒一笔，至少 3 笔）
        if (gLoads.count >= 3 && now - [gLoads.firstObject[0] doubleValue] >= kXRHBypassWindow - 5) {
            double sum = 0;
            for (NSArray *l in gLoads) sum += [l[1] doubleValue];
            double avg = sum / gLoads.count, limit = XRHPrefDouble(@"bypassWatts", 4, 2, 10);
            if (!gBypass && avg > limit) { gBypass = YES; XRHLog(@"直充：1 分钟平均 %.1f W > %.1f W", avg, limit); }
            else if (gBypass && avg < limit - kXRHBypassGap) { gBypass = NO; XRHLog(@"直充结束：1 分钟平均 %.1f W", avg); }
        }
    }
    if (was != gBypass) XRHWriteState(max, resumeAt);
    return gBypass;
}

#pragma mark - 耗电排行（读系统电池记录）

static NSString *XRHPowerlogPath(void) {
    NSString *root = @"/var/containers/Shared/SystemGroup";
    for (NSString *uuid in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
        NSString *p = [NSString stringWithFormat:@"%@/%@/Library/BatteryLife/CurrentPowerlog.PLSQL", root, uuid];
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return nil;
}

// 屏幕在 [from, to) 里开着的比例。events：[[时间, 开着?]…] 按时间排好，第一条是 from 之前最后一次变化
static double XRHScreenOnShare(NSArray<NSArray *> *events, double from, double to) {
    if (to <= from) return 0;
    double on = 0, t = from;
    BOOL state = NO;
    for (NSArray *e in events) {
        double et = [e[0] doubleValue];
        if (et <= from) { state = [e[1] boolValue]; continue; }
        if (et >= to) break;
        if (state) on += et - t;
        t = et;
        state = [e[1] boolValue];
    }
    if (state) on += to - t;
    return on / (to - from);
}

static NSArray *XRHTopList(NSDictionary<NSString *, NSNumber *> *energy) {
    NSArray *names = [energy keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        if (out.count >= 60 || [energy[n] doubleValue] <= 0) break;
        [out addObject:@[n, @(lround([energy[n] doubleValue]))]];
    }
    return out;
}

// 返回一句给日志的话（在后台队列跑，日志由主线程写）
static NSString *XRHDrainQuery(void) {
    NSString *note;
    double now = [NSDate date].timeIntervalSince1970, from = now - 24 * 3600;
    NSMutableDictionary *result = [@{@"time": @(now), @"all": @[], @"locked": @[], @"lockedHours": @0} mutableCopy];
    NSString *path = XRHPowerlogPath();
    sqlite3 *db = NULL;
    if (path && sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        sqlite3_busy_timeout(db, 3000);
        sqlite3_stmt *st = NULL;
        // 屏幕开关：from 之前最后一次 + 之后的每次
        NSMutableArray *screen = [NSMutableArray array];
        const char *sqlScreen = "SELECT timestamp, Active FROM PLDisplayAgent_EventPoint_Display WHERE Block = 'Backlight' AND timestamp >= "
                                "(SELECT IFNULL(MAX(timestamp), 0) FROM PLDisplayAgent_EventPoint_Display WHERE Block = 'Backlight' AND timestamp < ?1) ORDER BY timestamp";
        if (sqlite3_prepare_v2(db, sqlScreen, -1, &st, NULL) == SQLITE_OK) {
            sqlite3_bind_double(st, 1, from);
            while (sqlite3_step(st) == SQLITE_ROW) [screen addObject:@[@(sqlite3_column_double(st, 0)), @(sqlite3_column_int(st, 1) != 0)]];
        }
        sqlite3_finalize(st);
        // 每小时每个节点的耗电（去掉硬件节点）
        const char *sqlEnergy = "SELECT e.timestamp, e.timeInterval, e.Energy, n.Name FROM PLAccountingOperator_Aggregate_RootNodeEnergy e "
                                "JOIN PLAccountingOperator_EventNone_Nodes n ON n.ID = e.NodeID "
                                "WHERE e.timestamp + e.timeInterval > ?1 AND n.Name != '__GLOBAL__' "
                                "AND e.NodeID NOT IN (SELECT DISTINCT RootNodeID FROM PLAccountingOperator_Aggregate_RootNodeEnergy)";
        NSMutableDictionary<NSString *, NSNumber *> *all = [NSMutableDictionary dictionary], *locked = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber *, NSNumber *> *bucketLocked = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber *, NSMutableDictionary *> *lockedByBucket = [NSMutableDictionary dictionary];   // 后台耗电提醒用：每个锁屏小时各进程的耗电
        int rows = 0;
        if (sqlite3_prepare_v2(db, sqlEnergy, -1, &st, NULL) == SQLITE_OK) {
            sqlite3_bind_double(st, 1, from);
            while (sqlite3_step(st) == SQLITE_ROW) {
                double ts = sqlite3_column_double(st, 0), len = sqlite3_column_double(st, 1), e = sqlite3_column_double(st, 2);
                const unsigned char *name = sqlite3_column_text(st, 3);
                if (!name || e <= 0) continue;
                rows++;
                NSString *n = [NSString stringWithUTF8String:(const char *)name];
                all[n] = @([all[n] doubleValue] + e);
                NSNumber *key = @(lround(ts));
                if (!bucketLocked[key]) bucketLocked[key] = @(screen.count > 0 && XRHScreenOnShare(screen, MAX(ts, from), MIN(ts + MAX(len, 1), now)) < 0.2);
                if ([bucketLocked[key] boolValue]) {
                    locked[n] = @([locked[n] doubleValue] + e);
                    NSMutableDictionary *b = lockedByBucket[key] ?: (lockedByBucket[key] = [NSMutableDictionary dictionary]);
                    b[n] = @([b[n] doubleValue] + e);
                }
            }
        } else {
            note = [NSString stringWithFormat:@"耗电排行：查询失败 %s", sqlite3_errmsg(db)];
        }
        sqlite3_finalize(st);
        // 推送重连：最近 24 小时每小时几次（第 0 个是 23 小时前开始的那一小时，最后一个是现在这一小时）
        double hour0 = floor(now / 3600) * 3600 - 23 * 3600;
        NSMutableArray *push = [NSMutableArray array];
        for (int i = 0; i < 24; i++) [push addObject:@0];
        if (sqlite3_prepare_v2(db, "SELECT CAST((timestamp - ?1) / 3600 AS INTEGER), COUNT(*) FROM PLPushAgent_EventPoint_APSDConnectedEvent "
                                   "WHERE timestamp >= ?1 GROUP BY 1", -1, &st, NULL) == SQLITE_OK) {
            sqlite3_bind_double(st, 1, hour0);
            while (sqlite3_step(st) == SQLITE_ROW) {
                int i = sqlite3_column_int(st, 0);
                if (i >= 0 && i < 24) push[i] = @(sqlite3_column_int(st, 1));
            }
            result[@"push"] = push;
            result[@"pushFrom"] = @(hour0);
        }
        sqlite3_finalize(st);
        // 网络唤醒：最近 24 小时
        if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM PLNetworkAgent_EventPoint_Wake WHERE timestamp >= ?1", -1, &st, NULL) == SQLITE_OK) {
            sqlite3_bind_double(st, 1, from);
            if (sqlite3_step(st) == SQLITE_ROW) result[@"wakes"] = @(sqlite3_column_int(st, 0));
        }
        sqlite3_finalize(st);
        sqlite3_close(db);
        int lockedHours = 0;
        for (NSNumber *v in bucketLocked.allValues) lockedHours += v.boolValue;
        result[@"all"] = XRHTopList(all);
        result[@"locked"] = XRHTopList(locked);
        result[@"lockedHours"] = @(lockedHours);
        // 后台耗电提醒：最近 3 个锁屏小时，第三方 App（不是 com.apple. 开头、带点的 bundle ID）每小时都超过设定占比
        NSArray<NSNumber *> *keys = [lockedByBucket.allKeys sortedArrayUsingSelector:@selector(compare:)];
        if (XRHPrefBool(@"bgDrainAlert", NO) && keys.count >= 3) {
            double need = XRHPrefInt(@"bgDrainShare", 30, 20, 60) / 100.0;
            NSArray *last3 = [keys subarrayWithRange:NSMakeRange(keys.count - 3, 3)];
            NSString *best = nil;
            double bestShare = 0;
            for (NSString *n in lockedByBucket[last3.lastObject]) {
                if (![n containsString:@"."] || [n hasPrefix:@"com.apple."]) continue;
                double minShare = 1;
                for (NSNumber *k in last3) {
                    double total = 0;
                    for (NSNumber *v in lockedByBucket[k].allValues) total += v.doubleValue;
                    minShare = MIN(minShare, total > 0 ? [lockedByBucket[k][n] doubleValue] / total : 0);
                }
                if (minShare >= need && minShare > bestShare) { best = n; bestShare = minShare; }
            }
            if (best) result[@"alert"] = @{@"name": best, @"share": @(bestShare), @"time": last3.lastObject};
        }
        if (!note) note = [NSString stringWithFormat:@"耗电排行：%d 行，%lu 个进程，锁屏小时 %d，屏幕事件 %lu", rows, (unsigned long)all.count, lockedHours, (unsigned long)screen.count];
    } else {
        note = [NSString stringWithFormat:@"耗电排行：打不开电池记录 %@", path ?: @"（没找到）"];
        if (db) sqlite3_close(db);
    }
    [result writeToFile:XRH_DRAIN_FILE atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:XRH_DRAIN_FILE error:nil];
    return note;
}

#pragma mark - 每周小结

// 一天里有没有连续 3 小时推送重连每小时 > 15 次
static BOOL XRHPushBadRun(NSArray<NSNumber *> *counts) {
    int run = 0;
    for (NSNumber *c in counts) {
        run = c.intValue > 15 ? run + 1 : 0;
        if (run >= 3) return YES;
    }
    return NO;
}

// rolling = 最近 7 天（「预览」）；否则上一周（周一 0 点到这周一 0 点）。在后台队列跑，返回给日志的一句话
static NSString *XRHWeekQuery(BOOL rolling) {
    double now = [NSDate date].timeIntervalSince1970, from, to;
    if (rolling) { to = now; from = now - 7 * 86400; }
    else {
        NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        cal.firstWeekday = 2;   // 周一开头
        NSDate *start = nil;
        [cal rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&start interval:NULL forDate:[NSDate date]];
        to = start.timeIntervalSince1970;
        from = to - 7 * 86400;
    }
    NSMutableDictionary *w = [@{@"mode": rolling ? @"preview" : @"week", @"from": @(from), @"to": @(to), @"time": @(now)} mutableCopy];

    // 充电次数
    int charges = 0;
    for (NSDictionary *r in [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Caches/com.xyrith.xrhea.charges.plist"][@"records"]) {
        double t = [r[@"start"] doubleValue];
        if (t >= from && t < to) charges++;
    }
    w[@"charges"] = @(charges);

    // 锁屏时平均每小时掉多少：电量曲线里灭屏、没接电源的时段（每段至少 10 分钟）
    NSArray<NSArray *> *pts = [NSDictionary dictionaryWithContentsOfFile:XRH_LEVELS_FILE][@"levels"];
    double drop = 0, hours = 0;
    for (NSUInteger i = 0; i < pts.count;) {
        int f = [pts[i][2] intValue];
        if (!((f & 4) && !(f & 1))) { i++; continue; }
        NSUInteger j = i;
        while (j < pts.count && ([pts[j][2] intValue] & 4) && !([pts[j][2] intValue] & 1)) j++;
        double t0 = MAX([pts[i][0] doubleValue], from), t1 = MIN(j < pts.count ? [pts[j][0] doubleValue] : now, to);
        if (t1 - t0 >= 600) { hours += (t1 - t0) / 3600; drop += MAX([pts[i][1] doubleValue] - [pts[MIN(j, pts.count - 1)][1] doubleValue], 0); }
        i = j;
    }
    if (hours >= 1) w[@"standby"] = @(round(drop / hours * 10) / 10);

    // 耗电最多、推送重连偏多的天数（系统电池记录）
    NSString *path = XRHPowerlogPath();
    sqlite3 *db = NULL;
    if (path && sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        sqlite3_busy_timeout(db, 3000);
        sqlite3_stmt *st = NULL;
        NSMutableArray *top = [NSMutableArray array];
        if (sqlite3_prepare_v2(db, "SELECT n.Name, SUM(e.Energy) s FROM PLAccountingOperator_Aggregate_RootNodeEnergy e "
                                   "JOIN PLAccountingOperator_EventNone_Nodes n ON n.ID = e.NodeID "
                                   "WHERE e.timestamp >= ?1 AND e.timestamp < ?2 AND n.Name != '__GLOBAL__' "
                                   "AND e.NodeID NOT IN (SELECT DISTINCT RootNodeID FROM PLAccountingOperator_Aggregate_RootNodeEnergy) "
                                   "GROUP BY e.NodeID ORDER BY s DESC LIMIT 10", -1, &st, NULL) == SQLITE_OK) {
            sqlite3_bind_double(st, 1, from);
            sqlite3_bind_double(st, 2, to);
            while (sqlite3_step(st) == SQLITE_ROW) {
                const unsigned char *n = sqlite3_column_text(st, 0);
                if (n) [top addObject:[NSString stringWithUTF8String:(const char *)n]];
            }
        }
        sqlite3_finalize(st);
        w[@"top"] = top;
        NSMutableArray *hourly = [NSMutableArray array];
        for (int i = 0; i < 7 * 24; i++) [hourly addObject:@0];
        if (sqlite3_prepare_v2(db, "SELECT CAST((timestamp - ?1) / 3600 AS INTEGER), COUNT(*) FROM PLPushAgent_EventPoint_APSDConnectedEvent "
                                   "WHERE timestamp >= ?1 AND timestamp < ?2 GROUP BY 1", -1, &st, NULL) == SQLITE_OK) {
            sqlite3_bind_double(st, 1, from);
            sqlite3_bind_double(st, 2, to);
            while (sqlite3_step(st) == SQLITE_ROW) {
                int i = sqlite3_column_int(st, 0);
                if (i >= 0 && i < 7 * 24) hourly[i] = @(sqlite3_column_int(st, 1));
            }
            int bad = 0;
            for (int d = 0; d < 7; d++) bad += XRHPushBadRun([hourly subarrayWithRange:NSMakeRange(d * 24, 24)]);
            w[@"pushBadDays"] = @(bad);
        }
        sqlite3_finalize(st);
        sqlite3_close(db);
    }
    [w writeToFile:XRH_WEEK_FILE atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:XRH_WEEK_FILE error:nil];
    return [NSString stringWithFormat:@"每周小结（%@）：充电 %d 次，待机 %@，最多 %@，推送偏多 %@ 天", rolling ? @"最近 7 天" : @"上一周",
            charges, w[@"standby"] ?: @"—", [w[@"top"] firstObject] ?: @"—", w[@"pushBadDays"] ?: @"—"];
}

static void XRHWeekRefresh(BOOL rolling) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *note;
        @autoreleasepool { note = XRHWeekQuery(rolling); }
        dispatch_async(dispatch_get_main_queue(), ^{
            XRHLog(@"%@", note);
            notify_post(XRH_WEEK_DONE);
        });
    });
}

// 设置页要的时候查（在后台队列，不耽误停充判断）；每分钟最多一次，太勤就直接告诉它「好了」，让它读上次的。
// 查完带了后台耗电提醒、而且是新的一个锁屏小时，就发 drain-alert
static void XRHDrainRefresh(void) {
    static double last, lastAlert;
    static BOOL running;
    double now = [NSDate date].timeIntervalSince1970;
    if (running) return;
    if (now - last < 60 || !XRHPrefBool(@"enabled", YES)) { notify_post(XRH_DRAIN_DONE); return; }
    last = now;
    running = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *note;
        @autoreleasepool { note = XRHDrainQuery(); }
        dispatch_async(dispatch_get_main_queue(), ^{
            running = NO;
            XRHLog(@"%@", note);
            notify_post(XRH_DRAIN_DONE);
            NSDictionary *alert = [NSDictionary dictionaryWithContentsOfFile:XRH_DRAIN_FILE][@"alert"];
            if ([alert isKindOfClass:[NSDictionary class]] && [alert[@"time"] doubleValue] > lastAlert) {
                lastAlert = [alert[@"time"] doubleValue];
                XRHLog(@"后台耗电提醒：%@ 占 %.0f%%", alert[@"name"], [alert[@"share"] doubleValue] * 100);
                notify_post(XRH_DRAIN_ALERT);
            }
        });
    });
}

#pragma mark - 电量曲线

static NSMutableArray<NSArray *> *gLevels;
static int gBlankToken = -1;
static const double kXRHLevelKeep = 8 * 24 * 3600, kXRHLevelEvery = 10 * 60;   // 8 天：周一早上算上一整周也够

static void XRHLevelSample(void) {
    if (!XRHPrefBool(@"enabled", YES)) return;
    double level = XRHBatteryNumber(@"CurrentCapacity", NAN);
    if (isnan(level)) return;
    uint64_t blanked = 0;
    if (gBlankToken >= 0) notify_get_state(gBlankToken, &blanked);
    int flags = (XRHBatteryNumber(@"ExternalConnected", 0) > 0 ? 1 : 0) | (XRHBatteryNumber(@"IsCharging", 0) > 0 ? 2 : 0) | (blanked ? 4 : 0);
    double now = [NSDate date].timeIntervalSince1970;
    if (!gLevels) {
        NSArray *saved = [NSDictionary dictionaryWithContentsOfFile:XRH_LEVELS_FILE][@"levels"];
        gLevels = [saved isKindOfClass:[NSArray class]] ? [saved mutableCopy] : [NSMutableArray array];
    }
    NSArray *last = gLevels.lastObject;
    if (last && [last[1] intValue] == lround(level) && [last[2] intValue] == flags && now - [last[0] doubleValue] < kXRHLevelEvery) return;
    [gLevels addObject:@[@(lround(now)), @(lround(level)), @(flags)]];
    NSUInteger old = 0;
    while (old < gLevels.count && [gLevels[old][0] doubleValue] < now - kXRHLevelKeep) old++;
    if (old) [gLevels removeObjectsInRange:NSMakeRange(0, old)];
    [@{@"levels": gLevels} writeToFile:XRH_LEVELS_FILE atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:XRH_LEVELS_FILE error:nil];
}

#pragma mark - 判断（插拔、电量变化、改设置、每 20 秒）

static void XRHTick(NSString *reason) {
    CFPreferencesSynchronize(XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL enabled = XRHPrefBool(@"enabled", YES) && XRHPrefBool(@"chargeLimit", NO);
    int max = XRHPrefInt(@"chargeLimitMax", 80, 50, 100);
    int resumeAt = max - XRHPrefInt(@"chargeLimitGap", 5, 1, 40);
    XRHLevelSample();
    // 后台耗电提醒开着：每小时自己查一次耗电排行
    static double lastDrainCheck;
    if (XRHPrefBool(@"bgDrainAlert", NO) && [NSDate date].timeIntervalSince1970 - lastDrainCheck >= 3600) {
        lastDrainCheck = [NSDate date].timeIntervalSince1970;
        XRHDrainRefresh();
    }

    BOOL connected = XRHBatteryNumber(@"ExternalConnected", 0) > 0;
    BOOL charging = XRHBatteryNumber(@"IsCharging", 0) > 0;
    double level = XRHBatteryNumber(@"CurrentCapacity", NAN);
    double amps = XRHBatteryNumber(@"InstantAmperage", 0);
    BOOL newPlug = connected && !gWasConnected;
    BOOL unplugged = !connected && gWasConnected;
    gWasConnected = connected;
    if (isnan(level)) return;

    // 高温保护：该停就停（不管上限开没开）；解除或间歇到「充」的那段时，先恢复，再走下面的上限判断
    double temp = XRHBatteryNumber(@"Temperature", NAN) / 100.0;
    if (XRHThermalTick(connected, temp, max, resumeAt)) {
        CFAbsoluteTime since = CFAbsoluteTimeGetCurrent() - gLastCommand;
        if (!gInhibited) { gThermalInhibit = YES; XRHSetInhibit(YES, max, resumeAt, [NSString stringWithFormat:@"高温保护 %.1f℃", temp]); }
        else if (charging && since > 90) XRHSetInhibit(YES, max, resumeAt, @"高温保护：停着却又在充，再停一次");
        return;
    }
    BOOL bypass = XRHBypassTick(connected, level, max, resumeAt);
    if (gThermalInhibit) {
        gThermalInhibit = NO;
        if (bypass) gBypassInhibit = YES;   // 正好要直充：接着停着，算直充的
        else if (gInhibited) XRHSetInhibit(NO, max, resumeAt, gThermalHot ? @"间歇充电：充" : @"高温保护结束");
    }
    // 边充边玩直充：上限已经停着就不用管（那次停充还是上限的）
    if (bypass) {
        CFAbsoluteTime since = CFAbsoluteTimeGetCurrent() - gLastCommand;
        if (!gInhibited) { gBypassInhibit = YES; XRHSetInhibit(YES, max, resumeAt, [NSString stringWithFormat:@"边充边玩直充 %.1f W", XRHSystemLoad()]); }
        else if (charging && since > 90) XRHSetInhibit(YES, max, resumeAt, @"直充：停着却又在充，再停一次");
        return;
    }
    if (gBypassInhibit) {
        gBypassInhibit = NO;
        if (gInhibited) XRHSetInhibit(NO, max, resumeAt, @"直充结束");
    }

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
        XRHScheduleTick(NO, level, max, resumeAt);
        return;
    }
    if (!connected) { XRHScheduleTick(NO, level, max, resumeAt); return; }   // 没接电源时不用管，插上再说

    // 这次充满：不管上限
    if (XRHPrefBool(@"chargeLimitFullOnce", NO)) {
        if (gInhibited) XRHSetInhibit(NO, max, resumeAt, @"这次充满");
        return;
    }
    // 定时充满：到点了就放开充（没到点照常按上限停着）
    if (XRHScheduleTick(connected, level, max, resumeAt)) {
        if (gInhibited) XRHSetInhibit(NO, max, resumeAt, @"定时充满开始");
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
        notify_register_dispatch(XRH_WEEK_ASK, &token, dispatch_get_main_queue(), ^(int t) { XRHWeekRefresh(NO); });
        notify_register_dispatch(XRH_WEEK_PREVIEW, &token, dispatch_get_main_queue(), ^(int t) { XRHWeekRefresh(YES); });
        notify_register_dispatch(XRH_DRAIN_ASK, &token, dispatch_get_main_queue(), ^(int t) {
            CFPreferencesSynchronize(XRH_DOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
            XRHDrainRefresh();
        });
        // 亮灭屏：电量曲线上标出锁屏的时段
        notify_register_check("com.apple.springboard.hasBlankedScreen", &gBlankToken);
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &token, dispatch_get_main_queue(), ^(int t) { XRHLevelSample(); });
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 20 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ XRHTick(@"定时"); });
        dispatch_resume(timer);

        dispatch_main();
    }
}
