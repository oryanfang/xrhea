// xrhea 的提示（在 SpringBoard 里画）。「提示样式」（toastStyle）：0 自动（有灵动岛用灵动岛，没有用横幅）/ 1 灵动岛 / 2 横幅；
// 灵动岛又分长短（islandStyle）：
//   - 长条（默认，XRHShowIslandLong）：照系统插电那条，约 78% 屏宽、和灵动岛等高、纯黑；左一句白字，右彩色数值 + 图标
//   - 短条（XRHShowIsland）：2/3 屏宽，左圆环图标 + 短值，右短补充
//   - 横幅（XRHShowBanner）：从顶部滑下的深色毛玻璃卡片，圆环图标 + 两行字，往上划或点一下收起
// 灵动岛展开时把状态栏（时间、信号、电池）淡出，收起后淡回。点提示会打开「设置 › xrhea › 电池信息」（可关）。
// 图标：SF Symbol 或自绘（xrh. 开头），渐变上色：普通薄荷 → 青、警告黄 → 橙。同一时间只显示一条，后来的排队（最多 3 条）。
//
// 用法见 XRHCommon.h 的 XRHShowToast / XRHShowToastFull。
#import "XRHCommon.h"
#import <notify.h>
#import <sys/utsname.h>

// 手势回调用的小目标对象：手势只弱引用 target，所以挂在手势上让它活着
@interface XRHBlockTarget : NSObject
@property (nonatomic, copy) void (^block)(void);
@end
@implementation XRHBlockTarget
- (void)fire { if (self.block) self.block(); }
@end

static void XRHAddGestureBlock(UIGestureRecognizer *g, void (^block)(void)) {
    XRHBlockTarget *t = [XRHBlockTarget new];
    t.block = block;
    [g addTarget:t action:@selector(fire)];
    objc_setAssociatedObject(g, "xrh_target", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static const NSTimeInterval kXRHToastHold = 3.0;      // 展开后停留多久

// 正在显示的这条点了打开哪一页（Root.plist 里那行的 id）：默认 battery（电池信息），每周小结是 log（日志）
static NSString *gToastTapPath;

// 点提示：打开「设置 › xrhea › 电池信息」（Root.plist 里这行 id = battery）。
// SpringBoard 里 UIApplication openURL 不行；LSApplicationWorkspace openSensitiveURL 可以，但不能在主线程同步调（lsd 会回头找
// SpringBoard，卡死），放后台线程。锁屏 / 灭屏时会失败（返回 NO），那就只是收起提示（2026-11-19 真机验证）
static void XRHToastOpenDetail(void) {
    if (![[XRHPrefs shared] boolForKey:kXRHToastTapOpen fallback:YES]) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        id ws = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"LSApplicationWorkspace"), NSSelectorFromString(@"defaultWorkspace"));
        SEL sel = NSSelectorFromString(@"openSensitiveURL:withOptions:");
        if (![ws respondsToSelector:sel]) return;
        BOOL ok = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(ws, sel, [NSURL URLWithString:[@"prefs:root=xrhea&path=" stringByAppendingString:gToastTapPath ?: @"battery"]], nil);
        XRHDebugLog(@"[Toast] 点提示打开详情 ok=%d", ok);
    });
}

#pragma mark - 有没有灵动岛

// 看机型代号：iPhone15,2/15,3 = 14 Pro / Pro Max，iPhone15,4/15,5 = 15 / 15 Plus，iPhone16,x 起全系都有
BOOL XRHHasDynamicIsland(void) {
    static int has = -1;
    if (has >= 0) return has;
    struct utsname u;
    uname(&u);
    int major = 0, minor = 0;
    has = sscanf(u.machine, "iPhone%d,%d", &major, &minor) == 2 && (major >= 16 || (major == 15 && minor >= 2));
    return has;
}

static BOOL XRHUseIslandStyle(void) {
    int style = (int)XRHDouble(kXRHToastStyle, 0, 0, 2);
    if (style == 1) return YES;
    if (style == 2) return NO;
    return XRHHasDynamicIsland();
}

#pragma mark - 图标：细线圆环 + 渐变色图标（留白，和 xrhea 图标同一种线条风格）

