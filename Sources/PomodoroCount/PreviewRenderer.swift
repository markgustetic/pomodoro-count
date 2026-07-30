import SwiftUI
import AppKit

/// Renders the popover UI to a PNG without showing any window, so the layout
/// can be reviewed headlessly. Run with `swift run PomodoroCount --preview <path>`.
enum PreviewRenderer {
    @MainActor
    static func render(to path: String) {
        let model = AppModel(storeURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pomo-preview-\(UUID().uuidString).json"))

        // Seed a week of sample history so the panel looks realistic. Each
        // entry is that day's pomodoros, one category name per record (nil
        // means the fallback bucket). Row counts per day still sum to the
        // original perDay = [3, 5, 2, 6, 4, 1, 4], but *which* category each
        // record belongs to is chosen so today's panel shows every row state
        // honestly: Work sits partway to its goal (partial dots), AI study
        // has met its goal (met-goal accent), Music has none yet (empty
        // dots), and the fallback bucket still holds one (bare count, no
        // dots, since its goal is 0).
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let categoryPlan: [[String?]] = [
            ["Work", "Work", nil],                                    // 6 days ago (3)
            ["Work", "Work", "Work", "AI study", "Music"],             // 5 days ago (5)
            ["Work", nil],                                             // 4 days ago (2)
            ["Work", "Work", "Work", "Work", "AI study", "Music"],     // 3 days ago (6)
            ["Work", "Work", "AI study", nil],                         // 2 days ago (4)
            ["Music"],                                                 // yesterday (1)
            ["Work", "Work", "AI study", nil],                         // today (4): Work 2/4, AI study 1/1, Music 0/1, General 1
        ]
        var seeded: [Record] = []
        for (i, categories) in categoryPlan.enumerated() {
            let day = cal.date(byAdding: .day, value: i - 6, to: today)!
            let stamp = cal.date(byAdding: .hour, value: 10, to: day)!
            for category in categories {
                seeded.append(Record(at: stamp, source: "manual", category: category))
            }
        }
        model.records = seeded
        model.settings.categoriesEnabled = true
        model.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "AI study", dailyGoal: 1),
            Category(name: "Music", dailyGoal: 1),
        ]
        if PreviewOverrides.armedBreak {
            // The only route into `.breakReady` is a completed focus session,
            // so drive one. That logs a pomodoro, which nudges the fallback
            // bucket's count past what the seeding comment above describes —
            // true of this mode only, and the whole point of it.
            model.settings.soundEnabled = false
            model.settings.autoStartBreak = false
            model.startWork()
            model.forceCompleteForTesting()
        }
        if let theme = PreviewOverrides.theme { model.settings.theme = theme }
        let bg: Color = model.settings.theme == .synthwave
            ? Color(hex: 0x0B0616)
            : Color(nsColor: .windowBackgroundColor)

        let view = HStack(alignment: .top, spacing: 18) {
            RootView(initialTab: .focus).environmentObject(model)
            RootView(initialTab: .history).environmentObject(model)
            RootView(initialTab: .settings).environmentObject(model)
        }
        .padding(18)
        .background(bg)

        guard let png = rasterize(view, scale: 2) else {
            print("Preview render failed")
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Wrote preview → \(path)")
            exit(0)
        } catch {
            print("Write failed: \(error)")
            exit(1)
        }
    }

    /// Draws a SwiftUI view to PNG data.
    ///
    /// This hosts the view in an offscreen window and draws the real AppKit view
    /// hierarchy, rather than using `ImageRenderer`. `ImageRenderer` cannot
    /// rasterize NSView-backed controls — the switches and steppers in Settings
    /// come out as yellow "unrenderable" placeholders — so it would misreport
    /// what the panel actually looks like.
    @MainActor
    private static func rasterize(_ view: some View, scale: CGFloat) -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        // Controls only lay out and draw once they belong to a window.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }

        rep.size = bounds.size   // points, so the context scales to `scale`
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        hosting.displayIgnoringOpacity(bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
