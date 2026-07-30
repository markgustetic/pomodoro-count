import XCTest

/// Plumbing shared by both UI test suites: where the built app binary is, and
/// how to seed and read the throwaway store both of them run against.

enum BuiltApp {
    private final class Marker {}

    /// The app binary in the built-products directory.
    ///
    /// Walked up to rather than hardcoded: the test bundle sits several levels
    /// inside `UITests-Runner.app`, and how many is Xcode's business, not this
    /// test's.
    static func binary() throws -> URL {
        var dir = Bundle(for: Marker.self).bundleURL
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("PomodoroCount.app/Contents/MacOS/PomodoroCount")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw XCTSkip("PomodoroCount.app not found near \(Bundle(for: Marker.self).bundleURL.path)")
    }
}

enum TestStore {
    struct SeedFailed: Error, CustomStringConvertible {
        let path: String
        var description: String { "seeding did not write \(path)" }
    }

    /// Writes a throwaway store, seeded by the app itself, so a test can never
    /// read or write the real pomodoro history. Returns the store's path.
    ///
    /// Run as a plain subprocess rather than through `XCUIApplication`:
    /// `--seed-store` writes the file and exits immediately, and XCUITest
    /// treats an app that exits during launch as a launch failure.
    static func seed() throws -> String {
        let path = NSTemporaryDirectory()
            + "pomodoro-uitest-\(UUID().uuidString)/data.json"
        let seeder = Process()
        seeder.executableURL = try BuiltApp.binary()
        seeder.arguments = ["--seed-store", path]
        try seeder.run()
        seeder.waitUntilExit()
        guard FileManager.default.fileExists(atPath: path) else {
            throw SeedFailed(path: path)
        }
        return path
    }

    /// The category order as persisted, read straight out of the store the app
    /// writes.
    ///
    /// Reading the file rather than the UI is deliberate: the store is the
    /// thing that has to be right — an order that never reached disk would look
    /// identical until the next launch.
    static func categoryOrder(at path: String) throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let settings = json?["settings"] as? [String: Any]
        let categories = settings?["categories"] as? [[String: Any]] ?? []
        return categories.compactMap { $0["name"] as? String }
    }

    /// Asserts the store settles on `expected`. The write lands on drop, so
    /// this waits a moment rather than racing it.
    static func expectOrder(_ expected: [String], at path: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && (try? categoryOrder(at: path)) != expected {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(try categoryOrder(at: path), expected, file: file, line: line)
    }
}
