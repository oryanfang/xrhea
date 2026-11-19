# Building · 从源码编译

[English](#english) · [中文](#中文)

## English

Requires [Theos](https://theos.dev) (the **roothide** fork) and GNU make 4 (`gmake` from Homebrew; macOS's own make 3.81 is too old). Theos does not support spaces in the project path.

```bash
gmake package                     # debug build (writes a debug log on the device)
gmake package FINALPACKAGE=1      # release build
```

The Makefile expects Theos at `~/theos-roothide`; change the first block of `Makefile` if yours is elsewhere.

**Install to a device.** Create `local.mk` in the project root (it is not committed) with your device's SSH address, then run `gmake package install`:

```make
THEOS_DEVICE_IP = iphone.local
```

**Layout.**
- `Tweak/`: the SpringBoard tweak: alerts (`Alerts.m`), the alert UI (`Toast.m`), the plug‑in prompt (`ChargePrompt.m`).
- `Daemon/`: `xrhead`, the root daemon that stops and resumes charging for the charge limit.
- `Prefs/`: the settings pages. The `.plist` files in `Prefs/Resources` are generated: edit `Prefs/make_plists.py` and run `python3 Prefs/make_plists.py`.
- `Shared/`: battery readings (`XRBattery`) and helpers used by all of the above.
- `tools/make_logo.swift`: draws the xrhea icon (`swift tools/make_logo.swift export Prefs/Resources`).

**Debug build.** A debug build writes a log to `/var/mobile/Library/Caches/com.xyrith.xrhea.status` (the daemon writes `com.xyrith.xrhea.daemon.log` next to it), and adds a Home Screen shortcut that opens the settings. Release builds write nothing and have no shortcut.

**Other jailbreaks.** Only roothide is supported and tested. For rootless, set `THEOS_PACKAGE_SCHEME = rootless` and the package architecture accordingly.

## 中文

需要 [Theos](https://theos.dev)（**roothide** 分支）和 GNU make 4（Homebrew 的 `gmake`；macOS 自带的 make 3.81 太旧）。Theos 不支持路径里有空格。

```bash
gmake package                     # 调试版（会在手机上写调试日志）
gmake package FINALPACKAGE=1      # 正式版
```

Makefile 默认 Theos 在 `~/theos-roothide`，路径不同请改 `Makefile` 第一段。

**装到手机。** 在项目根目录建一个 `local.mk`（不会提交），写上手机的 SSH 地址，再运行 `gmake package install`：

```make
THEOS_DEVICE_IP = iphone.local
```

**目录。**
- `Tweak/`：注入 SpringBoard 的插件：提醒（`Alerts.m`）、提醒的界面（`Toast.m`）、插电弹窗（`ChargePrompt.m`）。
- `Daemon/`：`xrhead`，充电上限的 root 后台服务，负责停充和恢复。
- `Prefs/`：设置页。`Prefs/Resources` 里的 `.plist` 是生成的：改 `Prefs/make_plists.py`，再运行 `python3 Prefs/make_plists.py`。
- `Shared/`：电池读数（`XRBattery`）和上面几部分共用的小工具。
- `tools/make_logo.swift`：画 xrhea 图标（`swift tools/make_logo.swift export Prefs/Resources`）。

**调试版。** 调试版会在手机上写 `/var/mobile/Library/Caches/com.xyrith.xrhea.status`（后台服务写同目录的 `com.xyrith.xrhea.daemon.log`），还会在桌面放一个直达设置的快捷图标。正式版什么都不写，也没有快捷图标。

**其他越狱。** 只支持、也只测过 roothide。rootless 要把 `THEOS_PACKAGE_SCHEME` 改成 `rootless`、包架构相应调整。
