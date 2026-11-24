#!/usr/bin/env python3
# 生成 Prefs/Resources 下的设置页 plist（Root / About / Guide）和中英文翻译表。照 xrkit 的 make_plists.py 改的。
# 改设置页就改这里，然后运行：python3 Prefs/make_plists.py
#
# 写法约定（同 xrkit）：
# - 需要注销才生效的项：respring=True → 名字后面显示橙色小标签「需注销」，说明文字里不再重复
# - 设置页的文字和 Prefs/*.m 里 XRHL(@"…") 的文字都要在 EN 里有英文，漏翻会直接报错
import plistlib, os

DOMAIN = "com.xyrith.xrhea"
NOTIFY = "com.xyrith.xrhea/prefschanged"
HERE = os.path.dirname(os.path.abspath(__file__))
# 版本号从 control 读（升版本只改 control）
VERSION = next(l.split(":", 1)[1].strip() for l in open(os.path.join(HERE, "..", "control")) if l.startswith("Version:"))
OUT = os.path.join(HERE, "Resources")


def group(label=None, footer=None):
    d = {"cell": "PSGroupCell"}
    if label: d["label"] = label
    if footer: d["footerText"] = footer
    return d


def _pref(d, key, default, respring, requires):
    d.update({"key": key, "default": default, "defaults": DOMAIN, "PostNotification": NOTIFY})
    if respring: d["xrhRespring"] = True
    if requires: d["xrhRequires"] = requires
    return d


def switch(label, key, default=False, respring=False, requires=None):
    return _pref({"cell": "PSSwitchCell", "label": label}, key, default, respring, requires)


def choice(label, key, values, titles, default, short=None, message=None, respring=False, requires=None):
    d = {"cell": "PSLinkListCell", "detail": "PSListItemsController", "label": label,
         "validValues": values, "validTitles": titles}
    if short: d["shortTitles"] = short
    if message: d["staticTextMessage"] = message
    return _pref(d, key, default, respring, requires)


def slider(label, key, default, lo, hi, fmt, name_chars, requires=None, step=None):
    # 单行滑块：名字 ━━○━━ 数值（XRHSliderCell，抄自 xrkit）
    d = {"cell": "PSStaticTextCell", "cellClass": "XRHSliderCell", "label": label,
         "min": lo, "max": hi, "xrhFormat": fmt, "xrhNameChars": name_chars}
    if step: d["xrhStep"] = step
    return _pref(d, key, default, False, requires)


def value(label, text):
    # 只读的一行：名字在左、值在右（XRHSubListController -xrhStaticValue: 返回 xrhValue）
    return {"cell": "PSTitleValueCell", "label": label, "get": "xrhStaticValue:", "xrhValue": text}


def button(label, action):
    return {"cell": "PSButtonCell", "label": label, "action": action}


def link(label, plist, icon=None):
    d = {"cell": "PSLinkCell", "label": label, "detail": "XRHSubListController", "plistName": plist}
    if icon and os.path.exists(os.path.join(OUT, icon)): d["icon"] = icon
    return d


PAGES = {}

PAGES["Root"] = ("xrhea", [
    group(),
    # 电池信息：详情页是代码写的（XRHBatteryController），图标和右边的健康度在 XRHRootListController 里填
    {"cell": "PSLinkCell", "label": "电池信息", "detail": "XRHBatteryController", "xrhBatteryRow": True, "id": "battery"},   # id：prefs:root=xrhea&path=battery 直达（点提示打开详情用）
    # 日志：页面是代码写的（Prefs/XRHLogController.m），充电记录由插件 Tweak/ChargeLog.m 写
    {"cell": "PSLinkCell", "label": "日志", "detail": "XRHLogController", "xrhSymbol": "chart.xyaxis.line", "xrhSymbolColor": "blue", "id": "log"},   # id：每周小结点开直达
    # 充电上限：图标是代码画的橙底半亮闪电（XRHRootListController 的 XRHBoltHalfIcon）
    dict(link("充电上限", "ChargeLimit"), xrhDrawn="boltHalf"),
    # 优化：图标是代码画的紫底白色叶子（XRHRootListController 的 XRHLeafIcon）
    dict(link("优化", "Optimize"), xrhDrawn="leaf"),
    # 低电量模式：图标是代码画的黄底白色电池（XRHRootListController 的 XRHLowPowerIcon）
    dict(link("低电量模式", "LowPower"), xrhDrawn="lowPower"),
    dict(link("提示", "Toast"), xrhSymbol="bell.badge.fill", xrhSymbolColor="red"),
    # 以后的功能区（提醒等）每个一个子页面，加在这里
    group(),
    switch("启用 xrhea", "enabled", True, respring=True),
    group(),
    # 关于的图标用 xrhea 自己的图标（About.png 由 tools/make_logo.swift 导出）
    link("关于", "About", "About.png"),
    # 注销在导航栏右上角（XRHRootListController -viewDidLoad）
])

# 优化：高温保护、边充边玩直充在 xrhead（Daemon/main.m 的 XRHThermalTick / XRHBypassTick）；
# 后台耗电提醒：xrhead 每小时查系统电池记录（XRHDrainQuery），SpringBoard 弹（Tweak/Alerts.m 第 15 条）
PAGES["Optimize"] = ("优化", [
    # 最上面是状态行（XRHOptimizeStatusCell：未触发 / 高温保护 / 直充中）
    group(),
    {"cell": "PSStaticTextCell", "cellClass": "XRHOptimizeStatusCell", "label": "状态", "height": 52},
    # 数值都用滑块（默认 = 推荐值，页脚写推荐值），特殊需求自己拖
    group("充电保护", "停充：达到温度后停止充电。间歇充电：停 3 分钟、充 3 分钟交替，平均电流约减半。低于设定温度 3℃ 后恢复。无线充电发热更多，按单独的温度提前保护。推荐有线 40℃、无线 37℃。"),
    dict(switch("高温保护", "thermalGuard", False), xrhNote="充电时", height=52),
    dict(slider("温度", "thermalTemp", 40, 30, 50, "celsius", 2, requires="thermalGuard", step=1), height=52),
    dict(slider("无线", "thermalTempWireless", 37, 30, 50, "celsius", 2, requires="thermalGuard", step=1), height=52),
    dict(choice("处理方式", "thermalMode", [0, 1], ["停充", "间歇充电"], 1, requires="thermalGuard"), height=52),
    group("直充", "整机功耗 1 分钟平均高于设定值时停止给电池充电，由电源直接供电；低于设定值 1 W 后恢复。电量低于 20% 时不直充。推荐 4 W。"),
    dict(switch("边充边玩直充", "bypassCharge", False), xrhNote="高负载时", height=52),
    dict(slider("功耗", "bypassWatts", 4, 2, 10, "watts", 2, requires="bypassCharge", step=0.5), height=52),
    group("后台", "每小时查看一次系统电池记录；连续 3 个锁屏小时超过设定占比时提醒，同一个 App 每天最多一次。推荐 30%。"),
    dict(switch("后台耗电提醒", "bgDrainAlert", False), xrhNote="锁屏时单个 App 占比过高", height=52),
    dict(slider("占比", "bgDrainShare", 30, 20, 60, "level", 2, requires="bgDrainAlert", step=5), height=52),
])

