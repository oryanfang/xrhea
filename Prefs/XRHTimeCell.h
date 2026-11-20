#import <Preferences/PSTableCell.h>

// 选时间的一行：左边名字，右边系统的紧凑时间按钮（点一下弹出转轮），同系统「闹钟」「睡眠」里选时间的样子。
// 存的是一天里的第几分钟（7:00 → 420）。
//
// plist 里用：cell = PSStaticTextCell，cellClass = XRHTimeCell，label、key、defaults、PostNotification、default 照常写
@interface XRHTimeCell : PSTableCell
@end
