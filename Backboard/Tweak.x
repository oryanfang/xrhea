// backboardd 里的部分：低电量模式下保持高刷新率（「设置 › xrhea › 低电量模式 › 保持高刷新率」）。
// 原理（2026-11-20 真机探测）：低电量模式切换时，QuartzCore 的 -[CAWindowServerDisplay powerStateDidChange:]
// 读一次 NSProcessInfo.isLowPowerModeEnabled，读到 YES 就在内部把屏幕最高刷新率压到 60Hz（不走 setMaximumRefreshRate:）。
// 做法：只在 powerStateDidChange: 执行期间、同一线程上，让这次读取回答 NO；别处读到的仍是真实状态，其他省电措施不变。
// 开关由 SpringBoard 用 Darwin 通知 com.xyrith.xrhea/keep-high-refresh 的状态值传来（1 = 开）：
// backboardd 的沙盒读不到 xrhea 的偏好，也写不了文件。改开关时重发一次 NSProcessInfoPowerStateDidChange，让屏幕马上重新判断。
// 这个 dylib 只链 Foundation（backboardd 不加载 UIKit）。
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <pthread.h>
#import <substrate.h>

#define XRH_KEEP_HIGH_REFRESH "com.xyrith.xrhea/keep-high-refresh"

static BOOL gKeepHigh;              // SpringBoard 传来的开关
static BOOL gInPowerChange;         // 正在 powerStateDidChange: 里
static pthread_t gPowerThread;

#if XRH_DEBUG
// 调试日志：沙盒不让写文件，存进 backboardd 自己的偏好（com.apple.backboardd 的 xrheaLog 键，最多 200 行）
static void XRHBBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void XRHBBLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    static NSMutableArray *lines;
    static NSDateFormatter *f;
    @synchronized ([NSFileManager class]) {
        if (!lines) { lines = [NSMutableArray array]; f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss"; }
        [lines addObject:[NSString stringWithFormat:@"%@ %@", [f stringFromDate:[NSDate date]], line]];
        if (lines.count > 200) [lines removeObjectAtIndex:0];
        CFPreferencesSetAppValue(CFSTR("xrheaLog"), (__bridge CFArrayRef)lines, CFSTR("com.apple.backboardd"));
        CFPreferencesAppSynchronize(CFSTR("com.apple.backboardd"));
    }
}
#else
#define XRHBBLog(...) do {} while (0)
#endif

static BOOL (*orig_isLPM)(id, SEL);
static BOOL hook_isLPM(id self, SEL _cmd) {
    BOOL r = orig_isLPM(self, _cmd);
    if (r && gKeepHigh && gInPowerChange && pthread_equal(pthread_self(), gPowerThread)) {
        XRHBBLog(@"powerStateDidChange: 读低电量 → 回答 NO（保持高刷新率）");
        return NO;
    }
    return r;
}

static void (*orig_powerChanged)(id, SEL, id);
static void hook_powerChanged(id self, SEL _cmd, id arg) {
    if (!gKeepHigh) { orig_powerChanged(self, _cmd, arg); return; }
    BOOL nested = gInPowerChange;
    gInPowerChange = YES;
    gPowerThread = pthread_self();
    orig_powerChanged(self, _cmd, arg);
    gInPowerChange = nested;
}

static void XRHReadKeepHigh(int token, BOOL retrigger) {
    uint64_t v = 0;
    notify_get_state(token, &v);
    BOOL keep = v == 1;
    if (keep == gKeepHigh) return;
    gKeepHigh = keep;
    XRHBBLog(@"保持高刷新率 = %d，低电量 = %d", keep, NSProcessInfo.processInfo.lowPowerModeEnabled);
    // 低电量模式开着时才需要重新判断（关着时两种情况一样）
    if (retrigger && NSProcessInfo.processInfo.lowPowerModeEnabled)
        [[NSNotificationCenter defaultCenter] postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:NSProcessInfo.processInfo];
}

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"backboardd"]) return;
        // 清掉 2026-11-20 探测时临时存的日志键
        CFPreferencesSetAppValue(CFSTR("xrheaProbeLog"), NULL, CFSTR("com.apple.backboardd"));
#if !XRH_DEBUG
        CFPreferencesSetAppValue(CFSTR("xrheaLog"), NULL, CFSTR("com.apple.backboardd"));
#endif
        CFPreferencesAppSynchronize(CFSTR("com.apple.backboardd"));

        Class wsd = objc_getClass("CAWindowServerDisplay");
        SEL powerSel = NSSelectorFromString(@"powerStateDidChange:");
        // 系统改了这条路就什么都不装（不会出错，只是功能不生效）
        if (!wsd || ![wsd instancesRespondToSelector:powerSel] || ![NSProcessInfo instancesRespondToSelector:@selector(isLowPowerModeEnabled)]) {
            XRHBBLog(@"CAWindowServerDisplay powerStateDidChange: 不在，不装");
            return;
        }
        // 先读开关再装 hook：backboardd 启动时就会调一次 powerStateDidChange:（SpringBoard 上次设的状态值还在）
        int token;
        notify_register_dispatch(XRH_KEEP_HIGH_REFRESH, &token, dispatch_get_main_queue(), ^(int t) { XRHReadKeepHigh(t, YES); });
        XRHReadKeepHigh(token, NO);
        MSHookMessageEx(objc_getClass("NSProcessInfo"), @selector(isLowPowerModeEnabled), (IMP)hook_isLPM, (IMP *)&orig_isLPM);
        MSHookMessageEx(wsd, powerSel, (IMP)hook_powerChanged, (IMP *)&orig_powerChanged);
        XRHBBLog(@"xrheabb 已装 pid=%d 保持高刷新率=%d", getpid(), gKeepHigh);
    }
}
