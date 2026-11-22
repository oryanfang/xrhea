#import "XRHRootListController.h"
#import "XRHLocalize.h"
#import "XRHBatteryController.h"

NSInteger gXRHPrefsLanguage = -1;
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/utsname.h>
#import <notify.h>
#import <objc/runtime.h>

// 公开仓库：反馈（Issues）和检查更新（Releases）都用它
static NSString *const kXRHRepo = @"oryanfang/xrhea";
// 软件源（GitHub Pages）
static NSString *const kXRHSourceURL = @"https://oryanfang.github.io/repo/";

// 私有 API：通过 FrontBoardServices 让 SpringBoard 重启（注销）
@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)url;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@interface PSListController (XRHPrivate)
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

#pragma mark - 名字后面的小标签（「需注销」「预览」）

// 小胶囊标签：橙色「需注销」（只是提示）、青绿色「预览」（能点，见下）
static UIImage *XRHTagImage(NSString *text, UIColor *color, UIFont *font) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%p|%.1f", text, color, font.pointSize];
    if (cache[key]) return cache[key];
    UIFont *tagFont = [UIFont systemFontOfSize:round(font.pointSize * 0.68) weight:UIFontWeightMedium];
    NSDictionary *attrs = @{NSFontAttributeName: tagFont, NSForegroundColorAttributeName: color};
    CGSize t = [text sizeWithAttributes:attrs];
    CGSize size = CGSizeMake(ceil(t.width) + 10, ceil(t.height) + 3);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[color colorWithAlphaComponent:0.15] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:size.height / 2] fill];
        [text drawAtPoint:CGPointMake((size.width - t.width) / 2, (size.height - t.height) / 2) withAttributes:attrs];
    }];
    cache[key] = image;
    return image;
}

// 「预览」按钮：放在开关左边、右对齐排成一列（不跟着名字长短跑），点一下 SpringBoard 用手机此刻的数据弹一次（Tweak/Alerts.m）
@interface XRHTryButton : UIButton
@property (nonatomic) NSInteger alert;   // 1…6
@end

@implementation XRHTryButton
- (void)xrh_tapped {
    if (self.alert <= 0) return;
    // 先把偏好同步出去：SpringBoard 读到的是刚改的样式和开关
    CFPreferencesAppSynchronize(CFSTR("com.xyrith.xrhea"));
    notify_post([NSString stringWithFormat:@"com.xyrith.xrhea/try-alert-%ld", (long)self.alert].UTF8String);
}
@end

// plist 里写 xrhRespring = true：名字后面跟橙色「需注销」（改完要注销才生效）。
// 提醒开关写 xrhTry = 1…6、xrhNote = 条件：名字后面跟灰色小字的条件，开关左边一列青绿色「预览」
static void XRHDecorateCell(UITableViewCell *cell, PSSpecifier *spec) {
    if (!cell.textLabel) return;
    NSInteger tryAlert = [[spec propertyForKey:@"xrhTry"] integerValue];
    XRHTryButton *button = objc_getAssociatedObject(cell, "xrh_try");
    button.hidden = tryAlert <= 0;   // cell 复用到别的行时藏起来
    button.alert = tryAlert;
    BOOL respring = [[spec propertyForKey:@"xrhRespring"] boolValue];
    NSString *note = [spec propertyForKey:@"xrhNote"];
    if ((!respring && !tryAlert && !note.length) || !spec.name.length) return;

    UIFont *font = cell.textLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:spec.name attributes:@{NSFontAttributeName: font}];
    // 条件里带 %d 的（「到点：充到 %d%%」）：填上设置里选的电量
    if ([note containsString:@"%d"]) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("alertTargetLevel"), CFSTR("com.xyrith.xrhea"));
        int level = (v && CFGetTypeID(v) == CFNumberGetTypeID()) ? (int)lround([(__bridge NSNumber *)v doubleValue]) : 90;
        if (v) CFRelease(v);
        note = [NSString stringWithFormat:note, level];
    }
    if (note.length) {
        UIFont *small = [UIFont monospacedDigitSystemFontOfSize:round(font.pointSize * 0.8) weight:UIFontWeightRegular];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:note] attributes:@{
            NSFontAttributeName: small, NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}]];
    }
    if (respring) {
        UIImage *tag = XRHTagImage(XRHL(@"需注销"), UIColor.systemOrangeColor, font);
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = tag;
        // 标签和文字垂直居中
        att.bounds = CGRectMake(0, round((font.capHeight - tag.size.height) / 2), tag.size.width, tag.size.height);
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:@{NSFontAttributeName: font}]];
        [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
    }
    cell.textLabel.attributedText = text;
    if (tryAlert <= 0) return;

    if (!button) {
        UIImage *tag = XRHTagImage(XRHL(@"预览"), UIColor.systemTealColor, font);
        button = [XRHTryButton buttonWithType:UIButtonTypeCustom];
        [button setImage:tag forState:UIControlStateNormal];
        // 点按区域比标签大一圈，好按
        CGSize ts = tag.size;
        CGRect cb = cell.contentView.bounds;
        button.frame = CGRectMake(cb.size.width - ts.width - 12 - 10, (cb.size.height - ts.height) / 2 - 10, ts.width + 20, ts.height + 20);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [button addTarget:button action:@selector(xrh_tapped) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:button];
        objc_setAssociatedObject(cell, "xrh_try", button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.alert = tryAlert;
    }
}

