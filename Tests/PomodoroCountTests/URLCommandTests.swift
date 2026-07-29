import Testing
import Foundation
@testable import PomodoroCount

/// pomodorocount://log[?category=Name] — the hardware door. Logging a
/// pomodoro from a Stream Deck button, a Shortcuts automation, or a script
/// is the app's whole reason to exist; the URL is how they knock.
@MainActor
@Suite struct URLCommandTests {

    // MARK: Parsing

    @Test func aPlainLogGoesToTheBucket() {
        #expect(URLCommand.parse(URL(string: "pomodorocount://log")!) == .log(category: nil))
    }

    @Test func aCategoryRidesTheQueryString() {
        let url = URL(string: "pomodorocount://log?category=Deep%20Work")!
        #expect(URLCommand.parse(url) == .log(category: "Deep Work"))
    }

    @Test func theSchemeIsCaseInsensitive() {
        #expect(URLCommand.parse(URL(string: "PomodoroCount://log")!) == .log(category: nil))
    }

    /// Automation tools title-case things they shouldn't. The host is no more
    /// case-significant than the scheme, and a silent no-op on LOG would be
    /// the worst kind of failure for a hardware button.
    @Test func theHostIsCaseInsensitiveToo() {
        #expect(URLCommand.parse(URL(string: "pomodorocount://LOG")!) == .log(category: nil))
        #expect(URLCommand.parse(URL(string: "pomodorocount://Log?category=X")!) == .log(category: "X"))
    }

    @Test func foreignSchemesAndUnknownCommandsParseToNothing() {
        #expect(URLCommand.parse(URL(string: "https://log")!) == nil)
        #expect(URLCommand.parse(URL(string: "pomodorocount://reset")!) == nil)
        #expect(URLCommand.parse(URL(string: "pomodorocount://")!) == nil)
    }

    // MARK: Handling

    @Test func handlingLogsOnePomodoro() {
        let (m, _) = makeModel()
        m.handle(URL(string: "pomodorocount://log")!)
        #expect(m.totalCount == 1)
        #expect(m.records.first?.category == nil)
    }

    @Test func aKnownCategoryReceivesTheRecord() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Deep Work", dailyGoal: 2)]
        m.handle(URL(string: "pomodorocount://log?category=Deep%20Work")!)
        #expect(m.records.first?.category == "Deep Work")
    }

    /// A URL is not allowed to invent categories or attach names the list
    /// doesn't hold — an unknown name logs to the bucket, never a new label.
    @Test func anUnknownCategoryFallsBackToTheBucket() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Deep Work", dailyGoal: 2)]
        m.handle(URL(string: "pomodorocount://log?category=Nonsense")!)
        #expect(m.totalCount == 1)
        #expect(m.records.first?.category == nil)
    }

    @Test func anUnparseableURLLogsNothing() {
        let (m, _) = makeModel()
        m.handle(URL(string: "pomodorocount://reset")!)
        #expect(m.totalCount == 0)
    }
}
