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

    // MARK: A reminder that came due while nobody was looking

    /// The timer cannot be trusted to fire at the hour: a sleeping Mac runs no
    /// timers, and one armed for 18:00 fires whenever the machine next gets
    /// round to it. So the decision is taken from the clock, not from the fact
    /// of firing. All of these sit two days out so the real timer the model
    /// arms along the way is never due during a test run.
    private let day = Calendar.current.date(
        byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: Date()))!
    private func at(_ hour: Int, daysLater: Int = 0) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: daysLater, to: day)!
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    @Test func withNothingArmedThereIsNothingToDo() {
        #expect(NudgeDue.action(due: nil, now: at(19)) == .wait)
    }

    @Test func aReminderStillAheadWaits() {
        #expect(NudgeDue.action(due: at(18), now: at(10)) == .wait)
    }

    @Test func aReminderIsDeliveredOnTheHour() {
        #expect(NudgeDue.action(due: at(18), now: at(18)) == .deliver)
    }

    /// Lid shut at 17:00, opened at 19:00. Late, but still about today.
    @Test func aReminderMissedEarlierTheSameDayIsDeliveredLate() {
        #expect(NudgeDue.action(due: at(18), now: at(19)) == .deliver)
    }

    /// Lid shut at 17:00, opened at 08:00. "3 to go to hit today's goal" would
    /// now be counting a day that has barely started.
    @Test func aReminderFromAnEarlierDayIsDropped() {
        #expect(NudgeDue.action(due: at(18), now: at(8, daysLater: 1)) == .skip)
    }

    @Test func wakingTheSameEveningDeliversTheMissedReminderOnce() {
        let (m, _) = makeModel()
        defer { m.nudgeTimer?.invalidate() }
        m.settings.nudgeHour = 18
        m.scheduleNudge(now: at(10))

        #expect(m.settleNudge(now: at(19)) == "No pomodoros logged today.")
        #expect(m.nudgeDue == at(18, daysLater: 1), "and tomorrow's is armed")
        #expect(m.settleNudge(now: at(19)) == nil, "the timer and the wake must not both deliver it")
    }

    @Test func wakingTheNextMorningStaysQuietAndArmsThatEvening() {
        let (m, _) = makeModel()
        defer { m.nudgeTimer?.invalidate() }
        m.settings.nudgeHour = 18
        m.scheduleNudge(now: at(10))

        #expect(m.settleNudge(now: at(8, daysLater: 1)) == nil)
        #expect(m.nudgeDue == at(18, daysLater: 1))
    }

    @Test func wakingBeforeTheHourOnlyRearms() {
        let (m, _) = makeModel()
        defer { m.nudgeTimer?.invalidate() }
        m.settings.nudgeHour = 18
        m.scheduleNudge(now: at(10))

        #expect(m.settleNudge(now: at(12)) == nil)
        #expect(m.nudgeDue == at(18))
    }

    @Test func turningTheReminderOffLeavesNothingDue() {
        let (m, _) = makeModel()
        defer { m.nudgeTimer?.invalidate() }
        m.settings.nudgeHour = 18
        m.scheduleNudge(now: at(10))

        m.setNudgeHour(nil)
        #expect(m.nudgeDue == nil)
        #expect(m.settleNudge(now: at(19)) == nil)
    }

    // MARK: Persistence

    @Test func offByDefaultAndSurvivesReload() {
        let (m, url) = makeModel()
        #expect(m.settings.nudgeHour == nil)
        m.settings.nudgeHour = 18
        #expect(AppModel(storeURL: url).settings.nudgeHour == 18)
    }
}
