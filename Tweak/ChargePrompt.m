// 插上电源时的弹窗（充电上限开着时）：「已设定充到 80%，是否确认？」——「确认」/「这次充满」。
// 外出前想一次充满的人点「这次充满」，这次接着电源期间不管上限，拔线就作废（写 chargeLimitFullOnce，xrhead 读）。
// 同一个弹窗兼做「每月充满一次」提醒：距上次充满超过 30 天时，标题换成「该充满一次了」，并把「这次充满」设成推荐按钮。
// 「插上电源时询问」关掉后，只在该充满时才弹。
//
// 弹窗用自己的一个 UIWindow（窗口层级在系统提醒之上）承载 UIAlertController；点完就收掉窗口。
#import "XRHCommon.h"
#import <notify.h>

static const NSTimeInterval kXRHFullReminderDays = 30;

static UIWindow *gPromptWindow;
static BOOL gConnected;

static void XRHPostPrefsChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(XRH_PREFS_CHANGED), NULL, NULL, YES);
}

static void XRHSetFullOnce(BOOL on) {
    XRHWritePref(kXRHChargeLimitFullOnce, on ? @YES : nil);
    XRHPostPrefsChanged();
    XRHDebugLog(@"[Prompt] 这次充满 = %d", on);
}

static void XRHDismissPrompt(void) {
    gPromptWindow.hidden = YES;
    gPromptWindow = nil;
}


static void XRHShowPrompt(int max, BOOL overdue, int days) {
    if (gPromptWindow) return;
    UIWindowScene *scene = XRHActiveWindowScene();
    if (!scene) return;

    NSString *title = overdue ? XRHText(@"该充满一次了", @"Time for a Full Charge") : XRHText(@"充电上限", @"Charge Limit");
    NSString *message = [NSString stringWithFormat:XRHText(@"已设定充到 %d%%，是否确认？", @"Charging is set to stop at %d%%. Keep it?"), max];
    if (overdue) {
        message = [message stringByAppendingFormat:XRHText(@"\n\n已经 %d 天没充满过了，建议这次充满一次，让电量统计保持准确。",
                                                             @"\n\nIt's been %d days since the last full charge. Charging to 100%% this time keeps the battery reading accurate."), days];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *keep = [UIAlertAction actionWithTitle:[NSString stringWithFormat:XRHText(@"确认，到 %d%% 停", @"Keep, Stop at %d%%"), max]
                                                   style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        XRHDismissPrompt();
    }];
    UIAlertAction *full = [UIAlertAction actionWithTitle:XRHText(@"这次充满", @"Charge to 100% This Time")
                                                   style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        XRHSetFullOnce(YES);
        XRHDismissPrompt();
    }];
    [alert addAction:keep];
    [alert addAction:full];
    alert.preferredAction = overdue ? full : keep;

    gPromptWindow = [[UIWindow alloc] initWithWindowScene:scene];
    gPromptWindow.windowLevel = UIWindowLevelAlert + 10;
    gPromptWindow.backgroundColor = UIColor.clearColor;
    gPromptWindow.rootViewController = [UIViewController new];
    gPromptWindow.hidden = NO;
    [gPromptWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    XRHDebugLog(@"[Prompt] 弹窗 max=%d overdue=%d days=%d", max, overdue, days);
}

// 插电弹窗还开着（提醒模块等它关掉再弹插电提示，免得被弹窗的暗背景压住）
BOOL XRHChargePromptShowing(void) {
    return gPromptWindow != nil;
}

// 电源变化（插 / 拔）
static void XRHPowerChanged(void) {
    BOOL connected = XRBatteryExternalConnected();
    if (connected == gConnected) return;
    gConnected = connected;

    if (!connected) {
        // 拔线：「这次充满」作废，弹窗还开着就收掉
        if (XRHOn(kXRHChargeLimitFullOnce)) XRHSetFullOnce(NO);
        XRHDismissPrompt();
        return;
    }
    if (![XRHPrefs shared].enabled || !XRHOn(kXRHChargeLimit)) return;
    double level = XRBatteryLevel();
    if (isnan(level) || level >= 100) return;

    int max = (int)XRHDouble(kXRHChargeLimitMax, 80, 50, 100);
    NSDictionary *state = XRHLimitState();
    double lastFull = [state[@"lastFull"] doubleValue];
    int days = lastFull > 0 ? (int)(([NSDate date].timeIntervalSince1970 - lastFull) / 86400) : 0;
    BOOL overdue = lastFull > 0 && days >= kXRHFullReminderDays;
    BOOL ask = [[XRHPrefs shared] boolForKey:kXRHChargeLimitAsk fallback:YES];
    if (!ask && !overdue) return;
    // 电源刚接上时系统自己也在弹充电动画，稍等一下再弹
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (XRBatteryExternalConnected()) XRHShowPrompt(max, overdue, days);
    });
}

void XRHInitChargePrompt(void) {
    gConnected = XRBatteryExternalConnected();   // 注销时本来就插着线：不算新插上，不弹
    int token;
    notify_register_dispatch("com.apple.system.powersources.source", &token, dispatch_get_main_queue(), ^(int t) { XRHPowerChanged(); });
    // 有的情况下 powersources.source 来得晚，再用 UIDevice 的充电状态通知兜一下
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { XRHPowerChanged(); }];
}
