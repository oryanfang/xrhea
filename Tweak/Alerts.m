// 提醒：在 SpringBoard 里按条件判断，用 Toast.m 的提示弹出来。每条在「设置 › xrhea › 提示」里单独开关，后面的「预览」
// 用手机此刻的数据弹一次（XRHTryAlert）。显示的内容（灵动岛长条的左字右值、短条的短值、横幅的两行字）在各条的 XRHShowXxx 里。
//
//   充电  1 插电：插上后等电流稳了（最多 25 秒）、等插电弹窗关掉；显示充电头送进来的功率（同 USB 数显线），横幅带预计时间
//           预计时间优先用「记住的充电速度」：每次充完按充电头记下 80% 前 / 后实际每分钟充几 %（XRH_RATES_FILE）
//           定时充满在等着时（xrhead 状态文件 schedFull > 0、还没开始充）改弹「定时充满 ｜ 7:00」
//        13 到点（默认关）：充到自己设的电量（alertTargetLevel，默认 90%）提醒，不停充
//         2 停充：充电上限停充了（xrhead 状态文件 inhibited 从 0 变 1），显示停下时的实际电量（可能比上限少 1%）
//        17 直充：边充边玩直充开始时（xrhead 状态文件 bypass 从 0 变 1），显示整机功耗；恢复充电时不弹
//         7 充满：没开上限、充到 100%（插上时已满不算）
//         5 总结：拔线时，插了 ≥ 1 分钟、充了 ≥ 1%
//   异常  3 慢充：插上 45 秒后，有线、在充、电量 < 80%，只跑 5 V 或功率连续 30 秒 < 5 W
//         8 降速：插着电时 ChargerData.TimeChargingThermallyLimited 在涨（系统因过热限流）
//        12 接触不良：1 分钟内拔线 ≥ 3 次（这时不弹拔线总结）
//        14 中断：插上 30 秒后，连续 30 秒插着电却没在充（不是上限停的、没充满、电量 < 79%、ChargerData.NotChargingReason ≠ 0）
//         4 过热：≥ 40 ℃ 偏热、≥ 45 ℃ 过热；降到 38 ℃ 以下才会再弹（偏热升到过热算新的一次）
//        11 低温：充电时电池 < 5 ℃；升到 8 ℃ 以上才会再弹
//   用电  9 待机耗电：锁屏 ≥ 半小时、期间没接过电源、掉 ≥ 3% 且每小时 > 3%，亮屏时弹
//        10 睡前：22～2 点、没插线、电量 < 30%，每晚一次
//         6 高耗电（默认关）：用电池、亮屏时 1 分钟平均功率 > 6 W
//        15 后台耗电（默认关，开关在「优化」页）：xrhead 发 com.xyrith.xrhea/drain-alert（某个第三方 App 连续 3 个锁屏小时占锁屏耗电过多），
//           亮屏时弹；同一个 App 每天最多一次
//        16 每周（默认关）：周一 9:00 以后第一次亮屏时，让 xrhead 算上一周（week-ask → week-done），弹「上周：充电 12 次 · 待机 0.9%/时」，
//           点开是「日志」页；每周一次（记在偏好 weeklyShown）。「预览」算最近 7 天
// 不做：低电量（系统自己有）；健康度下降（容量一点点往下掉是正常老化，频繁提醒只会让人焦虑）。
//
// 防打扰：同一种 30 分钟内只弹一次；插电、停充、慢充、降速、充满、到点、中断每次插拔最多一次。
// 专注模式（勿扰、睡眠等）开着时不弹，哪几条照常弹自己选（focusAllow.<键>，默认只有过热、低温）；被挡掉的不占冷却。
// 读数频率：接着电源时 5 秒一次，用电池时 10 秒一次，灭屏时不读（每次只读几个键，见 XRBattery.m）。
#import "XRHCommon.h"
#import <notify.h>
#import <dlfcn.h>

static const NSTimeInterval kXRHAlertCooldown = 30 * 60;   // 同一种提醒的最短间隔
static const double kXRHHotWarn = 40, kXRHHotSevere = 45, kXRHHotRearm = 38;
static const double kXRHSlowWatts = 5, kXRHDrainWatts = 6;

// 顺序 = 设置页「预览」的编号 - 1（com.xyrith.xrhea/try-alert-1 … -14），新的只往后加
typedef NS_ENUM(NSInteger, XRHAlert) { XRHAlertPlugIn, XRHAlertLimit, XRHAlertSlow, XRHAlertHot, XRHAlertUnplug, XRHAlertDrain,
                                       XRHAlertFull, XRHAlertThrottle, XRHAlertStandby,
                                       XRHAlertBedtime, XRHAlertCold, XRHAlertFlaky, XRHAlertTarget, XRHAlertStopped, XRHAlertBgDrain, XRHAlertWeekly, XRHAlertBypass, XRHAlertCount };

static NSTimeInterval gLastShown[XRHAlertCount];
static dispatch_source_t gTimer;
static NSTimeInterval gTimerInterval;
static int gBlankToken = -1;

// 这次插着电源期间的状态（拔线清空）
static BOOL gConnected;
static double gPlugLevel = NAN;                 // 插上时的电量
static NSTimeInterval gPlugTime;
static BOOL gShownThisPlug[XRHAlertCount];
static BOOL gWasInhibited;                      // 上一次读到的「已停充」
static NSMutableArray<NSNumber *> *gWatts;      // 最近几次的功率（接电源时判断充电慢，用电池时判断耗电快）
static NSMutableArray<NSNumber *> *gAmps;       // 最近几次的电流（耗电快时估还能用多久）
static int gHotLevel;                           // 0 正常 / 1 已弹过偏热 / 2 已弹过过热
static double gLastGained = NAN, gLastMinutes = NAN, gLastLevel = NAN;   // 上次拔线的总结（「预览」没插着线时用）
static double gThermalBase = NAN;               // 7 降速：ChargerData.TimeChargingThermallyLimited 上次读到的值（涨了 = 正在因过热限流）
static double gBlankLevel = NAN;                // 9 待机：灭屏时的电量
static NSTimeInterval gBlankTime;               //        灭屏时间（0 = 没在记）
static BOOL gBlankPlugged;                      //        这段锁屏期间接过电源（接过就不算）
static double gLastStandbyDrop = NAN, gLastStandbyHours = NAN;   // 上次锁屏的掉电记录（「预览」用）
static const double kXRHStandbyRate = 3;        // 每小时掉多少 % 算快
static NSString *gBedtimeNight;                 // 10 睡前：已经提醒过的那一晚（yyyy-MM-dd，0～2 点算前一天）
static const double kXRHBedtimeLevel = 30, kXRHColdWarn = 5, kXRHColdRearm = 8;
static BOOL gColdShown;                         // 11 低温：弹过了，升到 8 ℃ 以上才会再弹
static NSMutableArray<NSNumber *> *gUnplugTimes;   // 12 接触：最近的拔线时间
static int gStoppedTicks;                       // 14 中断：连续几次读到「插着却不充」

// 记住实际充电速度（插电提醒的预计时间用）：这次插着期间每变 1% 记一笔（系统的 powersources.percent 通知，灭屏也会来）
static NSString *gRateKey;                      // 这次的充电头（「27W」「无线15W」）
static double gFastL0 = NAN, gFastL1 = NAN, gTailL0 = NAN, gTailL1 = NAN;   // 80% 前 / 后这一段的起止电量
static NSTimeInterval gFastT0, gFastT1, gTailT0, gTailT1;

#pragma mark - 小工具

static NSString *XRHAlertKey(XRHAlert a);

static BOOL XRHAlertOn(XRHAlert a) {
    return [[XRHPrefs shared] boolForKey:XRHAlertKey(a) fallback:a != XRHAlertDrain && a != XRHAlertTarget && a != XRHAlertBgDrain && a != XRHAlertWeekly];
}

static NSString *XRHAlertKey(XRHAlert a) {
    static NSString *keys[XRHAlertCount] = { kXRHAlertPlugIn, kXRHAlertLimit, kXRHAlertSlow, kXRHAlertHot, kXRHAlertUnplug, kXRHAlertDrain,
                                             kXRHAlertFull, kXRHAlertThrottle, kXRHAlertStandby,
                                             kXRHAlertBedtime, kXRHAlertCold, kXRHAlertFlaky, kXRHAlertTarget, kXRHAlertStopped, kXRHAlertBgDrain, kXRHAlertWeekly, kXRHAlertBypass };
    return keys[a];
}

// 专注模式（勿扰、睡眠等）开着没有：读 SpringBoard 自己的 SBDoNotDisturbStateMonitor（2026-11-19 真机探测）。
// DNDStateService 直接问会被拒（XPC error，换什么 client identifier 都一样）。只在要弹提醒时读，不在启动 / 布局时调 sharedInstance
static BOOL XRHFocusActive(void) {
    Class c = NSClassFromString(@"SBDoNotDisturbStateMonitor");
    if (![c respondsToSelector:NSSelectorFromString(@"sharedInstance")]) return NO;
    id mon = ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedInstance"));
    id state = [mon respondsToSelector:NSSelectorFromString(@"state")] ? ((id (*)(id, SEL))objc_msgSend)(mon, NSSelectorFromString(@"state")) : nil;
    return [state respondsToSelector:@selector(isActive)] && ((BOOL (*)(id, SEL))objc_msgSend)(state, @selector(isActive));
}

