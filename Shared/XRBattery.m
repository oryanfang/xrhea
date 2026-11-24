#import "XRBattery.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach.h>

typedef mach_port_t xr_io_object_t;
static xr_io_object_t (*pIOServiceGetMatchingService)(mach_port_t, CFDictionaryRef);
static CFMutableDictionaryRef (*pIOServiceMatching)(const char *);
static CFTypeRef (*pIORegistryEntryCreateCFProperty)(xr_io_object_t, CFStringRef, CFAllocatorRef, uint32_t);

// AppleSmartBattery 服务只找一次（一直留着，不释放）
static xr_io_object_t XRBatteryService(void) {
    static xr_io_object_t svc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!h) return;
        pIOServiceGetMatchingService = dlsym(h, "IOServiceGetMatchingService");
        pIOServiceMatching = dlsym(h, "IOServiceMatching");
        pIORegistryEntryCreateCFProperty = dlsym(h, "IORegistryEntryCreateCFProperty");
        if (pIOServiceGetMatchingService && pIOServiceMatching && pIORegistryEntryCreateCFProperty)
            svc = pIOServiceGetMatchingService(0, pIOServiceMatching("AppleSmartBattery"));
    });
    return svc;
}

BOOL XRBatteryAvailable(void) { return XRBatteryService() != 0; }

id XRBatteryObject(NSString *key) {
    xr_io_object_t svc = XRBatteryService();
    if (!svc || !key) return nil;
    return (__bridge_transfer id)pIORegistryEntryCreateCFProperty(svc, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
}

double XRBatteryNumber(NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        id v = XRBatteryObject(k);
        if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    }
    return NAN;
}

double XRBatteryVoltage(void)        { return XRBatteryNumber(@[@"Voltage", @"AppleRawBatteryVoltage"]); }
double XRBatteryAmperage(void)       { return XRBatteryNumber(@[@"InstantAmperage", @"Amperage"]); }
double XRBatteryFullCapacity(void)   { return XRBatteryNumber(@[@"NominalChargeCapacity", @"AppleRawMaxCapacity"]); }
double XRBatteryDesignCapacity(void) { return XRBatteryNumber(@[@"DesignCapacity"]); }
double XRBatteryCurrentCharge(void)  { return XRBatteryNumber(@[@"AppleRawCurrentCapacity"]); }
double XRBatteryCycleCount(void)     { return XRBatteryNumber(@[@"CycleCount"]); }

double XRBatteryWatts(void) {
    double v = XRBatteryVoltage(), a = XRBatteryAmperage();
    return (isnan(v) || isnan(a)) ? NAN : fabs(v * a) / 1e6;
}

double XRBatteryInputWatts(void) {
    NSDictionary *t = XRBatteryObject(@"PowerTelemetryData");
    if (![t isKindOfClass:[NSDictionary class]]) return NAN;
    id v = t[@"SystemPowerIn"];
    return [v isKindOfClass:[NSNumber class]] && [v doubleValue] > 0 ? [v doubleValue] / 1000 : NAN;
}

double XRBatteryPowerWatts(void) {
    if (XRBatteryExternalConnected()) {
        double in = XRBatteryInputWatts();
        if (!isnan(in)) return in;
    }
    return XRBatteryWatts();
}

double XRBatteryTemperature(void) {
    double t = XRBatteryNumber(@[@"Temperature"]);
    return isnan(t) ? NAN : t / 100.0;
}

double XRBatteryHealth(void) {
    double full = XRBatteryFullCapacity(), design = XRBatteryDesignCapacity();
    return (isnan(full) || isnan(design) || design <= 0) ? NAN : full / design;
}

double XRBatteryTimeRemaining(void) {
    double m = XRBatteryNumber(@[@"TimeRemaining", @"AvgTimeToEmpty"]);
    // macOS 上算不出来时是 65535，这里当作没有（iOS 上还没见过，先防着）
    return (isnan(m) || m >= 65535) ? NAN : m;
}

double XRBatteryLevel(void) { return XRBatteryNumber(@[@"CurrentCapacity"]); }

static BOOL XRBatteryFlag(NSString *key, BOOL fallback) {
    id v = XRBatteryObject(key);
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : fallback;
}

BOOL XRBatteryExternalConnected(void) {
    UIDevice *dev = UIDevice.currentDevice;
    if (!dev.batteryMonitoringEnabled) dev.batteryMonitoringEnabled = YES;
    return XRBatteryFlag(@"ExternalConnected", dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull);
}

BOOL XRBatteryIsCharging(void) {
    id v = XRBatteryObject(@"IsCharging");
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    double a = XRBatteryAmperage();
    if (!isnan(a) && a > 0) return YES;
    UIDevice *dev = UIDevice.currentDevice;
    if (!dev.batteryMonitoringEnabled) dev.batteryMonitoringEnabled = YES;
    return dev.batteryState == UIDeviceBatteryStateCharging;
}

BOOL XRBatteryFullyCharged(void) { return XRBatteryFlag(@"FullyCharged", NO); }

// 充电器：没接电源时 AdapterDetails 可能还留着上一次的，所以先看 ExternalConnected
static NSDictionary *XRBatteryAdapter(void) {
    if (!XRBatteryExternalConnected()) return nil;
    NSDictionary *d = XRBatteryObject(@"AdapterDetails");
    return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}

static double XRBatteryAdapterNumber(NSString *key, double scale) {
    id v = XRBatteryAdapter()[key];
    return ([v isKindOfClass:[NSNumber class]] && [v doubleValue] > 0) ? [v doubleValue] / scale : NAN;
}

double XRBatteryAdapterWatts(void)   { return XRBatteryAdapterNumber(@"Watts", 1); }
double XRBatteryAdapterVoltage(void) { return XRBatteryAdapterNumber(@"AdapterVoltage", 1000); }
double XRBatteryAdapterCurrent(void) { return XRBatteryAdapterNumber(@"Current", 1000); }

NSString *XRBatteryAdapterName(void) {
    id n = XRBatteryAdapter()[@"Name"];
    return [n isKindOfClass:[NSString class]] && [n length] ? n : nil;
}

BOOL XRBatteryAdapterIsWireless(void) {
    id v = XRBatteryAdapter()[@"IsWireless"];
    return [v isKindOfClass:[NSNumber class]] && [v boolValue];
}
