#import "XRHLogPages.h"
#import "XRHLogData.h"
#import "XRHLogCharts.h"
#import "XRHLocalize.h"
#import "XRHKeys.h"
#import <notify.h>

#pragma mark - 一次充电的详情

@interface XRHChargeDetailController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation XRHChargeDetailController {
    NSDictionary *_record;
    UITableView *_table;
    NSArray<NSArray<NSArray<NSString *> *> *> *_rows;   // 每组 [[名字, 值]…]；第 0 组是曲线
}

- (instancetype)initWithRecord:(NSDictionary *)record {
    if ((self = [super initWithNibName:nil bundle:nil])) _record = record;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSDictionary *r = _record;
    self.title = [NSString stringWithFormat:@"%@ %@", XRHLogDay([r[@"start"] doubleValue]), XRHLogSpan(r)];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    NSMutableArray *thisTime = [NSMutableArray array];
    [thisTime addObject:@[XRHL(@"时长"), XRHLogDuration([r[@"end"] doubleValue] - [r[@"start"] doubleValue])]];
    if ([r[@"mah"] integerValue] > 0) [thisTime addObject:@[XRHL(@"充入"), [NSString stringWithFormat:@"%ld mAh", (long)[r[@"mah"] integerValue]]]];
    if (r[@"wAvg"]) [thisTime addObject:@[XRHL(@"平均功率"), XRHLogWatts(r[@"wAvg"])]];
    if (r[@"wMax"]) [thisTime addObject:@[XRHL(@"最高功率"), XRHLogWatts(r[@"wMax"])]];
    if (r[@"tMax"]) [thisTime addObject:@[XRHL(@"最高温度"), [NSString stringWithFormat:@"%.1f ℃", [r[@"tMax"] doubleValue]]]];

    NSInteger result = [r[@"result"] integerValue];
    NSString *ended = result == 2 ? XRHL(@"充满") : result == 1 ? XRHL(@"到上限停充") : XRHL(@"拔线");
    NSMutableArray *state = [NSMutableArray array];
    [state addObject:@[XRHL(@"充电器"), XRHChargerName(r[@"charger"])]];
    [state addObject:@[XRHL(@"结束方式"), ended]];
    if ([r[@"sched"] boolValue]) [state addObject:@[XRHL(@"定时充满"), XRHL(@"开启")]];
    if ([r[@"heat"] boolValue]) [state addObject:@[XRHL(@"高温保护"), XRHL(@"已触发")]];
    [state addObject:@[XRHL(@"降速"), [r[@"thr"] boolValue] ? XRHL(@"有") : XRHL(@"无")]];
    _rows = @[@[], thisTime, state];

    _table = XRHLogTable(self);
    _table.dataSource = self;
    _table.delegate = self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _rows.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : _rows[section].count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? XRHL(@"本次") : section == 2 ? XRHL(@"状态") : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 190 : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        XRHChargeChartView *chart = [[XRHChargeChartView alloc] initWithFrame:cell.contentView.bounds];
        chart.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        chart.record = _record;
        [cell.contentView addSubview:chart];
        return cell;
    }
    NSArray<NSString *> *row = _rows[indexPath.section][indexPath.row];
    return XRHLogValueCell(tableView, row[0], row[1], NO);
}

@end

#pragma mark - 全部记录（按天分组）

@interface XRHChargeListController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation XRHChargeListController {
    UITableView *_table;
    NSArray<NSString *> *_days;
    NSArray<NSArray<NSDictionary *> *> *_groups;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = XRHL(@"全部记录");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    NSMutableArray *days = [NSMutableArray array], *groups = [NSMutableArray array];
    for (NSDictionary *r in XRHLogRecords()) {
        NSString *day = XRHLogDay([r[@"start"] doubleValue]);
        if (![days.lastObject isEqualToString:day]) { [days addObject:day]; [groups addObject:[NSMutableArray array]]; }
        [groups.lastObject addObject:r];
    }
    _days = days;
    _groups = groups;
    _table = XRHLogTable(self);
    _table.dataSource = self;
    _table.delegate = self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _groups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _groups[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return _days[section]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *r = _groups[indexPath.section][indexPath.row];
    return XRHLogSubtitleCell(tableView, XRHLogSpan(r), XRHLogSummary(r), nil, YES);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:[[XRHChargeDetailController alloc] initWithRecord:_groups[indexPath.section][indexPath.row]] animated:YES];
}