# 低电量模式：自动开关在 SpringBoard（Tweak/LowPower.m）；保持高刷新率在 backboardd（Backboard/Tweak.x），开关由 SpringBoard 用 Darwin 通知状态值传过去
PAGES["LowPower"] = ("低电量模式", [
    group("自动开关", "锁屏时开启的低电量模式在解锁后关闭，充电时开启的在拔线后关闭；电量低于设定值时保持开启。充电时开启可减少后台活动，充电更快、温度更低；系统充到 80% 时会自动关闭。推荐低于 20% 开启、充到 80% 关闭。"),
    dict(switch("低电量时开启", "lpmBelowOn", False), xrhNote="低于设定电量时", height=52),
    dict(slider("电量", "lpmBelow", 20, 0, 100, "level", 2, requires="lpmBelowOn", step=5), height=52),
    dict(switch("充电后关闭", "lpmOffOn", False), xrhNote="充到设定电量时", height=52),
    dict(slider("电量", "lpmOffAt", 80, 0, 100, "level", 2, requires="lpmOffOn", step=5), height=52),
    dict(switch("锁屏时开启", "lpmLocked", False), xrhNote="解锁后恢复", height=52),
    dict(switch("充电时开启", "lpmCharging", False), xrhNote="拔线后恢复", height=52),
    group("显示", "低电量模式下屏幕最高刷新率保持 120Hz，其他省电措施不变；滑动时耗电略增。仅限 ProMotion 机型。"),
    dict(switch("保持高刷新率", "lpmKeepHighRefresh", False), xrhNote="低电量模式下", height=52),
])

PAGES["ChargeLimit"] = ("充电上限", [
    # 和「优化」页同一套写法：每组有组名、说明贴在组下（footer），数值用滑块（默认 = 推荐值）
    group("上限", "达到上限后停止充电，由电源直接供电；比上限低出回落值后恢复充电，避免在上限附近反复启停。推荐上限 80%、回落 5%。"),
    switch("充电上限", "chargeLimit", False),
    dict(slider("上限", "chargeLimitMax", 80, 60, 90, "level", 2, requires="chargeLimit", step=5), height=52),
    dict(slider("回落", "chargeLimitGap", 5, 3, 20, "level", 2, requires="chargeLimit", step=1), height=52),
    dict(group("插电", "可选择本次充满，拔线后恢复上限。30 天未充满时提示充满一次，用于校准电量。"), xrhRequires="chargeLimit"),
    dict(switch("插电时询问", "chargeLimitAsk", True, requires="chargeLimit"), xrhNote="上限或本次充满", height=52),
    # 定时充满（Daemon/main.m 的 XRHScheduleTick）：先停在上限，按记住的充电速度算好时间，充满时间前刚好充满
    dict(group("定时充满", "夜间先停在上限，按充电器实测速度计算开始时间，在设定时间前充满。"), xrhRequires="chargeLimit"),
    dict(switch("定时充满", "chargeSchedule", False, requires="chargeLimit"), xrhNote="设定时间前充满", height=52),
    _pref({"cell": "PSStaticTextCell", "cellClass": "XRHTimeCell", "label": "充满时间", "height": 52},
          "chargeScheduleTime", 7 * 60, False, "chargeLimit,chargeSchedule"),
    # 注意事项放在页面最底下
    group(None, "停充约 30 秒后生效，快充时提前 1% 停止。需关闭系统「优化电池充电」。关闭本功能、卸载或重启后恢复充电。"),
])

def alert(label, note, key, default, n):
    # 提醒开关：短名字 + 灰色小字的条件（xrhNote）+ 右边一列青绿色「预览」（xrhTry，XRHDecorateCell 画），行高 52 留点呼吸
    return dict(switch(label, key, default), xrhNote=note, xrhTry=n, height=52)


PAGES["Toast"] = ("提示", [
    group(),
    choice("提示样式", "toastStyle", [0, 1, 2], ["自动", "灵动岛", "横幅"], 0, short=["自动", "灵动岛", "横幅"],
           message="「自动」：有灵动岛用灵动岛，没有用横幅。\n「灵动岛」：从灵动岛左右展开，几秒后缩回去，点一下提前收起。\n「横幅」：从顶部滑下一张卡片，往上划或点一下收起。"),
    # 专注静默：点进去自己选哪几条照常弹（Focus 页）；点按跳转：同提醒开关，短名字 + 灰色小字
    dict(link("专注模式", "Focus"), xrhNote="勿扰时不弹", height=52),
    dict(switch("点击提示", "toastTapOpen", True), xrhNote="打开相关页面", height=52),
    # 灵动岛长短：两张缩略图上下排，点哪张选哪张（XRHIslandStyleCell）。0 长条（同系统充电那条，默认）/ 1 短条（2/3 屏宽）
    group("灵动岛"),
    {"cell": "PSStaticTextCell", "cellClass": "XRHIslandStyleCell", "key": "islandStyle", "default": 0,
     "defaults": DOMAIN, "PostNotification": NOTIFY, "height": 160},
    # 提醒（Tweak/Alerts.m）：开关下面不放文字描述，保持简洁；名字写类别、条件放灰色小字。分「充电」「异常」「用电」三组；
    # 名字只写类别，条件放灰色小字；「预览」排成一列在开关左边，能点，用手机此刻的数据弹一次。前 5 个默认开，「高耗电」默认关
    group("充电"),
    alert("插电", "显示充电功率", "alertPlugIn", True, 1),
    alert("到点", "充到 %d%% 提醒", "alertTarget", False, 13),
    # 到点的电量：滑块 50～100%，一格 5%（直接拖着选，不用点进列表页）；打开「到点」才出现
    dict(slider("电量", "alertTargetLevel", 90, 50, 100, "level", 2, requires="alertTarget", step=5), height=52),
    alert("停充", "到上限时", "alertLimit", True, 2),
    alert("直充", "边充边玩停充时", "alertBypass", True, 17),
    alert("充满", "充到 100% 时", "alertFull", True, 7),
    alert("总结", "拔线时显示充了多少", "alertUnplug", True, 5),
    group("异常"),
    alert("慢充", "功率低于 5 W", "alertSlow", True, 3),
    alert("降速", "过热被限速", "alertThrottle", True, 8),
    alert("接触不良", "频繁断开", "alertFlaky", True, 12),
    alert("中断", "插着电却不充", "alertStopped", True, 14),
    alert("过热", "电池 ≥ 40 ℃", "alertHot", True, 4),
    alert("低温", "充电时 < 5 ℃", "alertCold", True, 11),
    group("用电", "待机耗电、睡前、高耗电只在使用电池时判断。每周默认关闭。"),
    alert("待机耗电", "锁屏每小时 > 3%", "alertStandby", True, 9),
    alert("睡前", "22 点后电量 < 30%", "alertBedtime", True, 10),
    alert("高耗电", "功率 > 6 W", "alertDrain", False, 6),
    alert("每周", "周一 9:00 小结", "alertWeekly", False, 16),
])

