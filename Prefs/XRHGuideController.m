#import "XRHGuideController.h"
#import "XRHLocalize.h"

@interface XRHGuideController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation XRHGuideController {
    UITableView *_table;
    NSArray<NSDictionary *> *_sections;   // [{title, items: [{title, body}]}]
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = XRHL(@"这些数字怎么看");
    NSString *path = [XRHPrefsBundle() pathForResource:@"Guide" ofType:@"plist"];
    NSDictionary *all = [NSDictionary dictionaryWithContentsOfFile:path];
    _sections = all[XRHUsesEnglish() ? @"en" : @"zh"] ?: @[];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.dataSource = self;
    _table.delegate = self;
    _table.allowsSelection = NO;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 120;
    [self.view addSubview:_table];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _sections.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_sections[section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _sections[section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"guide"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"guide"];
    NSDictionary *item = _sections[indexPath.section][@"items"][indexPath.row];
    NSString *title = item[@"title"];

    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    c.text = title.length ? title : nil;
    c.textProperties.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    c.textProperties.numberOfLines = 0;
    // 正文：行距稍微放宽，读起来不挤
    NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
    para.lineSpacing = 3;
    para.paragraphSpacing = 4;
    c.secondaryAttributedText = [[NSAttributedString alloc] initWithString:item[@"body"] ?: @"" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSParagraphStyleAttributeName: para,
    }];
    c.secondaryTextProperties.numberOfLines = 0;
    c.textToSecondaryTextVerticalPadding = 6;
    cell.contentConfiguration = c;
    return cell;
}

@end
