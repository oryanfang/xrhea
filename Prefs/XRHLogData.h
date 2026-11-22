// 「日志」各页共用的数据读取和格式（XRHLogData.m）。
// 数据都是插件 / xrhead 写在 /var/mobile/Library/Caches 的文件（路径见 XRHKeys.h）：充电记录、电量曲线、耗电排行；
// 充电器改的名字存在偏好 chargerNames 里。
#pragma once
#import <UIKit/UIKit.h>

static NSString *const kXRHDash = @"—";
static const double kXRHStandbyFast = 3;   // 锁屏时每小时掉超过 3% 算快（同 Alerts.m 的待机提醒）
static const int kXRHPushBad = 15;         // 推送重连每小时超过这么多次算偏多（平时 5～10 次）

NSArray<NSDictionary *> *XRHLogRecords(void);
NSDictionary *XRHLogCurrent(void);
NSDictionary *XRHChargerNames(void);
void XRHSaveChargerName(NSString *key, NSString *name);
BOOL XRHChargerWireless(NSString *key);
NSString *XRHChargerDefaultName(NSString *key);
NSString *XRHChargerName(NSString *key);
NSArray<NSDictionary *> *XRHLogChargers(NSArray<NSDictionary *> *records, NSDictionary *current);
NSDateFormatter *XRHLogFormatter(NSString *format);
NSString *XRHLogClock(double unix);
NSString *XRHLogDay(double unix);
NSString *XRHLogDaysAgo(double unix);
NSString *XRHLogSpan(NSDictionary *r);
NSString *XRHLogDuration(double seconds);
NSString *XRHLogWatts(id w);
NSString *XRHLogSummary(NSDictionary *r);
UITableView *XRHLogTable(UIViewController *vc);
UITableViewCell *XRHLogSubtitleCell(UITableView *tableView, NSString *title, NSString *subtitle, NSString *value, BOOL link);
UITableViewCell *XRHLogValueCell(UITableView *tableView, NSString *title, NSString *value, BOOL link);
NSArray<NSArray *> *XRHLogLevels(double from);
NSDictionary *XRHDrainData(void);
NSString *XRHSystemName(NSString *name);
id XRHAppProxy(NSString *name);
UIImage *XRHGearIcon(void);
UIImage *XRHAppIcon(NSString *bundleID);
NSArray<NSDictionary *> *XRHDrainRanking(NSArray *list);
UIImage *XRHDrainIcon(NSDictionary *item);
NSString *XRHShareText(double share);
double XRHStandbyRate(NSArray<NSArray *> *pts, double now);
NSInteger XRHPushTotal(NSArray<NSNumber *> *counts);
NSInteger XRHPushMax(NSArray<NSNumber *> *counts);
BOOL XRHPushBad(NSArray<NSNumber *> *counts);
