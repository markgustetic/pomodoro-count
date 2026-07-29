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

    // MARK: Advancing to the next unfinished category

    /// The session that meets the goal still credits the target it ran against;
    /// only the *next* one goes somewhere new.
    @Test func meetingAGoalMovesTheTargetOnButNotThisRecord() {
        let m = configured()
        m.sessionTarget = .named("Music")        // goal 1, so this session meets it
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.sessionTarget == .named("Work"))
    }

    /// External hardware is the headline way pomodoros arrive here, so a log
    /// that fills the last slot has to move the target just as a session does.
    @Test func anExternalLogThatMeetsTheGoalMovesTheTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Work"))
    }

    /// Nothing re-checks the target at Start, which is what lets a deliberate
    /// re-pick of a finished category stick: the next session credits it. (It
    /// advances again straight after, having met the goal a second time.)
    @Test func aDeliberateRePickIsHonouredForTheNextSession() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))       // Music met; target moved to Work
        m.sessionTarget = .named("Music")        // the user insists
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
    }

    /// The day's whole plan is met, so there is nowhere to advance to and
    /// further pomodoros overshoot where they are.
    @Test func theTargetStaysPutWhenEveryGoalIsMet() {
        let m = configured()
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 1),
            Category(name: "Music", dailyGoal: 1),
        ]
        m.sessionTarget = .named("Work")
        m.logExternal(to: .named("Music"))       // Music met
        m.logExternal(to: .named("Work"))        // Work met, nothing left
        #expect(m.sessionTarget == .named("Work"))
    }

    /// Goals are invisible while categories are off and must not drive
    /// anything — the same rule `todayGoalTotal` follows.
    @Test func nothingAdvancesWhileCategoriesAreOff() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categoriesEnabled = false
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Music"))
    }

    @Test func nothingAdvancesWhenTheSettingIsOff() {
        let m = configured()
        m.settings.autoAdvanceTarget = false
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Music"))
    }
}