// 开着、冷却过了、（需要时）这次插拔还没弹过 → 记下并返回 YES
static BOOL XRHAlertTake(XRHAlert a, BOOL oncePerPlug) {
    if (!XRHAlertOn(a)) return NO;
    // 专注模式静默：每条可以自己选专注时照不照样弹（focusAllow.<键>，默认只有过热、低温照常）；
    // 被挡掉的不算弹过，不占冷却
    BOOL allow = [[XRHPrefs shared] boolForKey:[kXRHFocusAllowPrefix stringByAppendingString:XRHAlertKey(a)] fallback:a == XRHAlertHot || a == XRHAlertCold];
    if (!allow && [[XRHPrefs shared] boolForKey:kXRHToastFocusQuiet fallback:YES] && XRHFocusActive()) {
        XRHDebugLog(@"[Alert] 专注模式，静默 %ld", (long)a);
        return NO;
    }
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (gLastShown[a] > 0 && now - gLastShown[a] < kXRHAlertCooldown) return NO;
    if (oncePerPlug && gShownThisPlug[a]) return NO;
    gLastShown[a] = now;
    gShownThisPlug[a] = YES;
    return YES;
}

static BOOL XRHScreenBlanked(void) {
    if (gBlankToken < 0) return NO;
    uint64_t state = 0;
    notify_get_state(gBlankToken, &state);
    return state != 0;
}

// 充电上限这次生效吗（开着、没点「这次充满」、定时充满还没到点）
static BOOL XRHLimitActive(void) {
    return XRHOn(kXRHChargeLimit) && !XRHOn(kXRHChargeLimitFullOnce) && ![XRHLimitState()[@"schedActive"] boolValue];
}

static int XRHLimitMax(void) {
    return (int)XRHDouble(kXRHChargeLimitMax, 80, 50, 100);
}

// 时长短写（灵动岛右边只有约 80pt）：「约40分钟」「约1.5小时」「约2小时」——一小时以上只到半小时，
// 「约2小时10分」太长，会被缩小一号
static NSString *XRHShortDuration(double minutes) {
    long m = XRHRoundMinutes(minutes);
    if (m < 60) return [NSString stringWithFormat:XRHText(@"约%ld分钟", @"~%ld min"), m];
    long halves = MAX(2, lround(minutes / 30));
    if (halves % 2 == 0) return [NSString stringWithFormat:XRHText(@"约%ld小时", @"~%ld h"), halves / 2];
    return [NSString stringWithFormat:XRHText(@"约%.1f小时", @"~%.1f h"), halves / 2.0];
}

// 横幅里的长写：「约 40 分钟」「约 1 小时 20 分钟」
static NSString *XRHLongDuration(double minutes) {
    long m = XRHRoundMinutes(minutes);
    if (m < 60) return [NSString stringWithFormat:XRHText(@"约 %ld 分钟", @"about %ld min"), m];
    if (m % 60 == 0) return [NSString stringWithFormat:XRHText(@"约 %ld 小时", @"about %ld h"), m / 60];
    return [NSString stringWithFormat:XRHText(@"约 %ld 小时 %ld 分钟", @"about %ld h %ld min"), m / 60, m % 60];
}

static double XRHAverage(NSArray<NSNumber *> *a, NSUInteger last) {
    if (a.count < last || !last) return NAN;
    double sum = 0;
    for (NSUInteger i = a.count - last; i < a.count; i++) sum += a[i].doubleValue;
    return sum / last;
}

static void XRHPush(NSMutableArray<NSNumber *> *a, double v, NSUInteger max) {
    if (isnan(v)) return;
    [a addObject:@(v)];
    while (a.count > max) [a removeObjectAtIndex:0];
}

#pragma mark - 各条提醒的内容（测试通知也走这里，所以数值都从参数进来）

// 瓦数两个：adapterW 是充电器额定功率（标题里，说明插的是什么头），nowW 是此刻真正充进电池的功率（灵动岛左边 + 横幅补充里）。
// 灵动岛上显示实际功率，不显示额定功率（同一个充电头额定每次都一样，看着像写死的）
static void XRHShowPlugIn(double adapterW, BOOL wireless, double level, double minutes, int target, double nowW) {
    NSString *watts = isnan(adapterW) || adapterW <= 0 ? nil : [NSString stringWithFormat:@"%.0fW", adapterW];
    NSString *now = isnan(nowW) || nowW <= 0 ? nil : [NSString stringWithFormat:nowW < 10 ? @"%.1fW" : @"%.0fW", nowW];
    NSString *title = wireless ? (watts ? [NSString stringWithFormat:XRHText(@"%@ 无线充电", @"%@ Wireless"), watts] : XRHText(@"无线充电", @"Wireless Charging"))
                               : (watts ? [NSString stringWithFormat:XRHText(@"%@ 充电器", @"%@ Charger"), watts] : XRHText(@"正在充电", @"Charging"));
    NSString *detail, *shortDetail;
    if (level >= target) {
        detail = target < 100 ? [NSString stringWithFormat:XRHText(@"已经到上限 %d%%，不会再充", @"Already at the %d%% limit"), target]
                              : XRHText(@"已充满", @"Fully charged");
        shortDetail = target < 100 ? XRHText(@"已到上限", @"At limit") : XRHText(@"已充满", @"Full");
    } else if (isnan(minutes)) {
        detail = target < 100 ? [NSString stringWithFormat:XRHText(@"会充到 %d%% 停", @"Will stop at %d%%"), target] : nil;
        shortDetail = target < 100 ? [NSString stringWithFormat:XRHText(@"到%d%%", @"to %d%%"), target] : XRHText(@"充电中", @"Charging");
    } else {
        detail = target < 100 ? [NSString stringWithFormat:XRHText(@"%@到 %d%%", @"%@ to %d%%"), XRHLongDuration(minutes), target]
                              : [NSString stringWithFormat:XRHText(@"%@充满", @"Full in %@"), XRHLongDuration(minutes)];
        shortDetail = XRHShortDuration(minutes);
    }
    if (now && level < target) {
        NSString *nowText = [NSString stringWithFormat:XRHText(@"现在 %@", @"Now %@"), now];
        detail = detail ? [NSString stringWithFormat:XRHText(@"%@，%@", @"%@, %@"), nowText, detail] : nowText;
    }
    // 长条：左「正在充电 / 无线充电 / 已到上限 / 已充满」，右 此刻功率
    NSString *label = level >= target ? (target < 100 ? XRHText(@"已到上限", @"At Limit") : XRHText(@"已充满", @"Fully Charged"))
                                      : (wireless ? XRHText(@"无线充电", @"Wireless") : XRHText(@"正在充电", @"Charging"));
    XRHShowToastFull(XRHToastInfo, @"bolt.fill", title, detail, now ?: watts ?: XRHText(@"充电", @"On"), shortDetail,
                     label, now ?: watts ?: [NSString stringWithFormat:@"%.0f%%", level]);
}

// level 是停下来时的实际电量，不是设置里的上限：充得快时 xrhead 会提前 1% 停（80% 的上限可能停在 79%），显示上限会对不上
static void XRHShowLimit(int level) {
    XRHShowToastFull(XRHToastInfo, @"checkmark",
                 [NSString stringWithFormat:XRHText(@"已充到 %d%%，停止充电", @"Reached %d%%, charging paused"), level],
                 XRHText(@"现在直接用电源供电，电池不充也不放", @"Running on the charger; the battery is resting"),
                 [NSString stringWithFormat:@"%d%%", level], XRHText(@"已停充", @"Paused"),
                 XRHText(@"已停止充电", @"Charging Paused"), [NSString stringWithFormat:@"%d%%", level]);
}

static void XRHShowSlow(double watts, BOOL fiveVolt) {
    NSString *w = [NSString stringWithFormat:@"%.0fW", isnan(watts) ? 5 : MAX(watts, 1)];
    if (fiveVolt) {
        XRHShowToastFull(XRHToastWarning, @"xrh.bolt.half", XRHText(@"不支持快充", @"No Fast Charging"),
                     XRHText(@"线或充电头只能跑 5V，换支持 PD 快充的试试", @"The cable or charger only does 5 V; try a USB-C PD one"),
                     @"5V", XRHText(@"充电慢", @"Slow"), XRHText(@"不支持快充", @"No Fast Charge"), @"5V");
    } else {
        XRHShowToastFull(XRHToastWarning, @"xrh.bolt.half", XRHText(@"充电很慢", @"Charging Slowly"),
                     XRHText(@"换根线或换个充电头试试", @"Try another cable or charger"),
                     w, XRHText(@"充电慢", @"Slow"), XRHText(@"充电很慢", @"Charging Slowly"), w);
    }
}

static void XRHShowHot(double temp, BOOL severe) {
    NSString *t = [NSString stringWithFormat:@"%.0f℃", temp];
    XRHShowToastFull(XRHToastWarning, @"thermometer.high",
                 [NSString stringWithFormat:XRHText(@"电池 %.0f℃", @"Battery %.0f °C"), temp],
                 severe ? XRHText(@"过热，拔掉充电线、退出大型游戏", @"Too hot: unplug and close heavy apps")
                        : XRHText(@"偏热，先歇一会儿，别边充边玩", @"Running warm, take a break"),
                 t, severe ? XRHText(@"过热", @"Hot") : XRHText(@"偏热", @"Warm"),
                 severe ? XRHText(@"电池过热", @"Battery Hot") : XRHText(@"电池偏热", @"Battery Warm"), t);
}

