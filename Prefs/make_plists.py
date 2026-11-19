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
    # 充电上限：图标是代码画的（XRHRootListController，xrhSymbol + xrhSymbolColor）
    dict(link("充电上限", "ChargeLimit"), xrhSymbol="bolt.shield.fill", xrhSymbolColor="teal"),
    dict(link("提示", "Toast"), xrhSymbol="bell.badge.fill", xrhSymbolColor="red"),
    # 以后的功能区（提醒等）每个一个子页面，加在这里
    group(),
    switch("启用 xrhea", "enabled", True, respring=True),
    group(),
    # 关于的图标用 xrhea 自己的图标（About.png 由 tools/make_logo.swift 导出）
    link("关于", "About", "About.png"),
    # 注销在导航栏右上角（XRHRootListController -viewDidLoad）
])

PAGES["ChargeLimit"] = ("充电上限", [
    group(None, "到上限就停止充电，插着线时电源直接给手机供电，电池不充也不放。掉到恢复线以下才重新充，不会在上限附近反复启停。"),
    switch("启用充电上限", "chargeLimit", False),
    choice("上限", "chargeLimitMax", [60, 70, 75, 80, 85, 90], ["60%", "70%", "75%", "80%", "85%", "90%"], 80,
           requires="chargeLimit"),
    choice("掉到多少再充", "chargeLimitGap", [3, 5, 10, 20], ["上限 − 3%", "上限 − 5%", "上限 − 10%", "上限 − 20%"], 5,
           short=["−3%", "−5%", "−10%", "−20%"], requires="chargeLimit",
           message="比如上限 80%、选「上限 − 5%」：充到 80% 停，用到 75% 以下再插着线时才重新充。"),
    switch("插上电源时询问", "chargeLimitAsk", True, requires="chargeLimit"),
    group(None, "插上电源时弹窗问「确认」还是「这次充满」，外出前想充满就点「这次充满」，拔线后自动恢复上限。"
                "超过 30 天没充满过时，这个弹窗会提醒你充满一次（关掉询问也会提醒），让电量统计保持准确。"),
    group(None, "停充要等 30 秒左右才生效，为了不超过上限，充得快时会提前一点停，可能停在上限少 1%。"
                "请关掉系统「设置 › 电池 › 充电」里的优化充电，它和 xrhea 用的是同一个开关，会互相打架。"
                "关掉这里或卸载 xrhea 会马上恢复充电；重启手机也会恢复默认。"),
])

def alert(label, note, key, default, n):
    # 提醒开关：短名字 + 灰色小字的条件（xrhNote）+ 右边一列青绿色「试试看」（xrhTry，XRHDecorateCell 画），行高 52 留点呼吸
    return dict(switch(label, key, default), xrhNote=note, xrhTry=n, height=52)


PAGES["Toast"] = ("提示", [
    group(),
    choice("提示样式", "toastStyle", [0, 1, 2], ["自动", "灵动岛", "横幅"], 0, short=["自动", "灵动岛", "横幅"],
           message="「自动」：有灵动岛用灵动岛，没有用横幅。\n「灵动岛」：从灵动岛左右展开，几秒后缩回去，点一下提前收起。\n「横幅」：从顶部滑下一张卡片，往上划或点一下收起。"),
    # 专注静默：点进去自己选哪几条照常弹（Focus 页）；点按跳转：同提醒开关，短名字 + 灰色小字
    dict(link("专注模式", "Focus"), xrhNote="勿扰时不弹", height=52),
    dict(switch("点击提示", "toastTapOpen", True), xrhNote="打开电池详情", height=52),
    # 灵动岛长短：两张缩略图上下排，点哪张选哪张（XRHIslandStyleCell）。0 长条（同系统充电那条，默认）/ 1 短条（2/3 屏宽）
    group("灵动岛"),
    {"cell": "PSStaticTextCell", "cellClass": "XRHIslandStyleCell", "key": "islandStyle", "default": 0,
     "defaults": DOMAIN, "PostNotification": NOTIFY, "height": 160},
    # 提醒（Tweak/Alerts.m）：开关下面不放文字描述，保持简洁；名字写类别、条件放灰色小字。分「充电」「异常」「用电」三组；
    # 名字只写类别，条件放灰色小字；「试试看」排成一列在开关左边，能点，用手机此刻的数据弹一次。前 5 个默认开，「高耗电」默认关
    group("充电"),
    alert("插电", "显示充电功率", "alertPlugIn", True, 1),
    alert("到点", "充到 %d%% 提醒", "alertTarget", False, 13),
    # 到点的电量：滑块 50～100%，一格 5%（直接拖着选，不用点进列表页）；打开「到点」才出现
    dict(slider("电量", "alertTargetLevel", 90, 50, 100, "level", 2, requires="alertTarget", step=5), height=52),
    alert("停充", "到上限时", "alertLimit", True, 2),
    alert("充满", "充到 100% 时", "alertFull", True, 7),
    alert("总结", "拔线时显示充了多少", "alertUnplug", True, 5),
    group("异常"),
    alert("慢充", "功率低于 5 W", "alertSlow", True, 3),
    alert("降速", "过热被限速", "alertThrottle", True, 8),
    alert("接触不良", "频繁断开", "alertFlaky", True, 12),
    alert("中断", "插着电却不充", "alertStopped", True, 14),
    alert("过热", "电池 ≥ 40 ℃", "alertHot", True, 4),
    alert("低温", "充电时 < 5 ℃", "alertCold", True, 11),
    group("用电", "不要为了热闹而点亮每一个开关。"),
    alert("待机耗电", "锁屏每小时 > 3%", "alertStandby", True, 9),
    alert("睡前", "22 点后电量 < 30%", "alertBedtime", True, 10),
    alert("高耗电", "功率 > 6 W", "alertDrain", False, 6),
])