#pragma mark - 自绘图标

// 「充电上限」入口：橙底白色半亮闪电（同系统设置的彩色方块；下半截实心 = 已充，上半截只有轮廓 = 上限以上不充）
static UIImage *XRHBoltHalfIcon(void) {
    static UIImage *icon;
    if (icon) return icon;
    CGSize size = CGSizeMake(29, 29);
    icon = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemOrangeColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] fill];
        UIBezierPath *bolt = [UIBezierPath bezierPath];
        [bolt moveToPoint:CGPointMake(16.2, 5.5)];
        [bolt addLineToPoint:CGPointMake(9, 16)];
        [bolt addLineToPoint:CGPointMake(14, 16)];
        [bolt addLineToPoint:CGPointMake(12.6, 23.5)];
        [bolt addLineToPoint:CGPointMake(20, 13)];
        [bolt addLineToPoint:CGPointMake(15, 13)];
        [bolt closePath];
        bolt.lineJoinStyle = kCGLineJoinRound;
        bolt.lineWidth = 1.3;
        [UIColor.whiteColor setStroke];
        [bolt stroke];
        CGContextSaveGState(ctx.CGContext);
        CGContextClipToRect(ctx.CGContext, CGRectMake(0, 13.2, 29, 16));
        [UIColor.whiteColor setFill];
        [bolt fill];
        CGContextRestoreGState(ctx.CGContext);
    }];
    return icon;
}

// 「优化」入口：紫底白色叶子（细线轮廓 + 叶脉）
static UIImage *XRHLeafIcon(void) {
    static UIImage *icon;
    if (icon) return icon;
    CGSize size = CGSizeMake(29, 29);
    icon = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemIndigoColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] fill];
        UIBezierPath *leaf = [UIBezierPath bezierPath];
        [leaf moveToPoint:CGPointMake(8, 21)];
        [leaf addCurveToPoint:CGPointMake(21.5, 7.5) controlPoint1:CGPointMake(8, 12) controlPoint2:CGPointMake(13, 8)];
        [leaf addCurveToPoint:CGPointMake(8, 21) controlPoint1:CGPointMake(21, 16) controlPoint2:CGPointMake(17, 21)];
        [leaf closePath];
        leaf.lineWidth = 1.4;
        leaf.lineJoinStyle = kCGLineJoinRound;
        [UIColor.whiteColor setStroke];
        [leaf stroke];
        UIBezierPath *vein = [UIBezierPath bezierPath];
        [vein moveToPoint:CGPointMake(8, 21)];
        [vein addLineToPoint:CGPointMake(16, 13)];
        vein.lineWidth = 1.3;
        vein.lineCapStyle = kCGLineCapRound;
        [vein stroke];
    }];
    return icon;
}

