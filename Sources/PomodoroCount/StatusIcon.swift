import AppKit

/// Draws the menu bar item: a custom icon + the status text, as a single
/// template image so macOS tints it correctly in light/dark and on click.
enum StatusIcon {

    private struct Key: Equatable {
        let phase: Phase, running: Bool, text: String, description: String?
        let done: Int, goal: Int          // -1/-1 when no goal strip is drawn
    }

    /// The last render. One entry is the right size: the item re-renders on
    /// every 0.5s tick, but `ceil` moves the countdown text only once a
    /// second, so half of all calls repeat the previous inputs exactly —
    /// and those should not redraw a pixel-identical image.
    @MainActor private static var lastRender: (key: Key, image: NSImage)?

    /// `description` is what VoiceOver announces; the drawn text alone ("3") is
    /// meaningless read aloud. `goalProgress`, when present, draws a thin strip
    /// along the item's bottom edge: dots while the goal is small enough to
    /// count at a glance, a bar once it isn't — the same language the panel's
    /// category rows speak.
    @MainActor
    static func render(phase: Phase, running: Bool, text: String,
                       description: String? = nil,
                       goalProgress: (done: Int, goal: Int)? = nil) -> NSImage {
        let key = Key(phase: phase, running: running, text: text, description: description,
                      done: goalProgress?.done ?? -1, goal: goalProgress?.goal ?? -1)
        if let lastRender, lastRender.key == key { return lastRender.image }
        let image = draw(phase: phase, running: running, text: text,
                         description: description, goalProgress: goalProgress)
        lastRender = (key, image)
        return image
    }

    private static func draw(phase: Phase, running: Bool, text: String,
                             description: String?,
                             goalProgress: (done: Int, goal: Int)?) -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,   // template ⇒ tinted by the system
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let iconSize: CGFloat = 15
        let height: CGFloat = 18
        // No text means no gap either, or the item keeps padding it can't use —
        // the whole point of icon-only is giving the width back to the menu bar.
        let gap: CGFloat = text.isEmpty ? 0 : 3
        let width = ceil(iconSize + gap + textSize.width)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let iconRect = NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
            drawIcon(phase: phase, running: running, in: iconRect)
            if !text.isEmpty {
                let textY = (height - textSize.height) / 2
                (text as NSString).draw(at: NSPoint(x: iconSize + gap, y: textY), withAttributes: attrs)
            }
            if let goalProgress {
                drawGoalStrip(done: goalProgress.done, goal: goalProgress.goal,
                              width: width)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description ?? (text.isEmpty ? "Pomodoro Count" : text)
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

    /// The goal strip along the item's bottom edge. Dots up to eight — one per
    /// goal unit, filled up to what's done — then a bar, because nine 2pt dots
    /// stop being countable and start being noise. Unfilled shapes draw at a
    /// quarter alpha: this is a template image, so opacity is the only shade
    /// of grey it has.
    private static func drawGoalStrip(done: Int, goal: Int, width: CGFloat) {
        let filled = min(done, goal)
        if goal <= 8 {
            let diameter: CGFloat = 2.5
            let step = width / CGFloat(goal)
            for index in 0..<goal {
                let x = step * (CGFloat(index) + 0.5) - diameter / 2
                let dot = NSBezierPath(ovalIn: NSRect(x: x, y: 0, width: diameter, height: diameter))
                NSColor.black.withAlphaComponent(index < filled ? 1 : 0.25).setFill()
                dot.fill()
            }
        } else {
            let track = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: 2),
                                     xRadius: 1, yRadius: 1)
            NSColor.black.withAlphaComponent(0.25).setFill()
            track.fill()
            let fraction = min(1, CGFloat(filled) / CGFloat(goal))
            if fraction > 0 {
                let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width * fraction, height: 2),
                                        xRadius: 1, yRadius: 1)
                NSColor.black.setFill()
                fill.fill()
            }
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
