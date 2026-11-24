#import "XRHLogExport.h"
#import "XRHLogData.h"
#import "XRHLocalize.h"
#import "XRHKeys.h"
#import "XRBattery.h"
#import "XRHEvents.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

#pragma mark - 导出（给 AI 看的 Markdown）

// 导出的文字直接中英两份，跟着设置页的语言走（不进翻译表）
static NSString *XRHE(NSString *zh, NSString *en) { return XRHUsesEnglish() ? en : zh; }

static id XRHExportPref(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.xyrith.xrhea")));
}
static BOOL XRHExportOn(NSString *key, BOOL fallback) {
    id v = XRHExportPref(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}
static double XRHExportNum(NSString *key, double fallback) {
    id v = XRHExportPref(key);
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
}
static NSString *XRHExportOnOff(BOOL on) { return on ? XRHE(@"开", @"on") : XRHE(@"关", @"off"); }

NSString *XRHExportTime(double unix, NSString *format) {
    return [XRHLogFormatter(format) stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix]];
}

static NSString *XRHExportNumText(double v, NSString *format) {
    return isnan(v) ? @"—" : [NSString stringWithFormat:format, v];
}

// 按小时汇总 xrhead 记的电量：每小时末的电量、这一小时里在充 / 锁屏（没接电源）各几分钟
static NSArray<NSArray<NSString *> *> *XRHExportHourly(NSArray<NSArray *> *pts, double now) {
    if (pts.count < 2) return @[];
    double from = floor([pts.firstObject[0] doubleValue] / 3600) * 3600;
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger i = 0;
    for (double h = from; h < now; h += 3600) {
        double end = MIN(h + 3600, now), charge = 0, locked = 0;
        while (i + 1 < pts.count && [pts[i + 1][0] doubleValue] <= h) i++;
        for (NSUInteger j = i; j < pts.count; j++) {
            double t0 = MAX([pts[j][0] doubleValue], h), t1 = MIN(j + 1 < pts.count ? [pts[j + 1][0] doubleValue] : now, end);
            if ([pts[j][0] doubleValue] >= end) break;
            if (t1 <= t0) continue;
            int f = [pts[j][2] intValue];
            if (f & 2) charge += t1 - t0;
            if ((f & 4) && !(f & 1)) locked += t1 - t0;
        }
        long level = -1;
        for (NSUInteger j = i; j < pts.count && [pts[j][0] doubleValue] < end; j++) level = [pts[j][1] integerValue];
        if (level < 0) continue;
        [rows addObject:@[XRHExportTime(h, @"MM-dd HH:00"), [NSString stringWithFormat:@"%ld%%", level],
                          [NSString stringWithFormat:@"%.0f", charge / 60], [NSString stringWithFormat:@"%.0f", locked / 60]]];
    }
    return rows;
}

static void XRHExportTable(NSMutableString *md, NSArray<NSString *> *head, NSArray<NSArray<NSString *> *> *rows) {
    [md appendFormat:@"| %@ |\n|", [head componentsJoinedByString:@" | "]];
    for (NSUInteger i = 0; i < head.count; i++) [md appendString:@" --- |"];
    [md appendString:@"\n"];
    for (NSArray *r in rows) [md appendFormat:@"| %@ |\n", [r componentsJoinedByString:@" | "]];
    [md appendString:@"\n"];
}