// 高温保护进入时（xrhead 写 thermalHot）
static void XRHShowThermalGuard(double temp) {
    BOOL pulse = [[XRHPrefs shared] doubleForKey:@"thermalMode" fallback:1] >= 1;
    NSString *t = [NSString stringWithFormat:@"%.0f℃", temp];
    XRHShowToastFull(XRHToastWarning, @"thermometer.high",
                 [NSString stringWithFormat:XRHText(@"高温保护 %@", @"Heat Protection %@"), t],
                 pulse ? XRHText(@"已切换为间歇充电", @"Switched to intermittent charging") : XRHText(@"已暂停充电", @"Charging paused"),
                 t, pulse ? XRHText(@"间歇充电", @"Pulsing") : XRHText(@"暂停充电", @"Paused"),
                 XRHText(@"高温保护", @"Heat Protection"), t);
}

// 边充边玩直充进入时（xrhead 写 bypass）；watts = 充电头送进来的功率，这时基本就是整机功耗
static void XRHShowBypass(double watts) {
    NSString *w = isnan(watts) ? @"—" : [NSString stringWithFormat:@"%.0fW", MAX(watts, 1)];
    XRHShowToastFull(XRHToastInfo, @"powerplug",
                 XRHText(@"边充边玩直充", @"Bypass While Gaming"),
                 XRHText(@"功耗高，暂停给电池充电，由电源直接供电", @"High load: battery charging paused, running on the charger"),
                 w, XRHText(@"直充", @"Bypass"),
                 XRHText(@"直充，暂停给电池充电", @"Bypass, Battery Paused"), w);
}

static void XRHShowUnplug(double level, double gained, double minutes) {
    XRHShowToastFull(XRHToastInfo, @"powerplug.fill",
                 [NSString stringWithFormat:XRHText(@"这次充了 %.0f%%", @"Charged %.0f%%"), gained],
                 [NSString stringWithFormat:XRHText(@"用时%@，现在 %.0f%%", @"Took %@, now at %.0f%%"), XRHLongDuration(minutes), level],
                 [NSString stringWithFormat:@"%.0f%%", level], [NSString stringWithFormat:@"+%.0f%%", gained],
                 XRHText(@"本次充入", @"Charged"), [NSString stringWithFormat:@"+%.0f%%", gained]);
}

static void XRHShowDrain(double watts, double minutesLeft) {
    XRHShowToastFull(XRHToastWarning, @"xrh.battery.drain", XRHText(@"耗电很快", @"Draining Fast"),
                 isnan(minutesLeft) ? XRHText(@"最近一分钟平均功率很高", @"High power use over the last minute")
                                    : [NSString stringWithFormat:XRHText(@"按现在的用法%@用完", @"At this rate, empty in %@"), XRHLongDuration(minutesLeft)],
                 [NSString stringWithFormat:@"%.0fW", watts], isnan(minutesLeft) ? XRHText(@"耗电快", @"Fast") : XRHShortDuration(minutesLeft),
                 XRHText(@"耗电很快", @"Draining Fast"), [NSString stringWithFormat:@"%.0fW", watts]);
}

static void XRHShowFull(void) {
    XRHShowToastFull(XRHToastInfo, @"battery.100.bolt", XRHText(@"已充满", @"Fully Charged"),
                 XRHText(@"可以拔掉充电线了", @"You can unplug now"), @"100%", XRHText(@"已充满", @"Full"),
                 XRHText(@"已充满", @"Fully Charged"), @"100%");
}

static void XRHShowThrottle(double temp) {
    NSString *t = isnan(temp) ? @"—" : [NSString stringWithFormat:@"%.0f℃", temp];
    XRHShowToastFull(XRHToastWarning, @"thermometer.medium", XRHText(@"充电已降速", @"Charging Slowed"),
                 [NSString stringWithFormat:XRHText(@"电池 %@，系统在限流保护电池", @"Battery at %@; iOS is limiting charging"), t],
                 t, XRHText(@"已降速", @"Slowed"), XRHText(@"过热降速", @"Heat Throttled"), t);
}

static void XRHShowStandby(double drop, double hours) {
    NSString *dur = XRHShortDuration(hours * 60);
    if ([dur hasPrefix:@"约"]) dur = [dur substringFromIndex:1];
    if ([dur hasPrefix:@"~"]) dur = [dur substringFromIndex:1];
    XRHShowToastFull(XRHToastWarning, @"moon.zzz.fill",
                 ([XRHText(@"zh", @"en") isEqualToString:@"zh"] ? [NSString stringWithFormat:@"锁屏%@掉了 %.0f%%", XRHLongDuration(hours * 60), drop]
                                                                   : [NSString stringWithFormat:@"Lost %.0f%% while locked", drop]),
                 XRHText(@"可能有 App 在后台耗电", @"An app may be draining it in the background"),
                 [NSString stringWithFormat:@"-%.0f%%", drop], dur,
                 XRHText(@"锁屏掉电", @"Standby Drain"), [NSString stringWithFormat:@"-%.0f%%", drop]);
}

static void XRHShowBedtime(double level) {
    XRHShowToastFull(XRHToastWarning, @"moon.fill",
                 [NSString stringWithFormat:XRHText(@"电量 %.0f%%，睡前记得充电", @"%.0f%% left, charge before bed"), level],
                 XRHText(@"按现在的电量可能撑不到明早", @"It may not last until morning"),
                 [NSString stringWithFormat:@"%.0f%%", level], XRHText(@"记得充电", @"Charge"),
                 XRHText(@"睡前记得充电", @"Charge Tonight"), [NSString stringWithFormat:@"%.0f%%", level]);
}

static void XRHShowCold(double temp) {
    NSString *t = [NSString stringWithFormat:@"%.0f℃", temp];
    XRHShowToastFull(XRHToastWarning, @"snowflake", [NSString stringWithFormat:XRHText(@"电池 %@，低温充电", @"Charging at %@"), t],
                 XRHText(@"太冷时充电伤电池，等手机回暖再充", @"Charging in the cold wears the battery; let it warm up first"),
                 t, XRHText(@"低温充电", @"Cold"), XRHText(@"低温充电", @"Cold Charging"), t);
}

static void XRHShowFlaky(NSInteger times) {
    XRHShowToastFull(XRHToastWarning, @"cable.connector",
                 [NSString stringWithFormat:XRHText(@"1 分钟内断开了 %ld 次", @"Disconnected %ld times in a minute"), (long)times],
                 XRHText(@"线或接口可能松了，清理接口或换根线", @"The cable or port may be loose; clean the port or try another cable"),
                 [NSString stringWithFormat:XRHText(@"%ld次", @"%ldx"), (long)times], XRHText(@"接触不良", @"Loose"),
                 XRHText(@"接触不良", @"Loose Cable"), [NSString stringWithFormat:XRHText(@"%ld次", @"%ldx"), (long)times]);
}

static int XRHTargetLevel(void) {
    return (int)lround(XRHDouble(kXRHAlertTargetLevel, 90, 50, 100));
}

static void XRHShowTarget(int target) {
    XRHShowToastFull(XRHToastInfo, @"flag.checkered",
                 [NSString stringWithFormat:XRHText(@"已充到 %d%%", @"Reached %d%%"), target],
                 XRHText(@"可以拔掉充电线了", @"You can unplug now"),
                 [NSString stringWithFormat:@"%d%%", target], XRHText(@"到点了", @"Done"),
                 XRHText(@"已充到目标", @"Target Reached"), [NSString stringWithFormat:@"%d%%", target]);
}

// 睡前提醒的「那一晚」：22～24 点算当天，0～2 点算前一天；其他时间返回 nil
static NSString *XRHBedtimeNight(void) {
    NSDate *now = [NSDate date];
    NSInteger hour = [NSCalendar.currentCalendar component:NSCalendarUnitHour fromDate:now];
    if (hour >= 2 && hour < 22) return nil;
    NSDate *day = hour < 2 ? [now dateByAddingTimeInterval:-3 * 3600] : now;
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd";
    return [f stringFromDate:day];
}

// bundle ID → 装着的 App 的名字（系统语言）；不是装着的 App（系统服务等）返回 nil
static NSString *XRHInstalledAppName(NSString *bundleID) {
    Class cls = NSClassFromString(@"LSApplicationProxy");
    if (!cls || ![bundleID isKindOfClass:NSString.class] || ![bundleID containsString:@"."]) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(cls, NSSelectorFromString(@"applicationProxyForIdentifier:"), bundleID);
    id state = [proxy respondsToSelector:NSSelectorFromString(@"appState")] ? [proxy valueForKey:@"appState"] : nil;
    if (![state respondsToSelector:NSSelectorFromString(@"isInstalled")] || ![[state valueForKey:@"installed"] boolValue]) return nil;
    NSString *name = [proxy valueForKey:@"localizedName"];
    return name.length ? name : nil;
}

// 15 后台耗电：name 是 bundle ID，显示 App 的名字（认不出来就显示 bundle ID）
static NSString *XRHAppName(NSString *bundleID) {
    return XRHInstalledAppName(bundleID) ?: bundleID;
}

static void XRHShowBgDrain(NSString *app, double share) {
    NSString *pct = [NSString stringWithFormat:@"%.0f%%", share * 100];
    XRHShowToastFull(XRHToastWarning, @"moon.zzz",
                     [NSString stringWithFormat:XRHText(@"%@ 后台耗电多", @"%@ Drains in Background"), app],
                     [NSString stringWithFormat:XRHText(@"锁屏时占耗电的 %@。可关闭它的后台 App 刷新，或把定位改成「使用 App 期间」", @"%@ of standby drain. Turn off its Background App Refresh, or set Location to While Using"), pct],
                     pct, app, XRHText(@"后台耗电", @"Background Drain"), pct);
}

