#import <Preferences/PSTableCell.h>

// 「提示」页的灵动岛长短选择器：左右两张缩略图（长条 / 短条），下面名字 + 圆形选择钮（同系统「显示与亮度」的浅色 / 深色）。
// 缩略图不写字（缩这么小写字看不清，还显得挤），只画比例：白线 = 文字、薄荷线 + 点 = 数值和图标
//   长条（默认，值 0）：约 78% 屏宽，左白字、右彩色数值 + 图标
//   短条（值 1）：2/3 屏宽，左圆环图标 + 数值、右短补充
//
// plist 里用：cell = PSStaticTextCell，cellClass = XRHIslandStyleCell，key = islandStyle，defaults、PostNotification、default 照常写，
//            height 给够缩略图 + 名字 + 选择钮（make_plists.py 里是 160）
@interface XRHIslandStyleCell : PSTableCell
@end
