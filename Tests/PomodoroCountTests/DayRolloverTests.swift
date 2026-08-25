import Testing
import Foundation
@testable import PomodoroCount

/// A break should not outlive the day it was earned in. The decision is
/// extracted from the notification handler so a fifth `Phase` case fails a
/// test here rather than quietly inheriting "do nothing" — the same reason
/// `StatusIcon.glyph` lives outside the drawing routine.
@MainActor
@Suite struct DayRolloverDecisionTests {

    /// Start of "today" for these cases, with the break stamped the day before.
    private var newDay: Date { Calendar.current.startOfDay(for: Date()) }
    private var yesterday: Date { newDay.addingTimeInterval(-3600) }

    @Test func anArmedBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakReady,
                                   breakEnteredOn: yesterday, newDay: newDay) == .resetToIdle)
    }

    @Test func aRunningBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakTime,
                                   breakEnteredOn: yesterday, newDay: newDay) == .resetToIdle)
    }

    /// Nothing to stop, but the cycle counter behind an idle timer is still
    /// yesterday's.
    @Test func idleRestartsTheCycle() {
        #expect(DayRollover.action(phase: .idle,
                                   breakEnteredOn: nil, newDay: newDay) == .restartCycle)
    }

    /// A focus session in progress at midnight is real work about to become a
    /// record. Ending it would destroy that — and its cycle counter is left
    /// alone too, so the wake-time race resolves the same way in either order.
    @Test func aFocusSessionIsLeftAlone() {
        #expect(DayRollover.action(phase: .work,
                                   breakEnteredOn: nil, newDay: newDay) == .none)
    }

    /// The wake-time race: a session running across a sleep that crosses
    /// midnight completes *on the new day*, and the wake that reports the day
    /// change is the same one that let it complete. A break armed then is not a
    /// leftover.
    @Test func aBreakArmedOnTheNewDayItselfSurvives() {
        #expect(DayRollover.action(phase: .breakReady,
                                   breakEnteredOn: newDay.addingTimeInterval(60),
                                   newDay: newDay) == .none)
    }

    @Test func aBreakWithNoStampIsTreatedAsALeftover() {
        #expect(DayRollover.action(phase: .breakTime,
                                   breakEnteredOn: nil, newDay: newDay) == .resetToIdle)
    }
}

/// The wiring: which notification-shaped events actually run the reset.
///
/// `handleDayChange` is called from two notifications, and only one of them
/// means the day changed. `didWakeNotification` fires on every wake — a
/// five-minute lid-close in the middle of a break included — so the reset is
/// gated on a stamp rather than on the call.
@MainActor
@Suite struct DayRolloverWiringTests {

    private func tomorrow() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    }

    @Test func aNewDayClearsAnArmedBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakReady, "precondition: a break is armed")

        m.handleDayChange(now: tomorrow())

        #expect(m.phase == .idle)
        #expect(!m.isRunning)
        #expect(m.remaining == 0)
    }

    @Test func aNewDayClearsARunningBreak() {
        let (m, _) = makeModel()
        m.startBreak()
        #expect(m.phase == .breakTime)

        m.handleDayChange(now: tomorrow())

        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func aNewDayLeavesARunningFocusSessionAlone() {
        let (m, _) = makeModel()
        m.startWork()

        m.handleDayChange(now: tomorrow())

        #expect(m.phase == .work)
        #expect(m.isRunning, "midnight must not throw away work in progress")
    }

    /// `autoStartBreak` has to be off, or taking the fourth break would zero
    /// the cycle counter itself and this would pass without the new code.
    @Test func aNewDayRestartsTheLongBreakCycle() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        for _ in 0..<4 {
            m.startWork()
            m.forceCompleteForTesting()
        }
        #expect(m.nextBreakIsLong, "precondition: a long break is owed")

        m.handleDayChange(now: tomorrow())

        #expect(!m.nextBreakIsLong)
    }

    /// The commonest overnight state is not an armed break but plain idle:
    /// yesterday's last break was taken or skipped, so the timer is at rest
    /// while the cycle counter still holds yesterday's sessions. Zeroing it
    /// only on the break phases left the first pomodoro of the morning earning
    /// a long break.
    @Test func aNewDayRestartsTheLongBreakCycleFromIdle() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        for _ in 0..<3 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()                       // break taken or skipped: back to idle
        }
        #expect(m.phase == .idle, "precondition: at rest overnight")

        m.handleDayChange(now: tomorrow())

        m.startWork()
        m.forceCompleteForTesting()
        #expect(!m.nextBreakIsLong,
                "the first pomodoro of a new day cannot earn the long break")
    }

    /// The other half of the same rule: restarting the cycle must not reach a
    /// break that survived the rollover. A long break armed just after midnight
    /// is owed at its full length, and zeroing the counter under it would
    /// silently shorten the break the panel is already promising.
    @Test func aLongBreakArmedOnTheNewDayKeepsItsLength() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.longBreakMinutes = 30
        for _ in 0..<4 {
            m.startWork()
            m.forceCompleteForTesting()
            if m.phase == .breakReady && !m.nextBreakIsLong { m.reset() }
        }
        #expect(m.phase == .breakReady && m.nextBreakIsLong,
                "precondition: a long break is armed")

        let tomorrow = tomorrow()
        m.breakEnteredOn = tomorrow
        m.handleDayChange(now: tomorrow)

        #expect(m.nextBreakIsLong)
        #expect(m.armedBreakMinutes == 30)
    }

    /// The wake-from-a-nap case, and the reason the stamp exists at all.
    @Test func wakingLaterTheSameDayLeavesTheBreakRunning() {
        let (m, _) = makeModel()
        m.startBreak()

        m.handleDayChange(now: Date().addingTimeInterval(300))

        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
    }

    /// Pins the behaviour the count already has: it is derived from dated
    /// records, so yesterday's do not show up in today's tally.
    @Test func yesterdaysRecordsDoNotCountToday() {
        let (m, _) = makeModel()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        m.records.append(Record(at: yesterday, source: "manual", category: nil))

        m.handleDayChange()

        #expect(m.todayCount == 0)
    }

    /// The race, through the model rather than the pure function: the break was
    /// armed after midnight, so the same wake that reports the new day must not
    /// wipe it. Written by setting the stamp directly — `complete()` reads the
    /// real clock, which a test cannot move.
    @Test func aBreakArmedAfterMidnightSurvivesTheSameRollover() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakReady, "precondition: a break is armed")

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        m.breakEnteredOn = tomorrow
        m.handleDayChange(now: tomorrow)

        #expect(m.phase == .breakReady, "a break earned on the new day is not a leftover")
    }

    /// The stamp is set on the way into a break and cleared on the way out, so
    /// a stale value can never make a later break look like a leftover.
    @Test func theBreakStampIsClearedWhenTheTimerStops() {
        let (m, _) = makeModel()
        m.startBreak()
        #expect(m.breakEnteredOn != nil)
        m.reset()
        #expect(m.breakEnteredOn == nil)
    }

    /// The other way out of a break: it runs to its end rather than being
    /// stopped. `breakEnteredOn` promises nil off a break, and both exits have
    /// to keep that promise.
    @Test func theBreakStampIsClearedWhenABreakCompletes() {
        let (m, _) = makeModel()
        m.startBreak()
        #expect(m.breakEnteredOn != nil)
        m.forceCompleteForTesting()
        #expect(m.phase == .idle, "precondition: the break finished")
        #expect(m.breakEnteredOn == nil)
    }
}