// 16 每周小结：xrhead 算好的 week.plist
static void XRHShowWeekly(NSDictionary *w, BOOL preview) {
    int charges = [w[@"charges"] intValue], bad = [w[@"pushBadDays"] intValue];
    NSString *when = preview ? XRHText(@"最近 7 天", @"Last 7 Days") : XRHText(@"上周", @"Last Week");
    NSMutableString *title = [NSMutableString stringWithFormat:XRHText(@"%@：充电 %d 次", @"%@: %d charges"), when, charges];
    if (w[@"standby"]) [title appendFormat:XRHText(@" · 待机 %.1f%%/时", @" · standby %.1f%%/h"), [w[@"standby"] doubleValue]];
    // 耗电最多：第一个是 App 的（系统服务不算）
    NSString *top = nil;
    for (NSString *n in w[@"top"]) if ((top = XRHInstalledAppName(n))) break;
    NSMutableArray *parts = [NSMutableArray array];
    if (top) [parts addObject:[NSString stringWithFormat:XRHText(@"耗电最多：%@", @"Top: %@"), top]];
    if (bad > 0) [parts addObject:[NSString stringWithFormat:XRHText(@"推送重连偏多 %d 天", @"frequent push reconnects on %d days"), bad]];
    NSString *count = [NSString stringWithFormat:XRHText(@"%d 次", @"%d"), charges];
    XRHShowToastOpening(XRHToastInfo, @"calendar", title,
                        parts.count ? [parts componentsJoinedByString:@" · "] : XRHText(@"数据还在收集中", @"Still collecting data"),
                        count, when, preview ? when : XRHText(@"上周小结", @"Weekly Summary"),
                        [NSString stringWithFormat:XRHText(@"充电 %d 次", @"%d charges"), charges], @"log");
}

static void XRHShowStopped(double level) {
    XRHShowToastFull(XRHToastWarning, @"powerplug",
                 XRHText(@"插着电但没在充", @"Plugged In, Not Charging"),
                 XRBatteryAdapterIsWireless() ? XRHText(@"无线充电可能没对准，挪一下手机", @"The wireless charger may be misaligned")
                                 : XRHText(@"可能是温度保护或充电器异常", @"Possibly heat protection or a charger issue"),
                 [NSString stringWithFormat:@"%.0f%%", level], XRHText(@"未充电", @"Not charging"),
                 XRHText(@"插着没在充", @"Not Charging"), [NSString stringWithFormat:@"%.0f%%", level]);
}

// 「插着却不充」：接着电源、没在充、没充满、电量 < 79%（避开系统优化充电停在 80%），而且不是 xrhead 停的
static BOOL XRHLooksStopped(double level, int *reason) {
    NSDictionary *charger = XRBatteryObject(@"ChargerData");
    int r = [charger isKindOfClass:NSDictionary.class] ? [charger[@"NotChargingReason"] intValue] : 0;
    if (reason) *reason = r;
    if (!XRBatteryExternalConnected() || XRBatteryIsCharging() || XRBatteryFullyCharged() || isnan(level) || level >= 79) return NO;
    if (XRHLimitActive()) {
        if (XRHLimitInhibited()) return NO;
    }
    if (XRHThermalHot() || XRHBypassActive()) return NO;   // 高温保护、边充边玩直充停的
    return r != 0;
}

// 定时充满在等着（xrhead 算好了开始 / 充满时间、还没开始充）：插电提醒改成「定时充满 ｜ 7:00」
static NSString *XRHClock(double unix) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"H:mm";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix]];
}

static void XRHShowScheduled(double start, double full, int max) {
    NSString *fullAt = XRHClock(full), *startAt = XRHClock(start);
    XRHShowToastFull(XRHToastInfo, @"alarm",
                     [NSString stringWithFormat:XRHText(@"定时充满 %@", @"Full by %@"), fullAt],
                     [NSString stringWithFormat:XRHText(@"先停在 %d%%，约 %@ 开始充", @"Holding at %d%%, charging from about %@"), max, startAt],
                     fullAt, XRHText(@"定时充满", @"Scheduled"),
                     XRHText(@"定时充满", @"Full by"), fullAt);
}

// 定时充满在等着就弹「定时充满」并返回 YES（插电提醒和「预览」共用）
static BOOL XRHShowScheduledIfWaiting(void) {
    NSDictionary *state = XRHLimitState();
    double schedStart = [state[@"schedStart"] doubleValue], schedFull = [state[@"schedFull"] doubleValue];
    if (!XRHLimitActive() || schedFull <= 0 || [state[@"schedActive"] boolValue]) return NO;
    XRHDebugLog(@"[Alert] 插电 定时充满 %@ 开始、%@ 充满", XRHClock(schedStart), XRHClock(schedFull));
    XRHShowScheduled(schedStart, schedFull, XRHLimitMax());
    return YES;
}

#pragma mark - 记住实际充电速度

// 插上时只看几十秒的电流算预计，会偏悲观：电流之后还会往上走（真机：插上 25 秒 1.9A，实际 45 分钟从 23% 充到 81%，
// 按电流估的是 2 小时 10 分钟充满）。所以每次充完记下这个充电头实际每分钟充几 %，下次插同一个头直接用；
// 分 80% 前（快）、80% 后（慢）两段，各自取新旧平均（新的占一半）
static NSString *XRHRateKeyNow(void) {
    double w = XRBatteryAdapterWatts();
    if (isnan(w) || w <= 0) return nil;
    return [NSString stringWithFormat:XRBatteryAdapterIsWireless() ? @"无线%.0fW" : @"%.0fW", w];
}

static NSDictionary *XRHLearnedRate(NSString *key) {
    if (!key) return nil;
    NSDictionary *all = [NSDictionary dictionaryWithContentsOfFile:XRH_RATES_FILE];
    NSDictionary *r = all[key];
    return [r isKindOfClass:NSDictionary.class] ? r : nil;
}

static void XRHRateReset(void) {
    gFastL0 = gFastL1 = gTailL0 = gTailL1 = NAN;
}

// 电量每变一次记一笔：只记「真的在充」的时候（停充、充满后不记）
static void XRHRateSample(void) {
    if (!gConnected || !gRateKey || !XRBatteryIsCharging() || XRHLimitInhibited()) return;
    double level = XRBatteryLevel();
    if (isnan(level)) return;
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (level <= 80) {
        if (isnan(gFastL0)) { gFastL0 = level; gFastT0 = now; }
        gFastL1 = level; gFastT1 = now;
    }
    if (level >= 80 && level <= 100) {
        if (isnan(gTailL0)) { gTailL0 = level; gTailT0 = now; }
        gTailL1 = level; gTailT1 = now;
    }
}

