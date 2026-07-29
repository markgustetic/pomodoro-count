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

    // MARK: Goal progress in the item

    /// The pips only exist where goals do: categories on and a positive total.
    @Test func goalProgressIsAbsentWithoutGoals() {
        let (m, _) = makeModel()
        #expect(m.menuBarGoalProgress == nil)

        m.settings.categoriesEnabled = true
        #expect(m.menuBarGoalProgress == nil, "no goals set means nothing to show")
    }

    @Test func goalProgressReportsTheDayAgainstTheWholeGoal() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Deep work", dailyGoal: 3)]
        m.settings.fallbackGoal = 1
        m.logExternal(to: .named("Deep work"))
        m.logExternal()

        let progress = m.menuBarGoalProgress
        #expect(progress?.done == 2)
        #expect(progress?.goal == 4)
    }

    /// Progress participates in the render: a changed count must not be
    /// served the previous image, and the drawn pixels must actually differ.
    @Test func goalProgressChangesTheRenderedImage() {
        let none = StatusIcon.render(phase: .idle, running: false, text: "2")
        let some = StatusIcon.render(phase: .idle, running: false, text: "2",
                                     goalProgress: (done: 2, goal: 4))
        let more = StatusIcon.render(phase: .idle, running: false, text: "2",
                                     goalProgress: (done: 3, goal: 4))
        #expect(some !== none)
        #expect(more !== some)
        #expect(some.tiffRepresentation != none.tiffRepresentation)
        #expect(more.tiffRepresentation != some.tiffRepresentation)
    }

    /// The timer fires every 0.5s but `ceil` moves the countdown text only
    /// once a second, so half of all renders repeat the previous inputs
    /// exactly. Those must return the cached image, not redraw an identical
    /// one — the item is live for the whole of every session.
    @Test func renderingTheSameInputsReturnsTheCachedImage() {
        let first = StatusIcon.render(phase: .work, running: true, text: "12:34", description: "Focus")
        let second = StatusIcon.render(phase: .work, running: true, text: "12:34", description: "Focus")
        #expect(first === second)

        let moved = StatusIcon.render(phase: .work, running: true, text: "12:33", description: "Focus")
        #expect(moved !== first)
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
