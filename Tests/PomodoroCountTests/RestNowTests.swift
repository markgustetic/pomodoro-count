import Testing
import Foundation
@testable import PomodoroCount

/// The cup button mid-session: the session counts as done and the break
/// starts, rather than the session being thrown away.
@MainActor
@Suite struct RestNowTests {

    @Test func restingMidSessionLogsTheSessionAndStartsTheBreak() {
        let (m, _) = makeModel()
        m.startWork()
        m.restNow()
        #expect(m.records.count == 1)
        #expect(m.records[0].source == "timer")
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
    }

    /// Paused is still mid-session; the press means the same thing.
    @Test func restingFromAPausedSessionLogsItToo() {
        let (m, _) = makeModel()
        m.startWork()
        m.pause()
        m.restNow()
        #expect(m.records.count == 1)
        #expect(m.phase == .breakTime)
    }

    /// Whatever `autoStartBreak` says, the cup was a request for the break
    /// itself, not for an armed one.
    @Test func restingStartsTheBreakEvenWithAutoStartOff() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.restNow()
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
    }

    /// A logged session advances the long-break cycle like any other.
    @Test func restingCountsTowardsTheLongBreak() {
        let (m, _) = makeModel()
        for _ in 0..<3 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()
        }
        m.startWork()
        m.restNow()
        #expect(m.currentBreakIsLong)
    }

    /// From idle there is no session to log: the cup just starts a break.
    @Test func restingFromIdleLogsNothing() {
        let (m, _) = makeModel()
        m.restNow()
        #expect(m.records.isEmpty)
        #expect(m.phase == .breakTime)
    }

    /// The cup is hidden in the break phases; a press that arrives anyway
    /// must not log a second session or restart the break.
    @Test func restingDuringABreakDoesNothing() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        m.restNow()
        #expect(m.records.count == 1)
        #expect(m.phase == .breakReady)
    }
}
