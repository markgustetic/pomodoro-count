import Testing
import Foundation
@testable import PomodoroCount

/// A focus session is dated when it ended, not when the app noticed.
///
/// The countdown is a wall-clock end date checked on a tick, and a sleeping Mac
/// does not tick. A session started at 23:00 with the lid shut at 23:20 ran out
/// at 23:50 — and was recorded at 07:00 the next morning, when the first tick
/// after the wake found it overdue. That put it on the wrong day: today's count
/// read 1 before any work, yesterday lost a pomodoro and possibly its streak,
/// and a one-time task the session was aimed at collected a record on a day the
/// task no longer existed.
@MainActor
@Suite struct OverdueSessionTests {

    // MARK: The rule

    @Test func anOverdueSessionEndedWhenItsClockRanOut() {
        let now = Date()
        let scheduled = now.addingTimeInterval(-7 * 3600)
        #expect(AppModel.sessionEnd(scheduled: scheduled, now: now) == scheduled)
    }

    /// Never the future. `forceCompleteForTesting()` and a tick that lands a
    /// hair early both complete a session whose end date is still ahead, and a
    /// record dated later than now would sort above everything logged after it.
    @Test func aSessionCannotEndInTheFuture() {
        let now = Date()
        #expect(AppModel.sessionEnd(scheduled: now.addingTimeInterval(600), now: now) == now)
    }

    @Test func noScheduledEndMeansNow() {
        let now = Date()
        #expect(AppModel.sessionEnd(scheduled: nil, now: now) == now)
    }

    // MARK: Through the model

    @Test func aSessionThatRanOutHoursAgoIsDatedThen() {
        let (m, _) = makeModel()
        m.startWork()
        let ended = Date().addingTimeInterval(-3 * 3600)

        m.forceCompleteForTesting(endedAt: ended)

        #expect(m.records.count == 1)
        #expect(m.records.first?.at == ended)
        #expect(m.records.first?.source == "timer")
    }

    @Test func aSessionThatRanOutYesterdayCountsForYesterday() {
        let (m, _) = makeModel()
        m.startWork()

        m.forceCompleteForTesting(endedAt: Date.daysAgo(1))

        #expect(m.records.count == 1)
        #expect(m.todayCount == 0, "this morning must not open with a pomodoro already on it")
        #expect(m.totalCount == 1)
    }

    @Test func aSessionThatCompletesOnTimeIsDatedNow() {
        let (m, _) = makeModel()
        let before = Date()
        m.startWork()

        m.forceCompleteForTesting()

        let at = try! #require(m.records.first?.at)
        #expect(at >= before && at <= Date())
    }

    /// The cup ends a session early, so there is no clock that ran out: the
    /// session ended when the button was pressed.
    @Test func restingNowDatesTheSessionAtThePress() {
        let (m, _) = makeModel()
        let before = Date()
        m.startWork()

        m.restNow()

        let at = try! #require(m.records.first?.at)
        #expect(at >= before && at <= Date())
        m.reset()
    }

    /// The case that made the old stamp visibly wrong. The sweep leaves a task
    /// alone while its session runs precisely so this record can credit it —
    /// and the record then has to land on the task's own day, not on the day
    /// after it expired.
    @Test func aTaskCarriedPastMidnightIsCreditedOnItsOwnDay() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.addTask(name: "Ship it", goal: 1, now: Date.daysAgo(1))
        m.startWork()
        let ended = Date.daysAgo(1)

        m.forceCompleteForTesting(endedAt: ended)

        #expect(m.records.first?.category == "Ship it")
        #expect(m.records.first?.at == ended)
        #expect(!m.categoryExists("Ship it"), "the task still leaves once its session is logged")
    }

    // MARK: What the banner says

    /// "That's 0 today" under "Pomodoro complete" would read as a bug. A
    /// session that landed on an earlier day says where it went instead.
    @Test func theBannerDoesNotQuoteTodaysCountForAnEarlierDay() {
        let armed = AppModel.completionBody(count: 0, breakArmed: true, countedToday: false)
        let plain = AppModel.completionBody(count: 0, breakArmed: false, countedToday: false)
        #expect(!armed.contains("today"))
        #expect(!plain.contains("today"))
        #expect(armed.contains("break"), "an armed break is still the news")
        #expect(!plain.contains("break"))
    }

    @Test func theBannerIsUnchangedForASessionThatCountsToday() {
        #expect(AppModel.completionBody(count: 4, breakArmed: true, countedToday: true)
                == AppModel.completionBody(count: 4, breakArmed: true))
        #expect(AppModel.completionBody(count: 4, breakArmed: false, countedToday: true)
                == AppModel.completionBody(count: 4, breakArmed: false))
    }
}