// 拔线时：这一段充得够多（80% 前 ≥ 10%、80% 后 ≥ 8%）就记下来
static void XRHRateLearn(void) {
    if (!gRateKey) return;
    NSMutableDictionary *all = [[NSDictionary dictionaryWithContentsOfFile:XRH_RATES_FILE] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *r = [all[gRateKey] isKindOfClass:NSDictionary.class] ? [all[gRateKey] mutableCopy] : [NSMutableDictionary dictionary];
    BOOL changed = NO;
    void (^learn)(NSString *, double, double, NSTimeInterval) = ^(NSString *k, double gained, double minimum, NSTimeInterval secs) {
        if (isnan(gained) || gained < minimum || secs < 5 * 60) return;
        double rate = gained / (secs / 60), old = [r[k] doubleValue];
        r[k] = @(old > 0 ? (old + rate) / 2 : rate);
    };
    double before = [r[@"fast"] doubleValue] + [r[@"tail"] doubleValue];
    learn(@"fast", gFastL1 - gFastL0, 10, gFastT1 - gFastT0);
    learn(@"tail", gTailL1 - gTailL0, 8, gTailT1 - gTailT0);
    changed = [r[@"fast"] doubleValue] + [r[@"tail"] doubleValue] != before;
    XRHDebugLog(@"[Rate] %@ 80%%前 %.0f→%.0f（%.0f 分钟） 80%%后 %.0f→%.0f（%.0f 分钟） 记下 %@", gRateKey, gFastL0, gFastL1, (gFastT1 - gFastT0) / 60,
                gTailL0, gTailL1, (gTailT1 - gTailT0) / 60, changed ? r : @"（太短，不记）");
    if (!changed) return;
    all[gRateKey] = r;
    [all writeToFile:XRH_RATES_FILE atomically:YES];
}

// 按记住的速度算还要几分钟到 target（没有记录返回 NAN）。80% 后没记过就按 80% 前的 35%（同 XRBatteryEstimate.h 的经验值）
static double XRHMinutesByRate(NSDictionary *r, double level, int target) {
    double fast = [r[@"fast"] doubleValue], tail = [r[@"tail"] doubleValue];
    if (fast <= 0 || isnan(level)) return NAN;
    if (tail <= 0) tail = fast * kXRHTaperBefore80;
    double m = MAX(0, MIN(target, 80) - level) / fast;
    if (target > 80) m += MAX(0, target - MAX(level, 80)) / tail;
    return m;
}

#pragma mark - 插上电源：等电流稳一点、等插电弹窗关掉再弹

static void XRHPlugInWhenReady(NSMutableArray<NSNumber *> *amps, int tries) {
    if (!gConnected) return;
    // 插电弹窗开着就等它关（最多等 1 分钟，期间照样记电流）
    XRHPush(amps, XRBatteryAmperage(), 8);
    // 刚插上电流还在往上爬（真机：第 6 秒才 194mA，算出「12 小时充满」）：等最近 3 次相差不超过 15%、且 > 300mA 才算稳，最多等 25 秒
    BOOL stable = NO;
    if (amps.count >= 6) {
        double lo = INFINITY, hi = -INFINITY;
        for (NSUInteger i = amps.count - 3; i < amps.count; i++) { lo = MIN(lo, amps[i].doubleValue); hi = MAX(hi, amps[i].doubleValue); }
        stable = lo > 300 && (hi - lo) <= 0.15 * (hi + lo) / 2;
    }
    if (((!stable && tries < 25) || XRHChargePromptShowing()) && tries < 60) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ XRHPlugInWhenReady(amps, tries + 1); });
        return;
    }
    if (XRHChargePromptShowing() || !XRHAlertTake(XRHAlertPlugIn, YES)) return;
    // 弹窗里可能刚点了「这次充满」，偏好要重新读
    [[XRHPrefs shared] reload];
    int target = XRHLimitActive() ? XRHLimitMax() : 100;
    double level = XRBatteryLevel(), full = XRBatteryFullCapacity();
    double avg = XRHAverage(amps, MIN(amps.count, 3));
    if (!gRateKey) gRateKey = XRHRateKeyNow();   // 插上那一刻充电头信息可能还没报上来
    // 这个充电头充过、记下了实际速度就用它；第一次用的充电头按此刻的电流算
    NSDictionary *learned = XRHLearnedRate(gRateKey);
    double minutes = XRHMinutesByRate(learned, level, target);
    if (isnan(minutes)) minutes = (!isnan(avg) && avg > 300 && !isnan(full) && !isnan(level)) ? XRHMinutesToTarget(level, target, full, avg) : NAN;
    if (minutes > 6 * 60) minutes = NAN;   // 电流还没上来时算出来的大数不可信，宁可不写时间
    XRHDebugLog(@"[Alert] 插电 adapter=%.0fW level=%.0f avg=%.0fmA target=%d minutes=%.0f（%@）", XRBatteryAdapterWatts(), level, avg, target, minutes,
                learned ? [NSString stringWithFormat:@"按记住的速度 %@", learned] : @"按电流");
    // 显示的功率用充电头送进来的总功率（同数显线）；预计时间仍按充进电池的电流算
    double nowW = XRBatteryInputWatts();
    if (isnan(nowW)) {
        double volts = XRBatteryVoltage();
        nowW = (!isnan(avg) && !isnan(volts)) ? fabs(volts * avg) / 1e6 : NAN;
    }
    XRHDebugLog(@"[Alert] 插电 实际 %.1fW", nowW);
    if (XRHShowScheduledIfWaiting()) return;
    XRHShowPlugIn(XRBatteryAdapterWatts(), XRBatteryAdapterIsWireless(), level, minutes, target, nowW);
}

#pragma mark - 定时检查

static void XRHAlertTick(void);

static void XRHSetTimer(NSTimeInterval interval) {
    if (gTimer && gTimerInterval == interval) return;
    if (gTimer) dispatch_source_cancel(gTimer);
    gTimerInterval = interval;
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                              (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(NSEC_PER_SEC));
    dispatch_source_set_event_handler(gTimer, ^{ XRHAlertTick(); });
    dispatch_resume(gTimer);
}

static void XRHCheckHot(double temp) {
    if (isnan(temp)) return;
    if (temp < kXRHHotRearm) { gHotLevel = 0; return; }
    int level = temp >= kXRHHotSevere ? 2 : temp >= kXRHHotWarn ? 1 : 0;
    if (level <= gHotLevel) return;
    // 偏热 → 过热不受冷却限制（更严重了得说）；同一级 30 分钟内只弹一次
    if (level == 2 && gHotLevel == 1) gLastShown[XRHAlertHot] = 0;
    if (!XRHAlertTake(XRHAlertHot, NO)) return;
    gHotLevel = level;
    XRHDebugLog(@"[Alert] 温度 %.1f level=%d", temp, level);
    XRHShowHot(temp, level == 2);
}

static void XRHWeeklyCheck(void);

static void XRHAlertTick(void) {
    if (XRHScreenBlanked()) {
        // 灭屏时不读；把旧读数清掉，亮屏后重新攒，免得「1 分钟平均」里混着灭屏前的数
        [gWatts removeAllObjects];
        [gAmps removeAllObjects];
        return;
    }
    // 高温保护：进入时弹一次（不受提醒开关和冷却限制，它是功能本身的反馈）
    static BOOL wasThermal;
    BOOL thermal = XRHThermalHot();
    if (thermal && !wasThermal) {
        XRHDebugLog(@"[Alert] 高温保护 %.1f", XRBatteryTemperature());
        XRHShowThermalGuard(XRBatteryTemperature());
    }
    wasThermal = thermal;
    // 17 直充：边充边玩直充进入时弹（xrhead 写 bypass）；走普通提醒的开关、冷却和专注静默，30 分钟内只弹一次，免得功耗在门槛附近来回切时一直弹
    static BOOL wasBypass;
    BOOL bypass = XRHBypassActive();
    if (bypass && !wasBypass && XRHAlertTake(XRHAlertBypass, NO)) {
        XRHDebugLog(@"[Alert] 直充 %.1fW", XRBatteryInputWatts());
        XRHShowBypass(XRBatteryInputWatts());
    }
    wasBypass = bypass;

    BOOL anyOn = NO;
    for (int i = 0; i < XRHAlertCount; i++) anyOn |= XRHAlertOn(i);
    if (!anyOn) return;
    XRHWeeklyCheck();

    if (!thermal) XRHCheckHot(XRBatteryTemperature());   // 保护中不再弹「偏热」
    double watts = XRBatteryPowerWatts(), level = XRBatteryLevel();   // 接电源时是充电头送进来的总功率（同数显线）

    if (gConnected) {
        XRHPush(gWatts, watts, 6);
        // 2 到上限停充（看 xrhead 写的状态文件：从没停到停了）
        if (XRHLimitActive()) {
            BOOL inhibited = XRHLimitInhibited();
            if (inhibited && !gWasInhibited && XRHAlertTake(XRHAlertLimit, YES)) {
                XRHDebugLog(@"[Alert] 到上限 level=%.0f", level);
                XRHShowLimit(isnan(level) ? XRHLimitMax() : (int)lround(level));
            }
            gWasInhibited = inhibited;
        }
        // 7 充满：没开上限、到 100%（插上时已经满的不算，插的时候就记成弹过了）
        if (!XRHLimitActive() && (XRBatteryFullyCharged() || (!isnan(level) && level >= 100)) && XRHAlertTake(XRHAlertFull, YES)) {
            XRHDebugLog(@"[Alert] 充满");
            XRHShowFull();
        }
        // 8 降速：TimeChargingThermallyLimited 比上次大 = 这几秒在因过热限流
        NSDictionary *charger = XRBatteryObject(@"ChargerData");
        double thermal = [charger isKindOfClass:NSDictionary.class] && [charger[@"TimeChargingThermallyLimited"] isKindOfClass:NSNumber.class]
                         ? [charger[@"TimeChargingThermallyLimited"] doubleValue] : NAN;
        if (!isnan(thermal) && !isnan(gThermalBase) && thermal > gThermalBase && XRHAlertTake(XRHAlertThrottle, YES)) {
            XRHDebugLog(@"[Alert] 降速 thermal %.0f → %.0f", gThermalBase, thermal);
            XRHShowThrottle(XRBatteryTemperature());
        }
        if (!isnan(thermal)) gThermalBase = thermal;
        // 11 低温充电：在充、电池 < 5 ℃；升到 8 ℃ 以上才会再弹
        double temp = XRBatteryTemperature();
        if (!isnan(temp) && temp > kXRHColdRearm) gColdShown = NO;
        if (!gColdShown && XRBatteryIsCharging() && !isnan(temp) && temp < kXRHColdWarn && XRHAlertTake(XRHAlertCold, NO)) {
            gColdShown = YES;
            XRHDebugLog(@"[Alert] 低温充电 %.1f", temp);
            XRHShowCold(temp);
        }
        // 13 到点：充到自己设的电量（插上时已经过了就不算，插的时候记成弹过）
        if (!isnan(level) && level >= XRHTargetLevel() && XRHAlertTake(XRHAlertTarget, YES)) {
            XRHDebugLog(@"[Alert] 到点 %.0f", level);
            XRHShowTarget(XRHTargetLevel());
        }
        // 14 中断：插上 30 秒后，连续 30 秒（6 次）都是「插着却不充」；不充电原因的编码记进调试日志，以后好细分
        int reason = 0;
        if (CFAbsoluteTimeGetCurrent() - gPlugTime > 30 && XRHLooksStopped(level, &reason)) gStoppedTicks++;
        else gStoppedTicks = 0;
        if (gStoppedTicks >= 6 && XRHAlertTake(XRHAlertStopped, YES)) {
            XRHDebugLog(@"[Alert] 中断 level=%.0f NotChargingReason=%d", level, reason);
            XRHShowStopped(level);
        }
        // 3 充电很慢：有线、在充、电量 < 80%；只跑 5V，或功率连续 30 秒（6 次）< 5W
        if (!XRBatteryAdapterIsWireless() && XRBatteryIsCharging() && !isnan(level) && level < 80
            && CFAbsoluteTimeGetCurrent() - gPlugTime > 45) {   // 刚插上电流在往上爬：45 秒后、30 秒的窗口里全是爬升之后的读数才判断
            double v = XRBatteryAdapterVoltage();
            BOOL fiveVolt = !isnan(v) && v <= 5.5;
            BOOL slow = gWatts.count >= 6;
            for (NSNumber *w in gWatts) if (w.doubleValue >= kXRHSlowWatts) slow = NO;
            if ((fiveVolt || slow) && XRHAlertTake(XRHAlertSlow, YES)) {
                XRHDebugLog(@"[Alert] 充电慢 %.1fW %.1fV", watts, v);
                XRHShowSlow(watts, fiveVolt);
            }
        }
    } else {
        // 10 睡前：22～2 点、没插线、电量 < 30%，每晚一次
        NSString *night = XRHBedtimeNight();
        if (night && ![night isEqualToString:gBedtimeNight] && !isnan(level) && level < kXRHBedtimeLevel && XRHAlertTake(XRHAlertBedtime, NO)) {
            gBedtimeNight = night;
            XRHDebugLog(@"[Alert] 睡前 %.0f", level);
            XRHShowBedtime(level);
        }
        // 6 耗电很快：最近 1 分钟（6 次）平均 > 6W
        XRHPush(gWatts, watts, 6);
        XRHPush(gAmps, XRBatteryAmperage(), 6);
        double avgW = XRHAverage(gWatts, 6);
        if (!isnan(avgW) && avgW > kXRHDrainWatts && XRHAlertTake(XRHAlertDrain, NO)) {
            double avgA = XRHAverage(gAmps, gAmps.count), full = XRBatteryFullCapacity();
            double left = (!isnan(avgA) && avgA < -50 && !isnan(level) && !isnan(full)) ? level / 100 * full / -avgA * 60 : NAN;
            XRHDebugLog(@"[Alert] 耗电快 %.1fW 还能用 %.0f 分钟", avgW, left);
            XRHShowDrain(avgW, left);
        }
    }
}