// 自绘图标（苹果图标库里没有合适的）：在 24×24 的格子里画，线条风格同 xrhea 图标
//   xrh.bolt.half      充电很慢：细线闪电，只亮下半截（电没跑满）
//   xrh.battery.drain  耗电很快：细线电池，里面两道往下的箭头（后一道淡一半）
static UIImage *XRHCustomGlyph(NSString *name, CGFloat side) {
    BOOL bolt = [name isEqualToString:@"xrh.bolt.half"];
    if (!bolt && ![name isEqualToString:@"xrh.battery.drain"]) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextScaleCTM(c, side / 24, side / 24);
        [UIColor.blackColor setStroke];
        [UIColor.blackColor setFill];
        if (bolt) {
            UIBezierPath *outline = [UIBezierPath bezierPath];
            [outline moveToPoint:CGPointMake(13, 2)];
            [outline addLineToPoint:CGPointMake(4, 14)];
            [outline addLineToPoint:CGPointMake(11, 14)];
            [outline addLineToPoint:CGPointMake(10, 22)];
            [outline addLineToPoint:CGPointMake(19, 10)];
            [outline addLineToPoint:CGPointMake(12, 10)];
            [outline closePath];
            outline.lineWidth = 2;
            outline.lineJoinStyle = kCGLineJoinRound;
            [outline stroke];
            UIBezierPath *lit = [UIBezierPath bezierPath];
            [lit moveToPoint:CGPointMake(11, 14)];
            [lit addLineToPoint:CGPointMake(10, 22)];
            [lit addLineToPoint:CGPointMake(19, 10)];
            [lit addLineToPoint:CGPointMake(14.4, 10)];
            [lit closePath];
            [lit fill];
        } else {
            UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 7, 16, 10) cornerRadius:2.5];
            body.lineWidth = 2;
            [body stroke];
            UIBezierPath *nub = [UIBezierPath bezierPath];
            [nub moveToPoint:CGPointMake(21.5, 10.5)];
            [nub addLineToPoint:CGPointMake(21.5, 13.5)];
            nub.lineWidth = 2;
            nub.lineCapStyle = kCGLineCapRound;
            [nub stroke];
            for (int i = 0; i < 2; i++) {
                CGFloat x = i ? 13 : 8;
                UIBezierPath *arrow = [UIBezierPath bezierPath];
                [arrow moveToPoint:CGPointMake(x, 9.5)];
                [arrow addLineToPoint:CGPointMake(x, 14.5)];
                [arrow moveToPoint:CGPointMake(x - 2, 12.5)];
                [arrow addLineToPoint:CGPointMake(x, 14.5)];
                [arrow addLineToPoint:CGPointMake(x + 2, 12.5)];
                arrow.lineWidth = 1.8;
                arrow.lineCapStyle = kCGLineCapRound;
                arrow.lineJoinStyle = kCGLineJoinRound;
                [arrow strokeWithBlendMode:kCGBlendModeNormal alpha:i ? 0.5 : 1];
            }
        }
    }];
}

// 圆环里的图标（黑色，当蒙版用）：xrh. 开头的是自绘的，其他当 SF Symbol 名
static UIImage *XRHToastGlyph(NSString *symbol, CGFloat size) {
    if (!symbol.length) return nil;
    if ([symbol hasPrefix:@"xrh."]) return XRHCustomGlyph(symbol, round(size * 0.58));
    UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:
                    [UIImageSymbolConfiguration configurationWithPointSize:size * 0.42 weight:UIImageSymbolWeightSemibold]];
    return [img imageWithTintColor:UIColor.blackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIView *XRHToastDot(XRHToastKind kind, NSString *symbol, CGFloat size) {
    UIColor *a, *b;
    if (kind == XRHToastWarning) {
        a = [UIColor colorWithRed:1 green:0.82 blue:0.4 alpha:1];
        b = UIColor.systemOrangeColor;
    } else {
        a = [UIColor colorWithRed:0x3D/255.0 green:0xF5/255.0 blue:0xA8/255.0 alpha:1];
        b = [UIColor colorWithRed:0x1A/255.0 green:0xB8/255.0 blue:0xFF/255.0 alpha:1];
    }
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];

    // 细线圆环：线粗随大小走（灵动岛 26pt 约 1.5，横幅 36pt 约 2）
    CGFloat line = MAX(1.5, size / 18);
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(dot.bounds, line / 2 + 0.5, line / 2 + 0.5)].CGPath;
    ring.fillColor = UIColor.clearColor.CGColor;
    ring.strokeColor = [a colorWithAlphaComponent:0.9].CGColor;
    ring.lineWidth = line;
    [dot.layer addSublayer:ring];

    // 图标：用渐变填色，图标本身当蒙版（SF Symbol 或 xrhea 自绘的）
    UIImage *img = XRHToastGlyph(symbol, size);
    if (img) {
        CGSize is = img.size;
        CGRect r = CGRectMake((size - is.width) / 2, (size - is.height) / 2, is.width, is.height);
        CAGradientLayer *g = [CAGradientLayer layer];
        g.frame = r;
        g.colors = @[(id)a.CGColor, (id)b.CGColor];
        g.startPoint = CGPointMake(0, 0);
        g.endPoint = CGPointMake(1, 1);
        CALayer *mask = [CALayer layer];
        mask.frame = g.bounds;
        mask.contents = (id)img.CGImage;
        mask.contentsGravity = kCAGravityResizeAspect;
        mask.contentsScale = UIScreen.mainScreen.scale;
        g.mask = mask;
        [dot.layer addSublayer:g];
    }
    return dot;
}

