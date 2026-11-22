// 「日志」点进去的几页（XRHLogPages.m）：单次充电详情、全部记录、耗电排行、推送重连
#pragma once
#import <UIKit/UIKit.h>

@interface XRHChargeDetailController : UIViewController
- (instancetype)initWithRecord:(NSDictionary *)record;
@end

@interface XRHChargeListController : UIViewController
@end

@interface XRHDrainController : UIViewController
@end

@interface XRHPushController : UIViewController
@end
