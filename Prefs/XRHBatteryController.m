#import "XRHBatteryController.h"
#import "XRHGuideController.h"
#import "XRHLocalize.h"
#import "XRBattery.h"
#import "XRBatteryEstimate.h"
#import <Preferences/PSSpecifier.h>

@interface PSListController (XRHBatteryPrivate)
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

#pragma mark - 格式

static NSString *const kXRHDash = @"—";

static NSString *XRHMah(double v) {
    return isnan(v) ? kXRHDash : [NSString stringWithFormat:@"%.0f mAh", v];
}

NSString *XRHBatteryHealthText(void) {
    double h = XRBatteryHealth();
    return isnan(h) ? kXRHDash : [NSString stringWithFormat:@"%.0f%%", h * 100];
}

// 首页那一行的图标：和系统设置「电池」一样的绿底白电池，29pt
UIImage *XRHBatteryRowIcon(void) {
    static UIImage *icon;
    if (icon) return icon;
    CGSize size = CGSizeMake(29, 29);
    UIImage *glyph = [[UIImage systemImageNamed:@"battery.100percent"
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]]
                      imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    icon = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemGreenColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] fill];
        if (glyph) [glyph drawInRect:CGRectMake((size.width - glyph.size.width) / 2, (size.height - glyph.size.height) / 2,
                                                glyph.size.width, glyph.size.height)];
    }];
    return icon;
}

#pragma mark - 充电上限（设置在 ChargeLimit 页，停充由后台服务 xrhead 做）

// 充电上限现在管不管（开着、总开关开着、不是「这次充满」）
static BOOL XRHLimitOn(void) {
    CFPropertyListRef on = CFPreferencesCopyAppValue(CFSTR("chargeLimit"), CFSTR("com.xyrith.xrhea"));
    CFPropertyListRef master = CFPreferencesCopyAppValue(CFSTR("enabled"), CFSTR("com.xyrith.xrhea"));
    CFPropertyListRef once = CFPreferencesCopyAppValue(CFSTR("chargeLimitFullOnce"), CFSTR("com.xyrith.xrhea"));
    BOOL r = (on && [(__bridge id)on boolValue]) && (!master || [(__bridge id)master boolValue]) && !(once && [(__bridge id)once boolValue]);
    if (on) CFRelease(on);
    if (master) CFRelease(master);
    if (once) CFRelease(once);
    return r;
}

static int XRHLimitMax(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("chargeLimitMax"), CFSTR("com.xyrith.xrhea"));
    int max = v ? [(__bridge id)v intValue] : 80;
    if (v) CFRelease(v);
    return MAX(50, MIN(100, max));
}

// 现在是不是被 xrhea 停在上限（服务写的状态文件 + 接着电源 + 没在充）
static BOOL XRHLimitHolding(void) {
    if (!XRHLimitOn() || !XRBatteryExternalConnected() || XRBatteryIsCharging()) return NO;
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist"];
    return [state[@"inhibited"] boolValue];
}

#pragma mark - 异常判断（标 ⚠️，点开给解决办法）

// 一条异常：@[标题, 解决办法, @(是否严重)]；没有异常返回 nil。严重的标红，其余标橙
typedef NSArray *XRHWarning;
static XRHWarning XRHMakeWarning(NSString *title, NSString *message, BOOL severe) { return @[title, message, @(severe)]; }

static XRHWarning XRHWarnHealth(void) {
    double h = XRBatteryHealth();
    if (isnan(h) || h >= 0.8) return nil;
    return XRHMakeWarning(XRHL(@"最大容量低于 80%"),
        XRHL(@"电池已经明显老化，续航会变短。\n• 可以考虑换电池\n• 常插着线的话，打开「设置 › 电池 › 充电」里的 80% 上限，能延缓老化"), NO);
}