#pragma mark - 窗口（只接住提示本身的触摸，其他地方点穿过去）

@interface XRHToastWindow : UIWindow
@property (nonatomic, weak) UIView *touchView;
@end

@implementation XRHToastWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.touchView && hit && [hit isDescendantOfView:self.touchView]) return hit;
    return nil;
}
@end

#pragma mark - 显示

static XRHToastWindow *gToastWindow;
static NSMutableArray<NSArray *> *gToastQueue;   // 排队：@[kind, symbol, title, detail, compact, compactDetail, label, value]
static BOOL gToastShowing;

static void XRHToastNext(void);


static void XRHToastFinish(void) {
    gToastWindow.hidden = YES;
    gToastWindow = nil;
    gToastShowing = NO;
    XRHToastNext();
}

static UILabel *XRHToastLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    [l sizeToFit];
    return l;
}

#pragma mark - 展开时把状态栏藏起来

// 2/3 屏宽的胶囊会盖到时间和右边的信号格，所以展开那几秒把状态栏淡出、收起后淡回来。
// 前台 App 的状态栏也是 SpringBoard 画的（真机探测：App 的挂在 SBMainSwitcherWindow 里），所以只要在 SpringBoard
// 的所有窗口里按类名找到状态栏，把 alpha 调成 0，用完按原值还回去。
// 不用私有方法，只按类名找视图；找不到就什么也不做（胶囊照常显示，只是会盖住一部分时间）。
static NSMapTable<UIView *, NSNumber *> *gHiddenBars;   // 被我们藏起来的状态栏 → 原来的 alpha（弱引用视图）
static NSUInteger gBarGeneration;   // 每次藏 +1：淡回动画还没走完又来下一条时，别把原值记录删掉

static void XRHCollectStatusBars(UIView *v, NSArray<Class> *classes, NSMutableArray<UIView *> *out) {
    for (Class c in classes) {
        if ([v isKindOfClass:c]) {
            // 本来就是透明的（比如主屏那条备用的）不管；外层找到了就不再往里找，免得同一条状态栏淡两次
            if (!v.hidden && v.alpha >= 0.01) [out addObject:v];
            return;
        }
    }
    for (UIView *sub in v.subviews) XRHCollectStatusBars(sub, classes, out);
}


