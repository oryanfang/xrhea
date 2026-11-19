// xrhea 的图标（设置列表、关于页、Sileo）。Rhea（土卫五）是希腊神话里的众神之母、力量之源；电池就是手机的力量之源。
// 定稿（2026-11-18，方案 RA）：xrkit / xrsh 那种深蓝黑底、细白线；一个大写 R，
// R 上半部的「碗」画成一块电池——右端带正极小头，里面亮着七成电量（薄荷→青发光）。
// 竖笔和斜腿照常，横平竖直 + 一条斜腿，和 xrkit 的斜向交叉 X 区分开。
//
//   swift tools/make_logo.swift export Prefs/Resources Launcher/Resources
//   导出设置列表 icon*.png、关于页 About*.png（29pt @1x/@2x/@3x）、调试版桌面图标 AppIcon60x60@2x/3x，
//   以及 docs/icon-1024.png（1024 原图，以后 Sileo 用）

import AppKit

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func poly(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.addLines(between: pts); return p }
func strokePath(_ ctx: CGContext, _ p: CGPath, _ w: CGFloat, _ c: CGColor) {
    ctx.saveGState(); ctx.addPath(p); ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(c); ctx.strokePath(); ctx.restoreGState()
}

let mint: UInt32 = 0x3DF5A8, cyan: UInt32 = 0x1AB8FF
let t: CGFloat = 24   // 线粗，同 xrkit

// 发光填充：先带辉光填一次，再盖 薄荷→青 渐变（同 xrkit）
func fillGlow(_ ctx: CGContext, _ shape: CGPath, blur: CGFloat) {
    let b = shape.boundingBoxOfPath
    let g = CGGradient(colorsSpace: space, colors: [rgb(mint), rgb(cyan)] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: blur, color: rgb(0x2EE6C0, 0.55))
    ctx.addPath(shape); ctx.setFillColor(rgb(mint)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(g, start: P(b.minX, b.minY), end: P(b.maxX, b.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// 背景：深蓝到黑的斜向渐变 + 电量附近一点柔光（同 xrkit）
func coldBG(_ ctx: CGContext, glowAt c: CGPoint) {
    let bg = CGGradient(colorsSpace: space, colors: [rgb(0x18212D), rgb(0x0A0F16), rgb(0x040609)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: P(1024, 1024), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [rgb(mint, 0.08), rgb(mint, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 480, options: [])
}

// 整个图标，画在 1024 画布上（左上角原点）
func drawLogo(_ ctx: CGContext) {
    coldBG(ctx, glowAt: P(500, 400))
    ctx.saveGState(); ctx.translateBy(x: -34, y: 0)            // 连正极小头一起视觉居中
    let sx: CGFloat = 352, top: CGFloat = 272, bowlBot: CGFloat = 500, bot: CGFloat = 752
    let bowlR: CGFloat = 710, rad: CGFloat = 64
    // 白线放进一个透明层再统一降透明度，交接处不会叠亮
    ctx.setAlpha(0.9); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let solid = rgb(0xE8ECF0)
    let p = CGMutablePath()
    p.move(to: P(sx, bot)); p.addLine(to: P(sx, top))                       // 竖笔
    p.addLine(to: P(bowlR - rad, top))                                        // 碗 = 电池外壳
    p.addArc(tangent1End: P(bowlR, top), tangent2End: P(bowlR, bowlBot), radius: rad)
    p.addArc(tangent1End: P(bowlR, bowlBot), tangent2End: P(sx, bowlBot), radius: rad)
    p.addLine(to: P(sx, bowlBot))
    p.move(to: P(490, bowlBot)); p.addLine(to: P(690, bot))                  // 斜腿
    strokePath(ctx, p, t, solid)
    let my = (top + bowlBot) / 2
    strokePath(ctx, poly([P(bowlR + 42, my - 40), P(bowlR + 42, my + 40)]), t, solid)   // 正极
    ctx.endTransparencyLayer(); ctx.setAlpha(1)
    // 电量：七成
    let i = t / 2 + 24
    let inner = CGRect(x: sx + i, y: top + i, width: bowlR - sx - i * 2, height: bowlBot - top - i * 2)
    fillGlow(ctx, rr(CGRect(x: inner.minX, y: inner.minY, width: inner.width * 0.7, height: inner.height), 34), blur: 32)
    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext, side: CGFloat, rounded: Bool) {
    ctx.saveGState()
    if rounded { ctx.addPath(rr(CGRect(x: 0, y: 0, width: side, height: side), side * 0.225)); ctx.clip() }
    ctx.scaleBy(x: side / 1024, y: side / 1024)
    drawLogo(ctx)
    ctx.restoreGState()
}

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}
func save(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

let args = CommandLine.arguments
guard args.count >= 3 && args[1] == "export" else { print("用法见文件开头"); exit(1) }
try? FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: "docs", withIntermediateDirectories: true)
save(bitmap(1024, 1024) { drawIcon($0, side: 1024, rounded: true) }, "docs/icon-1024.png")
for scale in [1, 2, 3] {
    let side = 29 * scale, suffix = scale == 1 ? "" : "@\(scale)x"
    let img = bitmap(side, side) { drawIcon($0, side: CGFloat(side), rounded: true) }
    for name in ["icon", "About"] { save(img, "\(args[2])/\(name)\(suffix).png") }
}
if args.count >= 4 {   // 调试版桌面图标：不切圆角（系统自己切）
    try? FileManager.default.createDirectory(atPath: args[3], withIntermediateDirectories: true)
    for scale in [2, 3] {
        let side = 60 * scale
        save(bitmap(side, side) { drawIcon($0, side: CGFloat(side), rounded: false) }, "\(args[3])/AppIcon60x60@\(scale)x.png")
    }
}
print("导出完成")
