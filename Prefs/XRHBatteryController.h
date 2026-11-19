#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>

// 「电池信息」详情页：顶部大字最大容量 + 进度条，下面分组：实时、充电器（接着电源时）、容量、使用，最底下是「这些数字怎么看」指南页入口。
// 页面打开时每秒刷新一次，离开页面就停。
@interface XRHBatteryController : PSListController
@end

// 首页「电池信息」一行用：左边绿底电池图标、右边的健康度文字
UIImage *XRHBatteryRowIcon(void);
NSString *XRHBatteryHealthText(void);
// 同上，有异常（最大容量 / 温度 / 不支持快充）时前面带 ⚠️
NSAttributedString *XRHBatteryRowDetail(UIFont *font, UIColor *color);
