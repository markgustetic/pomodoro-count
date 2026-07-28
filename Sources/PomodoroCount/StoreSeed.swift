import Foundation

/// Writes a store file with known categories, so a UI test can start from a
/// fixed state without clicking its way through the add-category form.
///
/// This exists rather than a hand-written JSON fixture in the test target so
/// the seed goes through the app's own `Codable` types. A fixture would drift
/// silently the first time the schema changed, and the test would start failing
/// for a reason that had nothing to do with what it tests.
///
/// Deliberately not a UI harness. An earlier attempt hosted `CategoryList` in a
/// hand-built `NSPanel` meant to imitate the one `MenuBarExtra` puts the app in.
/// It could not be trusted: reproducing that panel's exact key-status and event
/// behaviour by hand is guesswork, and getting it wrong in the permissive
/// direction would have meant a test that passed for reorder mechanisms known to
/// be broken. The tests drive the real menu bar item instead.
enum StoreSeed {

    /// Categories the UI tests expect. `CategoryReorderUITests` asserts on these
    /// names, so the two must agree.
    static let categories = ["Alpha", "Bravo", "Charlie", "Delta"]

    /// Writes the seed and returns, for `--seed-store <path>`.
    static func write(to path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var settings = Settings()
        settings.categoriesEnabled = true
        settings.soundEnabled = false
        settings.categories = categories.map { Category(name: $0, dailyGoal: 1) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(AppModel.Persisted(records: [], settings: settings)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
