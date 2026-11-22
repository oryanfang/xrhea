// 低电量模式（「设置 › xrhea › 低电量模式」）：自动开关系统的低电量模式，并把「保持高刷新率」的开关传给 backboardd（Backboard/Tweak.x）。
//   lpmBelowOn + lpmBelow（滑块 0～100%，推荐 20）：没接电源、电量掉到这个数时开一次（这次放电期间只开一次，用户手动关掉就不再开）
//   lpmOffOn + lpmOffAt（滑块 0～100%，推荐 80）：接着电源充到这个数时关（不管是谁开的；系统自己在 80% 也会关）
//   lpmLocked：锁屏时开，解锁时关——只关自己开的那次；锁屏期间电量掉到 lpmBelow 以下的，解锁后保持开着
//   lpmCharging：插上电源时开，拔线时关——只关自己开的那次（插电前已经开着的不动）。系统充到 80% 会自己关低电量模式，这里不跟它抢
// 开关低电量模式：iOS 17 用 _CDBatterySaver（CoreDuet），没有就试 _PMLowPowerMode（LowPowerMode.framework）
#import "XRHCommon.h"
#import <notify.h>
#import <dlfcn.h>

static BOOL gLockLPM;      // 现在的低电量模式是锁屏时我们开的
static BOOL gLowFired;     // 这次放电期间「低于 X% 开」已经触发过
static int gLockToken = -1;
static BOOL gChargeLPM;    // 现在的低电量模式是插上电源时我们开的
static BOOL gLPMWasConnected;

static BOOL XRHLPMOn(void) {
    return NSProcessInfo.processInfo.lowPowerModeEnabled;
}

static BOOL XRHSetLPM(BOOL on, NSString *why) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode", RTLD_LAZY);
    });
    BOOL ok = NO;
    if (XRHClassResponds("_CDBatterySaver", @[@"batterySaver"])) {
        id saver = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("_CDBatterySaver"), NSSelectorFromString(@"batterySaver"));
        SEL set = NSSelectorFromString(@"setPowerMode:error:");
        if ([saver respondsToSelector:set]) {
            NSError *err = nil;
            ok = ((BOOL (*)(id, SEL, long, NSError **))objc_msgSend)(saver, set, on ? 1 : 0, &err);
        }
    } else if (XRHClassResponds("_PMLowPowerMode", @[@"sharedInstance"])) {
        id pm = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("_PMLowPowerMode"), NSSelectorFromString(@"sharedInstance"));
        SEL set = NSSelectorFromString(@"setPowerMode:fromSource:");
        if ([pm respondsToSelector:set]) {
            ((void (*)(id, SEL, long, id))objc_msgSend)(pm, set, on ? 1 : 0, @"xrhea");
            ok = YES;
        }
    }
    XRHDebugLog(@"[LowPower] 低电量模式 → %d（%@）ok=%d", on, why, ok);
    return ok;
}

static BOOL XRHLocked(void) {
    if (gLockToken < 0) return NO;
    uint64_t state = 0;
    notify_get_state(gLockToken, &state);
    return state != 0;
}

// 开关关着时返回 0；数值是滑块存的（默认 = 推荐值）
static int XRHLPMBelow(void) { return XRHOn(@"lpmBelowOn") ? (int)lround(XRHDouble(@"lpmBelow", 20, 0, 100)) : 0; }
static int XRHLPMOffAt(void) { return XRHOn(@"lpmOffOn") ? (int)lround(XRHDouble(@"lpmOffAt", 80, 0, 100)) : -1; }   // 关着是 −1（0% = 一插电就关）

