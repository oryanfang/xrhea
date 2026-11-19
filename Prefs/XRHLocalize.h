// 设置页的中 / 英文：原文是中文，en.lproj/Localizable.strings 是英文（由 make_plists.py 生成）。
// 关于页「语言」（偏好 prefsLanguage）：0 跟随系统——系统是中文时 NSBundle 选 zh-Hans.lproj（空表），查不到就用原文，
// 其他语言选 en.lproj；1 一律中文；2 一律英文。
#pragma once
#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>

static inline NSBundle *XRHPrefsBundle(void) {
    static NSBundle *bundle;
    if (!bundle) bundle = [NSBundle bundleForClass:NSClassFromString(@"XRHRootListController")];
    return bundle;
}

typedef NS_ENUM(NSInteger, XRHPrefsLanguage) { XRHPrefsLanguageSystem = 0, XRHPrefsLanguageChinese = 1, XRHPrefsLanguageEnglish = 2 };
extern NSInteger gXRHPrefsLanguage;   // -1 = 还没读偏好（定义在 XRHRootListController.m，各文件共用一份）

static inline XRHPrefsLanguage XRHCurrentPrefsLanguage(void) {
    if (gXRHPrefsLanguage < 0) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("prefsLanguage"), CFSTR("com.xyrith.xrhea"));
        gXRHPrefsLanguage = (v && CFGetTypeID(v) == CFNumberGetTypeID()) ? [(__bridge NSNumber *)v integerValue] : 0;
        if (v) CFRelease(v);
    }
    return (XRHPrefsLanguage)gXRHPrefsLanguage;
}

// 整段文字分中英两份的地方（指南页 Guide.plist）用：现在该显示英文吗
static inline BOOL XRHUsesEnglish(void) {
    switch (XRHCurrentPrefsLanguage()) {
        case XRHPrefsLanguageChinese: return NO;
        case XRHPrefsLanguageEnglish: return YES;
        default: return ![XRHPrefsBundle().preferredLocalizations.firstObject hasPrefix:@"zh"];
    }
}

// 设置页里选了新语言（XRHSubListController -setPreferenceValue:specifier:）
static inline void XRHSetPrefsLanguage(NSInteger lang) { gXRHPrefsLanguage = lang; }

static inline NSString *XRHL(NSString *text) {
    if (!text.length) return text;
    switch (XRHCurrentPrefsLanguage()) {
        case XRHPrefsLanguageChinese: return text;
        case XRHPrefsLanguageEnglish: {
            static NSDictionary *english;
            if (!english) {
                NSString *path = [XRHPrefsBundle() pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:@"en"];
                english = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
            }
            return english[text] ?: text;
        }
        default: return [XRHPrefsBundle() localizedStringForKey:text value:text table:@"Localizable"];
    }
}

// 设置页 plist 读进来以后，把名字、组说明、多选项的选项和说明都换成当前语言
static inline void XRHLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers) {
    for (PSSpecifier *spec in specifiers) {
        if (spec.name.length) spec.name = XRHL(spec.name);
        for (NSString *key in @[@"footerText", @"staticTextMessage", @"label", @"xrhNote"]) {
            id v = [spec propertyForKey:key];
            if ([v isKindOfClass:[NSString class]]) [spec setProperty:XRHL(v) forKey:key];
        }
        NSMutableDictionary *(^map)(NSDictionary *) = ^NSMutableDictionary *(NSDictionary *d) {
            NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:d.count];
            [d enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { m[k] = [v isKindOfClass:[NSString class]] ? XRHL(v) : v; }];
            return m;
        };
        if (spec.titleDictionary.count) spec.titleDictionary = map(spec.titleDictionary);
        if (spec.shortTitleDictionary.count) spec.shortTitleDictionary = map(spec.shortTitleDictionary);
    }
}
