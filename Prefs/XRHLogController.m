#import "XRHLogController.h"
#import "XRHLogData.h"
#import "XRHLogCharts.h"
#import "XRHLogPages.h"
#import "XRHLogExport.h"
#import "XRHLocalize.h"
#import "XRHKeys.h"
#import "XRBattery.h"
#import <notify.h>

#pragma mark - 「日志」页

typedef NS_ENUM(NSInteger, XRHLogRow) { XRHLogRowCurrent, XRHLogRowRecord, XRHLogRowAll, XRHLogRowEmpty };
typedef NS_ENUM(NSInteger, XRHLogSection) { XRHLogSecLevels, XRHLogSecHistory, XRHLogSecChargers, XRHLogSecDrain };
typedef NS_ENUM(NSInteger, XRHDrainRow) { XRHDrainRowStandby, XRHDrainRowRanking, XRHDrainRowPush, XRHDrainRowWakes };
static const NSUInteger kXRHLogRecent = 3;   // 首页显示最近几次

@interface XRHLogController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation XRHLogController {
    UITableView *_table;
    NSArray<NSNumber *> *_sections;     // XRHLogSection；没有充电器时不显示那组
    NSArray<NSDictionary *> *_records;
    NSDictionary *_current;
    NSArray<NSDictionary *> *_chargers;
    NSArray<NSArray *> *_historyRows;   // 「充电记录」组每行 @[类型, 记录或 NSNull]
    NSArray<NSArray *> *_levels;
    double _now, _standby;
    NSDictionary *_topLocked, *_topAll;  // 耗电排行第一名（「耗电排行」一行的副标题）
    NSArray<NSNumber *> *_drainRows;     // 耗电排查组有哪几行（XRHDrainRow）：没数据的不显示
    NSArray<NSNumber *> *_push;          // 最近 24 小时每小时推送重连次数
    NSNumber *_wakes;
    int _token;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = XRHL(@"日志");
    // 右上角导出：生成一份 Markdown（给自己或 AI 分析用），走系统分享（存到文件、隔空投送、拷贝…）
    UIBarButtonItem *export = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(xrh_export:)];
    export.accessibilityLabel = XRHL(@"导出");
    self.navigationItem.rightBarButtonItem = export;
    _table = XRHLogTable(self);
    _table.dataSource = self;
    _table.delegate = self;
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(XRH_DRAIN_DONE, &_token, dispatch_get_main_queue(), ^(int t) { [weakSelf xrh_reload]; });
}

- (void)dealloc { notify_cancel(_token); }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self xrh_reload];
    notify_post(XRH_DRAIN_ASK);   // xrhead 算好耗电排行会发 drain-updated，再刷新一次
}

- (void)xrh_reload {
    _now = NSDate.date.timeIntervalSince1970;
    _levels = XRHLogLevels(_now - 24 * 3600);
    _standby = XRHStandbyRate(_levels, _now);
    _records = XRHLogRecords();
    NSDictionary *cur = XRHLogCurrent();
    // 拔线后插件还要等 1 分钟才收尾，这段时间文件还在：接着电源才显示「正在充电」
    _current = cur && XRBatteryExternalConnected() ? cur : nil;
    _chargers = XRHLogChargers(_records, _current);
    NSMutableArray *rows = [NSMutableArray array];
    if (_current) [rows addObject:@[@(XRHLogRowCurrent), _current]];
    for (NSUInteger i = 0; i < MIN(_records.count, kXRHLogRecent); i++) [rows addObject:@[@(XRHLogRowRecord), _records[i]]];
    if (_records.count) [rows addObject:@[@(XRHLogRowAll), NSNull.null]];
    if (!rows.count) [rows addObject:@[@(XRHLogRowEmpty), NSNull.null]];
    _historyRows = rows;
    NSDictionary *drain = XRHDrainData();
    _topLocked = XRHDrainRanking(drain[@"locked"]).firstObject;
    _topAll = XRHDrainRanking(drain[@"all"]).firstObject;
    _push = [drain[@"push"] isKindOfClass:NSArray.class] ? drain[@"push"] : nil;
    _wakes = [drain[@"wakes"] isKindOfClass:NSNumber.class] ? drain[@"wakes"] : nil;
    NSMutableArray *drainRows = [NSMutableArray arrayWithObject:@(XRHDrainRowStandby)];
    if (_topAll) [drainRows addObject:@(XRHDrainRowRanking)];
    if (_push) [drainRows addObject:@(XRHDrainRowPush)];
    if (_wakes) [drainRows addObject:@(XRHDrainRowWakes)];
    _drainRows = drainRows;
    NSMutableArray *sections = [NSMutableArray arrayWithObjects:@(XRHLogSecLevels), @(XRHLogSecHistory), nil];
    if (_chargers.count) [sections addObject:@(XRHLogSecChargers)];
    [sections addObject:@(XRHLogSecDrain)];
    _sections = sections;
    [_table reloadData];
}