static XRHWarning XRHWarnTemp(void) {
    double t = XRBatteryTemperature();
    if (isnan(t) || t < 40) return nil;
    BOOL severe = t >= 45;
    return XRHMakeWarning(severe ? XRHL(@"电池过热") : XRHL(@"电池偏热"),
        XRHL(@"• 拔掉充电线\n• 退出游戏等耗电大的 App\n• 取下手机壳，放在阴凉处"), severe);
}

// 有线充电器只谈到 5 V：线或头不支持快充
static XRHWarning XRHWarnLowVoltage(void) {
    if (!XRBatteryExternalConnected() || XRBatteryAdapterIsWireless()) return nil;
    double v = XRBatteryAdapterVoltage();
    if (isnan(v) || v > 5.5) return nil;
    return XRHMakeWarning(XRHL(@"不支持快充"),
        XRHL(@"充电器和手机只谈到了 5 V，线或充电头不支持快充。\n• 换成支持 USB-C PD 快充的线和充电头"), NO);
}

// 充得太慢：插着有线充电器、在充、电量低于 80%，最近 30 秒功率一直低于 5 W（要攒满 30 秒才判断，详情页才有）
static XRHWarning XRHWarnSlowCharge(NSArray<NSNumber *> *watts) {
    if (watts.count < 30 || !XRBatteryIsCharging() || XRBatteryAdapterIsWireless()) return nil;
    double level = XRBatteryLevel();
    if (isnan(level) || level >= 80) return nil;
    for (NSNumber *w in [watts subarrayWithRange:NSMakeRange(watts.count - 30, 30)]) if (w.doubleValue >= 5) return nil;
    return XRHMakeWarning(XRHL(@"充电太慢"),
        XRHL(@"插着充电器，功率却一直低于 5 W。\n• 换一根线或换个充电头试试\n• 手机太热时也会自动降速"), NO);
}

// 耗电太快：用电池时，最近 1 分钟平均功率高于 6 W（大约是玩大型游戏的水平；要攒满 1 分钟才判断，详情页才有）。
// timeLeft：按现在的速度还能用多久（详情页「预计」那一格算好传进来，算不出来传 nil）
static XRHWarning XRHWarnHighDrain(NSArray<NSNumber *> *watts, NSString *timeLeft) {
    if (watts.count < 60 || XRBatteryExternalConnected()) return nil;
    double sum = 0;
    for (NSNumber *w in watts) sum += w.doubleValue;
    if (sum / watts.count <= 6) return nil;
    NSString *head = timeLeft ? [NSString stringWithFormat:XRHL(@"按现在的速度，约 %@ 用完。"), timeLeft] : XRHL(@"现在耗电比平时快很多。");
    return XRHMakeWarning(XRHL(@"耗电很快"),
        [head stringByAppendingString:XRHL(@"\n• 退出不用的 App，尤其是游戏和导航\n• 调低屏幕亮度\n• 打开低电量模式")], NO);
}

// 首页不开计时器，只看不用攒数据的几项
static BOOL XRHBatteryHasWarning(void) {
    return XRHWarnHealth() || XRHWarnTemp() || XRHWarnLowVoltage();
}

static UIImage *XRHWarnImage(BOOL severe) {
    return [[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]
            imageWithTintColor:severe ? UIColor.systemRedColor : UIColor.systemOrangeColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}

// 在文字后面接一个 ⚠️ 小图标（和文字垂直居中）
static NSAttributedString *XRHWithWarnIcon(NSString *text, UIFont *font, UIColor *color, BOOL severe, BOOL iconFirst) {
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    NSTextAttachment *att = [NSTextAttachment new];
    att.image = XRHWarnImage(severe);
    CGFloat h = font.capHeight + 3;
    att.bounds = CGRectMake(0, (font.capHeight - h) / 2, h * att.image.size.width / MAX(1, att.image.size.height), h);
    NSAttributedString *icon = [NSAttributedString attributedStringWithAttachment:att];
    NSAttributedString *body = [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}];
    NSAttributedString *gapStr = [[NSAttributedString alloc] initWithString:@" " attributes:@{NSFontAttributeName: font}];
    if (iconFirst) { [s appendAttributedString:icon]; [s appendAttributedString:gapStr]; [s appendAttributedString:body]; }
    else { [s appendAttributedString:body]; [s appendAttributedString:gapStr]; [s appendAttributedString:icon]; }
    return s;
}