// 「低电量模式」入口：黄底白色电池（细线外框 + 少量电量，同系统低电量的黄色）
static UIImage *XRHLowPowerIcon(void) {
    static UIImage *icon;
    if (icon) return icon;
    CGSize size = CGSizeMake(29, 29);
    icon = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemYellowColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] fill];
        [UIColor.whiteColor set];
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(5.5, 10, 16, 9) cornerRadius:2.3];
        body.lineWidth = 1.4;
        [body stroke];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(22.2, 12.8, 1.6, 3.4) cornerRadius:0.8] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.5, 12, 5, 5) cornerRadius:1] fill];
    }];
    return icon;
}

#pragma mark - 彩色方块图标（同系统设置的样子，29pt）

static UIImage *XRHSymbolIcon(NSString *symbol, NSString *colorName) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%@", symbol, colorName];
    if (cache[key]) return cache[key];
    NSDictionary *colors = @{@"teal": UIColor.systemTealColor, @"blue": UIColor.systemBlueColor, @"green": UIColor.systemGreenColor,
                             @"orange": UIColor.systemOrangeColor, @"red": UIColor.systemRedColor, @"indigo": UIColor.systemIndigoColor};
    UIColor *bg = colors[colorName] ?: UIColor.systemGrayColor;
    UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:
                       [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
                      imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGSize size = CGSizeMake(29, 29);
    UIImage *icon = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [bg setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:6.5] fill];
        if (glyph) [glyph drawInRect:CGRectMake((size.width - glyph.size.width) / 2, (size.height - glyph.size.height) / 2,
                                                glyph.size.width, glyph.size.height)];
    }];
    cache[key] = icon;
    return icon;
}

#pragma mark - 注销

static void XRHRespringNow(void) {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
    Class actionClass = NSClassFromString(@"SBSRelaunchAction");
    Class serviceClass = NSClassFromString(@"FBSSystemService");
    if (!actionClass || !serviceClass) return;
    // options 4 = FadeToBlackTransition
    SBSRelaunchAction *relaunch = [actionClass actionWithReason:@"RestartRenderServer" options:4 targetURL:nil];
    [[serviceClass sharedService] sendActions:[NSSet setWithObject:relaunch] withResult:nil];
    // 注销不一定会结束「设置」，留着的旧进程里设置页还是旧的（xrkit 0.2.3 踩过）。屏幕变黑后顺便退出，下次打开就是新进程
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
}

// 弹窗问要不要注销（主页的注销按钮、重置设置之后共用）
static void XRHConfirmRespring(UIViewController *vc, NSString *title, NSString *message, NSString *cancelTitle) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"注销") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { XRHRespringNow(); }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

@implementation XRHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        XRHLocalizeSpecifiers(_specifiers);
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    XRHDecorateCell(cell, spec);
    // 「电池信息」一行（plist 里 xrhBatteryRow = true）：绿底电池图标，右边显示健康度（有异常时前面带 ⚠️）
    // plist 里写了 xrhSymbol 的行：用 SF Symbols 画一个系统设置风格的彩色方块图标
    NSString *symbol = [spec propertyForKey:@"xrhSymbol"];
    if (symbol) cell.imageView.image = XRHSymbolIcon(symbol, [spec propertyForKey:@"xrhSymbolColor"]);
    if ([[spec propertyForKey:@"xrhDrawn"] isEqual:@"boltHalf"]) cell.imageView.image = XRHBoltHalfIcon();
    if ([[spec propertyForKey:@"xrhDrawn"] isEqual:@"leaf"]) cell.imageView.image = XRHLeafIcon();
    if ([[spec propertyForKey:@"xrhDrawn"] isEqual:@"lowPower"]) cell.imageView.image = XRHLowPowerIcon();
    if ([[spec propertyForKey:@"xrhBatteryRow"] boolValue]) {
        cell.imageView.image = XRHBatteryRowIcon();
        UILabel *detail = cell.detailTextLabel;
        if (detail) detail.attributedText = XRHBatteryRowDetail(detail.font ?: [UIFont systemFontOfSize:17], UIColor.secondaryLabelColor);
    }
    return cell;
}