- (XRHLogSection)xrh_section:(NSInteger)section { return (XRHLogSection)_sections[section].integerValue; }


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _sections.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self xrh_section:section]) {
        case XRHLogSecLevels: return 1;
        case XRHLogSecHistory: return _historyRows.count;
        case XRHLogSecChargers: return _chargers.count;
        case XRHLogSecDrain: return _drainRows.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self xrh_section:section]) {
        case XRHLogSecLevels: return XRHL(@"电量 · 24 小时");
        case XRHLogSecHistory: return XRHL(@"充电记录");
        case XRHLogSecChargers: return XRHL(@"充电器");
        case XRHLogSecDrain: return XRHL(@"耗电排查");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch ([self xrh_section:section]) {
        case XRHLogSecHistory: return XRHL(@"记录只保存在本机，保留 30 天。");
        case XRHLogSecChargers: return XRHL(@"速度为 80% 前每分钟充入的电量，点按可改名。");
        case XRHLogSecDrain: return _push ? XRHL(@"推送重连连续 3 小时超过每小时 15 次时标 ⚠️。") : nil;
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self xrh_section:indexPath.section] == XRHLogSecLevels ? 180 : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self xrh_section:indexPath.section]) {
        case XRHLogSecLevels: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            XRHLevelChartView *chart = [[XRHLevelChartView alloc] initWithFrame:cell.contentView.bounds];
            chart.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            chart.levels = _levels;
            chart.now = _now;
            [cell.contentView addSubview:chart];
            return cell;
        }
        case XRHLogSecChargers: {
            NSDictionary *c = _chargers[indexPath.row];
            NSMutableArray *parts = [NSMutableArray arrayWithObject:XRHChargerWireless(c[@"key"]) ? XRHL(@"无线") : XRHL(@"有线")];
            if ([c[@"count"] integerValue] > 0) [parts addObject:[NSString stringWithFormat:XRHL(@"%ld 次"), (long)[c[@"count"] integerValue]]];
            if ([c[@"last"] doubleValue] > 0) [parts addObject:[NSString stringWithFormat:XRHL(@"上次 %@"), XRHLogDaysAgo([c[@"last"] doubleValue])]];
            NSString *speed = [c[@"fast"] doubleValue] > 0 ? [NSString stringWithFormat:XRHL(@"%.1f%%/分"), [c[@"fast"] doubleValue]] : kXRHDash;
            return XRHLogSubtitleCell(tableView, XRHChargerName(c[@"key"]), [parts componentsJoinedByString:@" · "], speed, YES);
        }
        case XRHLogSecDrain: {
            switch ((XRHDrainRow)_drainRows[indexPath.row].integerValue) {
                case XRHDrainRowStandby: {
                    NSString *rate = isnan(_standby) ? kXRHDash : [NSString stringWithFormat:XRHL(@"%.1f%%/时"), _standby];
                    return XRHLogSubtitleCell(tableView, XRHL(@"锁屏待机"), XRHL(@"最近 24 小时平均"), rate, NO);
                }
                case XRHDrainRowRanking: {
                    NSString *sub = _topLocked ? [NSString stringWithFormat:XRHL(@"锁屏时最多：%@"), _topLocked[@"title"]]
                                               : [NSString stringWithFormat:XRHL(@"最多：%@"), _topAll[@"title"]];
                    return XRHLogSubtitleCell(tableView, XRHL(@"耗电排行"), sub, nil, YES);
                }
                case XRHDrainRowPush: {
                    NSString *total = [NSString stringWithFormat:XRHL(@"%ld 次"), (long)XRHPushTotal(_push)];
                    UITableViewCell *cell = XRHLogSubtitleCell(tableView, XRHL(@"推送重连"),
                        [NSString stringWithFormat:XRHL(@"最近 24 小时 · 最多 %ld 次/时"), (long)XRHPushMax(_push)],
                        XRHPushBad(_push) ? [@"⚠️ " stringByAppendingString:total] : total, YES);
                    if (XRHPushBad(_push)) ((UILabel *)cell.accessoryView).textColor = UIColor.systemOrangeColor;
                    cell.accessoryType = UITableViewCellAccessoryNone;   // 右边已经有数值，不再加箭头挤着
                    return cell;
                }
                case XRHDrainRowWakes:
                    return XRHLogSubtitleCell(tableView, XRHL(@"网络唤醒"), XRHL(@"最近 24 小时"), [NSString stringWithFormat:XRHL(@"%ld 次"), (long)_wakes.integerValue], NO);
            }
            break;
        }
        case XRHLogSecHistory: break;
    }
    NSArray *row = _historyRows[indexPath.row];
    switch ((XRHLogRow)[row[0] integerValue]) {
        case XRHLogRowCurrent: {
            NSDictionary *c = row[1];
            NSString *sub = [NSString stringWithFormat:@"%@ · %ld%% → %ld%%", [NSString stringWithFormat:XRHL(@"%@ 起"), XRHLogClock([c[@"start"] doubleValue])],
                             (long)lround([c[@"l0"] doubleValue]), (long)lround([c[@"l1"] doubleValue])];
            return XRHLogSubtitleCell(tableView, XRHL(@"正在充电"), sub, nil, NO);
        }
        case XRHLogRowRecord: {
            NSDictionary *r = row[1];
            return XRHLogSubtitleCell(tableView, [NSString stringWithFormat:@"%@ %@", XRHLogDay([r[@"start"] doubleValue]), XRHLogSpan(r)], XRHLogSummary(r), nil, YES);
        }
        case XRHLogRowAll:
            return XRHLogValueCell(tableView, XRHL(@"全部记录"), [NSString stringWithFormat:XRHL(@"%ld 次"), (long)_records.count], YES);
        case XRHLogRowEmpty: {
            UITableViewCell *cell = XRHLogValueCell(tableView, XRHL(@"暂无记录"), nil, NO);
            UIListContentConfiguration *c = (UIListContentConfiguration *)cell.contentConfiguration;
            c.textProperties.color = UIColor.secondaryLabelColor;
            cell.contentConfiguration = c;
            return cell;
        }
    }
    return [UITableViewCell new];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch ([self xrh_section:indexPath.section]) {
        case XRHLogSecLevels: return;
        case XRHLogSecChargers: [self xrh_renameCharger:_chargers[indexPath.row][@"key"]]; return;
        case XRHLogSecDrain:
            switch ((XRHDrainRow)_drainRows[indexPath.row].integerValue) {
                case XRHDrainRowRanking: [self.navigationController pushViewController:[XRHDrainController new] animated:YES]; break;
                case XRHDrainRowPush: [self.navigationController pushViewController:[XRHPushController new] animated:YES]; break;
                default: break;
            }
            return;
        case XRHLogSecHistory: break;
    }
    NSArray *row = _historyRows[indexPath.row];
    switch ((XRHLogRow)[row[0] integerValue]) {
        case XRHLogRowRecord:
            [self.navigationController pushViewController:[[XRHChargeDetailController alloc] initWithRecord:row[1]] animated:YES];
            break;
        case XRHLogRowAll:
            [self.navigationController pushViewController:[XRHChargeListController new] animated:YES];
            break;
        default: break;
    }
}

- (void)xrh_export:(UIBarButtonItem *)sender {
    NSString *name = [NSString stringWithFormat:@"xrhea-log-%@.md", XRHExportTime(NSDate.date.timeIntervalSince1970, @"yyyyMMdd-HHmm")];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *err = nil;
    if (![XRHExportMarkdown() writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:XRHL(@"导出失败") message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:XRHL(@"好") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:share animated:YES completion:nil];
}

- (void)xrh_renameCharger:(NSString *)key {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:XRHL(@"改名") message:XRHL(@"留空恢复默认名字。")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString *custom = XRHChargerNames()[key];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [custom isKindOfClass:NSString.class] ? custom : nil;
        field.placeholder = XRHChargerDefaultName(key);
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.returnKeyType = UIReturnKeyDone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"好") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        XRHSaveChargerName(key, alert.textFields.firstObject.text ?: @"");
        [weakSelf xrh_reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