// 首页「电池信息」一行右边：有异常时健康度前面带 ⚠️
NSAttributedString *XRHBatteryRowDetail(UIFont *font, UIColor *color) {
    NSString *text = XRHBatteryHealthText();
    if (!XRHBatteryHasWarning()) return [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}];
    BOOL severe = [XRHWarnTemp()[2] boolValue];
    return XRHWithWarnIcon(text, font, color, severe, YES);
}

// 点 ⚠️ 弹出的说明：解决办法左对齐（一条条往下读）
static void XRHShowWarning(UIViewController *vc, XRHWarning w) {
    if (!w) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:w[0] message:w[1] preferredStyle:UIAlertControllerStyleAlert];
    NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
    para.alignment = NSTextAlignmentLeft;
    para.paragraphSpacing = 4;
    @try {
        [alert setValue:[[NSAttributedString alloc] initWithString:w[1] attributes:@{
            NSParagraphStyleAttributeName: para, NSFontAttributeName: [UIFont systemFontOfSize:13]}] forKey:@"attributedMessage"];
    } @catch (__unused NSException *e) {}
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"好") style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 顶部：大字最大容量 + 进度条

// 颜色同图标：薄荷 → 青
@interface XRHBatteryHeader : UIView
@property (nonatomic, strong) UILabel *bigLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) CAGradientLayer *fill;
@property (nonatomic) double health;   // 0～1，NAN = 读不到
@property (nonatomic, strong) XRHWarning warning;          // 最大容量低于 80% 时有值：说明文字后面带 ⚠️，点顶部弹出解决办法
@property (nonatomic, copy) void (^onWarningTap)(XRHWarning warning);
@end

@implementation XRHBatteryHeader

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _bigLabel = [UILabel new];
        _bigLabel.font = [UIFont systemFontOfSize:56 weight:UIFontWeightBold];
        _bigLabel.textAlignment = NSTextAlignmentCenter;
        _bigLabel.textColor = UIColor.labelColor;
        [self addSubview:_bigLabel];

        _captionLabel = [UILabel new];
        _captionLabel.font = [UIFont systemFontOfSize:14];
        _captionLabel.textAlignment = NSTextAlignmentCenter;
        _captionLabel.textColor = UIColor.secondaryLabelColor;
        _captionLabel.text = XRHL(@"最大容量（相对新电池）");
        [self addSubview:_captionLabel];

        _track = [UIView new];
        _track.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.12];
        _track.layer.cornerRadius = 3;
        [self addSubview:_track];

        _fill = [CAGradientLayer layer];
        _fill.colors = @[(id)[UIColor colorWithRed:0x3D/255.0 green:0xF5/255.0 blue:0xA8/255.0 alpha:1].CGColor,
                         (id)[UIColor colorWithRed:0x1A/255.0 green:0xB8/255.0 blue:0xFF/255.0 alpha:1].CGColor];
        _fill.startPoint = CGPointMake(0, 0.5);
        _fill.endPoint = CGPointMake(1, 0.5);
        _fill.cornerRadius = 3;
        _fill.shadowColor = [UIColor colorWithRed:0x2E/255.0 green:0xE6/255.0 blue:0xC0/255.0 alpha:1].CGColor;
        _fill.shadowOpacity = 0.55;
        _fill.shadowRadius = 5;
        _fill.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_fill];
        _health = NAN;
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(xrh_tap)]];
    }
    return self;
}

- (void)xrh_tap {
    if (_warning && _onWarningTap) _onWarningTap(_warning);
}

