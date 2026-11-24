#import <Foundation/Foundation.h>

// 事件日志：正式版也写，用来事后对照「重启 / 异常前 xrhea 做过什么」（2026-11-24 加，用来排查整机重启）。
// 只记少量关键动作：启动、停充 / 恢复、低电量模式切换、保持高刷新率开关、插拔、锁屏 / 亮屏、发现新的 panic 日志。
// SpringBoard（mobile）和 xrhead（root）写同一个文件：O_APPEND 单次 write 一行，权限 0666；超过 256KB 换到 .1，最多两份（约 512KB）。
// 手机上的真实路径（roothide 下 SSH 要加 /rootfs 前缀）：
#define XRH_EVENTS_FILE @"/var/mobile/Library/Caches/com.xyrith.xrhea.events.log"

// tag 是来源短名（sb / daemon），一行格式：2026-11-24 03:30:01 [sb] 文本
void XRHEvent(const char *tag, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

// 最近 maxLines 行（含上一份 .1），从旧到新；没有就返回空数组
NSArray<NSString *> *XRHEventsTail(NSUInteger maxLines);
