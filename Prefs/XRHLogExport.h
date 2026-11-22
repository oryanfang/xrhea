// 「日志」右上角导出（XRHLogExport.m）：一份给自己或 AI 分析用的 Markdown，语言跟着设置页走
#pragma once
#import <Foundation/Foundation.h>

NSString *XRHExportMarkdown(void);
NSString *XRHExportTime(double unix, NSString *format);