- (void)setWarning:(XRHWarning)warning {
    if ((warning == nil) == (_warning == nil)) { _warning = warning; return; }
    _warning = warning;
    NSString *caption = XRHL(@"最大容量（相对新电池）");
    if (warning) _captionLabel.attributedText = XRHWithWarnIcon(caption, _captionLabel.font, UIColor.secondaryLabelColor, NO, NO);
    else _captionLabel.text = caption;
}

- (void)setHealth:(double)health {
    _health = health;
    _bigLabel.text = isnan(health) ? kXRHDash : [NSString stringWithFormat:@"%.0f%%", health * 100];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _bigLabel.frame = CGRectMake(0, 14, w, 64);
    _captionLabel.frame = CGRectMake(0, 80, w, 20);
    CGFloat barW = MIN(240, w - 64);
    _track.frame = CGRectMake((w - barW) / 2, 114, barW, 6);
    double h = isnan(_health) ? 0 : MAX(0, MIN(1, _health));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = CGRectMake(_track.frame.origin.x, 114, barW * h, 6);
    [CATransaction commit];
}

@end

#pragma mark - 详情页

// 数值行上要特殊上色的：功率（充电时绿）、温度（≥40℃ 橙、≥45℃ 红）
static NSString *const kXRHRowPower = @"xrhPower";
static NSString *const kXRHRowTemp = @"xrhTemp";
static NSString *const kXRHRowSpec = @"xrhSpec";

@implementation XRHBatteryController {
    XRHBatteryHeader *_header;
    NSTimer *_timer;
    BOOL _connected;                   // 页面上现在是不是带着「充电器」那一组
    NSMutableArray<NSNumber *> *_amps; // 最近 30 秒的电流（mA），算预计时间用，避免每秒乱跳
    NSMutableArray<NSNumber *> *_watts; // 最近 60 秒的功率（W），判断「充电太慢」（看后 30 秒）和「耗电很快」（看整 1 分钟）用
}

static PSSpecifier *XRHValueRow(id target, NSString *label, SEL getter) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:XRHL(label) target:target set:NULL get:getter
                                                    detail:Nil cell:PSTitleValueCell edit:Nil];
    return s;
}

- (PSSpecifier *)xrh_row:(NSString *)label get:(SEL)getter id:(NSString *)rowID {
    PSSpecifier *s = XRHValueRow(self, label, getter);
    [s setProperty:rowID forKey:@"id"];
    return s;
}

