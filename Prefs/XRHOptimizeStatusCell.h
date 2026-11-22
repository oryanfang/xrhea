#import <Preferences/PSTableCell.h>

// 「优化」页最上面的状态行：左边小圆点 + 现在在做什么（未触发 / 高温保护 / 直充中），右边数值（温度、整机功耗）。
// 读 xrhead 的状态文件（XRH_LIMIT_STATE_FILE 的 thermalHot / bypass），显示在屏幕上时每 2 秒刷新。
//
// plist 里用：cell = PSStaticTextCell，cellClass = XRHOptimizeStatusCell
@interface XRHOptimizeStatusCell : PSTableCell
@end