#pragma mark - 插拔

static void XRHAlertPowerChanged(void) {
    BOOL connected = XRBatteryExternalConnected();
    if (connected == gConnected) return;
    gConnected = connected;
    [gWatts removeAllObjects];   // 插拔前后的功率不是一回事，混着算不准
    [gAmps removeAllObjects];

    if (connected) {
        gPlugLevel = XRBatteryLevel();
        gPlugTime = CFAbsoluteTimeGetCurrent();
        memset(gShownThisPlug, 0, sizeof(gShownThisPlug));
        if (XRBatteryFullyCharged() || gPlugLevel >= 100) gShownThisPlug[XRHAlertFull] = YES;   // 插上时已经满了：不报「充满」
        if (gPlugLevel >= XRHTargetLevel()) gShownThisPlug[XRHAlertTarget] = YES;              // 插上时已经过了「到点」的电量
        gThermalBase = NAN;
        gStoppedTicks = 0;
        gRateKey = XRHRateKeyNow();
        XRHRateReset();
        if (gBlankTime > 0) gBlankPlugged = YES;
        gWasInhibited = XRHLimitInhibited();
        XRHSetTimer(5);
        if ([XRHPrefs shared].enabled && XRHAlertOn(XRHAlertPlugIn)) XRHPlugInWhenReady([NSMutableArray array], 0);
        return;
    }

    XRHSetTimer(10);
    XRHRateLearn();
    XRHRateReset();
    // 12 接触不良：1 分钟内拔了 ≥ 3 次（线松了时插拔通知会一阵一阵地来）
    NSTimeInterval nowT = CFAbsoluteTimeGetCurrent();
    [gUnplugTimes addObject:@(nowT)];
    while (gUnplugTimes.count && nowT - gUnplugTimes.firstObject.doubleValue > 60) [gUnplugTimes removeObjectAtIndex:0];
    if (gUnplugTimes.count >= 3 && XRHAlertTake(XRHAlertFlaky, NO)) {
        XRHDebugLog(@"[Alert] 接触不良 %lu 次", (unsigned long)gUnplugTimes.count);
        XRHShowFlaky(gUnplugTimes.count);
        gPlugLevel = NAN;
        return;   // 这时候「拔线总结」没意义
    }
    // 5 拔线总结：插了至少 1 分钟、至少充了 1%
    double level = XRBatteryLevel(), minutes = (CFAbsoluteTimeGetCurrent() - gPlugTime) / 60;
    double gained = level - gPlugLevel;
    XRHDebugLog(@"[Alert] 拔线 %.0f → %.0f（%.0f 分钟）", gPlugLevel, level, minutes);
    if (!isnan(gained) && gained >= 0) { gLastGained = gained; gLastMinutes = minutes; gLastLevel = level; }
    if (!isnan(gained) && gained >= 1 && minutes >= 1 && XRHAlertTake(XRHAlertUnplug, NO)) {
        // 稍等一下，让系统拔线的动静先过去
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            XRHShowUnplug(level, gained, minutes);
        });
    }
    gPlugLevel = NAN;
}

#pragma mark - 16 每周小结：周一 9:00 以后第一次亮屏时弹

static BOOL gWeekWanted, gWeekPreview;   // 在等 xrhead 算上一周 / 算最近 7 天（「预览」）

// 这周一 9:00（本地时间）。亮屏时每次读数都会问，算一次缓存 10 分钟（跨周、改时区最多晚 10 分钟发现）
static double XRHWeeklyDue(void) {
    static double due, computedAt;
    double now = NSDate.date.timeIntervalSince1970;
    if (due > 0 && now - computedAt < 600) return due;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.firstWeekday = 2;
    NSDate *start = nil;
    [cal rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&start interval:NULL forDate:NSDate.date];
    due = start.timeIntervalSince1970 + 9 * 3600;
    computedAt = now;
    return due;
}

// 亮屏时每次读数都看一眼（只读偏好，很轻）；到点了、这周还没弹过，就让 xrhead 算（5 分钟最多问一次）
static void XRHWeeklyCheck(void) {
    if (!XRHAlertOn(XRHAlertWeekly) || XRHScreenBlanked()) return;
    double now = NSDate.date.timeIntervalSince1970, due = XRHWeeklyDue();
    if (now < due || [[XRHPrefs shared] doubleForKey:@"weeklyShown" fallback:0] >= due) return;
    static double asked;
    if (now - asked < 300) return;
    asked = now;
    gWeekWanted = YES;
    notify_post("com.xyrith.xrhea/week-ask");
}

static void XRHWeekDone(void) {
    NSDictionary *w = [NSDictionary dictionaryWithContentsOfFile:XRH_WEEK_FILE];
    if (![w isKindOfClass:NSDictionary.class]) return;
    if ([w[@"mode"] isEqual:@"preview"]) {
        if (gWeekPreview) { gWeekPreview = NO; XRHShowWeekly(w, YES); }
        return;
    }
    if (!gWeekWanted || XRHScreenBlanked()) return;
    gWeekWanted = NO;
    if (!XRHAlertTake(XRHAlertWeekly, NO)) return;   // 专注模式挡掉的：不算弹过，下次亮屏再来
    XRHWritePref(@"weeklyShown", @(XRHWeeklyDue()));
    XRHDebugLog(@"[Alert] 每周小结 %@", w);
    XRHShowWeekly(w, NO);
}

#pragma mark - 15 后台耗电：xrhead 查到有 App 锁屏时耗电过多，亮屏时弹

static NSDictionary *gBgDrainPending;   // 等亮屏再弹的那条（drain.plist 的 alert）

static void XRHBgDrainShowPending(void) {
    if (!gBgDrainPending || XRHScreenBlanked()) return;
    NSDictionary *a = gBgDrainPending;
    gBgDrainPending = nil;
    NSString *name = a[@"name"];
    if (![name isKindOfClass:NSString.class]) return;
    // 同一个 App 每天最多一次（记在偏好 bgDrainShown 里，注销后也算数）
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd";
    NSString *today = [f stringFromDate:NSDate.date];
    NSDictionary *shown = [[XRHPrefs shared] objectForKey:@"bgDrainShown"];
    if ([shown isKindOfClass:NSDictionary.class] && [shown[name] isEqual:today]) return;
    if (!XRHAlertTake(XRHAlertBgDrain, NO)) return;
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    if ([shown isKindOfClass:NSDictionary.class]) [shown enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { if ([v isEqual:today]) m[k] = v; }];
    m[name] = today;
    XRHWritePref(@"bgDrainShown", m);
    double share = [a[@"share"] doubleValue];
    XRHDebugLog(@"[Alert] 后台耗电 %@ %.0f%%", name, share * 100);
    // 和「待机耗电」错开，亮屏时两条可能一起来
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XRHShowBgDrain(XRHAppName(name), share);
    });
}

static void XRHBgDrainArrived(void) {
    NSDictionary *a = [NSDictionary dictionaryWithContentsOfFile:XRH_DRAIN_FILE][@"alert"];
    if (![a isKindOfClass:NSDictionary.class]) return;
    gBgDrainPending = a;
    XRHBgDrainShowPending();
}

#pragma mark - 待机掉电：灭屏记电量，亮屏算这段掉了多少

