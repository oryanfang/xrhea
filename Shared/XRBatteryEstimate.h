// 预计时间的算法（设置页详情页「预计」和插件的插电提醒共用，只有头文件）。
#pragma once
#import <Foundation/Foundation.h>

// 充电后段变慢的系数：锂电池先恒流快充到 80% 左右，之后电流一路往下掉。
// 80% 以前：后面 20% 按「现在电流的 35%」算；已经过了 80%：电流还会继续掉，按「现在电流的 60%」算。
// 经验值，不是苹果公开的数字；比直接按现在电流算（会低估一半以上）现实得多
static const double kXRHTaperBefore80 = 0.35;
static const double kXRHTaperAfter80 = 0.6;

// 还要多少分钟充到 target%（充电上限开着时是上限，关着时是 100%）。
// level：电量 %，full：实际容量 mAh，amps：平均充电电流 mA（> 0）
static inline double XRHMinutesToTarget(double level, double target, double full, double amps) {
    double frac = MAX(0, MIN(1, level / 100)), goal = MAX(frac, MIN(1, target / 100));
    double fast = MAX(0, MIN(goal, 0.8) - frac) * full;               // 80% 之前，按现在的电流
    double tail = MAX(0, goal - MAX(frac, 0.8)) * full;                // 80% 以后（上限 ≤ 80% 时没有这段）
    double tailRate = amps * (frac < 0.8 ? kXRHTaperBefore80 : kXRHTaperAfter80);
    return (fast / amps + (tail > 0 ? tail / tailRate : 0)) * 60;
}

// 时长取整：一小时内取到 5 分钟，一小时以上取到 10 分钟（估算本来就不精确，写到个位数反而像很准）
static inline long XRHRoundMinutes(double minutes) {
    long m = minutes < 60 ? lround(minutes / 5) * 5 : lround(minutes / 10) * 10;
    return m < 5 ? 5 : m;
}
