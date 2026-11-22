#import <Preferences/PSViewController.h>
#import <UIKit/UIKit.h>

// 「日志」页：24 小时电量曲线（xrhead 记的 XRH_LEVELS_FILE）、充电记录（最近几次 + 全部记录）、充电器（实测速度，可改名）、耗电排查（锁屏待机速度 + 耗电排行，xrhead 读系统电池记录）。
// 数据是插件写的 XRH_CHARGES_FILE / XRH_CHARGE_CURRENT_FILE（Tweak/ChargeLog.m）和 XRH_RATES_FILE（Tweak/Alerts.m）；
// 充电器改的名字存在偏好 chargerNames 里。
@interface XRHLogController : PSViewController
@end
