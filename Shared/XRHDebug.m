#import "XRHDebug.h"
#import <sys/resource.h>

void XRHDebugReset(void) {
#if XRH_DEBUG
    [@"" writeToFile:XRH_DEBUG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
#endif
}

void XRHDebugLog(NSString *format, ...) {
#if XRH_DEBUG
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:XRH_DEBUG_FILE];
    if (!handle) {
        [@"" writeToFile:XRH_DEBUG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:XRH_DEBUG_FILE];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
#endif
}

#if XRH_DEBUG
static double XRHCPUSeconds(void) {
    struct rusage u;
    getrusage(RUSAGE_SELF, &u);
    return u.ru_utime.tv_sec + u.ru_utime.tv_usec / 1e6 + u.ru_stime.tv_sec + u.ru_stime.tv_usec / 1e6;
}

static void XRHSampleCPU(int remaining, double lastCPU, CFAbsoluteTime lastTime) {
    if (remaining <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        double cpu = XRHCPUSeconds();
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        XRHDebugLog(@"[CPU] %.1f%%", (cpu - lastCPU) / (now - lastTime) * 100.0);
        XRHSampleCPU(remaining - 1, cpu, now);
    });
}
#endif

void XRHDebugStartCPUSampling(void) {
#if XRH_DEBUG
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        XRHSampleCPU(12, XRHCPUSeconds(), CFAbsoluteTimeGetCurrent());
    });
#endif
}