def focus_allow(label, key, default=False):
    # 专注时照常弹这条：键 = focusAllow.<提醒的键>（Tweak/Alerts.m 的 XRHAlertTake 读），默认只有过热、低温照常
    return dict(switch(label, "focusAllow." + key, default, requires="toastFocusQuiet"), height=52)


PAGES["Focus"] = ("专注模式", [
    group(),
    dict(switch("专注时静默", "toastFocusQuiet", True), height=52),
    dict(group("照常提醒 · 充电"), xrhRequires="toastFocusQuiet"),
    focus_allow("插电", "alertPlugIn"), focus_allow("到点", "alertTarget"), focus_allow("停充", "alertLimit"),
    focus_allow("充满", "alertFull"), focus_allow("总结", "alertUnplug"),
    dict(group("照常提醒 · 异常"), xrhRequires="toastFocusQuiet"),
    focus_allow("慢充", "alertSlow"), focus_allow("降速", "alertThrottle"), focus_allow("接触不良", "alertFlaky"),
    focus_allow("中断", "alertStopped"), focus_allow("过热", "alertHot", True), focus_allow("低温", "alertCold", True),
    dict(group("照常提醒 · 用电"), xrhRequires="toastFocusQuiet"),
    focus_allow("待机耗电", "alertStandby"), focus_allow("睡前", "alertBedtime"), focus_allow("高耗电", "alertDrain"),
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
    group("软件源与反馈", "软件源地址：https://oryanfang.github.io/repo/\n「复制问题信息」会复制 xrhea 版本、iOS 版本、机型和改过的设置，可以贴进反馈里。"),
    button("软件源", "xrhOpenRepo"),
    button("反馈问题", "xrhOpenIssues"),
    button("复制问题信息", "xrhCopyInfo"),
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
    "软件源地址：https://oryanfang.github.io/repo/\n「复制问题信息」会复制 xrhea 版本、iOS 版本、机型和改过的设置，可以贴进反馈里。":
        "Source: https://oryanfang.github.io/repo/\n\"Copy Debug Info\" copies the xrhea and iOS versions, device model and changed settings for pasting into a report.",
    "软件源": "Source", "反馈问题": "Report an Issue", "复制问题信息": "Copy Debug Info",
    "把 xrhea 的所有设置恢复成默认值。完成后需要注销。": "Restores every xrhea setting to its default. Respring afterwards.",
    "重置所有设置": "Reset All Settings",
    # 提示
    "提示": "Alerts",
    "提示样式": "Style", "自动": "Automatic", "灵动岛": "Dynamic Island", "横幅": "Banner",
    "试试看": "Try It",
    "「自动」：有灵动岛用灵动岛，没有用横幅。\n「灵动岛」：从灵动岛左右展开，几秒后缩回去，点一下提前收起。\n「横幅」：从顶部滑下一张卡片，往上划或点一下收起。":
        "Automatic: Dynamic Island if your phone has one, otherwise a banner.\nDynamic Island: expands out of the island and shrinks back after a few seconds; tap to close early.\nBanner: a card slides down from the top; swipe up or tap to close.",
    "充电": "Charging", "电池": "Battery", "插电": "Plug-in", "停充": "Paused", "慢充": "Slow", "总结": "Summary", "过热": "Hot", "高耗电": "Drain",
    "专注模式": "Focus", "勿扰时不弹": "quiet during Focus", "点击提示": "Tap Alert", "打开电池详情": "opens battery details",
    "显示充电功率": "shows charging power", "充到 %d%% 提醒": "alert at %d%%", "到上限时": "at the limit", "充到 100% 时": "at 100%",
    "拔线时显示充了多少": "shows how much was added", "功率低于 5 W": "under 5 W", "过热被限速": "slowed by heat", "接触不良": "Loose Cable",
    "频繁断开": "keeps disconnecting", "插着电却不充": "plugged in, not charging", "电池 ≥ 40 ℃": "battery ≥ 40 °C",
    "充电时 < 5 ℃": "charging below 5 °C", "待机耗电": "Standby Drain", "锁屏每小时 > 3%": "locked, > 3% per hour",
    "22 点后电量 < 30%": "< 30% after 10 PM", "功率 > 6 W": "above 6 W", "专注时静默": "Silence During Focus",
    "照常提醒 · 充电": "Still Alert · Charging", "照常提醒 · 异常": "Still Alert · Issues", "照常提醒 · 用电": "Still Alert · Usage",
    "灵动岛": "Dynamic Island", "长条": "Long", "短条": "Short", "正在充电": "Charging", "约40分钟": "~40 min", "点按跳转": "Tap to Open", "打开电池信息": "battery details",
    "中断": "Stopped", "插着却不充": "plugged, not charging",
    "不要为了热闹而点亮每一个开关。": "No need to light up every switch.",
    "到点": "Target", "充到 %d%%": "at %d%%", "电量": "Level", "异常": "Issues", "用电": "Usage",
    "接触": "Loose", "1 分钟断开 ≥ 3 次": "≥ 3 drops / min", "低温": "Cold", "充电 < 5 ℃": "charging < 5 °C",
    "睡前": "Bedtime", "22 点后 < 30%": "< 30% after 10 PM",
    "充满": "Full", "降速": "Throttled", "待机": "Standby", "未开上限": "no limit", "过热限流": "heat-limited", "锁屏 > 3%/h": "locked > 3%/h",
    "功率 · 时长": "power · ETA", "到达上限": "at limit", "拔线充入量": "added on unplug", "≥ 40 ℃": "≥ 40 °C",
    # 充电上限
    "插上电源时询问": "Ask When Plugged In",
    "插上电源时弹窗问「确认」还是「这次充满」，外出前想充满就点「这次充满」，拔线后自动恢复上限。超过 30 天没充满过时，这个弹窗会提醒你充满一次（关掉询问也会提醒），让电量统计保持准确。":
        "When you plug in, xrhea asks whether to keep the limit or charge to 100% this time. Heading out? Tap \"Charge to 100% This Time\"; the limit comes back once you unplug. If it's been over 30 days since the last full charge, it reminds you to charge fully once (even with asking turned off) to keep the battery reading accurate.",
    '已到上限 %d%%': 'At Limit (%d%%)',
    '已到上限': 'At Limit',
    '约 %@ 到 %d%%': '%@ to %d%%',
    "充电上限": "Charge Limit",
    "到上限就停止充电，插着线时电源直接给手机供电，电池不充也不放。掉到恢复线以下才重新充，不会在上限附近反复启停。":
        "Charging stops at the limit. While plugged in, the charger powers the phone directly and the battery neither charges nor drains. It only resumes below the resume level, so it won't flip on and off around the limit.",
    "启用充电上限": "Enable Charge Limit", "上限": "Limit", "掉到多少再充": "Resume At",
    "−3%": "−3%", "−5%": "−5%", "−10%": "−10%", "−20%": "−20%",
    "上限 − 3%": "Limit − 3%", "上限 − 5%": "Limit − 5%", "上限 − 10%": "Limit − 10%", "上限 − 20%": "Limit − 20%",
    "比如上限 80%、选「上限 − 5%」：充到 80% 停，用到 75% 以下再插着线时才重新充。":
        "E.g. with an 80% limit and \"Limit − 5%\", charging stops at 80% and starts again once it's below 75% while plugged in.",
    "停充要等 30 秒左右才生效，为了不超过上限，充得快时会提前一点停，可能停在上限少 1%。请关掉系统「设置 › 电池 › 充电」里的优化充电，它和 xrhea 用的是同一个开关，会互相打架。关掉这里或卸载 xrhea 会马上恢复充电；重启手机也会恢复默认。":
        "Stopping takes about 30 seconds, so to never go over the limit it stops a little early when charging fast and may end 1% below the limit. Turn off Optimized Charging in Settings › Battery › Charging: it uses the same switch as xrhea and they'll fight. Turning this off or uninstalling xrhea resumes charging right away; restarting the phone also resets it.",
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
}
CODE_STRINGS = ["长条", "短条", "正在充电", "约40分钟", "试试看", "需注销", "注销", "确定要注销（重启 SpringBoard）吗？", "取消", "有新版 %@", "在 Sileo 中添加", "复制地址",
                "已复制", "好", "重置", "xrhea 的所有设置都会恢复默认。确定吗？", "已重置",
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