@end

#pragma mark - 耗电排行：一行（图标、名字、横条、百分比）

@interface XRHDrainCell : UITableViewCell
- (void)setItem:(NSDictionary *)item maxShare:(double)maxShare;
@end

@implementation XRHDrainCell {
    UIImageView *_icon;
    UILabel *_title, *_subtitle, *_value;
    UIView *_track, *_bar;
    double _ratio;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _icon = [UIImageView new];
        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:17];
        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:12];
        _subtitle.textColor = UIColor.secondaryLabelColor;
        _value = [UILabel new];
        _value.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];
        _value.textColor = UIColor.secondaryLabelColor;
        _value.textAlignment = NSTextAlignmentRight;
        _track = [UIView new];
        _track.backgroundColor = UIColor.tertiarySystemFillColor;
        _track.layer.cornerRadius = 1.5;
        _bar = [UIView new];
        _bar.backgroundColor = UIColor.systemBlueColor;
        _bar.layer.cornerRadius = 1.5;
        for (UIView *v in @[_icon, _title, _subtitle, _value, _track, _bar]) [self.contentView addSubview:v];
    }
    return self;
}

- (void)setItem:(NSDictionary *)item maxShare:(double)maxShare {
    _icon.image = XRHDrainIcon(item);
    _title.text = item[@"title"];
    _subtitle.text = item[@"subtitle"];
    _value.text = XRHShareText([item[@"share"] doubleValue]);
    _ratio = maxShare > 0 ? MIN([item[@"share"] doubleValue] / maxShare, 1) : 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height, x = 16 + 29 + 12;
    _icon.frame = CGRectMake(16, (h - 29) / 2, 29, 29);
    _value.frame = CGRectMake(w - 16 - 56, 0, 56, h);
    CGFloat tw = w - x - 16 - 56 - 8;
    BOOL sub = _subtitle.text.length > 0;
    CGFloat top = sub ? 7 : 10;
    _title.frame = CGRectMake(x, top, tw, 22);
    _subtitle.frame = CGRectMake(x, top + 21, tw, 15);
    CGFloat barY = sub ? top + 40 : top + 27;
    _track.frame = CGRectMake(x, barY, tw, 3);
    _bar.frame = CGRectMake(x, barY, MAX(tw * _ratio, 3), 3);
}

@end

#pragma mark - 耗电排行页

@interface XRHDrainController () <UITableViewDataSource, UITableViewDelegate>
@end

static const NSUInteger kXRHDrainShort = 8;   // 「全部」先列几项，点「显示全部」展开

@implementation XRHDrainController {
    UITableView *_table;
    NSArray<NSDictionary *> *_locked, *_all;
    NSInteger _lockedHours;
    BOOL _expanded;
    int _token;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = XRHL(@"耗电排行");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    _table = XRHLogTable(self);
    _table.dataSource = self;
    _table.delegate = self;
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(XRH_DRAIN_DONE, &_token, dispatch_get_main_queue(), ^(int t) { [weakSelf xrh_reload]; });
    [self xrh_reload];
    notify_post(XRH_DRAIN_ASK);
}

- (void)dealloc { notify_cancel(_token); }

