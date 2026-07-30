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

    /// The drag's cancellation path can resume with no burst in flight at all,
    /// so the depth must not go below zero. A negative depth would leave the
    /// next `suspendSaves()` back at zero, suspending nothing — the harm lands
    /// on the *following* drag, which is why resuming twice looks harmless on
    /// its own and this case has to be checked separately.
    @Test func anExtraResumeDoesNotBreakTheNextSuspension() {
        let (m, url) = makeModel()
        m.resumeSaves()                                               // a cancellation, nothing in flight

        m.suspendSaves()                                              // the next drag
        m.settings.workMinutes = 45
        #expect(AppModel(storeURL: url).settings.workMinutes == 50,
                "the next suspension held nothing")

        m.resumeSaves()
        #expect(AppModel(storeURL: url).settings.workMinutes == 45)
    }

    /// Bursts nest for real: the global hotkey and the `pomodorocount://log` URL
    /// both land a record — bracketed by their own suspend/resume — while a
    /// reorder drag is holding one open. The inner resume belongs to the log,
    /// not to the drag, so it must not perform the drag's held write.
    @Test func anInnerResumeDoesNotPerformTheOuterHeldWrite() {
        let (m, url) = makeModel()
        m.suspendSaves()                                              // the drag
        m.settings.workMinutes = 45

        m.suspendSaves()                                              // an external log arrives
        m.resumeSaves()

        #expect(AppModel(storeURL: url).settings.workMinutes == 50,
                "the drag's write reached disk on the log's resume")

        m.resumeSaves()                                               // the drag ends
        #expect(AppModel(storeURL: url).settings.workMinutes == 45)
    }

    /// The stutter this mechanism exists to prevent: once an inner burst has
    /// resumed, the outer one is still in flight, and every later change it
    /// makes — a row crossing, in the drag's case — must stay held rather than
    /// encoding the whole store to disk synchronously on the main actor.
    @Test func changesAfterAnInnerResumeAreStillHeld() {
        let (m, url) = makeModel()
        m.suspendSaves()                                              // the drag
        m.suspendSaves()                                              // an external log arrives
        m.resumeSaves()

        m.settings.workMinutes = 45                                   // a later row crossing
        #expect(AppModel(storeURL: url).settings.workMinutes == 50,
                "a change mid-drag wrote straight to disk")

        m.resumeSaves()                                               // the drag ends
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
        #expect(m.settings.autoAdvanceTarget)
        // An older data.json carries neither key. Decoding them to these
        // defaults is what makes the first launch after this ships re-aim once
        // — a nil stamp reads as "the day turned over" — rather than needing a
        // migration step of its own.
        #expect(!m.settings.targetPinned)
        #expect(m.settings.targetAimedOn == nil)
    }

    /// The pin and the day stamp both survive a relaunch: a pin the user set
    /// this morning must still hold after lunch, and a stamp that didn't
    /// persist would make every launch look like a new day.
    @Test func theTargetPinAndDayStampRoundTrip() {
        let (m, url) = makeModel()
        let stamp = Date(timeIntervalSince1970: 1_780_000_000)
        m.settings.targetPinned = true
        m.settings.targetAimedOn = stamp
        let reloaded = AppModel(storeURL: url).settings
        #expect(reloaded.targetPinned)
        #expect(reloaded.targetAimedOn == stamp)
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
