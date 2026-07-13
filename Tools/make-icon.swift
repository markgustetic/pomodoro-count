// Renders the Pomodoro Count app icon (a colored tomato on a warm squircle)
// into an .iconset directory. Run via: swift Tools/make-icon.swift <outdir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func starPath(center: NSPoint, points: Int, outer: CGFloat, inner: CGFloat, rotation: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for i in 0 ..< (points * 2) {
        let r = (i % 2 == 0) ? outer : inner
        let a = rotation + CGFloat(i) * .pi / CGFloat(points)
        let pt = NSPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        i == 0 ? path.move(to: pt) : path.line(to: pt)
    }
    path.close()
    return path
}

func drawIcon(_ S: CGFloat) {
    let full = NSRect(x: 0, y: 0, width: S, height: S)

    // Warm squircle background with a soft drop shadow.
    let bgRect = full.insetBy(dx: S * 0.06, dy: S * 0.06)
    let radius = bgRect.width * 0.2237
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = S * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.012)
    shadow.set()
    NSGradient(starting: rgb(1.0, 0.97, 0.90), ending: rgb(1.0, 0.85, 0.68))!.draw(in: bg, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Tomato body with a radial highlight toward the upper-left.
    let bodyW = S * 0.60, bodyH = S * 0.54
    let bodyRect = NSRect(x: (S - bodyW) / 2, y: S * 0.15, width: bodyW, height: bodyH)
    let body = NSBezierPath(ovalIn: bodyRect)
    NSGradient(starting: rgb(1.0, 0.45, 0.37), ending: rgb(0.80, 0.15, 0.16))!
        .draw(in: body, relativeCenterPosition: NSPoint(x: -0.25, y: 0.35))

    // Specular highlight.
    rgb(1, 1, 1, 0.22).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: bodyRect.minX + bodyW * 0.17, y: bodyRect.minY + bodyH * 0.52,
        width: bodyW * 0.32, height: bodyH * 0.22)).fill()

    // Green calyx (leaves) + stem on top.
    let cx = S / 2, cy = bodyRect.maxY - bodyH * 0.02
    let leaves = starPath(center: NSPoint(x: cx, y: cy), points: 6,
                          outer: S * 0.17, inner: S * 0.075, rotation: .pi / 2)
    NSGradient(starting: rgb(0.44, 0.75, 0.32), ending: rgb(0.20, 0.50, 0.18))!.draw(in: leaves, angle: -90)

    rgb(0.30, 0.53, 0.20).setFill()
    NSBezierPath(roundedRect: NSRect(x: cx - S * 0.022, y: cy, width: S * 0.044, height: S * 0.12),
                 xRadius: S * 0.02, yRadius: S * 0.02).fill()
}

func pngData(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    try! pngData(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("Wrote \(specs.count) PNGs to \(outDir)")
