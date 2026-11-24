// 插件各模块共用的小工具（只给 Tweak 用，设置面板不引用）。抄自 xrkit 的 XRKCommon.h，只留通用的部分
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "XRHPrefs.h"
#import "XRHDebug.h"
#import "XRHEvents.h"
#import "XRHKeys.h"
#import "XRBattery.h"
#import "XRBatteryEstimate.h"

#pragma mark - 偏好

static inline BOOL XRHOn(NSString *key) {
    return [[XRHPrefs shared] boolForKey:key fallback:NO];
}

static inline double XRHDouble(NSString *key, double fallback, double min, double max) {
    double v = [[XRHPrefs shared] doubleForKey:key fallback:fallback];
    return MAX(min, MIN(max, v));
}

// 插件自己往偏好里写，写完立刻同步
static inline void XRHWritePref(NSString *key, id value) {
    CFStringRef domain = (__bridge CFStringRef)XRH_PREFS_DOMAIN;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);   // value 为 nil 时删掉这个键
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

#pragma mark - 运行时

// 按名字取类，结果缓存在调用处（高频路径里代替 objc_getClass）
#define XRHClass(name) ({ static Class _xrh_cls; if (!_xrh_cls) _xrh_cls = objc_getClass(name); _xrh_cls; })

// 类存在且所有实例方法都存在才返回 YES。只给检查通过的功能装 hook，类名/方法在新系统变了也不会让 SpringBoard 崩
static inline BOOL XRHResponds(const char *className, NSArray<NSString *> *selectors) {
    Class cls = objc_getClass(className);
    if (!cls) return NO;
    for (NSString *sel in selectors) {
        if (![cls instancesRespondToSelector:NSSelectorFromString(sel)]) return NO;
    }
    return YES;
}

// 同上，检查类方法
static inline BOOL XRHClassResponds(const char *className, NSArray<NSString *> *selectors) {
    Class cls = objc_getClass(className);
    if (!cls) return NO;
    for (NSString *sel in selectors) {
        if (![cls respondsToSelector:NSSelectorFromString(sel)]) return NO;
    }
    return YES;
}

// 对象没有这个方法时返回 nil / fallback，不崩溃（只用于无参数、返回对象 / BOOL 的方法）
static inline id XRHSafeCall(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static inline BOOL XRHSafeBool(id obj, NSString *selName, BOOL fallback) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}

#pragma mark - 窗口、充电上限状态

// 前台的窗口场景（没有就随便一个），插件自己的提示 / 弹窗窗口挂在它上面
UIWindowScene *XRHActiveWindowScene(void);
// xrhead 写的状态文件（XRH_LIMIT_STATE_FILE）：{inhibited, max, resumeAt, time, lastFull}；读不到返回 nil
NSDictionary *XRHLimitState(void);
// 现在是不是 xrhead 停的充
BOOL XRHLimitInhibited(void);
BOOL XRHThermalHot(void);
BOOL XRHBypassActive(void);

#pragma mark - 改设置后立即刷新

// 模块登记"改设置后要做的刷新"，收到通知时在主线程按登记顺序执行。
// keys：这个刷新关心的偏好键，只有其中某个值变了才执行；传 nil 表示每次都执行
void XRHAddRefresher(NSArray<NSString *> *keys, void (^refresher)(void));
void XRHRunRefreshers(void);

#pragma mark - 各模块入口（各在自己的 .x 文件里，Tweak.x 按顺序调用）

void XRHInitChargePrompt(void);   // 插上电源时的充电上限弹窗（ChargePrompt.m）
void XRHInitLowPower(void);       // 低电量模式（LowPower.m）：自动开关
void XRHSyncHighRefresh(void);    // 低电量模式下保持高刷新率的开关传给 backboardd（LowPower.m）
void XRHInitAlerts(void);         // 提醒（Alerts.m）：插电、到上限、充电慢、偏热、拔线总结、耗电快
void XRHInitChargeLog(void);      // 充电记录（ChargeLog.m）：每次插拔记一条，设置页「日志」显示
BOOL XRHChargePromptShowing(void);

#pragma mark - 提示（Toast.m）

typedef NS_ENUM(NSInteger, XRHToastKind) { XRHToastInfo = 0, XRHToastWarning = 1 };
// 显示一条提示：symbol 是图标的 SF Symbol（可为 nil），detail 可为 nil。样式按「提示样式」设置：
//   灵动岛：2/3 屏宽胶囊，中间是镜头，左图标 + compact（如「27W」）、右 compactDetail（如「约1小时」），nil 时退回 title / detail；
//   横幅：图标 + title + detail
void XRHShowToast(XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail, NSString *compact, NSString *compactDetail);
// 同上，再带灵动岛长条用的两样：label（左边白字，如「正在充电」）、value（右边彩色数值，如「8.5W」，后面跟图标）。
// XRHShowToast 不带这两样时：左边用 title，右边用 compact（title 里已经有 compact 就用 compactDetail，免得重复）
void XRHShowToastFull(XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail, NSString *compact, NSString *compactDetail,
                      NSString *label, NSString *value);
// 同上，点提示打开的不是「电池信息」而是 tapPath 那一页（Root.plist 里那行的 id，比如 log）
void XRHShowToastOpening(XRHToastKind kind, NSString *symbol, NSString *title, NSString *detail, NSString *compact, NSString *compactDetail,
                         NSString *label, NSString *value, NSString *tapPath);
BOOL XRHHasDynamicIsland(void);

#pragma mark - 文字

// 插件里没有设置页那套翻译表，文字直接中英两份：关于页选了语言就按它，「跟随系统」看系统首选语言
static inline NSString *XRHText(NSString *zh, NSString *en) {
    double lang = XRHDouble(@"prefsLanguage", 0, 0, 2);
    if (lang == 1) return zh;
    if (lang == 2) return en;
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"] ? zh : en;
}