static void XRHHideStatusBars(UIWindow *except, NSTimeInterval duration) {
    // iOS 17：StatusKit 的 STUIStatusBar（主屏在 SBStatusBarWindow、App 在 SBMainSwitcherWindow，2026-11-19 真机探测）。
    // 不能动外面那层 STUIStatusBar_Wrapper：主屏上它的透明度归系统管，设成 0 立刻被改回 1。老系统是 UIKit 的 UIStatusBar_Modern
    NSMutableArray<Class> *classes = [NSMutableArray array];
    for (NSString *n in @[@"STUIStatusBar", @"UIStatusBar_Modern", @"_UIStatusBar"]) {
        Class c = NSClassFromString(n);
        if (c) [classes addObject:c];
    }
    if (!classes.count) return;
    NSMutableArray<UIView *> *bars = [NSMutableArray array];
    NSMutableSet<UIWindow *> *windows = [NSMutableSet set];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)s).windows];
    }
    for (UIWindow *w in windows) {
        if (w == except || w.hidden || w.alpha < 0.01) continue;
        XRHCollectStatusBars(w, classes, bars);
    }
    if (!gHiddenBars) gHiddenBars = [NSMapTable weakToStrongObjectsMapTable];
    gBarGeneration++;
    for (UIView *b in bars) {
        if ([gHiddenBars objectForKey:b]) continue;   // 上一条刚淡回一半：记录里已经是原值，别用半透明的覆盖
        [gHiddenBars setObject:@(b.alpha) forKey:b];
    }
#if XRH_DEBUG
    NSMutableArray *desc = [NSMutableArray array];
    for (UIView *b in bars) [desc addObject:[NSString stringWithFormat:@"%@@%@ a=%.2f", NSStringFromClass(b.class), NSStringFromClass(b.window.class), b.alpha]];
    XRHDebugLog(@"[Toast] 藏状态栏 %lu 条：%@", (unsigned long)bars.count, [desc componentsJoinedByString:@", "]);
#endif
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        for (UIView *b in bars) b.alpha = 0;
    } completion:nil];
}

static void XRHRestoreStatusBars(NSTimeInterval duration) {
    if (!gHiddenBars.count) return;
    NSMapTable *bars = [gHiddenBars copy];
    NSUInteger gen = gBarGeneration;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        for (UIView *b in bars) {
            // 中途被系统改过（不再是 0）就别动它，按系统的来
            if (b.alpha < 0.01) b.alpha = [[bars objectForKey:b] doubleValue];
        }
    } completion:^(BOOL f) {
        if (gen == gBarGeneration) [gHiddenBars removeAllObjects];
    }];
}

// 灵动岛短条（可选）：加长版胶囊
//   - 宽 = 屏幕 2/3（430 宽约 287pt），和灵动岛等高（37）、纯黑、同样的胶囊圆角，从灵动岛往两边长出来
//   - 中间是镜头开孔不放东西；左 细线圆环图标 + 短值，右 短补充（XRHShowToast 的 compact / compactDetail）
//   - 展开时状态栏（时间和两边图标）淡出，收回后淡入
// 不做成展开态大卡片：只是几秒的小提示，大卡片太抢眼
static void XRHShowIsland(XRHToastWindow *win, XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail) {
    CGFloat W = win.bounds.size.width;
    CGRect island = CGRectMake((W - 126) / 2, 11, 126, 37);
    CGFloat h = island.size.height;
    CGFloat gw = round(W * 2 / 3);
    CGRect grown = CGRectMake((W - gw) / 2, island.origin.y, gw, h);
    CGFloat side = (gw - island.size.width) / 2;

    UIColor *accent = kind == XRHToastWarning ? UIColor.systemOrangeColor
                                              : [UIColor colorWithRed:0x3D/255.0 green:0xF5/255.0 blue:0xA8/255.0 alpha:1];

    UIView *pill = [[UIView alloc] initWithFrame:island];
    pill.backgroundColor = UIColor.blackColor;
    pill.layer.cornerRadius = h / 2;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.clipsToBounds = YES;
    [win addSubview:pill];
    win.touchView = pill;

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, gw, h)];
    content.alpha = 0;
    [pill addSubview:content];

    // 中间那 126pt 是摄像头开孔，显示不了东西：只用左右两段（430 宽的屏上各约 80pt）。
    // 左：图标 + 短值（如「27W」）；右：短补充（如「约1小时」）。放不下先缩小再截断
    CGFloat pad = 9, dotSize = 22, gap = 6, inset = 6;   // inset：离镜头边留一点，别贴着
    UIView *dot = XRHToastDot(kind, symbol, dotSize);
    dot.center = CGPointMake(pad + dotSize / 2, h / 2);
    [content addSubview:dot];
    CGFloat lx = pad + dotSize + gap, lw = side - inset - lx;
    UILabel *t = XRHToastLabel(title ?: @"", 14, UIFontWeightSemibold, UIColor.whiteColor);
    t.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    t.adjustsFontSizeToFitWidth = YES;
    t.minimumScaleFactor = 0.75;
    t.frame = CGRectMake(lx, 0, MAX(lw, 0), h);
    [content addSubview:t];
    if (detail.length) {
        CGFloat rx = gw - side + inset, rw = gw - pad - 4 - rx;
        UILabel *d = XRHToastLabel(detail, 13, UIFontWeightMedium, accent);
        d.adjustsFontSizeToFitWidth = YES;
        d.minimumScaleFactor = 0.75;
        d.textAlignment = NSTextAlignmentRight;
        d.frame = CGRectMake(rx, 0, MAX(rw, 0), h);
        [content addSubview:d];
    }

    void (^collapse)(void) = ^{
        [UIView animateWithDuration:0.15 animations:^{ content.alpha = 0; } completion:^(BOOL f) {
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:0 animations:^{
                pill.frame = island;
                content.frame = CGRectMake(-side, 0, gw, h);
            } completion:^(BOOL f2) {
                XRHRestoreStatusBars(0.25);
                [UIView animateWithDuration:0.12 animations:^{ pill.alpha = 0; } completion:^(BOOL f3) { XRHToastFinish(); }];
            }];
        }];
    };
    __block BOOL done = NO;
    void (^once)(void) = ^{ if (done) return; done = YES; collapse(); };
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
    XRHAddGestureBlock(tap, ^{ XRHToastOpenDetail(); once(); });
    [pill addGestureRecognizer:tap];

    // 状态栏先淡出（比胶囊快一点，免得胶囊长过去时压在时间上），内容跟着胶囊从中间往两边露出来
    XRHHideStatusBars(win, 0.2);
    content.frame = CGRectMake(-side, 0, gw, h);
    [UIView animateWithDuration:0.5 delay:0.05 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:0 animations:^{
        pill.frame = grown;
        content.frame = CGRectMake(0, 0, gw, h);
        content.alpha = 1;
    } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kXRHToastHold * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
    }];
}

