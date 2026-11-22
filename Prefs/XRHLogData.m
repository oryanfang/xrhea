#import "XRHLogData.h"
#import "XRHLocalize.h"
#import "XRHKeys.h"
#import <objc/message.h>

#pragma mark - 读数据

// 充电记录，新的在前
NSArray<NSDictionary *> *XRHLogRecords(void) {
    NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:XRH_CHARGES_FILE];
    NSArray *records = [file[@"records"] isKindOfClass:NSArray.class] ? file[@"records"] : @[];
    return records.reverseObjectEnumerator.allObjects;
}

// 正插着的这次（插件每变 1% 写一次；拔线后 1 分钟内还在，那时不算「正在充电」）
NSDictionary *XRHLogCurrent(void) {
    NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:XRH_CHARGE_CURRENT_FILE];
    return [c isKindOfClass:NSDictionary.class] && c[@"start"] ? c : nil;
}

NSDictionary *XRHChargerNames(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)kXRHChargerNames, CFSTR("com.xyrith.xrhea"));
    id names = CFBridgingRelease(v);
    return [names isKindOfClass:NSDictionary.class] ? names : @{};
}

void XRHSaveChargerName(NSString *key, NSString *name) {
    NSMutableDictionary *names = [XRHChargerNames() mutableCopy];
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length) names[key] = name;
    else [names removeObjectForKey:key];
    CFPreferencesSetAppValue((__bridge CFStringRef)kXRHChargerNames, names.count ? (__bridge CFPropertyListRef)names : NULL, CFSTR("com.xyrith.xrhea"));
    CFPreferencesAppSynchronize(CFSTR("com.xyrith.xrhea"));
}

// 充电头的键是插件定的：「27W」「无线15W」
BOOL XRHChargerWireless(NSString *key) { return [key hasPrefix:@"无线"]; }

NSString *XRHChargerDefaultName(NSString *key) {
    if (!key.length) return XRHL(@"未知充电器");
    if (XRHChargerWireless(key)) return [NSString stringWithFormat:XRHL(@"%@ 无线"), [key substringFromIndex:2]];
    return [NSString stringWithFormat:XRHL(@"%@ 充电头"), key];
}

NSString *XRHChargerName(NSString *key) {
    NSString *custom = key ? XRHChargerNames()[key] : nil;
    return [custom isKindOfClass:NSString.class] && custom.length ? custom : XRHChargerDefaultName(key);
}

// 充电器列表：记过速度的 + 记录里出现过的；每个 {key, count, last, fast}，最近用过的在前
NSArray<NSDictionary *> *XRHLogChargers(NSArray<NSDictionary *> *records, NSDictionary *current) {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *all = [NSMutableDictionary dictionary];
    NSMutableDictionary *(^entry)(NSString *) = ^NSMutableDictionary *(NSString *key) {
        if (!all[key]) all[key] = [@{@"key": key, @"count": @0, @"last": @0} mutableCopy];
        return all[key];
    };
    NSDictionary *rates = [NSDictionary dictionaryWithContentsOfFile:XRH_RATES_FILE];
    [rates enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *r, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [r isKindOfClass:NSDictionary.class] && [r[@"fast"] doubleValue] > 0) entry(key)[@"fast"] = r[@"fast"];
    }];
    for (NSDictionary *r in records) {
        NSString *key = r[@"charger"];
        if (![key isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *e = entry(key);
        e[@"count"] = @([e[@"count"] integerValue] + 1);
        e[@"last"] = @(MAX([e[@"last"] doubleValue], [r[@"end"] doubleValue]));
    }
    NSString *curKey = current[@"charger"];
    if ([curKey isKindOfClass:NSString.class]) entry(curKey)[@"last"] = @(NSDate.date.timeIntervalSince1970);
    return [all.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"last"] compare:a[@"last"]];
    }];
}

#pragma mark - 格式

NSDateFormatter *XRHLogFormatter(NSString *format) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:XRHUsesEnglish() ? @"en_US" : @"zh_CN"];
    f.dateFormat = format;
    return f;
}

NSString *XRHLogClock(double unix) {
    return [XRHLogFormatter(@"H:mm") stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix]];
}

