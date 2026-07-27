import Testing
import Foundation
@testable import PomodoroCount

/// The menu bar item is the whole app for most of its life, and its width is
/// space taken from every other status item.
@MainActor
@Suite struct MenuBarTests {

    @Test func countIsShownWhileIdleByDefault() {
        let (m, _) = makeModel()
        m.logExternal()
        #expect(m.settings.showsCountInMenuBar)
        #expect(m.statusText == "1")
    }

    @Test func turningTheCountOffLeavesTheItemIconOnly() {
        let (m, _) = makeModel()
        m.logExternal()
        m.settings.showsCountInMenuBar = false
        #expect(m.statusText == "")
    }

    /// The countdown is the reason to give up the width, so it stays.
    @Test func theTimerStillShowsWithTheCountOff() {
        let (m, _) = makeModel()
        m.settings.showsCountInMenuBar = false
        m.startWork()
        #expect(m.statusText.contains(":"))
        m.startBreak()
        #expect(m.statusText.contains(":"))
    }

    @Test func iconOnlyIsNarrowerAndDropsTheTextGap() {
        let withCount = StatusIcon.render(phase: .idle, running: false, text: "8")
        let iconOnly = StatusIcon.render(phase: .idle, running: false, text: "")
        #expect(iconOnly.size.width < withCount.size.width)
        // Icon plus nothing: no leftover padding for text that isn't drawn.
        #expect(iconOnly.size.width == 15)
    }

    /// Hiding the count visually must not hide it from VoiceOver.
    @Test func voiceOverStillAnnouncesTheCountWhenHidden() {
        let (m, _) = makeModel()
        m.logExternal()
        m.logExternal()
        m.settings.showsCountInMenuBar = false
        #expect(m.statusText == "")
        #expect(m.statusDescription.contains("2 pomodoros today"))
        #expect(m.statusImage.accessibilityDescription == m.statusDescription)
    }

    @Test func iconOnlyImageIsStillATemplate() {
        let image = StatusIcon.render(phase: .idle, running: false, text: "")
        #expect(image.isTemplate)
        #expect(image.size.height > 0)
    }

    @Test func anEmptyIconStillHasAnAccessibleName() {
        let image = StatusIcon.render(phase: .idle, running: false, text: "")
        #expect(image.accessibilityDescription == "Pomodoro Count")
    }

    @Test func thePreferencePersists() {
        let (m, url) = makeModel()
        m.settings.showsCountInMenuBar = false
        #expect(!AppModel(storeURL: url).settings.showsCountInMenuBar)
    }

    /// Existing installs must not silently lose their count.
    @Test func filesWithoutThePreferenceDefaultToShowingTheCount() throws {
        let url = try storeURL(containing: #"{"records":[],"settings":{"workMinutes":25}}"#)
        #expect(AppModel(storeURL: url).settings.showsCountInMenuBar)
    }
}

@MainActor
@Suite struct FirstLaunchTests {

    @Test func aBrandNewInstallIsAFirstLaunch() {
        let model = AppModel(storeURL: temporaryStoreURL())
        #expect(model.isFirstLaunch)
    }

    /// The welcome must happen exactly once, including when the user does
    /// nothing at all on that first run — so it has to write the store itself.
    @Test func markLaunchedMakesTheNextLaunchOrdinary() {
        let url = temporaryStoreURL()
        let first = AppModel(storeURL: url)
        #expect(first.isFirstLaunch)
        first.markLaunched()
        #expect(!first.isFirstLaunch)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!AppModel(storeURL: url).isFirstLaunch)
    }

    @Test func anExistingInstallIsNeverAFirstLaunch() throws {
        let url = try storeURL(containing: #"{"records":[],"settings":{}}"#)
        #expect(!AppModel(storeURL: url).isFirstLaunch)
    }

    /// Upgrading must not re-trigger the welcome for someone with history.
    @Test func upgradingFromAnOlderVersionIsNotAFirstLaunch() throws {
        let url = try storeURL(containing: """
        {"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
        "at":"2026-07-01T10:00:00Z","source":"manual"}],\
        "settings":{"workMinutes":25,"breakMinutes":5}}
        """)
        let m = AppModel(storeURL: url)
        #expect(!m.isFirstLaunch)
        #expect(m.totalCount == 1)
    }
}