static void XRHScreenChanged(void) {
    if (XRHScreenBlanked()) {
        gBlankLevel = XRBatteryLevel();
        gBlankTime = CFAbsoluteTimeGetCurrent();
        gBlankPlugged = gConnected;
        return;
    }
    XRHBgDrainShowPending();
    XRHWeeklyCheck();
    if (gBlankTime <= 0) return;
    double hours = (CFAbsoluteTimeGetCurrent() - gBlankTime) / 3600, level = XRBatteryLevel();
    double drop = gBlankLevel - level;
    BOOL plugged = gBlankPlugged || gConnected;
    gBlankTime = 0;
    if (plugged || isnan(drop) || hours <= 0) return;
    if (hours >= 0.5) { gLastStandbyDrop = MAX(drop, 0); gLastStandbyHours = hours; }
    XRHDebugLog(@"[Alert] 锁屏 %.1f 小时掉 %.0f%%", hours, drop);
    // 锁屏至少半小时、至少掉 3%、每小时 > 3%
    if (hours < 0.5 || drop < 3 || drop / hours <= kXRHStandbyRate || !XRHAlertTake(XRHAlertStandby, NO)) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XRHShowStandby(drop, hours);
    });
}

#pragma mark - 设置页「预览」：用手机此刻的真实数据弹一次（条件没满足也弹，说明现在是什么情况）

static NSString *XRHWattsText(double w) {
    return isnan(w) || w <= 0 ? @"—" : [NSString stringWithFormat:w < 10 ? @"%.1fW" : @"%.0fW", w];
}

static void XRHTryAlert(int n) {
    [[XRHPrefs shared] reload];
    BOOL connected = XRBatteryExternalConnected();
    double level = XRBatteryLevel(), full = XRBatteryFullCapacity(), amps = XRBatteryAmperage();
    NSString *levelText = isnan(level) ? @"—" : [NSString stringWithFormat:@"%.0f%%", level];
    NSString *notPlugged = XRHText(@"未接电源", @"Unplugged");
    XRHDebugLog(@"[Alert] 预览 %d connected=%d level=%.0f amps=%.0f focus=%d", n, connected, level, amps, XRHFocusActive());
    switch (n) {
        case 1: {   // 插上电源
            if (!connected) {
                XRHShowToast(XRHToastInfo, @"bolt.fill", notPlugged, XRHText(@"插上电源后显示充电功率和预计时间", @"Plug in to see charging power and time"), @"—", notPlugged);
                return;
            }
            if (XRHShowScheduledIfWaiting()) return;
            int target = XRHLimitActive() ? XRHLimitMax() : 100;
            double minutes = XRHMinutesByRate(XRHLearnedRate(XRHRateKeyNow()), level, target);
            if (isnan(minutes)) minutes = (!isnan(amps) && amps > 300 && !isnan(full) && !isnan(level)) ? XRHMinutesToTarget(level, target, full, amps) : NAN;
            if (minutes > 6 * 60) minutes = NAN;
            XRHShowPlugIn(XRBatteryAdapterWatts(), XRBatteryAdapterIsWireless(), level, minutes, target, XRBatteryInputWatts());
            return;
        }
        case 2: {   // 到上限停充
            if (XRHLimitActive() && connected && XRHLimitInhibited()) { XRHShowLimit(isnan(level) ? XRHLimitMax() : (int)lround(level)); return; }
            BOOL on = XRHLimitActive();
            XRHShowToast(XRHToastInfo, @"checkmark",
                         [NSString stringWithFormat:XRHText(@"电量 %@", @"Battery %@"), levelText],
                         on ? [NSString stringWithFormat:XRHText(@"到 %d%% 会停止充电", @"Charging stops at %d%%"), XRHLimitMax()]
                            : XRHText(@"充电上限没有开启", @"Charge Limit is off"),
                         levelText, on ? [NSString stringWithFormat:XRHText(@"到%d%%停", @"Stop %d%%"), XRHLimitMax()] : XRHText(@"未开上限", @"No limit"));
            return;
        }
        case 3: {   // 充电很慢
            if (!connected) {
                XRHShowToast(XRHToastInfo, @"xrh.bolt.half", notPlugged, XRHText(@"有线充电时才会判断", @"Checked only while charging by cable"), @"—", notPlugged);
                return;
            }
            double w = XRBatteryPowerWatts(), v = XRBatteryAdapterVoltage();
            BOOL fiveVolt = !XRBatteryAdapterIsWireless() && !isnan(v) && v <= 5.5;
            BOOL slow = fiveVolt || (!isnan(w) && w < kXRHSlowWatts);
            if (slow) { XRHShowSlow(w, fiveVolt); return; }
            XRHShowToast(XRHToastInfo, @"xrh.bolt.half",
                         [NSString stringWithFormat:XRHText(@"充电功率 %@", @"Charging at %@"), XRHWattsText(w)],
                         XRHText(@"速度正常，低于 5 W 才会提醒", @"Normal; alerts below 5 W"), XRHWattsText(w), XRHText(@"正常", @"Normal"));
            return;
        }
        case 4: {   // 温度偏高
            double t = XRBatteryTemperature();
            if (!isnan(t) && t >= kXRHHotWarn) { XRHShowHot(t, t >= kXRHHotSevere); return; }
            NSString *tt = isnan(t) ? @"—" : [NSString stringWithFormat:@"%.0f℃", t];
            XRHShowToast(XRHToastInfo, @"thermometer.high",
                         [NSString stringWithFormat:XRHText(@"电池 %@", @"Battery %@"), tt],
                         XRHText(@"温度正常，到 40℃ 才会提醒", @"Normal; alerts at 40 °C"), tt, XRHText(@"正常", @"Normal"));
            return;
        }
        case 5: {   // 拔线总结：插着线就说插上以来充了多少，没插就重放上一次
            double gained = NAN, minutes = NAN, now = level;
            if (connected && !isnan(gPlugLevel)) { gained = level - gPlugLevel; minutes = (CFAbsoluteTimeGetCurrent() - gPlugTime) / 60; }
            else if (!isnan(gLastGained)) { gained = gLastGained; minutes = gLastMinutes; now = gLastLevel; }
            if (isnan(gained)) {
                XRHShowToast(XRHToastInfo, @"powerplug.fill", XRHText(@"还没有充电记录", @"No charging session yet"),
                             XRHText(@"充一次电再拔线就会有", @"Charge and unplug once to see one"), levelText, @"+0%");
                return;
            }
            XRHShowUnplug(now, MAX(gained, 0), MAX(minutes, 0));
            return;
        }
        case 6: {   // 耗电很快
            if (connected) {
                XRHShowToast(XRHToastInfo, @"xrh.battery.drain", XRHText(@"接着电源", @"Plugged in"),
                             XRHText(@"用电池时才会判断", @"Checked only on battery"), @"—", XRHText(@"充电中", @"Charging"));
                return;
            }
            double w = XRBatteryWatts();
            double left = (!isnan(amps) && amps < -50 && !isnan(level) && !isnan(full)) ? level / 100 * full / -amps * 60 : NAN;
            if (!isnan(w) && w > kXRHDrainWatts) { XRHShowDrain(w, left); return; }
            XRHShowToast(XRHToastInfo, @"xrh.battery.drain",
                         [NSString stringWithFormat:XRHText(@"耗电 %@", @"Using %@"), XRHWattsText(w)],
                         isnan(left) ? XRHText(@"耗电正常，高于 6 W 才会提醒", @"Normal; alerts above 6 W")
                                     : [NSString stringWithFormat:XRHText(@"耗电正常，%@用完", @"Normal, empty in %@"), XRHLongDuration(left)],
                         XRHWattsText(w), isnan(left) ? XRHText(@"正常", @"Normal") : XRHShortDuration(left));
            return;
        }
        case 7: {   // 充满
            if (connected && (XRBatteryFullyCharged() || level >= 100)) { XRHShowFull(); return; }
            BOOL limit = XRHLimitActive();
            XRHShowToast(XRHToastInfo, @"battery.100.bolt",
                         [NSString stringWithFormat:XRHText(@"电量 %@", @"Battery %@"), levelText],
                         limit ? XRHText(@"开着充电上限，不会充到 100%", @"Charge Limit is on; it won't reach 100%")
                               : (connected ? XRHText(@"充到 100% 时提醒", @"Alerts at 100%") : notPlugged),
                         levelText, limit ? XRHText(@"开着上限", @"Limit on") : (connected ? XRHText(@"充电中", @"Charging") : notPlugged));
            return;
        }
        case 8: {   // 降速
            double t = XRBatteryTemperature();
            if (!connected) {
                XRHShowToast(XRHToastInfo, @"thermometer.medium", notPlugged, XRHText(@"充电时才会判断", @"Checked only while charging"), @"—", notPlugged);
                return;
            }
            NSDictionary *charger = XRBatteryObject(@"ChargerData");
            double thermal = [charger isKindOfClass:NSDictionary.class] ? [charger[@"TimeChargingThermallyLimited"] doubleValue] : 0;
            BOOL limited = !isnan(gThermalBase) && thermal > gThermalBase;
            if (limited) { XRHShowThrottle(t); return; }
            NSString *tt = isnan(t) ? @"—" : [NSString stringWithFormat:@"%.0f℃", t];
            XRHShowToast(XRHToastInfo, @"thermometer.medium", [NSString stringWithFormat:XRHText(@"电池 %@", @"Battery %@"), tt],
                         XRHText(@"没有限流，充电速度正常", @"Not limited; charging normally"), tt, XRHText(@"未降速", @"Normal"));
            return;
        }
        case 9: {   // 待机
            if (isnan(gLastStandbyDrop)) {
                XRHShowToast(XRHToastInfo, @"moon.zzz.fill", XRHText(@"还没有锁屏记录", @"No standby record yet"),
                             XRHText(@"锁屏半小时以上再亮屏就会有", @"Lock for 30 min or more to get one"), levelText, XRHText(@"无记录", @"None"));
                return;
            }
            if (gLastStandbyDrop >= 3 && gLastStandbyDrop / gLastStandbyHours > kXRHStandbyRate) { XRHShowStandby(gLastStandbyDrop, gLastStandbyHours); return; }
            NSString *dur = XRHShortDuration(gLastStandbyHours * 60);
            XRHShowToast(XRHToastInfo, @"moon.zzz.fill",
                         [NSString stringWithFormat:XRHText(@"上次锁屏掉了 %.0f%%", @"Lost %.0f%% last time locked"), gLastStandbyDrop],
                         [NSString stringWithFormat:XRHText(@"锁了%@，待机正常", @"Locked %@; normal"), XRHLongDuration(gLastStandbyHours * 60)],
                         [NSString stringWithFormat:@"-%.0f%%", gLastStandbyDrop], dur);
            return;
        }
        case 10: {   // 睡前
            if (XRHBedtimeNight() && !connected && !isnan(level) && level < kXRHBedtimeLevel) { XRHShowBedtime(level); return; }
            XRHShowToast(XRHToastInfo, @"moon.fill", [NSString stringWithFormat:XRHText(@"电量 %@", @"Battery %@"), levelText],
                         connected ? XRHText(@"正在充电", @"Charging") : XRHText(@"晚上 10 点后低于 30% 会提醒", @"Alerts after 10 PM below 30%"),
                         levelText, connected ? XRHText(@"充电中", @"Charging") : XRHText(@"够用", @"OK"));
            return;
        }
        case 11: {   // 低温
            double t = XRBatteryTemperature();
            if (connected && XRBatteryIsCharging() && !isnan(t) && t < kXRHColdWarn) { XRHShowCold(t); return; }
            NSString *tt = isnan(t) ? @"—" : [NSString stringWithFormat:@"%.0f℃", t];
            XRHShowToast(XRHToastInfo, @"snowflake", [NSString stringWithFormat:XRHText(@"电池 %@", @"Battery %@"), tt],
                         XRHText(@"充电时低于 5℃ 会提醒", @"Alerts when charging below 5 °C"), tt, XRHText(@"正常", @"Normal"));
            return;
        }
        case 12: {   // 接触
            NSTimeInterval nowT = CFAbsoluteTimeGetCurrent();
            NSInteger times = 0;
            for (NSNumber *t in gUnplugTimes) if (nowT - t.doubleValue <= 60) times++;
            if (times >= 3) { XRHShowFlaky(times); return; }
            XRHShowToast(XRHToastInfo, @"cable.connector",
                         [NSString stringWithFormat:XRHText(@"最近 1 分钟断开 %ld 次", @"%ld disconnects in the last minute"), (long)times],
                         XRHText(@"连接正常，断开 3 次以上会提醒", @"Connection is fine; alerts at 3 or more"),
                         [NSString stringWithFormat:XRHText(@"%ld次", @"%ldx"), (long)times], XRHText(@"正常", @"Normal"));
            return;
        }
        case 13: {   // 到点
            int target = XRHTargetLevel();
            if (connected && !isnan(level) && level >= target) { XRHShowTarget(target); return; }
            XRHShowToast(XRHToastInfo, @"flag.checkered", [NSString stringWithFormat:XRHText(@"电量 %@", @"Battery %@"), levelText],
                         [NSString stringWithFormat:XRHText(@"充到 %d%% 时提醒，不会停充", @"Alerts at %d%%; keeps charging"), target],
                         levelText, [NSString stringWithFormat:XRHText(@"到%d%%", @"at %d%%"), target]);
            return;
        }
        case 17: {   // 直充
            if (XRHBypassActive()) { XRHShowBypass(XRBatteryInputWatts()); return; }
            BOOL on = [[XRHPrefs shared] boolForKey:@"bypassCharge" fallback:NO];
            double limit = [[XRHPrefs shared] doubleForKey:@"bypassWatts" fallback:4];
            NSString *lim = [NSString stringWithFormat:@"%gW", limit];
            XRHShowToast(XRHToastInfo, @"powerplug",
                         on ? [NSString stringWithFormat:XRHText(@"功耗高于 %@ 时直充", @"Bypass above %@"), lim] : XRHText(@"边充边玩直充没有开启", @"Bypass While Gaming is off"),
                         on ? XRHText(@"插着电时，整机功耗 1 分钟平均超过设定值才会直充", @"Starts when the 1-minute average load while plugged in exceeds the setting")
                            : XRHText(@"在「优化」页开启", @"Turn it on in Optimization"),
                         on ? lim : @"—", on ? XRHText(@"未直充", @"Not active") : XRHText(@"未开启", @"Off"));
            return;
        }
        case 16:    // 每周小结：让 xrhead 算最近 7 天，算好了 XRHWeekDone 弹
            gWeekPreview = YES;
            notify_post("com.xyrith.xrhea/week-preview");
            return;
        case 14: {   // 中断
            if (!connected) {
                XRHShowToast(XRHToastInfo, @"powerplug", notPlugged, XRHText(@"插着电时才会判断", @"Checked only while plugged in"), @"—", notPlugged);
                return;
            }
            int reason = 0;
            if (XRHLooksStopped(level, &reason)) { XRHShowStopped(level); return; }
            XRHDebugLog(@"[Alert] 预览 中断 NotChargingReason=%d charging=%d", reason, XRBatteryIsCharging());
            XRHShowToast(XRHToastInfo, @"powerplug", [NSString stringWithFormat:XRHText(@"电量 %@", @"Battery %@"), levelText],
                         XRBatteryIsCharging() ? XRHText(@"正在充电，连接正常", @"Charging normally") : XRHText(@"没在充，但属于正常情况（上限 / 充满）", @"Not charging, as expected (limit / full)"),
                         levelText, XRBatteryIsCharging() ? XRHText(@"充电中", @"Charging") : XRHText(@"正常", @"Normal"));
            return;
        }
    }
}

