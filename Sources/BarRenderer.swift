import AppKit

enum BarRenderer {
    static let barWidth: CGFloat = 34
    static let barHeight: CGFloat = 5
    static let textGap: CGFloat = 4
    static let height: CGFloat = 18

    static func color(for percent: Double) -> NSColor {
        switch UsageLevel(percent: percent) {
        case .ok: return NSColor.systemGreen
        case .warn: return NSColor.systemOrange
        case .critical: return NSColor.systemRed
        }
    }

    /// Two stacked bars: 5-hour on top, weekly below, each followed by its percentage.
    static func statusImage(fiveHour: Double, weekly: Double) -> NSImage {
        // Width follows the widest percentage label so there is no dead space on the right.
        let labels = [fiveHour, weekly].map { label(for: $0) }
        let textWidth = labels.map { $0.size().width }.max() ?? 0
        let width = ceil(barWidth + textGap + textWidth)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawRow(percent: fiveHour, y: 10.5)
            drawRow(percent: weekly, y: 2.5)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawRow(percent: Double, y: CGFloat) {
        let p = min(max(percent, 0), 100)
        let track = NSRect(x: 0, y: y, width: barWidth, height: barHeight)
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()

        let fillW = max(barWidth * CGFloat(p / 100), p > 0 ? barHeight : 0)
        let fill = NSRect(x: 0, y: y, width: fillW, height: barHeight)
        color(for: p).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()

        let text = label(for: p)
        let size = text.size()
        text.draw(at: NSPoint(x: barWidth + textGap, y: y + barHeight / 2 - size.height / 2 + 0.5))
    }

    static func label(for percent: Double) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        return NSAttributedString(string: "\(Int(min(max(percent, 0), 100).rounded()))%", attributes: attrs)
    }

    static func errorImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: height), flipped: false) { _ in
            let font = NSFont.systemFont(ofSize: 13, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.systemOrange]
            let text = NSAttributedString(string: "C!", attributes: attrs)
            let size = text.size()
            text.draw(at: NSPoint(x: 9 - size.width / 2, y: height / 2 - size.height / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}