def focus_allow(label, key, default=False):
    # 专注时照常弹这条：键 = focusAllow.<提醒的键>（Tweak/Alerts.m 的 XRHAlertTake 读），默认只有过热、低温照常
    return dict(switch(label, "focusAllow." + key, default, requires="toastFocusQuiet"), height=52)


PAGES["Focus"] = ("专注模式", [
    group(),
    dict(switch("专注时静默", "toastFocusQuiet", True), height=52),
    dict(group("照常提醒 · 充电"), xrhRequires="toastFocusQuiet"),
    focus_allow("插电", "alertPlugIn"), focus_allow("到点", "alertTarget"), focus_allow("停充", "alertLimit"), focus_allow("直充", "alertBypass"),
    focus_allow("充满", "alertFull"), focus_allow("总结", "alertUnplug"),
    dict(group("照常提醒 · 异常"), xrhRequires="toastFocusQuiet"),
    focus_allow("慢充", "alertSlow"), focus_allow("降速", "alertThrottle"), focus_allow("接触不良", "alertFlaky"),
    focus_allow("中断", "alertStopped"), focus_allow("过热", "alertHot", True), focus_allow("低温", "alertCold", True),
    dict(group("照常提醒 · 用电"), xrhRequires="toastFocusQuiet"),
    focus_allow("待机耗电", "alertStandby"), focus_allow("睡前", "alertBedtime"), focus_allow("高耗电", "alertDrain"),
    focus_allow("后台耗电", "bgDrainAlert"), focus_allow("每周", "alertWeekly"),
])

PAGES["About"] = ("关于", [
    # 只写验证过的，避免夸大：iOS 15、16 能装但没测过，不写"支持"
    group(None, "只在 iOS 17.3.1 上测试过。需要 roothide 越狱环境，只装了巨魔的手机用不了。打开本页时会到 GitHub 查一次有没有新版本。"),
    # 版本行：打开关于页时查 GitHub 最新 Release，有新版就显示「有新版 x.x.x」（XRHSubListController）
    dict(value("版本", VERSION), get="xrhVersionValue:", xrhVersion=True),
    value("作者", "xyrith"),
    value("适用系统", "iOS 17"),
    value("越狱环境", "roothide"),
    # 设置页语言（只影响设置页，XRHLocalize.h）：0 跟随系统 / 1 中文 / 2 English；改了马上重新加载，不用注销
    group(),
    choice("语言", "prefsLanguage", [0, 1, 2], ["跟随系统", "中文", "English"], 0, short=["跟随系统", "中文", "English"]),
    group("软件源与反馈", "软件源地址：https://oryanfang.github.io/repo/\n「复制问题信息」会复制 xrhea 版本、iOS 版本、机型和改过的设置，可以贴进反馈里。\n「重启记录」只有开机时间和系统崩溃原因，不含 App 和使用信息。"),
    button("软件源", "xrhOpenRepo"),
    button("反馈问题", "xrhOpenIssues"),
    button("复制问题信息", "xrhCopyInfo"),
    # 重启记录：xrhead 写的 restarts.plist（开机时间 + panic 原因），弹窗显示、可复制
    button("重启记录", "xrhRestarts"),
    # 捐赠：打开微信赞赏码页（XRHDonateController）；XRHRootListController.m 的 kXRHKofiURL 填了以后英文界面改成打开 Ko-fi
    dict(group(None, "xrhea 免费使用。喜欢的话可以请作者喝杯咖啡。"), xrhDonate=True),
    dict(button("捐赠", "xrhDonate"), xrhDonate=True),
    group(None, "把 xrhea 的所有设置恢复成默认值。完成后需要注销。"),
    button("重置所有设置", "xrhResetAll"),
])

