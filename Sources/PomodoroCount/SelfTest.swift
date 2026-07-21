import Foundation
import AppKit
import Carbon.HIToolbox

/// Lightweight in-process checks against the real `AppModel`. Run with
/// `swift run PomodoroCount --selftest`. Exits 0 if all pass, 1 otherwise.
/// (Command Line Tools ship no XCTest/Testing module, so this stands in.)
enum SelfTest {
    @MainActor
    static func run() {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            if condition {
                print("  ✓ \(label)")
            } else {
                print("  ✗ FAIL: \(label)")
                failures += 1
            }
        }

        func freshModel() -> (AppModel, URL) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pomo-selftest-\(UUID().uuidString)")
                .appendingPathComponent("data.json")
            return (AppModel(storeURL: url), url)
        }

        print("Pomodoro Count self-test\n")

        // Defaults
        do {
            let (m, _) = freshModel()
            check(m.settings.workMinutes == 50, "default focus is 50 min")
            check(m.settings.breakMinutes == 10, "default break is 10 min")
            check(m.todayCount == 0, "starts with zero today")
        }

        // External logging — the headline feature
        do {
            let (m, _) = freshModel()
            m.logExternal(); m.logExternal(); m.logExternal()
            check(m.todayCount == 3, "logExternal x3 → today = 3")
            check(m.totalCount == 3, "logExternal x3 → total = 3")
            check(m.records.allSatisfy { $0.source == "manual" }, "external logs marked 'manual'")
        }

        // Undo
        do {
            let (m, _) = freshModel()
            m.logExternal(); m.logExternal()
            m.undoLast()
            check(m.todayCount == 1, "undoLast removes one")
            m.undoLast(); m.undoLast()   // second removes last, third is a no-op
            check(m.todayCount == 0, "undoLast on empty is safe")
        }

        // Persistence round-trip
        do {
            let (m, url) = freshModel()
            m.logExternal(); m.logExternal()
            m.settings.workMinutes = 45
            let reloaded = AppModel(storeURL: url)
            check(reloaded.totalCount == 2, "records survive reload")
            check(reloaded.settings.workMinutes == 45, "settings survive reload")
        }

        // Shortcut defaults + round-trip
        do {
            let (m, url) = freshModel()
            check(m.settings.shortcut.display == "⌃⌥⌘P", "default shortcut is ⌃⌥⌘P")
            m.updateShortcut(Shortcut(keyCode: 49, carbonModifiers: UInt32(cmdKey | shiftKey), label: "Space"))
            let reloaded = AppModel(storeURL: url)
            check(reloaded.settings.shortcut.display == "⇧⌘Space", "custom shortcut persists")
        }

        // Backward compatibility: a data.json from an older version (no shortcut
        // / no globalShortcutEnabled keys) must still load and keep its records.
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pomo-selftest-\(UUID().uuidString)")
                .appendingPathComponent("data.json")
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let oldJSON = """
            {"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
            "at":"2026-07-01T10:00:00Z","source":"manual"}],\
            "settings":{"workMinutes":25,"breakMinutes":5,"autoStartBreak":true,"soundEnabled":true}}
            """
            try? oldJSON.data(using: .utf8)!.write(to: url)
            let m = AppModel(storeURL: url)
            check(m.totalCount == 1, "old data.json records survive schema change")
            check(m.settings.workMinutes == 25, "old settings survive schema change")
            check(m.settings.shortcut.display == "⌃⌥⌘P", "missing shortcut key defaults")
            check(m.settings.globalShortcutEnabled == true, "missing flag defaults to true")
            check(m.settings.theme == .classic, "missing theme defaults to classic")
        }

        // Theme choice persists
        do {
            let (m, url) = freshModel()
            check(m.settings.theme == .classic, "theme starts on classic")
            m.settings.theme = .synthwave
            let reloaded = AppModel(storeURL: url)
            check(reloaded.settings.theme == .synthwave, "theme choice survives reload")
            check(reloaded.settings.theme.palette.neon, "synthwave palette is neon")
            check(!ThemeChoice.classic.palette.neon, "classic palette is not neon")
        }

        // History grouping & weekly window
        do {
            let (m, _) = freshModel()
            let cal = Calendar.current
            let today = Date()
            let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
            let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: today)!
            m.records = [
                Record(at: today, source: "manual"),
                Record(at: today, source: "timer"),
                Record(at: twoDaysAgo, source: "manual"),
                Record(at: tenDaysAgo, source: "manual"),
            ]
            check(m.history().count == 3, "history groups into 3 distinct days")
            check(m.history().first?.count == 2, "most-recent day counts 2")
            check(m.todayCount == 2, "today counts 2")
            check(m.weekCount == 3, "week window excludes the 10-day-old one")
            check(m.totalCount == 4, "total counts all 4")
        }

        // Daily rollover: yesterday's pomodoros don't count toward today,
        // but they remain in history.
        do {
            let (m, _) = freshModel()
            let cal = Calendar.current
            let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
            m.records = [
                Record(at: yesterday, source: "manual"),
                Record(at: yesterday, source: "timer"),
            ]
            check(m.todayCount == 0, "new day starts at 0 (yesterday excluded)")
            check(m.totalCount == 2, "yesterday's pomodoros stay in history")
            check(m.history().count == 1, "yesterday still appears in history")
        }

        // Every feedback sound must actually resolve on this system, or the
        // count would change silently.
        do {
            for sound in [AppModel.Sound.countUp, .countDown, .sessionDone, .breakOver] {
                check(NSSound(named: sound.rawValue) != nil,
                      "sound '\(sound.rawValue)' exists")
            }
        }

        // Timer transitions
        do {
            let (m, _) = freshModel()
            check(m.phase == .idle, "begins idle")
            m.startWork()
            check(m.phase == .work && m.isRunning, "startWork → running work")
            check(abs(m.remaining - 50 * 60) <= 1.0, "work starts near 50:00")
            m.pause()
            check(!m.isRunning && m.phase == .work, "pause keeps phase, stops clock")
            m.reset()
            check(m.phase == .idle && !m.isRunning, "reset → idle")
        }

        // Formatting
        do {
            check(AppModel.mmss(50 * 60) == "50:00", "mmss 3000 → 50:00")
            check(AppModel.mmss(9 * 60 + 5) == "9:05", "mmss 545 → 9:05")
            check(AppModel.mmss(-3) == "0:00", "mmss negative → 0:00")
        }

        print("\n\(failures == 0 ? "ALL PASSED ✅" : "\(failures) CHECK(S) FAILED ❌")")
        exit(failures == 0 ? 0 : 1)
    }
}