// 灵动岛长条（默认）：照系统插电时那条——约 78% 屏宽（430 宽约 335pt）、和灵动岛等高 37、纯黑；
//   左边一句白字（label，如「正在充电」），右边彩色数值 + 图标（value，如「8.5W ⚡」），中间是镜头。展开时同样藏状态栏
// 图标不带圆环（系统那条电池图标也没有），仍是渐变色：普通薄荷 → 青、警告黄 → 橙
static void XRHShowIslandLong(XRHToastWindow *win, XRHToastKind kind, NSString *symbol, NSString *label, NSString *value) {
    CGFloat W = win.bounds.size.width;
    CGRect island = CGRectMake((W - 126) / 2, 11, 126, 37);
    CGFloat h = island.size.height;
    CGFloat gw = round(W * 0.78);
    CGRect grown = CGRectMake((W - gw) / 2, island.origin.y, gw, h);
    CGFloat side = (gw - island.size.width) / 2;   // 镜头两边各能用多宽

    UIColor *accent = kind == XRHToastWarning ? UIColor.systemOrangeColor
                                              : [UIColor colorWithRed:0x3D/255.0 green:0xF5/255.0 blue:0xA8/255.0 alpha:1];
    UIView *pill = [[UIView alloc] initWithFrame:island];
    pill.backgroundColor = UIColor.blackColor;
    pill.layer.cornerRadius = h / 2;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.clipsToBounds = YES;
    [win addSubview:pill];
    win.touchView = pill;

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, gw, h)];
    content.alpha = 0;
    [pill addSubview:content];

    CGFloat inset = 16, gap = 6, camGap = 8;
    UILabel *l = XRHToastLabel(label ?: @"", 15, UIFontWeightSemibold, UIColor.whiteColor);
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.75;
    l.frame = CGRectMake(inset, 0, MAX(side - inset - camGap, 0), h);
    [content addSubview:l];

    // 右边：数值 + 图标，靠右排
    CGFloat iconSize = 18, right = gw - inset + 2;
    UIImage *glyph = XRHToastGlyph(symbol, iconSize / 0.5);   // XRHToastGlyph 按圆环大小算图标，这里要图标本身约 18pt
    if (glyph) {
        CGSize gs = glyph.size;
        CGFloat scale = iconSize / MAX(gs.width, gs.height);
        CGSize is = CGSizeMake(round(gs.width * scale), round(gs.height * scale));
        CAGradientLayer *g = [CAGradientLayer layer];
        g.frame = CGRectMake(right - is.width, (h - is.height) / 2, is.width, is.height);
        UIColor *a = kind == XRHToastWarning ? [UIColor colorWithRed:1 green:0.82 blue:0.4 alpha:1] : accent;
        UIColor *b = kind == XRHToastWarning ? UIColor.systemOrangeColor : [UIColor colorWithRed:0x1A/255.0 green:0xB8/255.0 blue:0xFF/255.0 alpha:1];
        g.colors = @[(id)a.CGColor, (id)b.CGColor];
        g.startPoint = CGPointMake(0, 0);
        g.endPoint = CGPointMake(1, 1);
        CALayer *mask = [CALayer layer];
        mask.frame = g.bounds;
        mask.contents = (id)glyph.CGImage;
        mask.contentsGravity = kCAGravityResizeAspect;
        mask.contentsScale = UIScreen.mainScreen.scale;
        g.mask = mask;
        [content.layer addSublayer:g];
        right -= is.width + gap;
    }
    UILabel *v = XRHToastLabel(value ?: @"", 15, UIFontWeightSemibold, accent);
    v.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    v.adjustsFontSizeToFitWidth = YES;
    v.minimumScaleFactor = 0.75;
    v.textAlignment = NSTextAlignmentRight;
    CGFloat vx = gw - side + camGap;
    v.frame = CGRectMake(vx, 0, MAX(right - vx, 0), h);
    [content addSubview:v];

    void (^collapse)(void) = ^{
        [UIView animateWithDuration:0.15 animations:^{ content.alpha = 0; } completion:^(BOOL f) {
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:0 animations:^{
                pill.frame = island;
                content.frame = CGRectMake(-side, 0, gw, h);
            } completion:^(BOOL f2) {
                XRHRestoreStatusBars(0.25);
                [UIView animateWithDuration:0.12 animations:^{ pill.alpha = 0; } completion:^(BOOL f3) { XRHToastFinish(); }];
            }];
        }];
    };
    __block BOOL done = NO;
    void (^once)(void) = ^{ if (done) return; done = YES; collapse(); };
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
    XRHAddGestureBlock(tap, ^{ XRHToastOpenDetail(); once(); });
    [pill addGestureRecognizer:tap];

    XRHHideStatusBars(win, 0.2);
    content.frame = CGRectMake(-side, 0, gw, h);
    [UIView animateWithDuration:0.5 delay:0.05 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:0 animations:^{
        pill.frame = grown;
        content.frame = CGRectMake(0, 0, gw, h);
        content.alpha = 1;
    } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kXRHToastHold * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
    }];
}