# ---- 英文：中文原文 → 英文。系统语言不是中文时显示英文（XRHLocalize.h 的 XRHL / XRHLocalizeSpecifiers）
EN = {
    # 首页
    "启用 xrhea": "Enable xrhea", "电池信息": "Battery", "关于": "About", "语言": "Language", "跟随系统": "System", "中文": "中文",
    # 关于
    "只在 iOS 17.3.1 上测试过。需要 roothide 越狱环境，只装了巨魔的手机用不了。打开本页时会到 GitHub 查一次有没有新版本。":
        "Only tested on iOS 17.3.1. Requires a roothide jailbreak; it won't work with TrollStore alone. Opening this page checks GitHub once for a new version.",
    "版本": "Version", "作者": "Author", "适用系统": "Supported iOS", "越狱环境": "Jailbreak",
    "软件源与反馈": "Source & Feedback",
    "软件源地址：https://oryanfang.github.io/repo/\n「复制问题信息」会复制 xrhea 版本、iOS 版本、机型和改过的设置，可以贴进反馈里。\n「重启记录」只有开机时间和系统崩溃原因，不含 App 和使用信息。":
        "Source: https://oryanfang.github.io/repo/\n\"Copy Debug Info\" copies the xrhea and iOS versions, device model and changed settings for pasting into a report.\n\"Restart History\" only has boot times and system crash reasons, no apps or usage.",
    "重启记录": "Restart History", "开机": "Boots", "崩溃原因": "Crash reasons", "复制": "Copy",
    "还没有记录。xrhea 会在每次开机后记下开机时间，以及系统崩溃日志里的原因。": "No records yet. xrhea notes the boot time after each start, and the reason from any system crash log.",
    "没有崩溃日志": "No crash logs",
    "AOP 协处理器固件崩溃：苹果系统的已知问题，与 xrhea 无关": "AOP coprocessor firmware crash: a known Apple system issue, not caused by xrhea",
    "软件源": "Source", "反馈问题": "Report an Issue", "复制问题信息": "Copy Debug Info",
    "把 xrhea 的所有设置恢复成默认值。完成后需要注销。": "Restores every xrhea setting to its default. Respring afterwards.",
    "重置所有设置": "Reset All Settings",
    # 提示
    "提示": "Alerts",
    "提示样式": "Style", "自动": "Automatic", "灵动岛": "Dynamic Island", "横幅": "Banner",
    "预览": "Preview",
    "「自动」：有灵动岛用灵动岛，没有用横幅。\n「灵动岛」：从灵动岛左右展开，几秒后缩回去，点一下提前收起。\n「横幅」：从顶部滑下一张卡片，往上划或点一下收起。":
        "Automatic: Dynamic Island if your phone has one, otherwise a banner.\nDynamic Island: expands out of the island and shrinks back after a few seconds; tap to close early.\nBanner: a card slides down from the top; swipe up or tap to close.",
    "充电": "Charging", "电池": "Battery", "插电": "Plug-in", "停充": "Paused", "慢充": "Slow", "总结": "Summary", "过热": "Hot", "高耗电": "Drain",
    "专注模式": "Focus", "勿扰时不弹": "quiet during Focus", "点击提示": "Tap Alert", "打开相关页面": "opens the related page",
    "显示充电功率": "shows charging power", "充到 %d%% 提醒": "alert at %d%%", "到上限时": "at the limit", "充到 100% 时": "at 100%",
    "拔线时显示充了多少": "on unplug", "功率低于 5 W": "under 5 W", "过热被限速": "slowed by heat", "接触不良": "Loose Cable",
    "频繁断开": "drops often", "插着电却不充": "not charging", "电池 ≥ 40 ℃": "battery ≥ 40 °C",
    "充电时 < 5 ℃": "charging below 5 °C", "待机耗电": "Standby Drain", "锁屏每小时 > 3%": "> 3%/h locked",
    "22 点后电量 < 30%": "< 30% after 10 PM", "功率 > 6 W": "above 6 W", "专注时静默": "Silence During Focus",
    "照常提醒 · 充电": "Still Alert · Charging", "照常提醒 · 异常": "Still Alert · Issues", "照常提醒 · 用电": "Still Alert · Usage",
    "灵动岛": "Dynamic Island", "长条": "Long", "短条": "Short", "正在充电": "Charging", "约40分钟": "~40 min", "点按跳转": "Tap to Open", "打开电池信息": "battery details",
    "中断": "Stopped", "捐赠": "Donate", "截屏后打开微信 › 扫一扫 › 相册，选这张截图。": "Take a screenshot, then in WeChat tap Scan › Album and choose it. WeChat accepts Visa and Mastercard.", "打开微信": "Open WeChat", "xrhea 免费使用。喜欢的话可以请作者喝杯咖啡。": "xrhea is free. If you like it, you can buy the author a coffee.", "边充边玩停充时": "under load", "插着却不充": "plugged, not charging",
    "待机耗电、睡前、高耗电只在使用电池时判断。每周默认关闭。": "Standby, Bedtime and High Drain only apply on battery. Weekly is off by default.",
    "%@ 开始充，%@ 前充满": "Charging from %@, full by %@", "定时充满": "Scheduled Full Charge", "设定时间前充满": "full by the set time", "开始时间按充电器实测速度计算。": "The start time is based on the measured speed of the charger.", "充满时间": "Full By",
    "到点": "Target", "充到 %d%%": "at %d%%", "电量": "Level", "异常": "Issues", "用电": "Usage",
    "接触": "Loose", "1 分钟断开 ≥ 3 次": "≥ 3 drops / min", "低温": "Cold", "充电 < 5 ℃": "charging < 5 °C",
    "睡前": "Bedtime", "22 点后 < 30%": "< 30% after 10 PM",
    "充满": "Full", "降速": "Throttled", "待机": "Standby", "未开上限": "no limit", "过热限流": "heat-limited", "锁屏 > 3%/h": "locked > 3%/h",
    "功率 · 时长": "power · ETA", "到达上限": "at limit", "拔线充入量": "added on unplug", "≥ 40 ℃": "≥ 40 °C",
    # 优化
    "优化": "Optimization", "高温保护": "Heat Protection", "充电时": "while charging", "温度": "Temperature",
    "处理方式": "Action", "停充": "Stop Charging", "间歇充电": "Intermittent Charging",
    "停充：达到温度后停止充电。间歇充电：停 3 分钟、充 3 分钟交替，平均电流约减半。低于设定温度 3℃ 后恢复。推荐 40℃。":
        "Stop Charging: charging stops at the set temperature. Intermittent Charging: alternates 3 minutes off and 3 minutes on, roughly halving the average current. Resumes 3 °C below the set temperature. Recommended: 40 °C.",
    "低电量模式": "Low Power Mode", "自动开关": "Automation", "显示": "Display",
    "保持高刷新率": "Keep High Refresh Rate", "低于设定电量时": "below the set level", "充到设定电量时": "at the set level", "低电量模式下": "in Low Power Mode",
    "低电量模式下屏幕最高刷新率保持 120Hz，其他省电措施不变；滑动时耗电略增。仅限 ProMotion 机型。":
        "Keeps the display's maximum refresh rate at 120 Hz in Low Power Mode; other power savings stay on. Scrolling uses slightly more power. ProMotion models only.", "低电量时开启": "Turn On When Low", "充电后关闭": "Turn Off When Charged", "电量": "Level",
    "关闭": "Off", "锁屏时开启": "Turn On When Locked", "解锁后恢复": "restored on unlock",
    "锁屏时开启的低电量模式在解锁后关闭；电量低于设定值时保持开启。推荐低于 20% 开启、充到 80% 关闭。":
        "Low Power Mode turned on at lock turns off on unlock; it stays on if the battery is below the set level. Recommended: on below 20%, off at 80%.",
    "高温保护中": "Heat Protection", "38℃": "38 °C", "40℃": "40 °C", "42℃": "42 °C", "45℃": "45 °C",
    # 充电上限
    "插上电源时询问": "Ask When Plugged In",
    "插电时可选择本次充满，拔线后恢复上限。30 天未充满时提示充满一次，用于校准电量。":
        "Choose a one-time full charge when plugging in; the limit returns after unplugging. If not fully charged for 30 days, a full charge is suggested to calibrate the battery reading.",
    '已到上限 %d%%': 'At Limit (%d%%)',
    '已到上限': 'At Limit',
    '约 %@ 到 %d%%': '%@ to %d%%',
    "充电上限": "Charge Limit",
    "达到上限后停止充电，由电源直接供电；低于恢复线时恢复充电。":
        "Charging stops at the limit and the charger powers the phone directly. Charging resumes below the resume level.",
    "启用充电上限": "Enable Charge Limit", "上限": "Limit", "掉到多少再充": "Resume At",
    "−3%": "−3%", "−5%": "−5%", "−10%": "−10%", "−20%": "−20%",
    "上限 − 3%": "Limit − 3%", "上限 − 5%": "Limit − 5%", "上限 − 10%": "Limit − 10%", "上限 − 20%": "Limit − 20%",
    "比如上限 80%、选「上限 − 5%」：充到 80% 停，用到 75% 以下再插着线时才重新充。":
        "E.g. with an 80% limit and \"Limit − 5%\", charging stops at 80% and starts again once it's below 75% while plugged in.",
    "停充约 30 秒后生效，快充时提前 1% 停止。需关闭系统「优化电池充电」。关闭本功能、卸载或重启后恢复充电。":
        "Stopping takes effect after about 30 seconds; fast charging stops 1% early. Turn off the system’s Optimized Battery Charging. Turning this off, uninstalling or restarting resumes charging.",
    # 电池信息详情页（XRHBatteryController.m）
    "最大容量（相对新电池）": "Maximum Capacity (relative to new)", "容量": "Capacity",
    "实际容量": "Full Charge Capacity", "设计容量": "Design Capacity", "当前电量": "Current Charge",
    "实际容量是现在充满时能装多少电；最大容量 = 实际容量 ÷ 设计容量。":
        "Full charge capacity is how much the battery holds when fully charged now. Maximum capacity = full charge ÷ design capacity.",
    "使用": "Usage", "循环次数": "Cycle Count", "%.0f 次": "%.0f",
    # 异常提醒（⚠️）
    '按现在的速度，约 %@ 用完。': 'At this rate, about %@ left.',
    '现在耗电比平时快很多。': 'The battery is draining much faster than usual.',
    '耗电很快': 'Draining Fast',
    '\n• 退出不用的 App，尤其是游戏和导航\n• 调低屏幕亮度\n• 打开低电量模式': "\n• Close apps you're not using, especially games and navigation\n• Lower the screen brightness\n• Turn on Low Power Mode",
    '最大容量低于 80%': 'Maximum Capacity Below 80%',
    '电池已经明显老化，续航会变短。\n• 可以考虑换电池\n• 常插着线的话，打开「设置 › 电池 › 充电」里的 80% 上限，能延缓老化': "The battery is noticeably worn and battery life will be shorter.\n• Consider replacing the battery\n• If you're often plugged in, turn on the 80% Limit in Settings › Battery › Charging to slow further wear",
    '电池过热': 'Battery Too Hot',
    '电池偏热': 'Battery Running Warm',
    '• 拔掉充电线\n• 退出游戏等耗电大的 App\n• 取下手机壳，放在阴凉处': '• Unplug the charger\n• Close games and other demanding apps\n• Take off the case and keep it somewhere cool',
    '不支持快充': 'No Fast Charging',
    '充电器和手机只谈到了 5 V，线或充电头不支持快充。\n• 换成支持 USB-C PD 快充的线和充电头': "The charger and phone only agreed on 5 V, so the cable or charger doesn't support fast charging.\n• Use a cable and charger that support USB-C PD fast charging",
    '充电太慢': 'Charging Slowly',
    '插着充电器，功率却一直低于 5 W。\n• 换一根线或换个充电头试试\n• 手机太热时也会自动降速': "Plugged in, but power has stayed under 5 W.\n• Try a different cable or charger\n• The phone also slows charging when it's hot", "这些数字怎么看": "Understanding These Numbers",
    '实时': 'Live',
    '充电预计已经算上了 80% 以后会变慢；用完预计按你此刻的用法算，换个用法就会变。': 'The charging estimate accounts for charging slowing down after 80%. Time left assumes you keep using the phone the way you are right now.',
    '功率': 'Power',
    '温度': 'Temperature',
    '状态': 'Status',
    '电量': 'Level',
    '电压': 'Voltage',
    '电流': 'Current',
    '预计': 'Estimate',
    '充电器': 'Charger',
    '型号是充电器自己报上来的名字（苹果的内部写法）。': "The model is the name the charger reports (Apple's internal naming).",
    '最大功率': 'Max Power',
    '规格': 'Output',
    '型号': 'Model',
    '使用电池': 'On Battery',
    '已充满': 'Fully Charged',
    '充电中': 'Charging',
    '已接电源，暂停充电': 'Plugged In, Not Charging',
    '%ld 分': '%ld min', '%ld 小时': '%ld h',
    '%ld 小时 %ld 分': '%ld h %ld min',
    '约 %@ 充满': 'Full in about %@',
    '约 %@ 用完': 'About %@ left',
    '无线': 'Wireless',
    # 代码里的文字（Prefs/*.m）
    "需注销": "Respring", "注销": "Respring", "确定要注销（重启 SpringBoard）吗？": "Respring (restart SpringBoard) now?",
    "取消": "Cancel", "有新版 %@": "Update %@", "在 Sileo 中添加": "Add in Sileo", "复制地址": "Copy URL",
    "已复制": "Copied", "好": "OK", "重置": "Reset", "xrhea 的所有设置都会恢复默认。确定吗？": "All xrhea settings will be restored to defaults. Continue?",
    "已重置": "Reset Done", "有些设置要注销后才会完全恢复，现在注销吗？": "Some settings only fully reset after a respring. Respring now?",
    "稍后": "Later",
    # 日志（XRHLogController.m）
    "日志": "Log", "充电记录": "Charging History", "全部记录": "All Records", "暂无记录": "No Records Yet",
    "记录只保存在本机，保留 30 天。": "Records stay on this iPhone for 30 days.",
    "速度为 80% 前每分钟充入的电量，点按可改名。": "Speed is the charge added per minute below 80%. Tap to rename.",
    "今天": "Today", "昨天": "Yesterday", "%ld 天前": "%ld days ago", "上次 %@": "Last %@", "%ld 次": "%ld times", "%@ 起": "Since %@",
    "%@ 充电头": "%@ Charger", "%@ 无线": "%@ Wireless", "未知充电器": "Unknown Charger", "有线": "Wired", "%.1f%%/分": "%.1f%%/min",
    "时长": "Duration", "充入": "Added", "平均功率": "Average Power", "最高功率": "Peak Power", "最高温度": "Peak Temperature",
    "本次": "This Charge", "结束方式": "Ended By", "拔线": "Unplugged", "到上限停充": "Stopped at Limit", "开启": "On",
    "电量 · 24 小时": "Battery Level · 24 Hours", "现在": "Now", "锁屏掉电快": "Fast Drain While Locked", "数据收集中": "Collecting Data",
    # 耗电排查（XRHLogController.m）
    "耗电排查": "Battery Drain", "耗电排行": "Usage by App", "锁屏待机": "Standby", "最近 24 小时平均": "Average over the last 24 hours", "%.1f%%/时": "%.1f%%/h", "锁屏时最多：%@": "Most while locked: %@", "最多：%@": "Most: %@", "锁屏时 · 最近 24 小时": "While Locked · Last 24 Hours", "全部 · 最近 24 小时": "All · Last 24 Hours", "只算屏幕关闭超过八成的整小时，共 %ld 小时。": "Counts only hours with the screen off over 80% of the time (%ld h).", "数据来自系统电池记录，按小时汇总，约晚 1 小时。": "From the system battery log, summed per hour, about an hour behind.", "最近 24 小时没有整小时锁屏": "No fully locked hours in the last 24 hours", "暂无数据": "No Data", "显示全部": "Show All", "系统": "System", "推送服务": "Push Notifications", "定位服务": "Location Services", "蓝牙": "Bluetooth", "音频": "Audio", "个人热点": "Personal Hotspot", "锁定屏幕": "Lock Screen", "主屏幕": "Home Screen", "显示与触控": "Display & Touch", "系统内核": "System Kernel", "蜂窝网络": "Cellular", "无线局域网": "Wi-Fi", "后台下载": "Background Downloads", "iCloud 同步": "iCloud Sync", "iCloud 备份": "iCloud Backup", "网络服务": "Network Services", "隔空投送与共享": "AirDrop & Sharing", "小组件": "Widgets", "媒体处理": "Media Processing", "网页 App": "Web Apps", "通话": "Calls", "Safari 网页视图": "Safari View",
    # 优化（直充、后台耗电、状态行）
    "停充：达到温度后停止充电。间歇充电：停 3 分钟、充 3 分钟交替，平均电流约减半。低于设定温度 3℃ 后恢复。无线充电发热更多，按单独的温度提前保护。推荐有线 40℃、无线 37℃。": "Stop Charging: stops once the temperature is reached. Intermittent Charging: alternates 3 minutes off and 3 minutes on, roughly halving the average current. Resumes 3 °C below the set temperature. Wireless charging runs hotter, so it uses its own, lower temperature. Recommended: 40 °C wired, 37 °C wireless.",
    "充电保护": "Charging Protection",
    "充电时开启": "Turn On While Charging",
    "功耗": "Power",
    "占比": "Share",
    "后台": "Background",
    "后台耗电提醒": "Background Drain Alert",
    "拔线后恢复": "restored on unplug",
    "整机功耗 1 分钟平均高于设定值时停止给电池充电，由电源直接供电；低于设定值 1 W 后恢复。电量低于 20% 时不直充。推荐 4 W。": "When the phone's 1-minute average power draw is above the set value, the battery stops charging and the charger powers the phone directly. Charging resumes 1 W below the set value. Not used below 20%. Recommended: 4 W.",
    "每小时查看一次系统电池记录；连续 3 个锁屏小时超过设定占比时提醒，同一个 App 每天最多一次。推荐 30%。": "Checks the system battery log every hour and alerts when one app exceeds the set share for 3 locked hours in a row; at most once a day per app. Recommended: 30%.",
    "直充": "Bypass Charging",
    "边充边玩直充": "Bypass While Gaming",
    "锁屏时单个 App 占比过高": "one app uses too much while locked",
    "锁屏时开启的低电量模式在解锁后关闭，充电时开启的在拔线后关闭；电量低于设定值时保持开启。充电时开启可减少后台活动，充电更快、温度更低；系统充到 80% 时会自动关闭。推荐低于 20% 开启、充到 80% 关闭。": "Low Power Mode turned on when locked turns off on unlock; turned on while charging, it turns off on unplug. It stays on below the set level. On while charging, background activity drops, so charging is faster and cooler; the system turns it off at 80%. Recommended: on below 20%, off at 80%.",
    "高负载时": "under heavy load",
    "直充中": "Bypassing",
    "未触发": "Inactive",
    "未开启": "Off",
    # 充电上限页（滑块版）
    "达到上限后停止充电，由电源直接供电；比上限低出回落值后恢复充电，避免在上限附近反复启停。推荐上限 80%、回落 5%。": "Charging stops at the limit and the charger powers the phone directly. It resumes once the level drops below the limit by the margin, so it doesn't start and stop around the limit. Recommended: 80% limit, 5% margin.",
    "回落": "Margin",
    "插电时询问": "Ask When Plugged In",
    "上限或本次充满": "limit or full this time",
    "可选择本次充满，拔线后恢复上限。30 天未充满时提示充满一次，用于校准电量。": "Choose to charge fully this time; the limit returns after unplugging. If it hasn't reached 100% in 30 days, you'll be reminded to charge fully once to calibrate.",
    "夜间先停在上限，按充电器实测速度计算开始时间，在设定时间前充满。": "Holds at the limit overnight, then starts in time to be full by the set time, based on the charger's measured speed.",
    "导出": "Export", "导出失败": "Export Failed",
    # 推送重连、每周小结
    "后台耗电": "Background",
    "周一 9:00 小结": "Monday 9:00 summary",
    "每周": "Weekly",
    "推送重连": "Push Reconnects",
    "网络唤醒": "Network Wakes",
    "最近 24 小时": "Last 24 hours",
    "最近 24 小时 · 最多 %ld 次/时": "Last 24 hours · up to %ld/h",
    "┄ %d 次/时": "┄ %d/h",
    "可能的原因": "Possible Causes",
    "代理或 VPN 断开推送长连接": "A proxy or VPN drops the push connection",
    "把 push.apple.com、17.0.0.0/8 设为直连": "Route push.apple.com and 17.0.0.0/8 directly",
    "网络信号差、频繁切换": "Poor signal or frequent network switching",
    "换个网络对比，或开飞行模式再关": "Compare on another network, or toggle Airplane Mode",
    "连续 3 小时超过每小时 15 次，偏多。": "Over 15 per hour for 3 hours in a row: high.",
    "在正常范围内。": "Within the normal range.",
    "平时每小时 5～10 次。每次重连都会唤醒手机并用网络重新握手，蜂窝网络下更耗电。": "Normally 5–10 per hour. Each reconnect wakes the phone and redoes the network handshake, which costs more on cellular.",
    "推送重连连续 3 小时超过每小时 15 次时标 ⚠️。": "Push reconnects are marked ⚠️ when over 15 per hour for 3 hours in a row.",
    "已触发": "Triggered", "有": "Yes", "无": "None", "改名": "Rename", "留空恢复默认名字。": "Leave empty to use the default name.",
}
CODE_STRINGS = ["推送重连", "网络唤醒", "最近 24 小时", "最近 24 小时 · 最多 %ld 次/时", "┄ %d 次/时", "可能的原因", "代理或 VPN 断开推送长连接", "把 push.apple.com、17.0.0.0/8 设为直连", "网络信号差、频繁切换", "换个网络对比，或开飞行模式再关", "连续 3 小时超过每小时 15 次，偏多。", "在正常范围内。", "平时每小时 5～10 次。每次重连都会唤醒手机并用网络重新握手，蜂窝网络下更耗电。", "推送重连连续 3 小时超过每小时 15 次时标 ⚠️。", "导出", "导出失败", "直充中", "未触发", "未开启", "高温保护中", "高温保护", "停充", "间歇充电", "耗电排查", "耗电排行", "锁屏待机", "最近 24 小时平均", "%.1f%%/时", "锁屏时最多：%@", "最多：%@", "锁屏时 · 最近 24 小时", "全部 · 最近 24 小时", "只算屏幕关闭超过八成的整小时，共 %ld 小时。", "数据来自系统电池记录，按小时汇总，约晚 1 小时。", "最近 24 小时没有整小时锁屏", "暂无数据", "显示全部", "系统", "推送服务", "定位服务", "蓝牙", "音频", "个人热点", "锁定屏幕", "主屏幕", "显示与触控", "系统内核", "蜂窝网络", "无线局域网", "后台下载", "iCloud 同步", "iCloud 备份", "网络服务", "隔空投送与共享", "小组件", "媒体处理", "网页 App", "通话", "Safari 网页视图", "电量 · 24 小时", "现在", "锁屏掉电快", "数据收集中", "充电", "日志", "充电记录", "全部记录", "暂无记录", "记录只保存在本机，保留 30 天。", "速度为 80% 前每分钟充入的电量，点按可改名。",
                "今天", "昨天", "%ld 天前", "上次 %@", "%ld 次", "%@ 起", "%@ 充电头", "%@ 无线", "未知充电器", "有线", "%.1f%%/分",
                "时长", "充入", "平均功率", "最高功率", "最高温度", "本次", "结束方式", "拔线", "到上限停充", "开启", "已触发", "有", "无",
                "改名", "留空恢复默认名字。", "充满", "降速", "定时充满", "高温保护", "充电器", "电量", "功率", "状态", "无线", "正在充电",
                "%ld 分", "%ld 小时", "%ld 小时 %ld 分", "取消", "好",
"%@ 开始充，%@ 前充满", "长条", "短条", "正在充电", "约40分钟", "预览", "截屏后打开微信 › 扫一扫 › 相册，选这张截图。", "打开微信", "需注销", "注销", "确定要注销（重启 SpringBoard）吗？", "取消", "有新版 %@", "在 Sileo 中添加", "复制地址",
                "已复制", "好", "重置", "xrhea 的所有设置都会恢复默认。确定吗？", "已重置",
                "重启记录", "开机", "崩溃原因", "复制", "没有崩溃日志", "AOP 协处理器固件崩溃：苹果系统的已知问题，与 xrhea 无关", "还没有记录。xrhea 会在每次开机后记下开机时间，以及系统崩溃日志里的原因。",
                "有些设置要注销后才会完全恢复，现在注销吗？", "稍后", "重置所有设置", "软件源",
                # XRHBatteryController.m
                "电池信息", "最大容量（相对新电池）", "容量", "实际容量", "设计容量", "当前电量",
                "实际容量是现在充满时能装多少电；最大容量 = 实际容量 ÷ 设计容量。", "使用", "循环次数", "%.0f 次", "这些数字怎么看",
                '已到上限 %d%%', '已到上限', '约 %@ 到 %d%%',
                '按现在的速度，约 %@ 用完。', '现在耗电比平时快很多。', '耗电很快', '\n• 退出不用的 App，尤其是游戏和导航\n• 调低屏幕亮度\n• 打开低电量模式',
                '最大容量低于 80%', '电池已经明显老化，续航会变短。\n• 可以考虑换电池\n• 常插着线的话，打开「设置 › 电池 › 充电」里的 80% 上限，能延缓老化', '电池过热', '电池偏热', '• 拔掉充电线\n• 退出游戏等耗电大的 App\n• 取下手机壳，放在阴凉处', '不支持快充', '充电器和手机只谈到了 5 V，线或充电头不支持快充。\n• 换成支持 USB-C PD 快充的线和充电头', '充电太慢', '插着充电器，功率却一直低于 5 W。\n• 换一根线或换个充电头试试\n• 手机太热时也会自动降速',
                '实时', '充电预计已经算上了 80% 以后会变慢；用完预计按你此刻的用法算，换个用法就会变。', '功率', '温度', '状态', '电量', '电压', '电流', '预计', '充电器', '型号是充电器自己报上来的名字（苹果的内部写法）。', '最大功率', '规格', '型号', '使用电池', '已充满', '充电中', '已接电源，暂停充电', '%ld 分', '%ld 小时', '%ld 小时 %ld 分', '约 %@ 充满', '约 %@ 用完', '无线']


