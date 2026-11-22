#import "XRHOptimizeStatusCell.h"
#import "XRHLocalize.h"
#import "XRHKeys.h"
#import "XRBattery.h"

static BOOL XRHPrefOn(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.xyrith.xrhea"));
    BOOL on = v && [(__bridge id)v respondsToSelector:@selector(boolValue)] && [(__bridge id)v boolValue];
    if (v) CFRelease(v);
    return on;
}

static NSInteger XRHPrefInteger(NSString *key, NSInteger fallback) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.xyrith.xrhea"));
    NSInteger i = v && [(__bridge id)v respondsToSelector:@selector(integerValue)] ? [(__bridge id)v integerValue] : fallback;
    if (v) CFRelease(v);
    return i;
}

@implementation XRHOptimizeStatusCell {
    UIView *_dot;
    UILabel *_title, *_value;
    NSTimer *_timer;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _dot = [UIView new];
    _dot.layer.cornerRadius = 4;
    _title = [UILabel new];
    _title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _value = [UILabel new];
    _value.font = [UIFont monospacedDigitSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightRegular];
    _value.textColor = UIColor.secondaryLabelColor;
    _value.textAlignment = NSTextAlignmentRight;
    for (UIView *v in @[_dot, _title, _value]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:v];
    }
    UILayoutGuide *m = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_dot.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [_dot.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_dot.widthAnchor constraintEqualToConstant:8],
        [_dot.heightAnchor constraintEqualToConstant:8],
        [_title.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:10],
        [_title.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_value.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [_value.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_value.leadingAnchor constraintGreaterThanOrEqualToAnchor:_title.trailingAnchor constant:12],
    ]];
    [self xrh_refresh];
    return self;
}

// PSTableCell 会把 plist 里的 label（「状态」）填进自带的 textLabel，和自己画的文字叠在一起：藏掉
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.hidden = YES;
    self.detailTextLabel.hidden = YES;
}

// 在屏幕上时每 2 秒刷新，离开就停
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate];
    _timer = nil;
    if (!self.window) return;
    [self xrh_refresh];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) { [weakSelf xrh_refresh]; }];
}

- (void)xrh_refresh {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:XRH_LIMIT_STATE_FILE];
    BOOL connected = XRBatteryExternalConnected();
    double temp = XRBatteryTemperature();
    NSString *tempText = isnan(temp) ? @"—" : [NSString stringWithFormat:@"%.1f ℃", temp];
    UIColor *dot = UIColor.systemGrayColor;
    NSString *title, *value = tempText;

    CFPropertyListRef master = CFPreferencesCopyAppValue(CFSTR("enabled"), CFSTR("com.xyrith.xrhea"));
    BOOL enabled = !master || [(__bridge id)master boolValue];
    if (master) CFRelease(master);

    if (!enabled) {
        title = XRHL(@"未开启");
    } else if (connected && [state[@"thermalHot"] boolValue]) {
        dot = UIColor.systemOrangeColor;
        title = XRHL(@"高温保护");
        NSString *mode = XRHPrefInteger(@"thermalMode", 1) == 0 ? XRHL(@"停充") : XRHL(@"间歇充电");
        value = [NSString stringWithFormat:@"%@ · %@", mode, tempText];
    } else if (connected && [state[@"bypass"] boolValue]) {
        dot = UIColor.systemGreenColor;
        title = XRHL(@"直充中");
        NSDictionary *t = XRBatteryObject(@"PowerTelemetryData");
        id load = [t isKindOfClass:NSDictionary.class] ? t[@"SystemLoad"] : nil;
        if ([load isKindOfClass:NSNumber.class]) value = [NSString stringWithFormat:@"%.1f W · %@", [load doubleValue] / 1000, tempText];
    } else if (XRHPrefOn(@"thermalGuard") || XRHPrefOn(@"bypassCharge") || XRHPrefOn(@"bgDrainAlert")) {
        title = XRHL(@"未触发");
    } else {
        title = XRHL(@"未开启");
    }
    _dot.backgroundColor = dot;
    _title.text = title;
    _value.text = value;
}

@end