// 这一行现在有没有异常（只有标了 id 的几行会有）
- (XRHWarning)xrh_warningForRow:(NSString *)rowID {
    if ([rowID isEqualToString:kXRHRowTemp]) return XRHWarnTemp();
    if ([rowID isEqualToString:kXRHRowSpec]) return XRHWarnLowVoltage();
    if ([rowID isEqualToString:kXRHRowPower]) return XRHWarnSlowCharge(_watts) ?: XRHWarnHighDrain(_watts, [self xrh_timeLeft]);
    return nil;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _connected = XRBatteryExternalConnected();
        NSMutableArray *list = [NSMutableArray array];

        // 实时（每秒刷新）
        PSSpecifier *live = [PSSpecifier groupSpecifierWithName:XRHL(@"实时")];
        [live setProperty:XRHL(@"充电预计已经算上了 80% 以后会变慢；用完预计按你此刻的用法算，换个用法就会变。") forKey:@"footerText"];
        PSSpecifier *power = XRHValueRow(self, @"功率", @selector(xrhPower:));
        [power setProperty:kXRHRowPower forKey:@"id"];
        PSSpecifier *temp = XRHValueRow(self, @"温度", @selector(xrhTemperature:));
        [temp setProperty:kXRHRowTemp forKey:@"id"];
        [list addObjectsFromArray:@[
            live,
            XRHValueRow(self, @"状态", @selector(xrhState:)),
            XRHValueRow(self, @"电量", @selector(xrhLevel:)),
            power,
            XRHValueRow(self, @"电压", @selector(xrhVoltage:)),
            XRHValueRow(self, @"电流", @selector(xrhAmperage:)),
            temp,
            XRHValueRow(self, @"预计", @selector(xrhEstimate:)),
        ]];

        // 充电器（只在接着电源时出现）
        if (_connected) {
            PSSpecifier *adapter = [PSSpecifier groupSpecifierWithName:XRHL(@"充电器")];
            [adapter setProperty:XRHL(@"型号是充电器自己报上来的名字（苹果的内部写法）。") forKey:@"footerText"];
            [list addObjectsFromArray:@[
                adapter,
                XRHValueRow(self, @"最大功率", @selector(xrhAdapterWatts:)),
                [self xrh_row:@"规格" get:@selector(xrhAdapterSpec:) id:kXRHRowSpec],
                XRHValueRow(self, @"型号", @selector(xrhAdapterName:)),
            ]];
        }

        // 容量
        PSSpecifier *capacity = [PSSpecifier groupSpecifierWithName:XRHL(@"容量")];
        [capacity setProperty:XRHL(@"实际容量是现在充满时能装多少电；最大容量 = 实际容量 ÷ 设计容量。") forKey:@"footerText"];
        [list addObjectsFromArray:@[
            capacity,
            XRHValueRow(self, @"实际容量", @selector(xrhFullCapacity:)),
            XRHValueRow(self, @"设计容量", @selector(xrhDesignCapacity:)),
            XRHValueRow(self, @"当前电量", @selector(xrhCurrentCharge:)),
            [PSSpecifier groupSpecifierWithName:XRHL(@"使用")],
            XRHValueRow(self, @"循环次数", @selector(xrhCycleCount:)),
            // 最底下：指南页入口
            [PSSpecifier emptyGroupSpecifier],
            [PSSpecifier preferenceSpecifierNamed:XRHL(@"这些数字怎么看") target:self set:NULL get:NULL
                                           detail:XRHGuideController.class cell:PSLinkCell edit:Nil],
        ]];
        _specifiers = list;
        self.title = XRHL(@"电池信息");
    }
    return _specifiers;
}

#pragma mark 实时

- (id)xrhState:(PSSpecifier *)s {
    if (!XRBatteryExternalConnected()) return XRHL(@"使用电池");
    if (XRHLimitHolding()) return [NSString stringWithFormat:XRHL(@"已到上限 %d%%"), XRHLimitMax()];
    if (XRBatteryFullyCharged()) return XRHL(@"已充满");
    return XRBatteryIsCharging() ? XRHL(@"充电中") : XRHL(@"已接电源，暂停充电");
}

- (id)xrhLevel:(PSSpecifier *)s {
    double l = XRBatteryLevel();
    return isnan(l) ? kXRHDash : [NSString stringWithFormat:@"%.0f%%", l];
}

// 接着电源时显示充电头送进来的总功率（和数显线对得上），用电池时显示耗电功率
- (id)xrhPower:(PSSpecifier *)s {
    double w = XRBatteryPowerWatts();
    return isnan(w) ? kXRHDash : [NSString stringWithFormat:@"%.1f W", w];
}

- (id)xrhVoltage:(PSSpecifier *)s {
    double v = XRBatteryVoltage();
    return isnan(v) ? kXRHDash : [NSString stringWithFormat:@"%.2f V", v / 1000];
}

// 充电为正、放电为负（用真正的减号）
- (id)xrhAmperage:(PSSpecifier *)s {
    double a = XRBatteryAmperage();
    if (isnan(a)) return kXRHDash;
    return [NSString stringWithFormat:@"%@%.0f mA", a > 0 ? @"+" : (a < 0 ? @"−" : @""), fabs(a)];
}

- (id)xrhTemperature:(PSSpecifier *)s {
    double t = XRBatteryTemperature();
    return isnan(t) ? kXRHDash : [NSString stringWithFormat:@"%.1f ℃", t];
}