NSString *XRHExportMarkdown(void) {
    double now = NSDate.date.timeIntervalSince1970;
    NSMutableString *md = [NSMutableString string];
    struct utsname u;
    uname(&u);
    NSString *version = [XRHPrefsBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"—";

    [md appendFormat:@"# %@\n\n", XRHE(@"xrhea 电池日志", @"xrhea Battery Log")];
    [md appendFormat:@"- %@：%@\n- %@：%s · iOS %@\n- xrhea：%@\n\n", XRHE(@"导出时间", @"Exported"), XRHExportTime(now, @"yyyy-MM-dd HH:mm"),
        XRHE(@"机型", @"Device"), u.machine, UIDevice.currentDevice.systemVersion, version];
    [md appendFormat:@"> %@\n\n", XRHE(@"给 AI 的说明：这是一台越狱 iPhone 上 xrhea（电池与充电插件）导出的数据，都只来自这台手机。可以据此分析电池健康、充电习惯、充电器表现、锁屏耗电和哪些 App 在后台耗电，并给出具体建议。功率是充电头送进手机的总功率；「锁屏」指屏幕关闭且没接电源。",
        @"Note for AI: this data was exported by xrhea (a battery and charging tweak) on a jailbroken iPhone and comes only from this phone. Use it to analyze battery health, charging habits, charger performance, standby drain, and which apps drain the battery in the background, and give concrete advice. Power is the total power the charger delivers to the phone; \"locked\" means the screen is off and the phone is unplugged.")];

    // 电池
    [md appendFormat:@"## %@\n\n", XRHE(@"电池", @"Battery")];
    [md appendFormat:@"- %@：%@（%@ / %@ mAh）\n", XRHE(@"最大容量", @"Maximum capacity"), XRHExportNumText(XRBatteryHealth() * 100, @"%.1f%%"),
        XRHExportNumText(XRBatteryFullCapacity(), @"%.0f"), XRHExportNumText(XRBatteryDesignCapacity(), @"%.0f")];
    [md appendFormat:@"- %@：%@\n", XRHE(@"循环次数", @"Cycle count"), XRHExportNumText(XRBatteryCycleCount(), @"%.0f")];
    [md appendFormat:@"- %@：%@ · %@\n", XRHE(@"现在", @"Now"), XRHExportNumText(XRBatteryLevel(), @"%.0f%%"), XRHExportNumText(XRBatteryTemperature(), @"%.1f ℃")];
    [md appendFormat:@"- %@：%@\n\n", XRHE(@"电源", @"Power source"), XRBatteryExternalConnected()
        ? [NSString stringWithFormat:@"%@ %@", XRHE(@"接着电源", @"plugged in"), XRHExportNumText(XRBatteryAdapterWatts(), @"%.0f W")] : XRHE(@"电池", @"battery")];

    // 设置
    [md appendFormat:@"## %@\n\n", XRHE(@"设置", @"Settings")];
    BOOL limit = XRHExportOn(@"chargeLimit", NO);
    [md appendFormat:@"- %@：%@", XRHE(@"充电上限", @"Charge limit"), XRHExportOnOff(limit)];
    if (limit) [md appendFormat:@"（%@ %.0f%%，%@ %.0f%%）", XRHE(@"上限", @"limit"), XRHExportNum(@"chargeLimitMax", 80), XRHE(@"回落", @"margin"), XRHExportNum(@"chargeLimitGap", 5)];
    [md appendString:@"\n"];
    if (limit && XRHExportOn(@"chargeSchedule", NO)) {
        int m = (int)XRHExportNum(@"chargeScheduleTime", 420);
        [md appendFormat:@"- %@：%d:%02d\n", XRHE(@"定时充满", @"Scheduled full charge"), m / 60, m % 60];
    }
    BOOL heat = XRHExportOn(@"thermalGuard", NO);
    [md appendFormat:@"- %@：%@", XRHE(@"高温保护", @"Heat protection"), XRHExportOnOff(heat)];
    if (heat) [md appendFormat:@"（%@ %.0f℃，%@ %.0f℃，%@）", XRHE(@"有线", @"wired"), XRHExportNum(@"thermalTemp", 40), XRHE(@"无线", @"wireless"),
        XRHExportNum(@"thermalTempWireless", 37), XRHExportNum(@"thermalMode", 1) == 0 ? XRHE(@"停充", @"stop") : XRHE(@"间歇充电", @"intermittent")];
    [md appendString:@"\n"];
    BOOL bypass = XRHExportOn(@"bypassCharge", NO);
    [md appendFormat:@"- %@：%@", XRHE(@"边充边玩直充", @"Bypass while gaming"), XRHExportOnOff(bypass)];
    if (bypass) [md appendFormat:@"（%@ %.1f W）", XRHE(@"功耗高于", @"above"), XRHExportNum(@"bypassWatts", 4)];
    [md appendFormat:@"\n- %@：%@ %@ · %@ %@ · %@ %@", XRHE(@"低电量模式自动化", @"Low Power Mode automation"),
        XRHE(@"充电时", @"while charging"), XRHExportOnOff(XRHExportOn(@"lpmCharging", NO)),
        XRHE(@"锁屏时", @"while locked"), XRHExportOnOff(XRHExportOn(@"lpmLocked", NO)),
        XRHE(@"保持高刷新率", @"keep 120 Hz"), XRHExportOnOff(XRHExportOn(@"lpmKeepHighRefresh", NO))];
    [md appendFormat:@"\n- %@：%@\n\n", XRHE(@"系统优化电池充电", @"System Optimized Charging"), XRHE(@"xrhea 读不到，需自行确认", @"not readable by xrhea; check manually")];

    // 充电记录
    NSArray<NSDictionary *> *records = XRHLogRecords();
    [md appendFormat:@"## %@\n\n", [NSString stringWithFormat:XRHE(@"充电记录（最近 30 天，共 %lu 次）", @"Charging history (last 30 days, %lu sessions)"), (unsigned long)records.count]];
    if (records.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *r in records) {
            NSInteger res = [r[@"result"] integerValue];
            NSMutableArray *notes = [NSMutableArray array];
            if ([r[@"sched"] boolValue]) [notes addObject:XRHE(@"定时充满", @"scheduled")];
            if ([r[@"heat"] boolValue]) [notes addObject:XRHE(@"高温保护", @"heat protection")];
            if ([r[@"thr"] boolValue]) [notes addObject:XRHE(@"系统降速", @"throttled")];
            [rows addObject:@[XRHExportTime([r[@"start"] doubleValue], @"MM-dd HH:mm"), XRHLogDuration([r[@"end"] doubleValue] - [r[@"start"] doubleValue]),
                              [NSString stringWithFormat:@"%@%% → %@%%", r[@"l0"], r[@"l1"]], r[@"mah"] ? [NSString stringWithFormat:@"%@", r[@"mah"]] : @"—",
                              r[@"wAvg"] ? [NSString stringWithFormat:@"%.1f", [r[@"wAvg"] doubleValue]] : @"—", r[@"wMax"] ? [NSString stringWithFormat:@"%.1f", [r[@"wMax"] doubleValue]] : @"—",
                              r[@"tMax"] ? [NSString stringWithFormat:@"%.1f", [r[@"tMax"] doubleValue]] : @"—", XRHChargerName(r[@"charger"]),
                              res == 2 ? XRHE(@"充满", @"full") : res == 1 ? XRHE(@"停在上限", @"held at limit") : XRHE(@"拔线", @"unplugged"),
                              notes.count ? [notes componentsJoinedByString:@"、"] : @""]];
        }
        XRHExportTable(md, @[XRHE(@"开始", @"Start"), XRHE(@"时长", @"Duration"), XRHE(@"电量", @"Level"), XRHE(@"充入 mAh", @"Added mAh"),
                             XRHE(@"平均 W", @"Avg W"), XRHE(@"最高 W", @"Peak W"), XRHE(@"最高 ℃", @"Peak ℃"), XRHE(@"充电器", @"Charger"),
                             XRHE(@"结束", @"Ended"), XRHE(@"备注", @"Notes")], rows);
    } else {
        [md appendFormat:@"%@\n\n", XRHE(@"暂无记录。", @"No records yet.")];
    }

    // 充电器
    NSDictionary *rates = [NSDictionary dictionaryWithContentsOfFile:XRH_RATES_FILE];
    NSArray *chargers = XRHLogChargers(records, nil);
    if (chargers.count) {
        [md appendFormat:@"## %@\n\n", XRHE(@"充电器（实测速度，每分钟充入电量）", @"Chargers (measured speed, % per minute)")];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *c in chargers) {
            NSDictionary *r = rates[c[@"key"]];
            [rows addObject:@[XRHChargerName(c[@"key"]), XRHChargerWireless(c[@"key"]) ? XRHE(@"无线", @"wireless") : XRHE(@"有线", @"wired"),
                              [NSString stringWithFormat:@"%@", c[@"count"]],
                              [r[@"fast"] doubleValue] > 0 ? [NSString stringWithFormat:@"%.2f%%", [r[@"fast"] doubleValue]] : @"—",
                              [r[@"tail"] doubleValue] > 0 ? [NSString stringWithFormat:@"%.2f%%", [r[@"tail"] doubleValue]] : @"—"]];
        }
        XRHExportTable(md, @[XRHE(@"充电器", @"Charger"), XRHE(@"类型", @"Type"), XRHE(@"次数", @"Sessions"), XRHE(@"80% 前", @"Below 80%"), XRHE(@"80% 后", @"Above 80%")], rows);
    }

    // 电量（每小时）
    NSArray *hourly = XRHExportHourly(XRHLogLevels(now - 7 * 86400), now);   // xrhead 存 8 天，这里只导最近 7 天
    if (hourly.count) {
        double standby = XRHStandbyRate(XRHLogLevels(now - 24 * 3600), now);
        [md appendFormat:@"## %@\n\n", XRHE(@"电量（最近 7 天，每小时）", @"Battery level (last 7 days, hourly)")];
        if (!isnan(standby)) [md appendFormat:@"%@\n\n", [NSString stringWithFormat:XRHE(@"最近 24 小时锁屏时平均每小时掉 %.1f%%。", @"Average standby drain over the last 24 hours: %.1f%% per hour."), standby]];
        XRHExportTable(md, @[XRHE(@"时间", @"Hour"), XRHE(@"小时末电量", @"Level at end"), XRHE(@"充电分钟", @"Charging min"), XRHE(@"锁屏分钟", @"Locked min")], hourly);
    }

    // 推送重连、网络唤醒
    NSDictionary *drain = XRHDrainData();
    NSArray<NSNumber *> *push = [drain[@"push"] isKindOfClass:NSArray.class] ? drain[@"push"] : nil;
    if (push || drain[@"wakes"]) {
        [md appendFormat:@"## %@\n\n", XRHE(@"推送重连与网络唤醒（最近 24 小时）", @"Push reconnects and network wakes (last 24 hours)")];
        if (drain[@"wakes"]) [md appendFormat:@"- %@：%@\n", XRHE(@"网络唤醒", @"Network wakes"), drain[@"wakes"]];
        if (push) {
            [md appendFormat:@"- %@：%ld（%@ %ld，%@）\n- %@：%@\n", XRHE(@"推送重连", @"Push reconnects"), (long)XRHPushTotal(push),
                XRHE(@"单小时最多", @"peak per hour"), (long)XRHPushMax(push),
                XRHPushBad(push) ? XRHE(@"偏多：连续 3 小时超过每小时 15 次，平时 5～10 次", @"high: over 15 per hour for 3 hours in a row; normally 5–10")
                                 : XRHE(@"正常", @"normal"),
                XRHE(@"每小时（从早到晚）", @"Per hour (oldest first)"), [push componentsJoinedByString:@", "]];
        }
        [md appendString:@"\n"];
    }

    // 耗电排行
    for (NSString *which in @[@"locked", @"all"]) {
        NSArray<NSDictionary *> *rank = XRHDrainRanking(drain[which]);
        if (!rank.count) continue;
        BOOL lockedList = [which isEqualToString:@"locked"];
        [md appendFormat:@"## %@\n\n", lockedList
            ? [NSString stringWithFormat:XRHE(@"耗电排行 · 锁屏时（最近 24 小时里屏幕关闭超过八成的 %@ 个整小时）", @"Usage · while locked (%@ hours in the last 24 with the screen off over 80%% of the time)"), drain[@"lockedHours"]]
            : XRHE(@"耗电排行 · 全部（最近 24 小时，来自系统电池记录）", @"Usage · all (last 24 hours, from the system battery log)")];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *it in [rank subarrayWithRange:NSMakeRange(0, MIN(rank.count, 20))]) {
            [rows addObject:@[it[@"title"], it[@"subtitle"] ?: (it[@"bundleID"] ?: @""), XRHShareText([it[@"share"] doubleValue])]];
        }
        XRHExportTable(md, @[XRHE(@"名称", @"Name"), XRHE(@"标识", @"ID"), XRHE(@"占比", @"Share")], rows);
    }

    // 事件日志：排查重启 / 异常用（启动、停充、低电量切换、插拔、锁屏、发现 panic）
    NSArray<NSString *> *events = XRHEventsTail(300);
    if (events.count) {
        [md appendFormat:@"## %@\n\n%@\n\n```\n%@\n```\n", XRHE(@"事件日志（最近 300 条）", @"Event log (last 300 entries)"),
            XRHE(@"xrhea 做过的关键动作和系统事件，用来对照重启或异常发生前后的情况。「开机于」变了表示整机重启过；「发现 panic」是系统崩溃日志的第一行。",
                 @"Key actions by xrhea and system events, for checking what happened around a restart. A changed boot time means the phone restarted; \"panic\" lines quote the first line of a system crash log."),
            [events componentsJoinedByString:@"\n"]];
    }
    return md;
}

