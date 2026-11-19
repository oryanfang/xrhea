#import "XRHIslandStyleCell.h"
#import "XRHLocalize.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

@interface PSListController (XRHIslandStyleCell)
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

static UIColor *XRHMint(void) { return [UIColor colorWithRed:0x3D/255.0 green:0xF5/255.0 blue:0xA8/255.0 alpha:1]; }

@implementation XRHIslandStyleCell {
    NSArray<UIControl *> *_options;    // 0 长条、1 短条
    NSArray<UIView *> *_previews;      // 缩略图（选中时描边）
    NSArray<UILabel *> *_names;
    NSArray<UIImageView *> *_radios;   // 圆形选择钮（同系统浅色 / 深色那个）
    NSInteger _selected;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    NSMutableArray *options = [NSMutableArray array], *previews = [NSMutableArray array], *names = [NSMutableArray array], *radios = [NSMutableArray array];
    for (NSInteger i = 0; i < 2; i++) {
        UIControl *option = [UIControl new];
        option.tag = i;
        [option addTarget:self action:@selector(xrh_tapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:option];

        UIView *preview = [UIView new];
        preview.userInteractionEnabled = NO;
        preview.backgroundColor = [UIColor colorWithRed:0.23 green:0.33 blue:0.38 alpha:1];   // 像一块墙纸
        preview.layer.cornerRadius = 12;
        preview.layer.cornerCurve = kCACornerCurveContinuous;
        preview.layer.borderColor = UIColor.systemTealColor.CGColor;
        preview.clipsToBounds = YES;
        [option addSubview:preview];

        UILabel *name = [UILabel new];
        name.userInteractionEnabled = NO;
        name.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        [option addSubview:name];

        UIImageView *radio = [UIImageView new];
        radio.userInteractionEnabled = NO;
        radio.contentMode = UIViewContentModeScaleAspectFit;
        [option addSubview:radio];

        [options addObject:option];
        [previews addObject:preview];
        [names addObject:name];
        [radios addObject:radio];
    }
    _options = options;
    _previews = previews;
    _names = names;
    _radios = radios;
    [self xrh_loadFromSpecifier:specifier];
    return self;
}

// 用的是 PSStaticTextCell 类型，系统可能把它设成"不可用"（变灰、不能点），这里始终保持可用
- (void)setCellEnabled:(BOOL)enabled {
    [super setCellEnabled:YES];
    self.userInteractionEnabled = YES;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.text = nil;
    [self xrh_loadFromSpecifier:specifier];
}

- (void)xrh_loadFromSpecifier:(PSSpecifier *)specifier {
    if (!specifier) return;
    self.textLabel.text = nil;
    id value = nil;
    if ([specifier.target respondsToSelector:@selector(readPreferenceValue:)]) value = [specifier.target readPreferenceValue:specifier];
    if (!value) value = [specifier propertyForKey:@"default"];
    _selected = [value integerValue] == 1 ? 1 : 0;
    [self xrh_updateSelection];
}

- (void)xrh_updateSelection {
    NSArray *titles = @[XRHL(@"长条"), XRHL(@"短条")];
    for (NSInteger i = 0; i < 2; i++) {
        BOOL on = i == _selected;
        _previews[i].layer.borderWidth = on ? 2 : 0;
        _names[i].text = titles[i];
        _names[i].textColor = UIColor.labelColor;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        _radios[i].image = [UIImage systemImageNamed:on ? @"checkmark.circle.fill" : @"circle" withConfiguration:cfg];
        _radios[i].tintColor = on ? UIColor.systemTealColor : UIColor.tertiaryLabelColor;
    }
}

- (void)xrh_tapped:(UIControl *)sender {
    if (sender.tag == _selected) return;
    _selected = sender.tag;
    [self xrh_updateSelection];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    id target = self.specifier.target;
    if ([target respondsToSelector:@selector(setPreferenceValue:specifier:)]) [target setPreferenceValue:@(_selected) specifier:self.specifier];
}

#pragma mark - 排版：两张缩略图左右并排（同系统「显示与亮度」的浅色 / 深色），下面名字 + 圆形选择钮

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets m = self.contentView.layoutMargins;
    CGFloat avail = self.contentView.bounds.size.width - m.left - m.right;
    CGFloat gap = 28, tileW = MIN(132, (avail - gap) / 2), previewH = 64;
    CGFloat x0 = m.left + (avail - tileW * 2 - gap) / 2, y = 18;
    for (NSInteger i = 0; i < 2; i++) {
        _options[i].frame = CGRectMake(x0 + i * (tileW + gap), y, tileW, previewH + 58);
        _previews[i].frame = CGRectMake(0, 0, tileW, previewH);
        _names[i].frame = CGRectMake(0, previewH + 10, tileW, 18);
        _names[i].textAlignment = NSTextAlignmentCenter;
        _radios[i].frame = CGRectMake((tileW - 22) / 2, previewH + 32, 22, 22);
        [self xrh_drawPreview:i];
    }
}

// 缩略图不写字（太小看不清，反而显得挤）：只画长条的比例，左边一段白线 = 文字，右边一段彩色线 + 小图标 = 数值
- (void)xrh_drawPreview:(NSInteger)i {
    UIView *preview = _previews[i];
    for (UIView *v in preview.subviews) [v removeFromSuperview];
    CGFloat W = preview.bounds.size.width, k = W / 430.0;
    CGFloat h = MAX(round(37 * k), 12), gw = round(W * (i == 0 ? 0.78 : 2.0 / 3));
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake((W - gw) / 2, 10, gw, h)];
    pill.backgroundColor = UIColor.blackColor;
    pill.layer.cornerRadius = h / 2;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    [preview addSubview:pill];
    CGFloat bar = 3, mid = h / 2;
    UIView *(^line)(CGFloat, CGFloat, UIColor *) = ^UIView *(CGFloat x, CGFloat w, UIColor *c) {
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(x, mid - bar / 2, w, bar)];
        v.backgroundColor = c;
        v.layer.cornerRadius = bar / 2;
        [pill addSubview:v];
        return v;
    };
    UIView *(^dot)(CGFloat, CGFloat, BOOL) = ^UIView *(CGFloat cx, CGFloat d, BOOL ring) {
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(cx - d / 2, mid - d / 2, d, d)];
        v.layer.cornerRadius = d / 2;
        if (ring) { v.layer.borderWidth = 1; v.layer.borderColor = XRHMint().CGColor; }
        else v.backgroundColor = XRHMint();
        [pill addSubview:v];
        return v;
    };
    CGFloat pad = h * 0.45;
    if (i == 0) {
        line(pad, gw * 0.2, UIColor.whiteColor);                    // 左：文字
        dot(gw - pad - 2, 4, NO);                                   // 右：图标
        line(gw - pad - 8 - gw * 0.11, gw * 0.11, XRHMint());       // 右：数值
    } else {
        dot(pad + 3, 7, YES);                                       // 左：圆环图标
        line(pad + 9, gw * 0.12, UIColor.whiteColor);               // 左：数值
        line(gw - pad - gw * 0.16, gw * 0.16, XRHMint());           // 右：短补充
    }
}

@end