// 电量、电源变了
static void XRHLowPowerTick(void) {
    if (![XRHPrefs shared].enabled) return;
    double level = XRBatteryLevel();
    BOOL connected = XRBatteryExternalConnected();
    if (isnan(level)) return;
    int below = XRHLPMBelow(), offAt = XRHLPMOffAt();

    // 充电时开启：插上时开（本来没开才开），拔线时关自己开的那次
    if (connected != gLPMWasConnected) {
        gLPMWasConnected = connected;
        if (connected && XRHOn(@"lpmCharging") && !XRHLPMOn() && XRHSetLPM(YES, @"插上电源")) gChargeLPM = YES;
        else if (!connected && gChargeLPM) {
            gChargeLPM = NO;
            if (XRHLPMOn() && !(below > 0 && level <= below)) XRHSetLPM(NO, @"拔线");   // 拔线时电量已经低于「低电量时开启」的线就留着
        }
    }

    if (connected || below <= 0 || level > below) gLowFired = NO;
    else if (!gLowFired) {
        gLowFired = YES;
        if (!XRHLPMOn()) XRHSetLPM(YES, [NSString stringWithFormat:@"电量 %.0f%% ≤ %d%%", level, below]);
        gLockLPM = NO;   // 现在是因为电量低开着，解锁时别关
    }

    // 锁屏开的那次，锁着时不因为充电去关（解锁时会关）
    if (offAt >= 0 && connected && level >= offAt && XRHLPMOn() && !(gLockLPM && XRHLocked())) {
        XRHSetLPM(NO, [NSString stringWithFormat:@"充到 %.0f%% ≥ %d%%", level, offAt]);
        gLockLPM = NO;
    }
}

static void XRHLockChanged(void) {
    if (![XRHPrefs shared].enabled) return;
    if (XRHLocked()) {
        if (XRHOn(@"lpmLocked") && !XRHLPMOn() && XRHSetLPM(YES, @"锁屏")) gLockLPM = YES;
    } else if (gLockLPM) {
        gLockLPM = NO;
        if (XRHLPMOn()) XRHSetLPM(NO, @"解锁");
    }
}

// 保持高刷新率（低电量模式下）：backboardd 读不到偏好，用 Darwin 通知的状态值传过去（1 = 开），见 Backboard/Tweak.x
void XRHSyncHighRefresh(void) {
    static int token = -1;
    if (token < 0 && notify_register_check("com.xyrith.xrhea/keep-high-refresh", &token) != NOTIFY_STATUS_OK) return;
    uint64_t v = [XRHPrefs shared].enabled && XRHOn(@"lpmKeepHighRefresh") ? 1 : 0;
    uint64_t old = 0;
    notify_get_state(token, &old);
    if (old == v) return;
    notify_set_state(token, v);
    notify_post("com.xyrith.xrhea/keep-high-refresh");
    XRHDebugLog(@"[LowPower] 保持高刷新率 → %llu", v);
}

void XRHInitLowPower(void) {
    XRHAddRefresher(@[@"lpmKeepHighRefresh"], ^{ XRHSyncHighRefresh(); });
    int token;
    notify_register_dispatch("com.apple.system.powersources.percent", &token, dispatch_get_main_queue(), ^(int t) { XRHLowPowerTick(); });
    notify_register_dispatch("com.apple.system.powersources.source", &token, dispatch_get_main_queue(), ^(int t) { XRHLowPowerTick(); });
    notify_register_dispatch("com.apple.springboard.lockstate", &gLockToken, dispatch_get_main_queue(), ^(int t) { XRHLockChanged(); });
#if XRH_DEBUG
    // 调试：com.xyrith.xrhea/test-lpm 切换一次低电量模式，确认开关接口能用
    notify_register_dispatch("com.xyrith.xrhea/test-lpm", &token, dispatch_get_main_queue(), ^(int t) {
        XRHDebugLog(@"[LowPower] test-lpm CD=%d PM=%d now=%d", objc_getClass("_CDBatterySaver") != nil, objc_getClass("_PMLowPowerMode") != nil, XRHLPMOn());
        XRHSetLPM(!XRHLPMOn(), @"测试");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ XRHDebugLog(@"[LowPower] test-lpm 之后 now=%d", XRHLPMOn()); });
    });
#endif
    gLPMWasConnected = XRBatteryExternalConnected();   // 注销时本来就插着线：不算新插上
    XRHLowPowerTick();
}
