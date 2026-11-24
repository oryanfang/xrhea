#import "XRHEvents.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static const off_t kXRHEventsMax = 256 * 1024;

void XRHEvent(const char *tag, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // NSDateFormatter 不是线程安全的：每次新建（事件很少，开销可以忽略）
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ [%s] %@\n", [f stringFromDate:[NSDate date]], tag ?: "?",
                      [msg stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    const char *path = XRH_EVENTS_FILE.fileSystemRepresentation;
    struct stat st;
    if (stat(path, &st) == 0 && st.st_size > kXRHEventsMax) {
        // 两个进程可能同时发现超了：rename 是原子的，后到的那个 rename 会把刚换的新文件（很小）挪走，最多丢几行
        rename(path, [XRH_EVENTS_FILE stringByAppendingString:@".1"].fileSystemRepresentation);
    }
    int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0666);
    if (fd < 0) return;
    fchmod(fd, 0666);   // umask 会去掉组 / 其他写权限；root 建的文件也要让 SpringBoard（mobile）能写
    write(fd, data.bytes, data.length);
    close(fd);
}

NSArray<NSString *> *XRHEventsTail(NSUInteger maxLines) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *p in @[[XRH_EVENTS_FILE stringByAppendingString:@".1"], XRH_EVENTS_FILE]) {
        NSString *s = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
        for (NSString *l in [s componentsSeparatedByString:@"\n"]) if (l.length) [lines addObject:l];
    }
    if (lines.count > maxLines) [lines removeObjectsInRange:NSMakeRange(0, lines.count - maxLines)];
    return lines;
}
