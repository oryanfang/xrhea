// 「日志」里的几张图（XRHLogCharts.m）：都是 drawRect 自己画，跟着深浅色重画
#pragma once
#import <UIKit/UIKit.h>

// 单次充电详情页顶部：「23% → 80%  +57%」+ 电量线（实线）和功率线（虚线）
@interface XRHChargeChartView : UIView
@property (nonatomic, copy) NSDictionary *record;
@end

// 日志页顶部：最近 24 小时电量，绿底 = 在充，橙底 = 锁屏掉电快
@interface XRHLevelChartView : UIView
@property (nonatomic, copy) NSArray<NSArray *> *levels;
@property (nonatomic) double now;
@end

// 推送重连详情页：每小时一根柱子，超过 15 次的标橙
@interface XRHPushChartView : UIView
@property (nonatomic, copy) NSArray<NSNumber *> *counts;
@property (nonatomic) double from;
@end
