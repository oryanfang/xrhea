# xrhea

**A battery and charging tweak for jailbroken iOS 17** · [简体中文](README.zh-CN.md)

Rhea, Saturn's moon, is the mother of the gods in Greek myth: the source of their strength. The battery is your phone's. xrhea looks after it: detailed battery readings, a real charge limit, and short, readable alerts from the Dynamic Island. Written from scratch.

Objective‑C / Logos, built with Theos, for **roothide** jailbreaks. Made for iOS 17 and **only tested on iOS 17.3.1**; some features may not work on other versions. The settings UI is in English and Chinese: it follows the system language, or pick one under About › Language.

## Features

**Battery details**
- Maximum capacity against a new battery, with a progress bar.
- Live: status, level, power, voltage, current, temperature and an estimate (time to full / to your limit while charging, time left on battery). While charging, power is what the charger delivers into the phone, so it matches a USB power meter.
- Charger: max power, negotiated voltage and current, model name.
- Capacity (full charge, design, current charge) and cycle count.
- A ⚠️ on readings that need attention (worn battery, too hot, charger stuck at 5 V, charging too slowly, draining fast), each with what to do about it, plus a short guide to reading the numbers.

**Charge limit**
- Stop charging at 60–90%. While plugged in, the charger powers the phone directly and the battery neither charges nor drains; charging resumes once the level drops below the limit by the amount you choose.
- Stops about 1% early when charging fast, so it never goes over.
- When you plug in, asks whether to keep the limit or charge to 100% this time (handy before heading out); the limit comes back when you unplug.
- Reminds you to charge fully once a month to keep the battery reading accurate.
- Runs as a small root daemon. Turning the limit off, uninstalling, or restarting the phone resumes normal charging.

**Alerts**
- Shown from the Dynamic Island, as a long pill like the one iOS shows when you plug in (text on the left, the value on the right) or a shorter one; phones without a Dynamic Island get a banner.
- Charging: plugged in (charging power), target level reached, limit reached, fully charged, charging summary on unplug.
- Issues: slow charging, charging slowed by heat, loose cable, plugged in but not charging, battery hot, charging in the cold.
- Usage: battery draining while locked, low battery at bedtime, high power draw.
- Each alert has its own switch and a **Try It** button that shows it with your phone's current readings.
- Quiet during Focus, with your own list of alerts that still come through (by default only hot and cold).
- Tap an alert to open the battery details.
- Each alert shows at most once every 30 minutes.

**About page**
- Language (System / 中文 / English), check GitHub for a new version, report an issue, copy debug info (versions, device model and changed settings), reset all settings.

Settings live in Settings › xrhea.

## Privacy

xrhea reads the battery's own readings on the phone and keeps everything there. It collects nothing and sends nothing; the only network request is the About page checking GitHub for a new version when you open it. The battery's and charger's serial numbers are never shown or saved.

## Install

Add the source `https://oryanfang.github.io/repo/` in Sileo or Zebra and install **xrhea**. Or download the `.deb` from [Releases](https://github.com/oryanfang/xrhea/releases).

roothide only (package architecture `iphoneos-arm64e`). For rootless / rootful you need to change the packaging yourself, see [BUILDING.md](BUILDING.md).

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE): free for personal study, research and other noncommercial use; commercial use is not allowed.