- (void)xrh_reload {
    NSDictionary *d = XRHDrainData();
    _locked = XRHDrainRanking(d[@"locked"]);
    _all = XRHDrainRanking(d[@"all"]);
    _lockedHours = [d[@"lockedHours"] integerValue];
    [_table reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(_locked.count, 1);
    if (!_all.count) return 1;
    return _expanded || _all.count <= kXRHDrainShort ? _all.count : kXRHDrainShort + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? XRHL(@"锁屏时 · 最近 24 小时") : XRHL(@"全部 · 最近 24 小时");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return [NSString stringWithFormat:XRHL(@"只算屏幕关闭超过八成的整小时，共 %ld 小时。"), (long)_lockedHours];
    return XRHL(@"数据来自系统电池记录，按小时汇总，约晚 1 小时。");
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *list = indexPath.section == 0 ? _locked : _all;
    if (indexPath.row >= list.count || (indexPath.section == 1 && !_expanded && _all.count > kXRHDrainShort && indexPath.row == kXRHDrainShort)) return 44;
    return list[indexPath.row][@"subtitle"] ? 62 : 50;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSDictionary *> *list = indexPath.section == 0 ? _locked : _all;
    if (!list.count) {
        UITableViewCell *cell = XRHLogValueCell(tableView, indexPath.section == 0 ? XRHL(@"最近 24 小时没有整小时锁屏") : XRHL(@"暂无数据"), nil, NO);
        UIListContentConfiguration *c = (UIListContentConfiguration *)cell.contentConfiguration;
        c.textProperties.color = UIColor.secondaryLabelColor;
        cell.contentConfiguration = c;
        return cell;
    }
    if (indexPath.section == 1 && !_expanded && _all.count > kXRHDrainShort && indexPath.row == kXRHDrainShort) {
        UITableViewCell *cell = XRHLogValueCell(tableView, XRHL(@"显示全部"), nil, NO);
        UIListContentConfiguration *c = (UIListContentConfiguration *)cell.contentConfiguration;
        c.textProperties.color = UIColor.systemBlueColor;
        cell.contentConfiguration = c;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    XRHDrainCell *cell = [tableView dequeueReusableCellWithIdentifier:@"drain"] ?: [[XRHDrainCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"drain"];
    [cell setItem:list[indexPath.row] maxShare:[list.firstObject[@"share"] doubleValue]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && !_expanded && _all.count > kXRHDrainShort && indexPath.row == kXRHDrainShort) {
        _expanded = YES;
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end


#pragma mark - 推送重连详情

@interface XRHPushController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation XRHPushController {
    UITableView *_table;
    NSArray<NSNumber *> *_counts;
    double _from;
    NSArray<NSArray<NSString *> *> *_causes;   // [[原因, 办法]…]
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = XRHL(@"推送重连");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    NSDictionary *d = XRHDrainData();
    _counts = [d[@"push"] isKindOfClass:NSArray.class] ? d[@"push"] : @[];
    _from = [d[@"pushFrom"] doubleValue];
    _causes = @[@[XRHL(@"代理或 VPN 断开推送长连接"), XRHL(@"把 push.apple.com、17.0.0.0/8 设为直连")],
                @[XRHL(@"网络信号差、频繁切换"), XRHL(@"换个网络对比，或开飞行模式再关")]];
    _table = XRHLogTable(self);
    _table.dataSource = self;
    _table.delegate = self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : _causes.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 1 ? XRHL(@"可能的原因") : nil; }

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return XRHPushBad(_counts) ? XRHL(@"连续 3 小时超过每小时 15 次，偏多。") : XRHL(@"在正常范围内。");
    return XRHL(@"平时每小时 5～10 次。每次重连都会唤醒手机并用网络重新握手，蜂窝网络下更耗电。");
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 170 : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        XRHPushChartView *chart = [[XRHPushChartView alloc] initWithFrame:cell.contentView.bounds];
        chart.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        chart.counts = _counts;
        chart.from = _from;
        [cell.contentView addSubview:chart];
        return cell;
    }
    NSArray<NSString *> *c = _causes[indexPath.row];
    return XRHLogSubtitleCell(tableView, c[0], c[1], nil, NO);
}

@end

