// 充电记录：每次插拔记一条，设置页「日志」显示（格式见 XRHKeys.h 的 XRH_CHARGES_FILE）。
//
// 插上开始记；电量每变 1%（系统的 powersources.percent 通知，灭屏也会来）记一笔，亮屏时另外每分钟补一笔功率和温度。
// 拔线后等 1 分钟：期间又插上算同一次（线松了、挪了一下无线充），没插上才收尾写进记录。
// 正插着的这次每笔都写进 XRH_CHARGE_CURRENT_FILE，注销 SpringBoard 后接着记，不会丢。
// 太短的不记：插了不到 2 分钟，或者没充进 1% 且不到 10 分钟。
// 平均功率按时间加权（每笔功率一直算到下一笔），只算真的在充的时段；停在上限、充满后不算。
#import "XRHCommon.h"
#import <notify.h>

static const NSTimeInterval kXRHLogKeep = 30 * 24 * 3600;   // 记录保留 30 天
static const NSUInteger kXRHLogMaxRecords = 300, kXRHLogMaxPoints = 200;
static const NSTimeInterval kXRHLogReplug = 60;             // 拔线后这么久内又插上算同一次

static NSMutableDictionary *gCur;      // 正插着的这次（没在记为 nil）
static BOOL gLogConnected;
static NSUInteger gUnplugGen;          // 拔线后的「1 分钟后收尾」用：又插上时加一，旧的收尾就作废
static int gLogBlankToken = -1;

static double XRHLogNow(void) { return NSDate.date.timeIntervalSince1970; }

// 和 Alerts.m 记充电速度用的键一样（「27W」「无线15W」），设置页靠它把记录和速度对上
static NSString *XRHLogChargerKey(void) {
    double w = XRBatteryAdapterWatts();
    if (isnan(w) || w <= 0) return nil;
    return [NSString stringWithFormat:XRBatteryAdapterIsWireless() ? @"无线%.0fW" : @"%.0fW", w];
}

static double XRHLogThermalLimited(void) {
    NSDictionary *charger = XRBatteryObject(@"ChargerData");
    id v = [charger isKindOfClass:NSDictionary.class] ? charger[@"TimeChargingThermallyLimited"] : nil;
    return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : NAN;
}

static double XRHLogRound(double v, double step) { return round(v / step) * step; }

static void XRHLogSaveCurrent(void) {
    if (gCur) [gCur writeToFile:XRH_CHARGE_CURRENT_FILE atomically:YES];
    else [NSFileManager.defaultManager removeItemAtPath:XRH_CHARGE_CURRENT_FILE error:nil];
}

#pragma mark - 记一笔