// 从详情页回来时，健康度那一行也刷新一下
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    for (PSSpecifier *spec in _specifiers) {
        if ([[spec propertyForKey:@"xrhBatteryRow"] boolValue]) [self reloadSpecifier:spec animated:NO];
    }
}

// 注销放在导航栏右上角（蓝字），不占列表位置
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:XRHL(@"注销") style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(respring)];
}

// 关于页切换语言后重新加载：注销按钮的文字也跟着换
- (void)reloadSpecifiers {
    [super reloadSpecifiers];
    self.navigationItem.rightBarButtonItem.title = XRHL(@"注销");
}

- (void)respring {
    XRHConfirmRespring(self, XRHL(@"注销"), XRHL(@"确定要注销（重启 SpringBoard）吗？"), XRHL(@"取消"));
}

@end

#pragma mark - 关于页：检查更新

// 比较版本号 "0.2.0" / "v0.3.1"（忽略开头的 v 和 "-构建号" "+debug" 这类后缀）：a 比 b 新返回 YES
static BOOL XRHVersionNewer(NSString *a, NSString *b) {
    NSArray *(^parts)(NSString *) = ^NSArray *(NSString *v) {
        if ([v hasPrefix:@"v"] || [v hasPrefix:@"V"]) v = [v substringFromIndex:1];
        v = [[v componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-+ "]] firstObject];
        return [v componentsSeparatedByString:@"."];
    };
    NSArray *pa = parts(a), *pb = parts(b);
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? [pa[i] integerValue] : 0, y = i < pb.count ? [pb[i] integerValue] : 0;
        if (x != y) return x > y;
    }
    return NO;
}

@implementation XRHSubListController {
    NSArray *_xrhAllSpecifiers;   // plist 里的全部项（含暂时隐藏的）
    NSString *_xrhNewVersion;     // 关于页：GitHub 上更新的版本号（没有更新时为 nil）
    NSURL *_xrhUpdateURL;         // 关于页：新版本的 Release 页面（点版本行先开 Sileo 插件页，打不开才用它）
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self xrh_versionSpecifier]) [self xrh_checkUpdate];
}

- (PSSpecifier *)xrh_versionSpecifier {
    for (PSSpecifier *spec in _xrhAllSpecifiers ?: [self specifiers]) {
        if ([[spec propertyForKey:@"xrhVersion"] boolValue]) return spec;
    }
    return nil;
}

// 查公开仓库最新的 Release（没发过 Release / 没网 / 被限流都当作没有更新，不提示）
- (void)xrh_checkUpdate {
    // 取最新的一个 Release（含预览版）：releases/latest 只返回正式版，预览版期间会查不到新版本
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases?per_page=1", kXRHRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error || !data || ![resp isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse *)resp).statusCode != 200) return;
        NSArray *list = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *json = [list isKindOfClass:[NSArray class]] ? list.firstObject : nil;
        if (![json isKindOfClass:[NSDictionary class]]) return;
        NSString *tag = json[@"tag_name"], *page = json[@"html_url"];
        if (![tag isKindOfClass:[NSString class]] || ![page isKindOfClass:[NSString class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf xrh_gotLatestVersion:tag page:[NSURL URLWithString:page]]; });
    }] resume];
}

- (void)xrh_gotLatestVersion:(NSString *)latest page:(NSURL *)page {
    PSSpecifier *spec = [self xrh_versionSpecifier];
    NSString *installed = [spec propertyForKey:@"xrhValue"];
    if (!spec || !page || !installed || !XRHVersionNewer(latest, installed)) return;
    _xrhNewVersion = [latest hasPrefix:@"v"] || [latest hasPrefix:@"V"] ? [latest substringFromIndex:1] : latest;
    _xrhUpdateURL = page;
    [self reloadSpecifier:spec animated:YES];
}

// 版本行显示的值：有新版时换成「有新版 x.x.x」
- (id)xrhVersionValue:(PSSpecifier *)specifier {
    return _xrhNewVersion ? [NSString stringWithFormat:XRHL(@"有新版 %@"), _xrhNewVersion] : [specifier propertyForKey:@"xrhValue"];
}

#pragma mark - 关于页：软件源、反馈