// 今天 / 昨天 / 11月19日（Nov 19）
NSString *XRHLogDay(double unix) {
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:unix];
    if ([NSCalendar.currentCalendar isDateInToday:d]) return XRHL(@"今天");
    if ([NSCalendar.currentCalendar isDateInYesterday:d]) return XRHL(@"昨天");
    return [XRHLogFormatter(XRHUsesEnglish() ? @"MMM d" : @"M月d日") stringFromDate:d];
}

// 今天 / 昨天 / 3 天前
NSString *XRHLogDaysAgo(double unix) {
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *d = [cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:unix]], *today = [cal startOfDayForDate:NSDate.date];
    NSInteger days = [cal components:NSCalendarUnitDay fromDate:d toDate:today options:0].day;
    if (days <= 0) return XRHL(@"今天");
    if (days == 1) return XRHL(@"昨天");
    return [NSString stringWithFormat:XRHL(@"%ld 天前"), (long)days];
}

NSString *XRHLogSpan(NSDictionary *r) {
    double start = [r[@"start"] doubleValue], end = [r[@"end"] doubleValue];
    return [NSString stringWithFormat:@"%@–%@", XRHLogClock(start), XRHLogClock(end)];
}

NSString *XRHLogDuration(double seconds) {
    long minutes = lround(seconds / 60);
    if (minutes < 60) return [NSString stringWithFormat:XRHL(@"%ld 分"), MAX(minutes, 1L)];
    if (minutes % 60 == 0) return [NSString stringWithFormat:XRHL(@"%ld 小时"), minutes / 60];
    return [NSString stringWithFormat:XRHL(@"%ld 小时 %ld 分"), minutes / 60, minutes % 60];
}

NSString *XRHLogWatts(id w) {
    return [w doubleValue] > 0 ? [NSString stringWithFormat:@"%.1f W", [w doubleValue]] : kXRHDash;
}

// 一条记录的副标题：23% → 80% · 18.6 W（开着定时充满时换成「定时充满」）
NSString *XRHLogSummary(NSDictionary *r) {
    NSString *levels = [NSString stringWithFormat:@"%ld%% → %ld%%", (long)[r[@"l0"] integerValue], (long)[r[@"l1"] integerValue]];
    if ([r[@"sched"] boolValue]) return [NSString stringWithFormat:@"%@ · %@", levels, XRHL(@"定时充满")];
    if ([r[@"wAvg"] doubleValue] > 0) return [NSString stringWithFormat:@"%@ · %@", levels, XRHLogWatts(r[@"wAvg"])];
    return levels;
}

UITableView *XRHLogTable(UIViewController *vc) {
    UITableView *t = [[UITableView alloc] initWithFrame:vc.view.bounds style:UITableViewStyleInsetGrouped];
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:t];
    return t;
}

// 标题 + 灰色副标题，右边可选一个灰色数值
UITableViewCell *XRHLogSubtitleCell(UITableView *tableView, NSString *title, NSString *subtitle, NSString *value, BOOL link) {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sub"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sub"];
    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    c.text = title;
    c.secondaryText = subtitle;
    c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    c.secondaryTextProperties.font = [UIFont systemFontOfSize:13];
    c.textToSecondaryTextVerticalPadding = 3;
    cell.contentConfiguration = c;
    UILabel *v = nil;
    if (value) {
        v = [UILabel new];
        v.text = value;
        v.textColor = UIColor.secondaryLabelColor;
        v.font = [UIFont systemFontOfSize:17];
        [v sizeToFit];
    }
    cell.accessoryView = v;
    cell.accessoryType = link ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = link ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

UITableViewCell *XRHLogValueCell(UITableView *tableView, NSString *title, NSString *value, BOOL link) {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"value"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"value"];
    UIListContentConfiguration *c = [UIListContentConfiguration valueCellConfiguration];
    c.text = title;
    c.secondaryText = value;
    cell.contentConfiguration = c;
    cell.accessoryView = nil;
    cell.accessoryType = link ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = link ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}


#pragma mark - 「日志」页顶部：24 小时电量曲线