// 横幅：从顶上滑下来的深色毛玻璃卡片，两行字；往上划可以提前收掉
static void XRHShowBanner(XRHToastWindow *win, XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail) {
    CGFloat W = win.bounds.size.width;
    CGFloat top = MAX(win.safeAreaInsets.top, 20) + 4;
    CGFloat bw = MIN(W - 16, 420), bh = detail.length ? 66 : 54;
    CGRect shown = CGRectMake((W - bw) / 2, top, bw, bh);
    CGRect hidden = CGRectOffset(shown, 0, -(top + bh + 10));

    UIView *card = [[UIView alloc] initWithFrame:hidden];
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.3;
    card.layer.shadowRadius = 14;
    card.layer.shadowOffset = CGSizeMake(0, 6);
    [win addSubview:card];
    win.touchView = card;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.frame = card.bounds;
    blur.layer.cornerRadius = 22;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [card addSubview:blur];

    UIView *dot = XRHToastDot(kind, symbol, 36);
    dot.center = CGPointMake(14 + 18, bh / 2);
    [card addSubview:dot];
    CGFloat tx = 14 + 36 + 12, tw = bw - tx - 16;
    UILabel *t = XRHToastLabel(title, 15, UIFontWeightSemibold, UIColor.whiteColor);
    [card addSubview:t];
    if (detail.length) {
        UILabel *d = XRHToastLabel(detail, 13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.7]);
        t.frame = CGRectMake(tx, bh / 2 - 20, tw, 20);
        d.frame = CGRectMake(tx, bh / 2 + 1, tw, 18);
        [card addSubview:d];
    } else {
        t.frame = CGRectMake(tx, 0, tw, bh);
    }

    __block BOOL done = NO;
    void (^dismiss)(void) = ^{
        if (done) return;
        done = YES;
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{ card.frame = hidden; }
                         completion:^(BOOL f) { XRHToastFinish(); }];
    };
    UISwipeGestureRecognizer *swipe = [UISwipeGestureRecognizer new];
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    XRHAddGestureBlock(swipe, dismiss);
    [card addGestureRecognizer:swipe];
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
    XRHAddGestureBlock(tap, ^{ XRHToastOpenDetail(); dismiss(); });
    [card addGestureRecognizer:tap];

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        card.frame = shown;
    } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kXRHToastHold + 0.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), dismiss);
    }];
}