// 软件源：在 Sileo 里添加，或复制地址（装了别的包管理器时自己粘贴）
- (void)xrhOpenRepo {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:XRHL(@"软件源") message:kXRHSourceURL
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSURL *sileo = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:kXRHSourceURL]];
    // 「设置」没声明 sileo 这个 scheme，canOpenURL 总是 NO，所以不判断，直接给出（没装 Sileo 时点了没反应）
    [sheet addAction:[UIAlertAction actionWithTitle:XRHL(@"在 Sileo 中添加") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [UIApplication.sharedApplication openURL:sileo options:@{} completionHandler:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:XRHL(@"复制地址") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = kXRHSourceURL;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:XRHL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    // iPad 上 action sheet 要有锚点
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)xrhOpenIssues {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/issues/new", kXRHRepo]];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

// 复制问题信息：版本、系统、机型、偏好域里存着的设置（数组、字典只写数量）
- (void)xrhCopyInfo {
    struct utsname u;
    uname(&u);
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"xrhea %@\n", [[self xrh_versionSpecifier] propertyForKey:@"xrhValue"] ?: @"?"];
    [text appendFormat:@"iOS %@ · %s\n", UIDevice.currentDevice.systemVersion, u.machine];
    [text appendString:@"Jailbreak: roothide\n"];   // 这段要贴进 GitHub Issue，统一用英文

    CFStringRef domain = CFSTR("com.xyrith.xrhea");
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSDictionary *prefs = keys.count ? CFBridgingRelease(CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain,
                                                                                   kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) : @{};
    if (!prefs.count) {
        [text appendString:@"Settings: all default\n"];
    } else {
        [text appendString:@"Changed settings:\n"];
        for (NSString *key in [prefs.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            id v = prefs[key];
            if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]]) {
                [text appendFormat:@"  %@ = %lu items\n", key, (unsigned long)[v count]];
            } else {
                [text appendFormat:@"  %@ = %@\n", key, v];
            }
        }
    }
    UIPasteboard.generalPasteboard.string = text;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:XRHL(@"已复制") message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"好") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 关于页的只读行（PSTitleValueCell）：值写在 plist 的 xrhValue 里
- (id)xrhStaticValue:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"xrhValue"];
}

