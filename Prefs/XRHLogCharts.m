#import "XRHLogCharts.h"
#import "XRHLogData.h"
#import "XRHLocalize.h"

#pragma mark - 详情页顶部：电量变化 + 电量 / 功率曲线

@implementation XRHChargeChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    NSDictionary *r = self.record;
    if (!r) return;
    CGFloat pad = 16, w = self.bounds.size.width, h = self.bounds.size.height;
    long l0 = [r[@"l0"] integerValue], l1 = [r[@"l1"] integerValue];

    // 23% → 80%  +57%
    NSString *big = [NSString stringWithFormat:@"%ld%% → %ld%%", l0, l1];
    NSDictionary *bigAttr = @{NSFontAttributeName: [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: UIColor.labelColor};
    CGSize bs = [big sizeWithAttributes:bigAttr];
    [big drawAtPoint:CGPointMake(pad, 14) withAttributes:bigAttr];
    UIFont *small = [UIFont systemFontOfSize:13];
    NSDictionary *smallAttr = @{NSFontAttributeName: small, NSForegroundColorAttributeName: UIColor.secondaryLabelColor};
    NSString *gain = [NSString stringWithFormat:@"%@%ld%%", l1 >= l0 ? @"+" : @"", l1 - l0];
    [gain drawAtPoint:CGPointMake(pad + bs.width + 8, 14 + bs.height - small.lineHeight - 3) withAttributes:smallAttr];

    // 曲线区：电量按 0～100%，功率按这次的最高值缩放
    CGFloat top = 14 + bs.height + 12, bottom = h - 12 - small.lineHeight - 6;
    CGRect area = CGRectMake(pad, top, w - pad * 2, MAX(bottom - top, 20));
    CGFloat px = 1 / UIScreen.mainScreen.scale;
    [UIColor.separatorColor setStroke];
    for (int i = 0; i <= 2; i++) {
        CGFloat y = round(CGRectGetMinY(area) + area.size.height * i / 2) + px / 2;
        UIBezierPath *g = [UIBezierPath bezierPath];
        [g moveToPoint:CGPointMake(CGRectGetMinX(area), y)];
        [g addLineToPoint:CGPointMake(CGRectGetMaxX(area), y)];
        g.lineWidth = px;
        [g stroke];
    }
    NSArray<NSArray *> *pts = [r[@"pts"] isKindOfClass:NSArray.class] ? r[@"pts"] : @[];
    double duration = MAX([r[@"end"] doubleValue] - [r[@"start"] doubleValue], 1), maxW = 0;
    for (NSArray *p in pts) if (p.count >= 3) maxW = MAX(maxW, [p[2] doubleValue]);
    CGFloat (^xAt)(NSArray *) = ^CGFloat(NSArray *p) { return CGRectGetMinX(area) + area.size.width * MIN(MAX([p[0] doubleValue] / duration, 0), 1); };

    UIBezierPath *level = [UIBezierPath bezierPath], *power = [UIBezierPath bezierPath];
    for (NSArray *p in pts) {
        if (p.count < 3) continue;
        CGPoint lp = CGPointMake(xAt(p), CGRectGetMaxY(area) - area.size.height * MIN(MAX([p[1] doubleValue], 0), 100) / 100);
        if (level.isEmpty) [level moveToPoint:lp]; else [level addLineToPoint:lp];
        double pw = [p[2] doubleValue];
        if (pw > 0 && maxW > 0) {
            CGPoint pp = CGPointMake(xAt(p), CGRectGetMaxY(area) - area.size.height * 0.9 * pw / maxW);
            if (power.isEmpty) [power moveToPoint:pp]; else [power addLineToPoint:pp];
        }
    }
    power.lineWidth = 1.5;
    CGFloat dash[] = {4, 3};
    [power setLineDash:dash count:2 phase:0];
    [UIColor.systemTealColor setStroke];
    [power stroke];
    level.lineWidth = 2;
    level.lineJoinStyle = kCGLineJoinRound;
    [UIColor.labelColor setStroke];
    [level stroke];

    // 底下：开始时间、图例、结束时间
    CGFloat ly = h - 12 - small.lineHeight;
    [XRHLogClock([r[@"start"] doubleValue]) drawAtPoint:CGPointMake(pad, ly) withAttributes:smallAttr];
    NSString *endClock = XRHLogClock([r[@"end"] doubleValue]);
    [endClock drawAtPoint:CGPointMake(w - pad - [endClock sizeWithAttributes:smallAttr].width, ly) withAttributes:smallAttr];
    NSMutableAttributedString *legend = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"— %@", XRHL(@"电量")] attributes:smallAttr];
    if (maxW > 0) {
        [legend appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"    ┄ %@", XRHL(@"功率")]
                                                                       attributes:@{NSFontAttributeName: small, NSForegroundColorAttributeName: UIColor.systemTealColor}]];
    }
    [legend drawAtPoint:CGPointMake((w - legend.size.width) / 2, ly)];
}

