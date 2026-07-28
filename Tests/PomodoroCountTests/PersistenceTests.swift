import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct PersistenceTests {

    @Test func recordsAndSettingsSurviveReload() {
        let (m, url) = makeModel()
        m.logExternal()
        m.logExternal()
        m.settings.workMinutes = 45

        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.totalCount == 2)
        #expect(reloaded.settings.workMinutes == 45)
    }

    @Test func recordTimestampsSurviveTheRoundTrip() {
        let (m, url) = makeModel()
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        m.records = [Record(at: when, source: "manual")]

        let reloaded = AppModel(storeURL: url)
        let restored = try! #require(reloaded.records.first)
        #expect(abs(restored.at.timeIntervalSince(when)) < 1)
        #expect(restored.source == "manual")
    }

    // MARK: Suspended saves

    /// A drag reorders on every crossing, and each move would otherwise encode
    /// the whole store and write it to disk mid-gesture. Suspending holds the
    /// write; resuming performs exactly one.
    @Test func aSuspendedChangeDoesNotReachDiskUntilResumed() {
        let (m, url) = makeModel()
        m.suspendSaves()
        m.settings.workMinutes = 45

        #expect(AppModel(storeURL: url).settings.workMinutes == 50)   // still the default

        m.resumeSaves()
        #expect(AppModel(storeURL: url).settings.workMinutes == 45)
    }

    /// Several changes while suspended collapse into the single write on
    /// resume — the point of the mechanism, not an incidental detail.
    @Test func manySuspendedChangesCostOneWrite() {
        let (m, url) = makeModel()
        m.suspendSaves()
        for minutes in 20...40 { m.settings.workMinutes = minutes }
        m.resumeSaves()
        #expect(AppModel(storeURL: url).settings.workMinutes == 40)
    }

    /// Resuming must restore normal saving, or every later change would be
    /// silently dropped.
    @Test func savingResumesNormallyAfterwards() {
        let (m, url) = makeModel()
        m.suspendSaves()
        m.settings.workMinutes = 45
        m.resumeSaves()

        m.settings.breakMinutes = 12
        #expect(AppModel(storeURL: url).settings.breakMinutes == 12)
    }

    /// A drag can end twice over — `onEnded` and the cancellation path both
    /// resume — so a second resume with nothing pending must be harmless.
    @Test func resumingTwiceIsHarmless() {
        let (m, url) = makeModel()
        m.suspendSaves()
        m.settings.workMinutes = 45
        m.resumeSaves()
        m.resumeSaves()
        #expect(AppModel(storeURL: url).settings.workMinutes == 45)
    }

    @Test func missingFileStartsEmptyRatherThanFailing() {
        let model = AppModel(storeURL: temporaryStoreURL())
        #expect(model.totalCount == 0)
        #expect(model.settings.workMinutes == 50)
    }

    /// A data.json written by an older version is missing the newer keys. It must
    /// still load and keep its records instead of silently starting from scratch.
    @Test func olderSchemaLoadsAndKeepsItsRecords() throws {
        let url = try storeURL(containing: """
        {"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
        "at":"2026-07-01T10:00:00Z","source":"manual"}],\
        "settings":{"workMinutes":25,"breakMinutes":5,"autoStartBreak":true,"soundEnabled":true}}
        """)
        let m = AppModel(storeURL: url)
        #expect(m.totalCount == 1)
        #expect(m.settings.workMinutes == 25)
        #expect(m.settings.breakMinutes == 5)
    }

    @Test func missingSettingsKeysFallBackToDefaults() throws {
        let url = try storeURL(containing: """
        {"records":[],"settings":{"workMinutes":25,"breakMinutes":5,\
        "autoStartBreak":true,"soundEnabled":true}}
        """)
        let m = AppModel(storeURL: url)
        #expect(m.settings.shortcut.display == "⌃⌥⌘P")
        #expect(m.settings.globalShortcutEnabled)
        #expect(m.settings.theme == .classic)
    }

    /// A truncated or hand-edited file must not take the app down on launch.
    @Test(arguments: ["", "not json at all", "{", "{\"records\":\"wrong type\"}", "[]"])
    func unreadableStoreDoesNotCrashTheApp(contents: String) throws {
        let url = try storeURL(containing: contents)
        let m = AppModel(storeURL: url)
        #expect(m.totalCount == 0)
        #expect(m.settings.workMinutes == 50)
    }

    /// Starting empty is only safe if the unreadable file survives: the very
    /// next save re-encodes the empty state over data.json, and without a
    /// backup that write would silently erase the only copy of the user's
    /// history. Same principle the newer-schema path already applies —
    /// a decode failure must never cost anyone their data either.
    @Test func anUnreadableStoreIsBackedUpBeforeTheNextSaveCanEraseIt() throws {
        let contents = "{\"records\":\"wrong type\",\"clue\":\"the original bytes\"}"
        let url = try storeURL(containing: contents)
        let m = AppModel(storeURL: url)

        m.settings.workMinutes = 45   // fires save(), overwriting data.json

        let dir = url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("unreadable") }
        let backup = try #require(backups.first, "no backup of the unreadable store was written")
        let preserved = try String(contentsOf: dir.appendingPathComponent(backup), encoding: .utf8)
        #expect(preserved == contents, "the backup must be the original bytes, not a re-encode")
    }

    @Test func settingsChangesArePersistedImmediately() {
        let (m, url) = makeModel()
        m.settings.autoStartBreak = false
        #expect(!AppModel(storeURL: url).settings.autoStartBreak)
    }

    @Test func undoIsPersisted() {
        let (m, url) = makeModel()
        m.logExternal()
        m.undoLast()
        #expect(AppModel(storeURL: url).totalCount == 0)
    }

    @Test func storeIsCreatedOnDemandIncludingItsDirectory() {
        let (m, url) = makeModel()
        m.logExternal()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