static void XRHLogSample(BOOL levelChanged) {
    if (!gCur) return;
    double now = XRHLogNow(), level = XRBatteryLevel(), watts = XRBatteryInputWatts(), temp = XRBatteryTemperature();
    BOOL charging = XRBatteryIsCharging();

    // 上一笔的功率一直算到现在（只算上一笔时真的在充的）
    double last = [gCur[@"last"] doubleValue], dt = now - last;
    if ([gCur[@"chgPrev"] boolValue] && gCur[@"wPrev"] && dt > 0 && dt < 3600) {
        gCur[@"ews"] = @([gCur[@"ews"] doubleValue] + [gCur[@"wPrev"] doubleValue] * dt);
        gCur[@"et"] = @([gCur[@"et"] doubleValue] + dt);
    }
    BOOL powered = charging && !isnan(watts) && watts > 0;
    gCur[@"chgPrev"] = @(powered);
    if (powered) gCur[@"wPrev"] = @(watts);
    if (powered && watts > [gCur[@"wMax"] doubleValue]) gCur[@"wMax"] = @(watts);
    if (!isnan(temp) && (!gCur[@"tMax"] || temp > [gCur[@"tMax"] doubleValue])) gCur[@"tMax"] = @(temp);
    if (!gCur[@"charger"]) {
        NSString *key = XRHLogChargerKey();
        if (key) gCur[@"charger"] = key;
    }
    if (!isnan(level)) gCur[@"l1"] = @(level);
    double mah = XRBatteryCurrentCharge();
    if (!isnan(mah)) {
        if (!gCur[@"c0"]) gCur[@"c0"] = @(mah);
        gCur[@"c1"] = @(mah);
    }

    // 上限、定时充满、高温保护（xrhead 的状态文件）
    NSDictionary *state = XRHLimitState();
    BOOL thermalHot = [state[@"thermalHot"] boolValue];
    BOOL held = [state[@"inhibited"] boolValue] && !thermalHot && ![state[@"bypassStop"] boolValue] && !charging;
    gCur[@"held"] = @(held);
    if (held) gCur[@"limit"] = @YES;
    if (thermalHot) gCur[@"heat"] = @YES;
    if ([state[@"schedFull"] doubleValue] > 0) gCur[@"sched"] = @YES;
    gCur[@"full"] = @(XRBatteryFullyCharged() || (!isnan(level) && level >= 100));
    double th = XRHLogThermalLimited();
    if (!isnan(th)) {
        if (!gCur[@"th0"]) gCur[@"th0"] = @(th);
        else if (th > [gCur[@"th0"] doubleValue]) gCur[@"thr"] = @YES;
    }

    // 曲线上的点：电量变了才加
    NSMutableArray *pts = gCur[@"pts"];
    NSArray *lastPt = pts.lastObject;
    if (!isnan(level) && pts.count < kXRHLogMaxPoints && (!lastPt || (levelChanged && [lastPt[1] doubleValue] != level))) {
        [pts addObject:@[@(lround(now - [gCur[@"start"] doubleValue])), @(lround(level)), @(powered ? XRHLogRound(watts, 0.1) : 0)]];
    }
    gCur[@"last"] = @(now);
    XRHLogSaveCurrent();
}

#pragma mark - 开始 / 收尾

static void XRHLogStart(void) {
    double now = XRHLogNow(), level = XRBatteryLevel();
    gCur = [NSMutableDictionary dictionary];
    gCur[@"start"] = @(now);
    gCur[@"last"] = @(now);
    if (!isnan(level)) gCur[@"l0"] = gCur[@"l1"] = @(level);
    gCur[@"wireless"] = @(XRBatteryAdapterIsWireless());
    gCur[@"pts"] = [NSMutableArray array];
    XRHDebugLog(@"[Log] 开始 %.0f%%", level);
    XRHLogSample(YES);
}

static void XRHLogFinish(void) {
    NSDictionary *c = gCur;
    gCur = nil;
    XRHLogSaveCurrent();
    if (!c) return;

    double start = [c[@"start"] doubleValue], end = [c[@"last"] doubleValue];
    double l0 = [c[@"l0"] doubleValue], l1 = [c[@"l1"] doubleValue], gained = l1 - l0;
    if (!c[@"l0"] || end - start < 120 || (gained < 1 && end - start < 600)) {
        XRHDebugLog(@"[Log] 太短，不记（%.0f 分钟，%.0f → %.0f）", (end - start) / 60, l0, l1);
        return;
    }
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"start"] = @(start);
    r[@"end"] = @(end);
    r[@"l0"] = @(lround(l0));
    r[@"l1"] = @(lround(l1));
    double mah = [c[@"c1"] doubleValue] - [c[@"c0"] doubleValue];
    if (c[@"c0"] && mah > 0) r[@"mah"] = @(lround(mah));
    double et = [c[@"et"] doubleValue];
    if (et >= 60) r[@"wAvg"] = @(XRHLogRound([c[@"ews"] doubleValue] / et, 0.1));
    if ([c[@"wMax"] doubleValue] > 0) r[@"wMax"] = @(XRHLogRound([c[@"wMax"] doubleValue], 0.1));
    if (c[@"tMax"]) r[@"tMax"] = @(XRHLogRound([c[@"tMax"] doubleValue], 0.1));
    if (c[@"charger"]) r[@"charger"] = c[@"charger"];
    r[@"wireless"] = c[@"wireless"] ?: @NO;
    r[@"result"] = @([c[@"full"] boolValue] ? 2 : [c[@"held"] boolValue] ? 1 : 0);
    for (NSString *k in @[@"limit", @"sched", @"heat", @"thr"]) if ([c[k] boolValue]) r[k] = @YES;
    NSMutableArray *pts = [c[@"pts"] mutableCopy] ?: [NSMutableArray array];
    if ([pts.lastObject[1] doubleValue] != lround(l1)) [pts addObject:@[@(lround(end - start)), @(lround(l1)), @0]];
    r[@"pts"] = pts;

    NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:XRH_CHARGES_FILE];
    NSMutableArray *records = [file[@"records"] isKindOfClass:NSArray.class] ? [file[@"records"] mutableCopy] : [NSMutableArray array];
    [records addObject:r];
    double cutoff = XRHLogNow() - kXRHLogKeep;
    while (records.count && ([records.firstObject[@"end"] doubleValue] < cutoff || records.count > kXRHLogMaxRecords)) [records removeObjectAtIndex:0];
    [@{@"records": records} writeToFile:XRH_CHARGES_FILE atomically:YES];
    XRHDebugLog(@"[Log] 记下 %.0f → %.0f（%.0f 分钟）%@ 平均 %@W 结束 %@", l0, l1, (end - start) / 60, r[@"charger"], r[@"wAvg"], r[@"result"]);
}

