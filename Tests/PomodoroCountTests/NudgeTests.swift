import Testing
import Foundation
@testable import PomodoroCount

/// The end-of-day nudge: one optional notification at a chosen hour when the
/// day's goal is unmet. The message decision and the next-fire arithmetic are
/// the tested pieces; the timer and notification are thin adapters over them.
@MainActor
@Suite struct NudgeTests {

    // MARK: What the nudge says

    @Test func saysHowManyToGoWhenGoalsAreUnmet() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Deep work", dailyGoal: 3)]
        m.settings.fallbackGoal = 1
        m.logExternal(to: .named("Deep work"))
        #expect(m.nudgeMessage() == "3 to go to hit today's goal.")
    }

    @Test func staysQuietOnceTheGoalIsMet() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Deep work", dailyGoal: 1)]
        m.logExternal(to: .named("Deep work"))
        #expect(m.nudgeMessage() == nil)
    }

    @Test func singularWhenOneRemains() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Deep work", dailyGoal: 2)]
        m.logExternal(to: .named("Deep work"))
        #expect(m.nudgeMessage() == "1 to go to hit today's goal.")
    }

    /// Without goals there is still a day worth not losing: an empty day
    /// nudges, a day with anything logged does not.
    @Test func withoutGoalsAnEmptyDayNudges() {
        let (m, _) = makeModel()
        #expect(m.nudgeMessage() == "No pomodoros logged today.")
    }

    @Test func withoutGoalsALoggedDayStaysQuiet() {
        let (m, _) = makeModel()
        m.logExternal()
        #expect(m.nudgeMessage() == nil)
    }

    /// Categories off means goals are invisible, so they must not drive the
    /// message even if old settings still carry numbers.
    @Test func hiddenGoalsDoNotCount() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = false
        m.settings.categories = [Category(name: "Old", dailyGoal: 5)]
        m.logExternal()
        #expect(m.nudgeMessage() == nil)
    }

    // MARK: When it fires

    @Test func firesLaterTodayWhenTheHourIsAhead() {
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let next = AppModel.nextNudgeDate(hour: 18, after: now)
        #expect(cal.isDate(next, inSameDayAs: now))
        #expect(cal.component(.hour, from: next) == 18)
    }

    @Test func firesTomorrowWhenTheHourHasPassed() {
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        let next = AppModel.nextNudgeDate(hour: 18, after: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        #expect(cal.isDate(next, inSameDayAs: tomorrow))
        #expect(cal.component(.hour, from: next) == 18)
    }

    // MARK: Persistence

    @Test func offByDefaultAndSurvivesReload() {
        let (m, url) = makeModel()
        #expect(m.settings.nudgeHour == nil)
        m.settings.nudgeHour = 18
        #expect(AppModel(storeURL: url).settings.nudgeHour == 18)
    }
}