// xrhead 记的电量（XRH_LEVELS_FILE）：最近 24 小时，再带上窗口前的最后一笔（曲线从左边接进来）
NSArray<NSArray *> *XRHLogLevels(double from) {
    NSArray *all = [NSDictionary dictionaryWithContentsOfFile:XRH_LEVELS_FILE][@"levels"];
    if (![all isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSArray *before = nil;
    for (NSArray *p in all) {
        if (![p isKindOfClass:NSArray.class] || p.count < 3) continue;
        if ([p[0] doubleValue] < from) { before = p; continue; }
        [out addObject:p];
    }
    if (before) [out insertObject:before atIndex:0];
    return out;
}


#pragma mark - 耗电排行：数据

// xrhead 读系统电池记录后写的汇总（XRH_DRAIN_FILE）
NSDictionary *XRHDrainData(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:XRH_DRAIN_FILE];
    return [d isKindOfClass:NSDictionary.class] ? d : nil;
}

// 系统进程的中文名（认不出来的就显示原名）。键是系统记录里的名字；BB- 开头的都算蜂窝网络
NSString *XRHSystemName(NSString *name) {
    static NSDictionary *names;
    if (!names) names = @{
        @"apsd": @"推送服务", @"com.apple.aps.framework": @"推送服务", @"locationd": @"定位服务", @"bluetoothd": @"蓝牙",
        @"mediaserverd-Audio": @"音频", @"audiomxd": @"音频", @"misd": @"个人热点", @"com.apple.lock-screen": @"锁定屏幕",
        @"com.apple.springboard": @"主屏幕", @"backboardd": @"显示与触控", @"kernel_task": @"系统内核", @"CommCenter": @"蜂窝网络",
        @"WiFi-Standard": @"无线局域网", @"nsurlsessiond": @"后台下载", @"cloudd": @"iCloud 同步", @"backupd": @"iCloud 备份",
        @"mDNSResponder": @"网络服务", @"sharingd": @"隔空投送与共享", @"com.apple.sharingd": @"隔空投送与共享",
        @"com.apple.chrono.WidgetRenderer-Default": @"小组件", @"mediaparserd": @"媒体处理", @"videocodecd": @"媒体处理",
        @"com.apple.webapp": @"网页 App", @"com.apple.InCallService": @"通话", @"com.apple.SafariViewService": @"Safari 网页视图",
    };
    if ([name hasPrefix:@"BB-"]) return XRHL(@"蜂窝网络");
    NSString *zh = names[name];
    return zh ? XRHL(zh) : nil;
}

// 名字对应的 App（扩展按 bundle ID 往上找它所在的 App：com.x.App.PacketTunnel → com.x.App）
id XRHAppProxy(NSString *name) {
    Class cls = NSClassFromString(@"LSApplicationProxy");
    if (!cls || ![name containsString:@"."]) return nil;
    NSString *bid = name;
    while (bid.length) {
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(cls, NSSelectorFromString(@"applicationProxyForIdentifier:"), bid);
        id appState = [proxy respondsToSelector:NSSelectorFromString(@"appState")] ? [proxy valueForKey:@"appState"] : nil;
        BOOL installed = [appState respondsToSelector:NSSelectorFromString(@"isInstalled")] && [[appState valueForKey:@"installed"] boolValue];
        NSString *title = installed && [proxy respondsToSelector:NSSelectorFromString(@"localizedName")] ? [proxy valueForKey:@"localizedName"] : nil;
        if (title.length) return proxy;
        NSRange dot = [bid rangeOfString:@"." options:NSBackwardsSearch];
        if (dot.location == NSNotFound || [bid componentsSeparatedByString:@"."].count <= 2) break;
        bid = [bid substringToIndex:dot.location];
    }
    return nil;
}

UIImage *XRHGearIcon(void) {
    static UIImage *icon;
    if (icon) return icon;
    CGSize size = CGSizeMake(29, 29);
    UIImage *glyph = [[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]]
                      imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    icon = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemGrayColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] fill];
        if (glyph) [glyph drawInRect:CGRectMake((size.width - glyph.size.width) / 2, (size.height - glyph.size.height) / 2, glyph.size.width, glyph.size.height)];
    }];
    return icon;
}

UIImage *XRHAppIcon(NSString *bundleID) {
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:sel]) return nil;
    UIImage *img = ((UIImage *(*)(id, SEL, id, int, CGFloat))objc_msgSend)(UIImage.class, sel, bundleID, 0, UIScreen.mainScreen.scale);
    if (!img) return nil;
    CGSize size = CGSizeMake(29, 29);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] addClip];
        [img drawInRect:(CGRect){CGPointZero, size}];
    }];
}