def page_strings(title, items):
    out = [title]
    for it in items:
        for k in ("label", "footerText", "staticTextMessage", "xrhNote"):
            if it.get(k): out.append(it[k])
        for k in ("validTitles", "shortTitles"):
            out += it.get(k, [])
    return out


needed = set(CODE_STRINGS)
for title, items in PAGES.values():
    needed.update(t for t in page_strings(title, items) if any(ord(c) > 127 for c in t))   # 纯英文 / 数字不用翻
missing = sorted(t for t in needed if t not in EN)
assert not missing, "这些文字还没有英文：\n" + "\n".join(missing)
for lang, table in (("en", EN), ("zh-Hans", {})):   # 中文用原文（空表 = 查不到就用原文）
    d = os.path.join(OUT, lang + ".lproj")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "Localizable.strings"), "wb") as f:
        plistlib.dump({k: table[k] for k in sorted(needed)} if table else {}, f, sort_keys=True)

for name, (title, items) in PAGES.items():
    with open(os.path.join(OUT, name + ".plist"), "wb") as f:
        plistlib.dump({"title": title, "items": items}, f, sort_keys=True)
    print(f"{name}.plist  {len(items)} 项")

# ---- 「这些数字怎么看」指南页（XRHGuideController 读 Guide.plist），改文字改这里。
# 每组：(组名中文, 组名英文, [(标题中文, 标题英文, 正文中文, 正文英文)])；标题可以是 None（只有正文的一条）
# 写法：每条一两句、直接说结论
GUIDE = [
    ("健康", "Health", [
        ("最大容量", "Maximum Capacity",
         "和新电池比还剩多少。低于 80% 续航会明显变短，可以考虑换电池。和系统「电池健康」可能差 1～2%。",
         "How much charge it holds compared with new. Below 80%, battery life gets noticeably shorter; consider a replacement. May differ from Battery Health by 1–2%."),
        ("循环次数", "Cycle Count",
         "累计用完 100% 电量算一次。iPhone 15 系列约 1000 次后还剩 80%，更早的机型约 500 次。",
         "Every 100% of charge used adds up to one cycle. iPhone 15 models keep about 80% after roughly 1000 cycles; earlier models after about 500."),
        ("三个容量", "The Three Capacities",
         "设计容量：出厂标称。实际容量：现在充满能装多少。当前电量：此刻还剩多少。",
         "Design: rated from the factory. Full charge: how much it holds when full now. Current: how much is in it right now."),
    ]),
    ("实时", "Live", [
        ("功率", "Power",
         "充电时是充电头送进手机的功率，和数显线对得上，越大充得越快。不充电时是手机的耗电速度：待机不到 1 W，玩游戏 5 W 以上。",
         "While charging, it's what the charger sends into the phone (matches a USB power meter); higher means faster. Otherwise it's how fast the phone uses power: under 1 W on standby, 5 W or more in games."),
        ("电流", "Current",
         "正数在充电，负数在耗电。",
         "Positive means charging, negative means draining."),
        ("电压", "Voltage",
         "一般 3.5～4.4 V，越满越高，不用太在意。",
         "Usually 3.5–4.4 V, higher when fuller. Nothing to worry about."),
        ("温度", "Temperature",
         "• 30 ℃ 以下：舒服\n• 30～40 ℃：充电、游戏时常见\n• 40 ℃ 以上（橙）：偏热，系统会放慢充电\n• 45 ℃ 以上（红）：拔线歇一会儿",
         "• Below 30 °C: comfortable\n• 30–40 °C: common while charging or gaming\n• Above 40 °C (orange): warm; charging slows down\n• Above 45 °C (red): unplug and let it rest"),
        ("已接电源，暂停充电", "Plugged In, Not Charging",
         "多半是优化充电或 80% 上限让它停在 80%，不是故障。太热时也会暂停。",
         "Usually Optimized Charging or the 80% Limit holding it at 80%. Not a fault. It also pauses when too hot."),
        ("预计", "Estimate",
         "充电：已经算上 80% 以后会变慢，比直接按现在的速度算准得多。用完：只按你此刻的用法算，打开游戏就会变短。都是大概，取整到 5～10 分钟。",
         "Charging: accounts for slowing down after 80%, so it's far more realistic than using the current rate. Time left: assumes you keep using the phone as you are now; open a game and it drops. Both are rough, rounded to 5–10 minutes."),
    ]),
    ("充电器", "Charger", [
        ("最大功率", "Max Power",
         "充电器能给的上限。实际功率比它低很正常。",
         "The most the charger can deliver. Actual power being lower is normal."),
        ("规格", "Output",
         "比如 9 V · 3 A = 27 W。只有 5 V 的话，多半是线或头不支持快充。",
         "e.g. 9 V · 3 A = 27 W. If it only shows 5 V, the cable or charger probably doesn't support fast charging."),
        ("型号", "Model",
         "充电器自己报的名字，第三方充电器可能没有。",
         "The name the charger reports. Third-party chargers may not have one."),
    ]),
    ("养电池", "Battery Care", [
        (None, None,
         "• 别在高温下充电，别边充边玩游戏\n• 常插着线的话，打开优化充电或 80% 上限\n• 随用随充，不用等用光\n• 长期不用，放在 50% 左右保存",
         "• Don't charge in the heat or game while charging\n• Often plugged in? Turn on Optimized Charging or the 80% Limit\n• Top up whenever; no need to run it flat\n• Storing it for a while? Leave it around 50%"),
    ]),
]


def guide_lang(i):
    return [{"title": sec[i], "items": [{"title": it[i] or "", "body": it[2 + i]} for it in sec[2]]} for sec in GUIDE]


with open(os.path.join(OUT, "Guide.plist"), "wb") as f:
    plistlib.dump({"zh": guide_lang(0), "en": guide_lang(1)}, f, sort_keys=True)
print(f"Guide.plist  {len(GUIDE)} 组")
