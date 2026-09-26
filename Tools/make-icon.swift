// Draws the app icon: a gradient ring with a "C" on a dark macOS squircle.
//   swift Tools/make-icon.swift Resources/AppIcon.icns
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS icon grid: 824 pt body centered in 1024, with a soft drop shadow.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.25, alpha: 1),
               ending: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1))!.draw(in: squircle, angle: -90)

    let center = NSPoint(x: 512 * s, y: 512 * s)
    let radius = 250 * s, width = 92 * s
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor.white.withAlphaComponent(0.12).setStroke()
    track.stroke()

    // 75 % arc from 12 o'clock, clockwise: green → neon green, same palette as the menu bar rings.
    let start = NSColor.systemGreen.usingColorSpace(.sRGB)!, end = NSColor(srgbRed: 0.55, green: 1, blue: 0.35, alpha: 1)
    let sweep: CGFloat = 270, segments = 180
    for i in 0..<segments {
        let t0 = CGFloat(i) / CGFloat(segments), t1 = CGFloat(i + 1) / CGFloat(segments)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90 - t0 * sweep + (i == 0 ? 0 : 0.6),
                      endAngle: 90 - t1 * sweep, clockwise: true)
        arc.lineWidth = width
        arc.lineCapStyle = (i == 0 || i == segments - 1) ? .round : .butt
        start.blended(withFraction: t1, of: end)!.setStroke()
        arc.stroke()
    }

    let font = NSFont.systemFont(ofSize: 300 * s, weight: .heavy)
    let text = NSAttributedString(string: "C", attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(text)
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
    CTLineDraw(line, ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
if out.pathExtension == "png" {
    try! drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: out)
} else {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try! p.run(); p.waitUntilExit()
}
