import SwiftUI
import AppKit

/// Renders the popover UI to a PNG without showing any window, so the layout
/// can be reviewed headlessly. Run with `swift run PomodoroCount --preview <path>`.
enum PreviewRenderer {
    @MainActor
    static func render(to path: String) {
        let model = AppModel(storeURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pomo-preview-\(UUID().uuidString).json"))

        // Seed a week of sample history so the panel looks realistic.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let perDay = [3, 5, 2, 6, 4, 1, 4]   // 6 days ago … today
        var seeded: [Record] = []
        for (i, count) in perDay.enumerated() {
            let day = cal.date(byAdding: .day, value: i - 6, to: today)!
            let stamp = cal.date(byAdding: .hour, value: 10, to: day)!
            for _ in 0..<count { seeded.append(Record(at: stamp, source: "manual")) }
        }
        model.records = seeded

        let view = HStack(alignment: .top, spacing: 18) {
            RootView(initialTab: .focus).environmentObject(model)
            RootView(initialTab: .history).environmentObject(model)
            RootView(initialTab: .settings).environmentObject(model)
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
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
}
