#import <Foundation/Foundation.h>

// 调试日志：仅在调试版（XRH_DEBUG=1）里写入状态文件，正式版为空操作。
// 文件在手机上的真实路径：/var/mobile/Library/Caches/com.xyrith.xrhea.status
// （通过 roothide 的 SSH 查看时要加 /rootfs 前缀）
#define XRH_DEBUG_FILE @"/var/mobile/Library/Caches/com.xyrith.xrhea.status"

void XRHDebugReset(void);
void XRHDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// 调试版：注销 30 秒后开始，每 10 秒记录一次本进程 CPU 占用（100% = 占满一个核），共 2 分钟
void XRHDebugStartCPUSampling(void);
