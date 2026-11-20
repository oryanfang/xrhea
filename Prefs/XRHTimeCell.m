#import "XRHTimeCell.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

@interface PSListController (XRHTimeCell)
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation XRHTimeCell {
    UILabel *_nameLabel;
    UIDatePicker *_picker;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _nameLabel.textColor = UIColor.labelColor;

    _picker = [UIDatePicker new];
    _picker.datePickerMode = UIDatePickerModeTime;
    _picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    _picker.minuteInterval = 5;
    [_picker addTarget:self action:@selector(xrh_changed) forControlEvents:UIControlEventValueChanged];

    for (UIView *v in @[_nameLabel, _picker]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:v];
    }
    UILayoutGuide *m = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_nameLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [_nameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_picker.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [_picker.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_picker.leadingAnchor constraintGreaterThanOrEqualToAnchor:_nameLabel.trailingAnchor constant:12],
    ]];
    [self xrh_loadFromSpecifier:specifier];
    return self;
}

// 用的是 PSStaticTextCell 类型，系统可能把它设成"不可用"（变灰、不能点），这里始终保持可用
- (void)setCellEnabled:(BOOL)enabled {
    [super setCellEnabled:YES];
    self.userInteractionEnabled = YES;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.text = nil;
    [self xrh_loadFromSpecifier:specifier];
}

- (void)xrh_loadFromSpecifier:(PSSpecifier *)specifier {
    if (!specifier) return;
    _nameLabel.text = specifier.name;
    self.textLabel.text = nil;
    id value = nil;
    if ([specifier.target respondsToSelector:@selector(readPreferenceValue:)]) value = [specifier.target readPreferenceValue:specifier];
    if (!value) value = [specifier propertyForKey:@"default"];
    NSInteger minutes = MAX(0, MIN(24 * 60 - 1, [value integerValue]));
    _picker.date = [NSCalendar.currentCalendar dateBySettingHour:minutes / 60 minute:minutes % 60 second:0 ofDate:[NSDate date] options:0];
}

- (void)xrh_changed {
    NSDateComponents *c = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:_picker.date];
    id target = self.specifier.target;
    if ([target respondsToSelector:@selector(setPreferenceValue:specifier:)])
        [target setPreferenceValue:@(c.hour * 60 + c.minute) specifier:self.specifier];
}

@end
