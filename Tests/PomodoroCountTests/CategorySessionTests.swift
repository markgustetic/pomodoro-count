import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategorySessionTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        return m
    }

    @Test func anUnsetTargetIsTheBucket() {
        let m = configured()
        #expect(m.sessionTarget == .fallback)
        #expect(m.resolve(m.sessionTarget) == nil)
        #expect(m.sessionTargetLabel == m.settings.fallbackName)
    }

    @Test func settingTheTargetPersistsIt() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.sessionTarget = .named("Work")
        #expect(AppModel(storeURL: url).settings.sessionTargetName == "Work")
    }

    @Test func aFinishedSessionCreditsItsTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.records.last?.source == "timer")
    }

    /// An archived target must not keep receiving pomodoros, and must not
    /// strand the session's one either. It falls to the bucket, the only
    /// destination an unset target has.
    @Test func anArchivedTargetCreditsTheBucket() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categories.removeAll { $0.name == "Music" }
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == nil)
    }

    @Test func aBreakCreditsNothing() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.startBreak()
        m.forceCompleteForTesting()
        #expect(m.records.isEmpty)
    }
}
