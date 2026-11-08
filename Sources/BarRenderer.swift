import AppKit

enum BarRenderer {
    static let barWidth: CGFloat = 34
    static let barHeight: CGFloat = 5
    static let textGap: CGFloat = 4
    static let height: CGFloat = 18

    static func color(for level: UsageLevel) -> NSColor {
        switch level {
        case .ok: return NSColor.systemGreen
        case .warn: return NSColor.systemOrange
        case .critical: return NSColor.systemRed
        }
    }

    /// Fill gradient, left to right: the level's system color brightening to a neon tint at the leading edge.
    static func gradient(for level: UsageLevel) -> (NSColor, NSColor) {
        switch level {
        case .ok: return (.systemGreen, NSColor(srgbRed: 0.55, green: 1.0, blue: 0.35, alpha: 1))
        case .warn: return (.systemOrange, NSColor(srgbRed: 1.0, green: 0.85, blue: 0.2, alpha: 1))
        case .critical: return (.systemRed, NSColor(srgbRed: 1.0, green: 0.35, blue: 0.6, alpha: 1))
        }
    }

    /// Two stacked bars, each followed by its percentage. A weekly bar gets a pace marker and pace-based colors.
    static func statusImage(top: Double, bottom: Double, topPace: Double? = nil, bottomPace: Double? = nil) -> NSImage {
        // Width follows the widest percentage label so there is no dead space on the right.
        let labels = [top, bottom].map { label(for: $0) }
        let textWidth = labels.map { $0.size().width }.max() ?? 0
        let width = ceil(barWidth + textGap + textWidth)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawRow(percent: top, pace: topPace, y: 9.5)
            drawRow(percent: bottom, pace: bottomPace, y: 1.5)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawRow(percent: Double, pace: Double?, y: CGFloat) {
        let p = min(max(percent, 0), 100)
        let track = NSRect(x: 0, y: y, width: barWidth, height: barHeight)
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()

        let fillW = max(barWidth * CGFloat(p / 100), p > 0 ? barHeight : 0)
        let fill = NSRect(x: 0, y: y, width: fillW, height: barHeight)
        let (start, end) = gradient(for: UsageLevel(percent: p, pace: pace))
        NSGradient(starting: start, ending: end)?
            .draw(in: NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5), angle: 0)

        // Pace marker: a tick half a point taller than the bar on each side, clear of the row above.
        if let pace = pace {
            let x = min(max(barWidth * CGFloat(pace / 100), 0.6), barWidth - 0.6)
            drawMarker(from: NSPoint(x: x, y: y - 0.5), to: NSPoint(x: x, y: y + barHeight + 0.5), width: 1)
        }

        let text = label(for: p)
        let size = text.size()
        text.draw(at: NSPoint(x: barWidth + textGap, y: y + barHeight / 2 - size.height / 2 + 0.5))
    }

    // Rings fill the menu bar's height, like the system icons next to them.
    static let ringsHeight: CGFloat = 22
    static let ringDiameter: CGFloat = 20
    static let ringGap: CGFloat = 4
    static let ringLineWidth: CGFloat = 2.6

    /// One ring per limit, filled clockwise from 12 o'clock, with a letter in the middle.
    static func ringsImage(_ rings: [(letter: String, percent: Double, pace: Double?)]) -> NSImage {
        let n = CGFloat(rings.count)
        let width = n * ringDiameter + max(n - 1, 0) * ringGap
        let image = NSImage(size: NSSize(width: width, height: ringsHeight), flipped: false) { _ in
            for (i, r) in rings.enumerated() {
                let center = NSPoint(x: CGFloat(i) * (ringDiameter + ringGap) + ringDiameter / 2, y: ringsHeight / 2 - 1)   // 1 pt low: reads as centered next to system icons
                drawRing(percent: r.percent, pace: r.pace, letter: r.letter, center: center)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawRing(percent: Double, pace: Double?, letter: String, center: NSPoint) {
        let p = min(max(percent, 0), 100)
        let radius = (ringDiameter - ringLineWidth) / 2 - 0.5
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = ringLineWidth
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()

        // NSGradient cannot follow an arc: draw short segments, each blended a bit further toward the end color.
        if p > 0 {
            let (start, end) = gradient(for: UsageLevel(percent: p, pace: pace))
            let sweep = CGFloat(p) * 3.6
            let segments = max(Int(p / 2), 1)
            for i in 0..<segments {
                let t0 = CGFloat(i) / CGFloat(segments), t1 = CGFloat(i + 1) / CGFloat(segments)
                let arc = NSBezierPath()
                // Each segment starts 1° early so neighbors overlap and leave no seam.
                arc.appendArc(withCenter: center, radius: radius,
                              startAngle: 90 - t0 * sweep + (i == 0 ? 0 : 1), endAngle: 90 - t1 * sweep, clockwise: true)
                arc.lineWidth = ringLineWidth
                arc.lineCapStyle = (i == 0 || i == segments - 1) ? .round : .butt
                (start.blended(withFraction: t1, of: end) ?? end).setStroke()
                arc.stroke()
            }
        }

        // Pace marker: a radial tick across the ring, clockwise from 12 o'clock like the fill.
        if let pace = pace {
            let a = CGFloat(min(max(pace, 0), 100)) * 3.6 * .pi / 180
            let point = { (r: CGFloat) in NSPoint(x: center.x + r * sin(a), y: center.y + r * cos(a)) }
            drawMarker(from: point(radius - 2.4), to: point(radius + 1.7), width: 1.1)
        }

        let font = NSFont.systemFont(ofSize: 7.5, weight: .bold)
        let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        // Center the glyphs' ink, not the line box: capitals and digits have no descender.
        let line = CTLineCreateWithAttributedString(text)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
        CTLineDraw(line, ctx)
    }

    /// A label-colored tick inside a transparent halo, so it stands out on the fill and the track alike.
    private static func drawMarker(from a: NSPoint, to b: NSPoint, width: CGFloat) {
        let line = NSBezierPath()
        line.move(to: a)
        line.line(to: b)
        line.lineCapStyle = .round
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        line.lineWidth = width + 1.4
        line.stroke()
        ctx.restoreGState()
        line.lineWidth = width
        NSColor.labelColor.setStroke()
        line.stroke()
    }

    static func label(for percent: Double) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        return NSAttributedString(string: "\(Int(min(max(percent, 0), 100).rounded()))%", attributes: attrs)
    }

    /// "C!" in orange when signed out; `waiting` shows a gray "C…" while a sign-in is in progress.
    static func errorImage(waiting: Bool = false) -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: waiting ? NSColor.secondaryLabelColor : NSColor.systemOrange]
        let text = NSAttributedString(string: waiting ? "C…" : "C!", attributes: attrs)
        let size = text.size()
        let width = max(18, ceil(size.width) + 2)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            text.draw(at: NSPoint(x: width / 2 - size.width / 2, y: height / 2 - size.height / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}