// 时长：「1 小时 20 分」/「45 分」
static NSString *XRHDuration(double minutes) {
    long m = XRHRoundMinutes(minutes);
    if (m < 60) return [NSString stringWithFormat:XRHL(@"%ld 分"), m];
    if (m % 60 == 0) return [NSString stringWithFormat:XRHL(@"%ld 小时"), m / 60];
    return [NSString stringWithFormat:XRHL(@"%ld 小时 %ld 分"), m / 60, m % 60];
}

// 充电后段变慢的系数和 XRHMinutesToTarget 在 Shared/XRBatteryEstimate.h（和插件的插电提醒共用）

// 充电：分两段算（见上）；放电：剩余电量 ÷ 平均电流。都用「电量 % × 实际容量」当剩余电量，
// 不用 AppleRawCurrentCapacity（它对应的是 AppleRawMaxCapacity，和实际容量不是一套，混着用会算偏）。电流太小（<50mA）时不估
- (id)xrhEstimate:(PSSpecifier *)s {
    // 定时充满在等着（xrhead 算好了时间、还没开始充）：「5:40 开始充，7:00 前充满」
    if (XRBatteryExternalConnected() && XRHLimitOn()) {
        NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist"];
        double start = [state[@"schedStart"] doubleValue], full = [state[@"schedFull"] doubleValue];
        if (full > 0 && ![state[@"schedActive"] boolValue]) {
            NSDateFormatter *f = [NSDateFormatter new];
            f.dateFormat = @"H:mm";
            return [NSString stringWithFormat:XRHL(@"%@ 开始充，%@ 前充满"),
                    [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:start]], [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:full]]];
        }
    }
    if (XRBatteryExternalConnected() && XRHLimitHolding()) return XRHL(@"已到上限");
    if (XRBatteryFullyCharged()) return XRHL(@"已充满");
    double avg = 0;
    for (NSNumber *n in _amps) avg += n.doubleValue;
    avg = _amps.count ? avg / _amps.count : NAN;
    double level = XRBatteryLevel(), full = XRBatteryFullCapacity();
    if (isnan(avg) || isnan(level) || isnan(full) || fabs(avg) < 50) return kXRHDash;
    BOOL charging = XRBatteryIsCharging();
    if (charging && avg > 0) {
        if (XRHLimitOn()) {
            int max = XRHLimitMax();
            if (level >= max) return XRHL(@"已到上限");
            return [NSString stringWithFormat:XRHL(@"约 %@ 到 %d%%"), XRHDuration(XRHMinutesToTarget(level, max, full, avg)), max];
        }
        return [NSString stringWithFormat:XRHL(@"约 %@ 充满"), XRHDuration(XRHMinutesToTarget(level, 100, full, avg))];
    }
    if (!charging && avg < 0) {
        return [NSString stringWithFormat:XRHL(@"约 %@ 用完"), XRHDuration(level / 100 * full / -avg * 60)];
    }
    return kXRHDash;
}

// 用电池时还能用多久（「耗电很快」的说明里用）；算不出来返回 nil
- (NSString *)xrh_timeLeft {
    double avg = 0;
    for (NSNumber *n in _amps) avg += n.doubleValue;
    avg = _amps.count ? avg / _amps.count : NAN;
    double level = XRBatteryLevel(), full = XRBatteryFullCapacity();
    if (isnan(avg) || isnan(level) || isnan(full) || avg > -50) return nil;
    return XRHDuration(level / 100 * full / -avg * 60);
}

#pragma mark 充电器

- (id)xrhAdapterWatts:(PSSpecifier *)s {
    double w = XRBatteryAdapterWatts();
    return isnan(w) ? kXRHDash : [NSString stringWithFormat:@"%.0f W", w];
}

- (id)xrhAdapterSpec:(PSSpecifier *)s {
    if (XRBatteryAdapterIsWireless()) return XRHL(@"无线");
    double v = XRBatteryAdapterVoltage(), a = XRBatteryAdapterCurrent();
    if (isnan(v) || isnan(a)) return kXRHDash;
    return [NSString stringWithFormat:@"%g V · %g A", round(v * 10) / 10, round(a * 10) / 10];
}

