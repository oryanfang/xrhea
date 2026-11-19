// 所有偏好键集中在这里，与 Prefs/make_plists.py 生成的 plist 里的 key 保持一致
#pragma once

// 总开关
#define kXRHEnabled            @"enabled"

// 充电上限（Daemon/main.m 的 xrhead 读这几个键；默认关）
#define kXRHChargeLimit        @"chargeLimit"
#define kXRHChargeLimitMax     @"chargeLimitMax"     // 上限 %，默认 80
#define kXRHChargeLimitGap     @"chargeLimitGap"     // 掉多少再充，默认 5（80% 停、75% 再充）
#define kXRHChargeLimitAsk     @"chargeLimitAsk"     // 插上电源时弹窗问「确认 / 这次充满」，默认开
#define kXRHChargeLimitFullOnce @"chargeLimitFullOnce" // 这次充满（插件写，拔线清掉；xrhead 读）

// 充电上限服务 xrhead 写的状态文件（Daemon/main.m 里同一个路径），插件和设置页读
#define XRH_LIMIT_STATE_FILE   @"/var/mobile/Library/Caches/com.xyrith.xrhea.limit.plist"

// 提示样式：0 自动（有灵动岛用灵动岛）/ 1 灵动岛 / 2 横幅
#define kXRHToastStyle         @"toastStyle"
#define kXRHIslandStyle        @"islandStyle"        // 灵动岛长短：0 长条（同系统充电那条，左字右值，默认）/ 1 短条（2/3 屏宽，左图标 + 值、右短补充）
#define kXRHToastTapOpen       @"toastTapOpen"       // 点提示打开「电池信息」详情页（默认开；锁屏时只收起）
#define kXRHToastFocusQuiet    @"toastFocusQuiet"    // 专注模式（勿扰、睡眠等）开着时不弹（默认开）
#define kXRHFocusAllowPrefix   @"focusAllow."        // + 提醒的键（如 focusAllow.alertHot）：专注时照样弹这条；默认只有过热、低温

// 提醒（Tweak/Alerts.m）：每种一个开关，前 5 个默认开、「耗电很快」默认关
#define kXRHAlertPlugIn        @"alertPlugIn"        // 插上电源：充电器功率 + 约多久到上限 / 充满
#define kXRHAlertLimit         @"alertLimit"         // 到上限停充了
#define kXRHAlertSlow          @"alertSlow"          // 充电很慢（只跑 5 V，或功率持续 < 5 W）
#define kXRHAlertHot           @"alertHot"           // 温度偏高（≥ 40 ℃ / ≥ 45 ℃）
#define kXRHAlertUnplug        @"alertUnplug"        // 拔线时总结这次充了多少
#define kXRHAlertDrain         @"alertDrain"         // 耗电很快（用电池时 1 分钟平均 > 6 W），默认关
#define kXRHAlertFull          @"alertFull"          // 充满（没开上限时到 100%）
#define kXRHAlertThrottle      @"alertThrottle"      // 降速（系统因为温度给充电限流）
#define kXRHAlertStandby       @"alertStandby"       // 待机掉电快（锁屏期间每小时掉 > 3%，亮屏时说）
#define kXRHAlertBedtime       @"alertBedtime"       // 睡前（22 点到 2 点、没插线、电量 < 30%，每晚一次）
#define kXRHAlertCold          @"alertCold"          // 低温充电（充电时电池 < 5 ℃）
#define kXRHAlertFlaky         @"alertFlaky"         // 接触不良（1 分钟内断开 ≥ 3 次）
#define kXRHAlertTarget        @"alertTarget"        // 到点（充到自己设的电量提醒，不停充），默认关
#define kXRHAlertTargetLevel   @"alertTargetLevel"   // 到点的电量 %，默认 90
#define kXRHAlertStopped       @"alertStopped"       // 中断（插着电却没在充，不是上限、不是充满）
