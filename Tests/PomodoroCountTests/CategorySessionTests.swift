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

    @Test func theTargetDefaultsToAutomaticNotTheBucket() {
        let m = configured()
        // Unset falls to the default chain, not an explicit request for the
        // bucket — with the bucket on (as here) that chain still reaches it.
        #expect(m.sessionTarget == .automatic)
        #expect(m.resolve(m.sessionTarget) == nil)
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

    /// An archived target must not strand the session's pomodoro.
    @Test func anArchivedTargetFallsBackToTheDefaultChain() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categories.removeAll { $0.name == "Music" }
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == nil)   // bucket is on
    }

    /// This is the case that actually discriminates between the old bug and
    /// the fix: with the bucket switched off, an archived (or unset) target
    /// must credit the marked default, not the bucket the user turned off.
    @Test func anArchivedTargetWithTheBucketOffCreditsTheDefaultNotTheBucket() {
        let m = configured()
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Work"
        m.sessionTarget = .named("Music")
        m.settings.categories.removeAll { $0.name == "Music" }
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Work")
    }

    @Test func aBreakCreditsNothing() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.startBreak()
        m.forceCompleteForTesting()
        #expect(m.records.isEmpty)
    }
}
