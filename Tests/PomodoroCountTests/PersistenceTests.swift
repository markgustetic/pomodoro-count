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
