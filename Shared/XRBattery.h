// 电池读数（xrhea 和 xrkit 共用的一份代码，两边各编一份，互不依赖）。
// 改了这里记得同步到 xrkit：~/Desktop/xrkit 里对应的文件（xrkit 目前还是电池模块里自带的一份，以后换成这个）。
//
// 数据来源：IORegistry 里 AppleSmartBattery 的属性。iOS 17.3.1 真机在 SpringBoard 里实测有：
//   NominalChargeCapacity / DesignCapacity / AppleRawMaxCapacity / AppleRawCurrentCapacity（mAh）、CycleCount、
//   Voltage（mV）、InstantAmperage / Amperage（mA，放电为负、充电为正）、Temperature（0.01 ℃）、
//   TimeRemaining / AvgTimeToEmpty（分钟）、CurrentCapacity（电量 %）、ExternalConnected / IsCharging / FullyCharged、
//   AdapterDetails{Watts, AdapterVoltage(mV), Current(mA), Name, Description, Manufacturer, IsWireless, SerialString…}
//   PowerTelemetryData{SystemPowerIn(mW) 充电头送进来的总功率、BatteryPower(mW) 充进电池的、SystemLoad(mW) 手机自己用的、
//                      SystemVoltageIn(mV) / SystemCurrentIn(mA) 输入电压电流…}（2026-11-19 真机：数显线 11W 时 SystemPowerIn 11646）
// 没有「充满还要多久」的键（AvgTimeToFull / TimeToFull 都没有）；充电时 TimeRemaining、AvgTimeToEmpty 不会动，不能拿来当预计时间。
// 「设置」进程里也能直接读（2026-11-18 xrhea 设置页真机验证过）；普通 App（沙盒）能不能读还没验证过。
//
// 读法：IOKit 函数用 dlsym 取，不链接 IOKit；服务只找一次、一直留着；每次只读要用的那几个键，
// 不要整份取（里面的 BatteryData 很大）。读不到的一律返回 NAN（界面上显示「—」）。
// Serial（电池序列号）是隐私信息，这里故意不提供。
#pragma once
#import <Foundation/Foundation.h>

// 按顺序找第一个有的键，返回数值；都没有返回 NAN
double XRBatteryNumber(NSArray<NSString *> *keys);
// 读一个键的原始值（比如 AdapterDetails 字典），没有返回 nil
// 能不能读到 AppleSmartBattery（读不到时插电检测退回 UIDevice 的电池状态）
BOOL XRBatteryAvailable(void);
id XRBatteryObject(NSString *key);

double XRBatteryVoltage(void);          // 电压，mV
double XRBatteryAmperage(void);         // 电流，mA（放电为负、充电为正）
double XRBatteryWatts(void);            // 电池端功率，W（|电压 × 电流|）：充电时是「充进电池」的那部分，不含手机自己用掉的
double XRBatteryInputWatts(void);       // 充电头送进手机的总功率，W（PowerTelemetryData.SystemPowerIn，mW）：和数显线显示的对得上；没接电源 / 读不到返回 NAN
double XRBatteryPowerWatts(void);       // 给人看的「功率」：接着电源时用 XRBatteryInputWatts（读不到退回电池端），用电池时用 XRBatteryWatts
double XRBatteryTemperature(void);      // 温度，℃
double XRBatteryFullCapacity(void);     // 当前满电容量，mAh
double XRBatteryDesignCapacity(void);   // 设计容量，mAh
double XRBatteryCurrentCharge(void);    // 当前电量，mAh
double XRBatteryHealth(void);           // 健康度 0～1（满电容量 ÷ 设计容量）
double XRBatteryCycleCount(void);       // 循环次数
double XRBatteryTimeRemaining(void);    // 系统算的预计剩余时间，分钟（充电时不更新，见上）
double XRBatteryLevel(void);            // 电量 0～100（%）

BOOL XRBatteryExternalConnected(void);  // 接着电源（线或无线）
BOOL XRBatteryIsCharging(void);         // 正在充电（接着电源但没在充，比如优化充电停在 80%，返回 NO）
BOOL XRBatteryFullyCharged(void);       // 已充满

// 充电器（没接时数值返回 NAN、字符串返回 nil）。序列号（SerialString）是隐私，不提供
double XRBatteryAdapterWatts(void);     // 功率，W
double XRBatteryAdapterVoltage(void);   // 协商电压，V
double XRBatteryAdapterCurrent(void);   // 协商电流，A
NSString *XRBatteryAdapterName(void);   // 型号名，比如 "40W Pwr Adapter 60W Max"（苹果内部写法）
BOOL XRBatteryAdapterIsWireless(void);  // 无线充电