@end



@implementation XRHLevelChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat pad = 16, w = self.bounds.size.width, h = self.bounds.size.height;
    UIFont *small = [UIFont systemFontOfSize:12];
    NSDictionary *smallAttr = @{NSFontAttributeName: small, NSForegroundColorAttributeName: UIColor.secondaryLabelColor};
    NSDictionary *axisAttr = @{NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: UIColor.tertiaryLabelColor};
    CGFloat legendY = h - 12 - small.lineHeight, axisY = legendY - 8 - small.lineHeight;
    CGRect area = CGRectMake(pad, 16, w - pad * 2 - 26, axisY - 6 - 16);
    double now = self.now, from = now - 24 * 3600;
    CGFloat (^xAt)(double) = ^CGFloat(double t) { return CGRectGetMinX(area) + area.size.width * MIN(MAX((t - from) / (now - from), 0), 1); };
    CGFloat (^yAt)(double) = ^CGFloat(double l) { return CGRectGetMaxY(area) - area.size.height * MIN(MAX(l, 0), 100) / 100; };

    // 网格：100 / 50 / 0，数字在右边
    CGFloat px = 1 / UIScreen.mainScreen.scale;
    [UIColor.separatorColor setStroke];
    for (NSNumber *l in @[@100, @50, @0]) {
        CGFloat y = round(yAt(l.doubleValue)) + px / 2;
        UIBezierPath *g = [UIBezierPath bezierPath];
        [g moveToPoint:CGPointMake(CGRectGetMinX(area), y)];
        [g addLineToPoint:CGPointMake(CGRectGetMaxX(area), y)];
        g.lineWidth = px;
        [g stroke];
        if (l.intValue > 0) [l.stringValue drawAtPoint:CGPointMake(CGRectGetMaxX(area) + 6, y - small.lineHeight / 2) withAttributes:axisAttr];
    }
    // 时间：24 小时前、12 小时前、现在
    [XRHLogClock(from) drawAtPoint:CGPointMake(CGRectGetMinX(area), axisY) withAttributes:axisAttr];
    NSString *mid = XRHLogClock(from + 12 * 3600), *nowText = XRHL(@"现在");
    [mid drawAtPoint:CGPointMake(CGRectGetMidX(area) - [mid sizeWithAttributes:axisAttr].width / 2, axisY) withAttributes:axisAttr];
    [nowText drawAtPoint:CGPointMake(CGRectGetMaxX(area) - [nowText sizeWithAttributes:axisAttr].width, axisY) withAttributes:axisAttr];

    // 图例
    NSMutableAttributedString *legend = [NSMutableAttributedString new];
    void (^item)(UIColor *, NSString *) = ^(UIColor *color, NSString *text) {
        if (legend.length) [legend appendAttributedString:[[NSAttributedString alloc] initWithString:@"     " attributes:smallAttr]];
        [legend appendAttributedString:[[NSAttributedString alloc] initWithString:@"■ " attributes:@{NSFontAttributeName: small, NSForegroundColorAttributeName: color}]];
        [legend appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:smallAttr]];
    };
    UIColor *chargeColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.2], *drainColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.25];
    item([UIColor.systemGreenColor colorWithAlphaComponent:0.5], XRHL(@"充电"));
    item([UIColor.systemOrangeColor colorWithAlphaComponent:0.6], XRHL(@"锁屏掉电快"));
    [legend drawAtPoint:CGPointMake(pad, legendY)];

    NSArray<NSArray *> *pts = self.levels;
    if (pts.count < 2) {
        NSString *wait = XRHL(@"数据收集中");
        CGSize ws = [wait sizeWithAttributes:smallAttr];
        [wait drawAtPoint:CGPointMake(CGRectGetMidX(area) - ws.width / 2, CGRectGetMidY(area) - ws.height / 2) withAttributes:smallAttr];
        if (pts.count == 0) return;
    }
    double (^T)(NSUInteger) = ^double(NSUInteger i) { return i < pts.count ? [pts[i][0] doubleValue] : now; };
    int (^F)(NSUInteger) = ^int(NSUInteger i) { return [pts[i][2] intValue]; };
    double (^L)(NSUInteger) = ^double(NSUInteger i) { return [pts[MIN(i, pts.count - 1)][1] doubleValue]; };

    // 底色：在充（绿）；锁屏、没接电源、每小时掉 > 3% 且至少半小时（橙）
    UIBezierPath *charge = [UIBezierPath bezierPath], *drain = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i < pts.count; i++) {
        if (F(i) & 2) [charge appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(xAt(T(i)), CGRectGetMinY(area), xAt(T(i + 1)) - xAt(T(i)), area.size.height)]];
    }
    for (NSUInteger i = 0; i < pts.count;) {
        if (!((F(i) & 4) && !(F(i) & 1))) { i++; continue; }
        NSUInteger j = i;
        while (j < pts.count && (F(j) & 4) && !(F(j) & 1)) j++;
        double hours = (T(j) - T(i)) / 3600, drop = L(i) - L(j);
        if (hours >= 0.5 && drop >= 3 && drop / hours > kXRHStandbyFast) {
            [drain appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(xAt(T(i)), CGRectGetMinY(area), xAt(T(j)) - xAt(T(i)), area.size.height)]];
        }
        i = j;
    }
    [chargeColor setFill];
    [charge fill];
    [drainColor setFill];
    [drain fill];

    // 电量线：画到现在（最后一笔之后没变化）
    UIBezierPath *line = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i < pts.count; i++) {
        CGPoint p = CGPointMake(xAt(T(i)), yAt(L(i)));
        if (i == 0) [line moveToPoint:p]; else [line addLineToPoint:p];
    }
    CGPoint end = CGPointMake(xAt(now), yAt(L(pts.count - 1)));
    [line addLineToPoint:end];
    line.lineWidth = 1.8;
    line.lineJoinStyle = kCGLineJoinRound;
    [UIColor.labelColor setStroke];
    [line stroke];
    [UIColor.labelColor setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(end.x - 3, end.y - 3, 6, 6)] fill];
}

