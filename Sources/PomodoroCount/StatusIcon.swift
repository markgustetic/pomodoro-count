import AppKit

/// Draws the menu bar item: a custom icon + the status text, as a single
/// template image so macOS tints it correctly in light/dark and on click.
enum StatusIcon {

    static func render(phase: Phase, running: Bool, text: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,   // template ⇒ tinted by the system
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let iconSize: CGFloat = 15
        let gap: CGFloat = 3
        let height: CGFloat = 18
        let width = ceil(iconSize + gap + textSize.width)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let iconRect = NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
            drawIcon(phase: phase, running: running, in: iconRect)
            let textY = (height - textSize.height) / 2
            (text as NSString).draw(at: NSPoint(x: iconSize + gap, y: textY), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawIcon(phase: Phase, running: Bool, in rect: NSRect) {
        // Paused: show a pause glyph regardless of phase.
        if !running && phase != .idle {
            symbol("pause.fill")?.draw(in: rect)
            return
        }
        switch phase {
        case .breakTime:
            symbol("cup.and.saucer.fill")?.draw(in: rect)
        case .idle, .work:
            drawTomato(in: rect)
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    /// A little tomato: round body with a short stem and two leaves.
    private static func drawTomato(in rect: NSRect) {
        NSColor.black.setFill()

        func x(_ f: CGFloat) -> CGFloat { rect.minX + f * rect.width }
        func y(_ f: CGFloat) -> CGFloat { rect.minY + f * rect.height }
        func p(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint { NSPoint(x: x(fx), y: y(fy)) }

        // Body
        let body = NSBezierPath(ovalIn: NSRect(
            x: x(0.06), y: y(0.02), width: rect.width * 0.88, height: rect.height * 0.80))
        body.fill()

        // Stem
        let stem = NSBezierPath(roundedRect: NSRect(
            x: x(0.44), y: y(0.74), width: rect.width * 0.12, height: rect.height * 0.24),
            xRadius: rect.width * 0.05, yRadius: rect.width * 0.05)
        stem.fill()

        // Leaves (two triangles fanning from the stem base)
        let left = NSBezierPath()
        left.move(to: p(0.50, 0.86))
        left.line(to: p(0.20, 0.80))
        left.line(to: p(0.44, 0.66))
        left.close()
        left.fill()

        let right = NSBezierPath()
        right.move(to: p(0.50, 0.86))
        right.line(to: p(0.80, 0.80))
        right.line(to: p(0.56, 0.66))
        right.close()
        right.fill()
    }
}
