#import <Preferences/PSTableCell.h>

// 自己画的单行滑块单元格（抄自 xrkit 的 XRKSliderCell，两边样子一致）：
//   名称  ━━━━━━━○━━━━━━━━━━  数值
// 不继承系统的 PSSliderTableCell（它会自己重排子视图，跟我们的排版打架、挤成一团）。
//
// plist 里用：cell = PSStaticTextCell，cellClass = XRHSliderCell，
//            label、key、defaults、PostNotification、default、min、max 照常写，
//            xrhFormat = level（整数电量 %，按 xrhStep 一格一格吸附，默认 5：90 → 90%）、
//                        percent（0.4 → 40%）、signedPercent（-0.05 → -5%）或 seconds（3 → 3.0 秒），
//            xrhNameChars = 名称栏宽度（按几个汉字算，同一组写成一样的，滑块左端才对齐；不写就按自己名字的长度）
@interface XRHSliderCell : PSTableCell
@end