#pragma mark - 插拔

static void XRHLogPowerChanged(void) {
    BOOL connected = XRBatteryExternalConnected();
    if (connected == gLogConnected) return;
    gLogConnected = connected;
    NSUInteger gen = ++gUnplugGen;
    if (connected) {
        if (gCur) { XRHDebugLog(@"[Log] 1 分钟内又插上，接着记"); XRHLogSample(NO); }
        else XRHLogStart();
        return;
    }
    if (!gCur) return;
    double level = XRBatteryLevel();
    if (!isnan(level)) gCur[@"l1"] = @(level);
    gCur[@"chgPrev"] = @NO;   // 拔线后的时间不算进平均功率
    XRHLogSaveCurrent();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kXRHLogReplug * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen == gUnplugGen && !gLogConnected) XRHLogFinish();
    });
}

#pragma mark - 入口

void XRHInitChargeLog(void) {
    gLogConnected = XRBatteryExternalConnected();
    // 注销前正在记的那次：还插着就接着记，已经拔了就收尾
    NSData *data = [NSData dataWithContentsOfFile:XRH_CHARGE_CURRENT_FILE];
    id saved = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:nil] : nil;
    if ([saved isKindOfClass:NSMutableDictionary.class] && [saved[@"pts"] isKindOfClass:NSMutableArray.class]) {
        gCur = saved;
        // 最后一笔离现在超过 1 小时、电量还比那时低：中间拔过线又插上了（比如关机期间），旧的收尾，这次重新开始
        BOOL stale = XRHLogNow() - [gCur[@"last"] doubleValue] > 3600 && XRBatteryLevel() < [gCur[@"l1"] doubleValue];
        if (!gLogConnected || stale) XRHLogFinish();
        else XRHLogSample(NO);
    }
    if (gLogConnected && !gCur) XRHLogStart();

    notify_register_check("com.apple.springboard.hasBlankedScreen", &gLogBlankToken);
    int token;
    notify_register_dispatch("com.apple.system.powersources.source", &token, dispatch_get_main_queue(), ^(int t) { XRHLogPowerChanged(); });
    notify_register_dispatch("com.apple.system.powersources.percent", &token, dispatch_get_main_queue(), ^(int t) {
        if (gLogConnected) XRHLogSample(YES);
    });
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { XRHLogPowerChanged(); }];

    // 亮屏时每分钟补一笔功率、温度（灭屏时只靠电量变化那一笔）
    static dispatch_source_t timer;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), 60 * NSEC_PER_SEC, 10 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (!gCur || !gLogConnected) return;
        uint64_t blanked = 0;
        if (gLogBlankToken >= 0) notify_get_state(gLogBlankToken, &blanked);
        if (!blanked) XRHLogSample(NO);
    });
    dispatch_resume(timer);
}
