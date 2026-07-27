import Foundation
@testable import PomodoroCount

/// A model backed by a throwaway file, so no test can ever read or write the
/// real `~/Library/Application Support/PomodoroCount/data.json`.
///
/// Sound is off by default: `logExternal` and friends play a system sound, and
/// a test run should not make forty pops. Pass `sound: true` to opt back in.
@MainActor
func makeModel(sound: Bool = false) -> (model: AppModel, url: URL) {
    let url = temporaryStoreURL()
    let model = AppModel(storeURL: url)
    model.settings.soundEnabled = sound
    return (model, url)
}

func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("pomodoro-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("data.json")
}

/// Writes `contents` to a fresh store path and returns it, for testing what the
/// app does with files it did not write itself.
func storeURL(containing contents: String) throws -> URL {
    let url = temporaryStoreURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.data(using: .utf8)!.write(to: url)
    return url
}

extension Date {
    static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }
}