- (id)xrhAdapterName:(PSSpecifier *)s { return XRBatteryAdapterName() ?: kXRHDash; }

#pragma mark 容量

- (id)xrhFullCapacity:(PSSpecifier *)s   { return XRHMah(XRBatteryFullCapacity()); }
- (id)xrhDesignCapacity:(PSSpecifier *)s { return XRHMah(XRBatteryDesignCapacity()); }
- (id)xrhCurrentCharge:(PSSpecifier *)s  { return XRHMah(XRBatteryCurrentCharge()); }
- (id)xrhCycleCount:(PSSpecifier *)s {
    double c = XRBatteryCycleCount();
    return isnan(c) ? kXRHDash : [NSString stringWithFormat:XRHL(@"%.0f 次"), c];
}

#pragma mark 页面

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = XRHL(@"电池信息");
    _amps = [NSMutableArray array];
    _watts = [NSMutableArray array];
    _header = [[XRHBatteryHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 140)];
    _header.health = XRBatteryHealth();
    _header.warning = XRHWarnHealth();
    __weak typeof(self) weakSelf = self;
    _header.onWarningTap = ^(XRHWarning w) { XRHShowWarning(weakSelf, w); };
    self.table.tableHeaderView = _header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_amps removeAllObjects];
    [_watts removeAllObjects];
    [self xrh_refresh];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [weakSelf xrh_refresh]; }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    NSString *rowID = [[self specifierAtIndexPath:indexPath] propertyForKey:@"id"];
    UIColor *color = UIColor.secondaryLabelColor;
    if ([rowID isEqualToString:kXRHRowPower] && XRBatteryIsCharging()) color = UIColor.systemGreenColor;
    if ([rowID isEqualToString:kXRHRowTemp]) {
        double t = XRBatteryTemperature();
        if (t >= 45) color = UIColor.systemRedColor;
        else if (t >= 40) color = UIColor.systemOrangeColor;
    }
    cell.detailTextLabel.textColor = color;
    // 有异常：右边挂 ⚠️，这一行可以点（点开看解决办法）；cell 会复用，没异常时要清掉
    XRHWarning w = [self xrh_warningForRow:rowID];
    if (w) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:XRHWarnImage([w[2] boolValue])];
        iv.frame = CGRectMake(0, 0, 20, 18);
        iv.contentMode = UIViewContentModeScaleAspectFit;
        cell.accessoryView = iv;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.accessoryView = nil;
        if (rowID) cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    XRHWarning w = [self xrh_warningForRow:[[self specifierAtIndexPath:indexPath] propertyForKey:@"id"]];
    if (w) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        XRHShowWarning(self, w);
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// 每秒：记一笔电流；插拔电源时整页重建（「充电器」那组要出现 / 消失），平时只刷新数值行（不会闪）
- (void)xrh_refresh {
    // 「这次充满」是 SpringBoard 写的，这个进程里的缓存要同步一下才看得到
    CFPreferencesAppSynchronize(CFSTR("com.xyrith.xrhea"));
    double a = XRBatteryAmperage();
    if (!isnan(a)) {
        [_amps addObject:@(a)];
        if (_amps.count > 30) [_amps removeObjectAtIndex:0];
    }
    double w = XRBatteryPowerWatts();
    if (!isnan(w)) {
        [_watts addObject:@(w)];
        if (_watts.count > 60) [_watts removeObjectAtIndex:0];
    }
    _header.health = XRBatteryHealth();
    _header.warning = XRHWarnHealth();
    if (XRBatteryExternalConnected() != _connected) {
        [_amps removeAllObjects];   // 插拔前后的电流方向相反，混在一起算不准
        [_watts removeAllObjects];
        [self reloadSpecifiers];
        return;
    }
    for (PSSpecifier *s in _specifiers) {
        if (s.cellType == PSTitleValueCell) [self reloadSpecifier:s animated:NO];
    }
}

@end