@end


#pragma mark - 推送重连每小时柱状图

@implementation XRHPushChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat pad = 16, w = self.bounds.size.width, h = self.bounds.size.height;
    NSArray<NSNumber *> *counts = self.counts;
    UIFont *small = [UIFont systemFontOfSize:12];
    NSDictionary *smallAttr = @{NSFontAttributeName: small, NSForegroundColorAttributeName: UIColor.secondaryLabelColor};

    // 424 次  最近 24 小时
    NSString *big = [NSString stringWithFormat:XRHL(@"%ld 次"), (long)XRHPushTotal(counts)];
    NSDictionary *bigAttr = @{NSFontAttributeName: [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: UIColor.labelColor};
    CGSize bs = [big sizeWithAttributes:bigAttr];
    [big drawAtPoint:CGPointMake(pad, 14) withAttributes:bigAttr];
    [XRHL(@"最近 24 小时") drawAtPoint:CGPointMake(pad + bs.width + 8, 14 + bs.height - small.lineHeight - 3) withAttributes:smallAttr];

    CGFloat axisY = h - 12 - small.lineHeight;
    CGRect area = CGRectMake(pad, 14 + bs.height + 14, w - pad * 2, axisY - 8 - (14 + bs.height + 14));
    double top = MAX(XRHPushMax(counts), kXRHPushBad * 2);
    CGFloat slot = area.size.width / MAX(counts.count, 1), bar = MAX(slot - 3, 2);
    for (NSUInteger i = 0; i < counts.count; i++) {
        double c = counts[i].doubleValue;
        CGFloat bh = MAX(area.size.height * c / top, c > 0 ? 2 : 0);
        [(c > kXRHPushBad ? UIColor.systemOrangeColor : UIColor.tertiaryLabelColor) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMinX(area) + slot * i + (slot - bar) / 2, CGRectGetMaxY(area) - bh, bar, bh) cornerRadius:1.5] fill];
    }
    // 15 次参考线
    CGFloat ly = round(CGRectGetMaxY(area) - area.size.height * kXRHPushBad / top) + 0.5;
    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:CGPointMake(CGRectGetMinX(area), ly)];
    [line addLineToPoint:CGPointMake(CGRectGetMaxX(area), ly)];
    CGFloat dash[] = {4, 3};
    [line setLineDash:dash count:2 phase:0];
    line.lineWidth = 1;
    [[UIColor.systemOrangeColor colorWithAlphaComponent:0.7] setStroke];
    [line stroke];

    // 底下：开始时间、参考线说明、现在
    NSDictionary *axisAttr = @{NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular], NSForegroundColorAttributeName: UIColor.tertiaryLabelColor};
    [XRHLogClock(self.from) drawAtPoint:CGPointMake(pad, axisY) withAttributes:axisAttr];
    NSString *mid = [NSString stringWithFormat:XRHL(@"┄ %d 次/时"), kXRHPushBad], *now = XRHL(@"现在");
    NSDictionary *midAttr = @{NSFontAttributeName: small, NSForegroundColorAttributeName: UIColor.systemOrangeColor};
    [mid drawAtPoint:CGPointMake((w - [mid sizeWithAttributes:midAttr].width) / 2, axisY) withAttributes:midAttr];
    [now drawAtPoint:CGPointMake(w - pad - [now sizeWithAttributes:axisAttr].width, axisY) withAttributes:axisAttr];
}

@end