// 重置所有设置：删掉 xrhea 偏好域里的全部键，通知插件重读，再问要不要注销
- (void)xrhResetAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:XRHL(@"重置所有设置")
        message:XRHL(@"xrhea 的所有设置都会恢复默认。确定吗？")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:XRHL(@"重置") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        CFStringRef domain = CFSTR("com.xyrith.xrhea");
        CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keys) {
            CFPreferencesSetMultiple(NULL, keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFRelease(keys);
        }
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.xyrith.xrhea/prefschanged"), NULL, NULL, YES);
        XRHConfirmRespring(weakSelf, XRHL(@"已重置"), XRHL(@"有些设置要注销后才会完全恢复，现在注销吗？"), XRHL(@"稍后"));
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 依赖显示：plist 里写了 xrhRequires = 某个开关的 key 的项，只有那个开关打开时才显示。
// 例如图标透明度的两个滑块，开关关着时整组只占一行。
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plistName = [self.specifier propertyForKey:@"plistName"];
        _xrhAllSpecifiers = plistName ? [self loadSpecifiersFromPlistName:plistName target:self] : @[];
        XRHLocalizeSpecifiers(_xrhAllSpecifiers);
        if (self.title.length) self.title = XRHL(self.title);
        _specifiers = [self xrh_visibleSpecifiers];
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    XRHDecorateCell(cell, spec);
    // 关于页版本行：有新版时蓝字 + 箭头，可以点
    if ([[spec propertyForKey:@"xrhVersion"] boolValue]) {
        BOOL update = _xrhUpdateURL != nil;
        cell.detailTextLabel.textColor = update ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        cell.accessoryType = update ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.selectionStyle = update ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if ([[spec propertyForKey:@"xrhVersion"] boolValue]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (!_xrhUpdateURL) return;
        // 先打开 Sileo 里 xrhea 的插件页（在那里直接更新）；没装 Sileo（打不开）时退回 GitHub 的 Release 页面。
        // 「设置」没声明 sileo scheme，canOpenURL 总是 NO，所以靠 openURL 的结果判断
        NSURL *release = _xrhUpdateURL;
        NSURL *sileo = [NSURL URLWithString:@"sileo://package/com.xyrith.xrhea"];
        [UIApplication.sharedApplication openURL:sileo options:@{} completionHandler:^(BOOL success) {
            if (!success) [UIApplication.sharedApplication openURL:release options:@{} completionHandler:nil];
        }];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// xrhRequires 可以写多个键（逗号隔开），全部开着才显示，比如「充满时间」要「充电上限」和「定时充满」都开
- (BOOL)xrh_requiresMet:(PSSpecifier *)spec {
    NSString *requires = [spec propertyForKey:@"xrhRequires"];
    if (!requires.length) return YES;
    for (NSString *key in [requires componentsSeparatedByString:@","]) {
        if (![self xrh_boolForKey:key]) return NO;
    }
    return YES;
}

- (NSMutableArray *)xrh_visibleSpecifiers {
    NSMutableArray *visible = [NSMutableArray array];
    for (PSSpecifier *spec in _xrhAllSpecifiers) if ([self xrh_requiresMet:spec]) [visible addObject:spec];
    return visible;
}

- (BOOL)xrh_boolForKey:(NSString *)key {
    for (PSSpecifier *spec in _xrhAllSpecifiers) {
        if ([[spec propertyForKey:@"key"] isEqualToString:key]) return [[self readPreferenceValue:spec] boolValue];
    }
    return NO;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    // 「提醒电量」改了：「到点」那行灰字里的电量跟着变
    if ([key isEqualToString:@"alertTargetLevel"]) {
        for (PSSpecifier *spec in _specifiers) {
            if ([[spec propertyForKey:@"key"] isEqualToString:@"alertTarget"]) [self reloadSpecifier:spec animated:NO];
        }
        return;
    }
    // 关于页「语言」：马上换，导航栈里已经打开的设置页（首页、关于页）都重新加载
    if ([key isEqualToString:@"prefsLanguage"]) {
        XRHSetPrefsLanguage([value integerValue]);
        for (UIViewController *vc in self.navigationController.viewControllers) {
            if ([vc isKindOfClass:[XRHRootListController class]] || [vc isKindOfClass:[XRHSubListController class]])
                [(PSListController *)vc reloadSpecifiers];
        }
        return;
    }
    // 依赖这个开关的项要出现 / 消失：变动的几项正好连成一块、紧跟在开关后面时用动画插入 / 移除；
    // 否则（比如「定时充满」那组隔着几段说明）整页重排，保证位置对
    BOOL depends = NO;
    for (PSSpecifier *spec in _xrhAllSpecifiers) {
        if ([[[spec propertyForKey:@"xrhRequires"] componentsSeparatedByString:@","] containsObject:key]) { depends = YES; break; }
    }
    if (!depends) return;
    NSArray *want = [self xrh_visibleSpecifiers];
    if ([want isEqualToArray:_specifiers]) return;
    BOOL adding = want.count > _specifiers.count;
    NSArray *longer = adding ? want : _specifiers, *shorter = adding ? _specifiers : want;
    NSMutableArray *diff = [NSMutableArray array];
    for (PSSpecifier *spec in longer) if (![shorter containsObject:spec]) [diff addObject:spec];
    NSUInteger anchor = [longer indexOfObject:specifier], first = [longer indexOfObject:diff.firstObject];
    BOOL contiguous = anchor != NSNotFound && first == anchor + 1 && first + diff.count <= longer.count
                      && [[longer subarrayWithRange:NSMakeRange(first, diff.count)] isEqualToArray:diff]
                      && [[NSMutableArray arrayWithArray:longer] count] - diff.count == shorter.count;
    if (contiguous && adding) [self insertContiguousSpecifiers:diff afterSpecifier:specifier animated:YES];
    else if (contiguous) [self removeContiguousSpecifiers:diff animated:YES];
    else [self reloadSpecifiers];
}

@end