static void XRHToastNext(void) {
    if (gToastShowing || !gToastQueue.count) return;
    NSArray *item = gToastQueue.firstObject;
    [gToastQueue removeObjectAtIndex:0];
    UIWindowScene *scene = XRHActiveWindowScene();
    if (!scene) return;
    gToastShowing = YES;
    gToastWindow = [[XRHToastWindow alloc] initWithWindowScene:scene];
    gToastWindow.windowLevel = UIWindowLevelStatusBar + 100;
    gToastWindow.backgroundColor = UIColor.clearColor;
    gToastWindow.rootViewController = nil;
    gToastWindow.hidden = NO;
    XRHToastKind kind = [item[0] integerValue];
    gToastTapPath = item.count > 8 && item[8] != NSNull.null ? item[8] : nil;
    NSString *symbol = item[1] == NSNull.null ? nil : item[1];
    NSString *detail = item[3] == NSNull.null ? nil : item[3];
    BOOL island = XRHUseIslandStyle();
    XRHDebugLog(@"[Toast] %@ kind=%ld %@ / %@", island ? @"灵动岛" : @"横幅", (long)kind, item[2], detail);
    NSString *title = item[2];
    NSString *compact = item[4] == NSNull.null ? nil : item[4], *compactDetail = item[5] == NSNull.null ? nil : item[5];
    if (!island) { XRHShowBanner(gToastWindow, kind, symbol, title, detail); return; }
    if ((int)XRHDouble(kXRHIslandStyle, 0, 0, 1) == 1) {   // 短条
        XRHShowIsland(gToastWindow, kind, symbol, compact ?: title, compactDetail ?: detail);
        return;
    }
    // 长条：没指定 label / value 时，左边用标题；右边用短值，标题里已经有这个值就换成短补充（免得「电池 34℃ ｜ 34℃」）
    NSString *label = item[6] == NSNull.null ? title : item[6];
    NSString *value = item[7] == NSNull.null ? nil : item[7];
    if (!value) value = (compact && ![title containsString:compact]) ? compact : (compactDetail ?: compact);
    XRHShowIslandLong(gToastWindow, kind, symbol, label, value);
}

void XRHShowToast(XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail, NSString *compact, NSString *compactDetail) {
    XRHShowToastFull(kind, symbol, title, detail, compact, compactDetail, nil, nil);
}

void XRHShowToastFull(XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail, NSString *compact, NSString *compactDetail,
                      NSString *label, NSString *value) {
    XRHShowToastOpening(kind, symbol, title, detail, compact, compactDetail, label, value, nil);
}

void XRHShowToastOpening(XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail, NSString *compact, NSString *compactDetail,
                         NSString *label, NSString *value, NSString *tapPath) {
    if (!title.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gToastQueue) gToastQueue = [NSMutableArray array];
        if (gToastQueue.count >= 3) return;   // 一下子来太多就丢掉后面的
        [gToastQueue addObject:@[@(kind), symbol ?: (id)NSNull.null, title, detail ?: (id)NSNull.null, compact ?: (id)NSNull.null, compactDetail ?: (id)NSNull.null,
                                  label ?: (id)NSNull.null, value ?: (id)NSNull.null, tapPath ?: (id)NSNull.null]];
        XRHToastNext();
    });
}