// 排行：系统记录里的名字换成 App / 中文名，同一个合并（比如 App 和它的扩展、apsd 和推送框架），按耗电排好。
// 每项 {title, subtitle（系统进程才有：原名 · 系统）, icon, share 0～1}
NSArray<NSDictionary *> *XRHDrainRanking(NSArray *list) {
    if (![list isKindOfClass:NSArray.class]) return @[];
    double total = 0;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *merged = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSArray *item in list) {
        if (![item isKindOfClass:NSArray.class] || item.count < 2) continue;
        NSString *name = item[0];
        double e = [item[1] doubleValue];
        total += e;
        id proxy = XRHAppProxy(name);
        NSString *key, *title, *subtitle = nil, *bundleID = nil;
        if (proxy) {
            bundleID = [proxy valueForKey:@"bundleIdentifier"];
            key = bundleID ?: name;
            title = [proxy valueForKey:@"localizedName"];
        } else {
            title = XRHSystemName(name) ?: name;
            key = [@"sys:" stringByAppendingString:title];
            subtitle = [NSString stringWithFormat:@"%@ · %@", name, XRHL(@"系统")];
        }
        NSMutableDictionary *m = merged[key];
        if (!m) {
            m = [@{@"title": title, @"e": @0} mutableCopy];
            if (subtitle) m[@"subtitle"] = subtitle;
            if (bundleID) m[@"bundleID"] = bundleID;
            merged[key] = m;
            [order addObject:key];
        } else if (subtitle && ![m[@"subtitle"] hasPrefix:name]) {
            m[@"subtitle"] = XRHL(@"系统");   // 几个进程合成一项：不再列原名
        }
        m[@"e"] = @([m[@"e"] doubleValue] + e);
    }
    if (total <= 0) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in order) {
        NSMutableDictionary *m = merged[k];
        m[@"share"] = @([m[@"e"] doubleValue] / total);
        [out addObject:m];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"share"] compare:a[@"share"]]; }];
    return out;
}

UIImage *XRHDrainIcon(NSDictionary *item) {
    UIImage *icon = item[@"bundleID"] ? XRHAppIcon(item[@"bundleID"]) : nil;
    return icon ?: XRHGearIcon();
}

NSString *XRHShareText(double share) {
    return share < 0.01 ? @"<1%" : [NSString stringWithFormat:@"%.0f%%", share * 100];
}

// 锁屏待机：最近 24 小时里锁屏、没接电源的时段（每段至少 10 分钟）合起来平均每小时掉多少；不够半小时返回 NAN
double XRHStandbyRate(NSArray<NSArray *> *pts, double now) {
    double drop = 0, hours = 0;
    for (NSUInteger i = 0; i < pts.count;) {
        int f = [pts[i][2] intValue];
        if (!((f & 4) && !(f & 1))) { i++; continue; }
        NSUInteger j = i;
        while (j < pts.count && ([pts[j][2] intValue] & 4) && !([pts[j][2] intValue] & 1)) j++;
        double t0 = MAX([pts[i][0] doubleValue], now - 24 * 3600), t1 = j < pts.count ? [pts[j][0] doubleValue] : now;
        double l1 = [pts[MIN(j, pts.count - 1)][1] doubleValue];
        if (t1 - t0 >= 600) { hours += (t1 - t0) / 3600; drop += MAX([pts[i][1] doubleValue] - l1, 0); }
        i = j;
    }
    return hours >= 0.5 ? drop / hours : NAN;
}


#pragma mark - 推送重连


NSInteger XRHPushTotal(NSArray<NSNumber *> *counts) {
    NSInteger t = 0;
    for (NSNumber *c in counts) t += c.integerValue;
    return t;
}

NSInteger XRHPushMax(NSArray<NSNumber *> *counts) {
    NSInteger m = 0;
    for (NSNumber *c in counts) m = MAX(m, c.integerValue);
    return m;
}

// 连续 3 小时每小时 > 15 次
BOOL XRHPushBad(NSArray<NSNumber *> *counts) {
    int run = 0;
    for (NSNumber *c in counts) {
        run = c.intValue > kXRHPushBad ? run + 1 : 0;
        if (run >= 3) return YES;
    }
    return NO;
}

