import Testing
import Foundation
@testable import PomodoroCount

/// A break should not outlive the day it was earned in. The decision is
/// extracted from the notification handler so a fifth `Phase` case fails a
/// test here rather than quietly inheriting "do nothing" — the same reason
/// `StatusIcon.glyph` lives outside the drawing routine.
@MainActor
@Suite struct DayRolloverDecisionTests {

    @Test func anArmedBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakReady) == .resetToIdle)
    }

    @Test func aRunningBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakTime) == .resetToIdle)
    }

    @Test func idleIsLeftAlone() {
        #expect(DayRollover.action(phase: .idle) == .none)
    }

    /// A focus session in progress at midnight is real work about to become a
    /// record. Ending it would destroy that.
    @Test func aFocusSessionIsLeftAlone() {
        #expect(DayRollover.action(phase: .work) == .none)
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
}
