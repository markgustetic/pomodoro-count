import SwiftUI
import AppKit

/// Renders the popover UI to a PNG without showing any window, so the layout
/// can be reviewed headlessly. Run with `swift run PomodoroCount --preview <path>`.
enum PreviewRenderer {

    /// Why a `--preview` run could not build the model it was asked to draw.
    ///
    /// Both cases stop the render. The alternative — quietly drawing the demo
    /// model instead — is the exact failure this path was built to end: a
    /// render that looks like an answer to a question it never read.
    enum StoreError: Error, CustomStringConvertible {
        case notFound(String)
        case unreadable(String, any Error)

        var description: String {
            switch self {
            case .notFound(let path):
                return "--preview --store: no store at \(path)"
            case .unreadable(let path, let error):
                return "--preview --store: could not read \(path) — \(error.localizedDescription)"
            }
        }
    }

    /// The model the preview draws.
    ///
    /// With no `--store`, the hand-seeded demo state below. With one, that
    /// store's own state — which is the only way to preview a panel the demo
    /// model cannot express: a pinned session target, a category name long
    /// enough to overflow the target pill, an archived category, a category
    /// list long enough to exercise `PanelTabScroller`'s height cap. The recipe
    /// is `--seed-store` → hand-edit the JSON → `--preview --store`.
    /// It found the pill overflow documented in `RootView` on its first use.
    ///
    /// The store is read through a **copy**, which is load-bearing rather than
    /// tidy: the render mutates the model it draws — `--armed-break` completes
    /// an entire focus session, `--theme` writes a setting — and `AppModel`
    /// persists on `didSet`. Aimed at the file itself, `--preview` would edit
    /// the state it was asked to show, and aimed at the real store it would log
    /// a pomodoro into the user's own history.
    @MainActor
    static func model(storePath: String?) throws -> AppModel {
        guard let storePath else { return demoModel() }
        guard FileManager.default.fileExists(atPath: storePath) else {
            throw StoreError.notFound(storePath)
        }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomo-preview-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("data.json")
        do {
            try FileManager.default.createDirectory(
                at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: storePath), to: copy)
        } catch {
            throw StoreError.unreadable(storePath, error)
        }
        return AppModel(storeURL: copy)
    }

    /// The stand-in state `--preview` renders when it is given no store, chosen
    /// so every row state in the panel is represented at once.
    @MainActor
    private static func demoModel() -> AppModel {
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
        return model
    }

    /// Draws the panel and exits.
    ///
    /// `--armed-break` and `--theme` are applied *after* the model is resolved,
    /// so both compose with either source of state — the demo model and a
    /// `--store` one alike.
    @MainActor
    static func render(to path: String, storePath: String? = nil) {
        let model: AppModel
        do {
            model = try Self.model(storePath: storePath)
        } catch {
            print("\(error)")
            exit(1)
        }

        if PreviewOverrides.armedBreak {
            // The only route into `.breakReady` is a completed focus session,
            // so drive one. That logs a pomodoro, which nudges the fallback
            // bucket's count past what the seeding comment above describes —
            // true of this mode only, and the whole point of it. Forcing
            // `autoStartBreak` off is what makes the session land in
            // `.breakReady` instead of `.breakTime`; `soundEnabled` off keeps
            // the screenshot silent. Both are settings on this shared preview
            // model, so the Settings tab rendered alongside Focus and History
            // in the same composite shows them off here, unlike the default
            // render — and, under `--store`, regardless of what that store says
            // about them. The pomodoro and the settings land on the store's
            // throwaway copy, never on the file named by `--store`.
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