#pragma mark - 入口

void XRHInitAlerts(void) {
    gWatts = [NSMutableArray array];
    gAmps = [NSMutableArray array];
    gUnplugTimes = [NSMutableArray array];
    for (int i = 0; i < XRHAlertCount; i++) gLastShown[i] = 0;
    gConnected = XRBatteryExternalConnected();   // 注销时本来就插着线：不算新插上
    if (gConnected) {
        gRateKey = XRHRateKeyNow();
        gPlugLevel = XRBatteryLevel();
        gPlugTime = CFAbsoluteTimeGetCurrent();
        gWasInhibited = XRHLimitInhibited();
    }
    notify_register_check("com.apple.springboard.hasBlankedScreen", &gBlankToken);
    int blankWatch;
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blankWatch, dispatch_get_main_queue(), ^(int t) { XRHScreenChanged(); });
    XRHSetTimer(gConnected ? 5 : 10);

    int token;
    notify_register_dispatch("com.apple.system.powersources.source", &token, dispatch_get_main_queue(), ^(int t) { XRHAlertPowerChanged(); });
    // 电量每变 1% 系统会发这个（灭屏也会来），记充电速度用
    notify_register_dispatch("com.apple.system.powersources.percent", &token, dispatch_get_main_queue(), ^(int t) {
        if (!gRateKey && gConnected) gRateKey = XRHRateKeyNow();
        XRHRateSample();
    });
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { XRHAlertPowerChanged(); }];

    // 16 每周小结：xrhead 算好了
    notify_register_dispatch("com.xyrith.xrhea/week-done", &token, dispatch_get_main_queue(), ^(int t) { XRHWeekDone(); });
    // 15 后台耗电：xrhead 每小时查一次，查到了发这个
    notify_register_dispatch("com.xyrith.xrhea/drain-alert", &token, dispatch_get_main_queue(), ^(int t) { XRHBgDrainArrived(); });

    // 设置页每条提醒后面的「预览」：com.xyrith.xrhea/try-alert-1 … -9
    for (int n = 1; n <= XRHAlertCount; n++) {
        notify_register_dispatch([NSString stringWithFormat:@"com.xyrith.xrhea/try-alert-%d", n].UTF8String, &token,
                                 dispatch_get_main_queue(), ^(int t) { XRHTryAlert(n); });
    }

#if XRH_DEBUG
    // 调试：发 com.xyrith.xrhea/test-alert，状态值 1～6 选哪条（xrh_np 发不了状态值，就按顺序轮着弹）
    static int next = 0;
    notify_register_dispatch("com.xyrith.xrhea/test-alert", &token, dispatch_get_main_queue(), ^(int t) {
        [[XRHPrefs shared] reload];
        switch (next++ % XRHAlertCount) {
            case 0: XRHShowPlugIn(27, NO, 45, 40, 80, 18.4); break;
            case 1: XRHShowLimit(79); break;
            case 2: XRHShowSlow(4, NO); break;
            case 3: XRHShowHot(42, NO); break;
            case 4: XRHShowUnplug(80, 35, 48); break;
            case 5: XRHShowDrain(8.2, 125); break;
            case 6: XRHShowFull(); break;
            case 7: XRHShowThrottle(38); break;
            case 8: XRHShowStandby(8, 2); break;
            case 9: XRHShowBedtime(25); break;
            case 10: XRHShowCold(3); break;
            case 11: XRHShowFlaky(3); break;
            case 12: XRHShowTarget(90); break;
            case 13: XRHShowStopped(42); break;
        }
    });
#endif
}
