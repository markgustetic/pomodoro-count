import Testing
import Foundation
@testable import PomodoroCount

/// The classic pomodoro rhythm: every fourth completed focus session earns a
/// longer break. The cycle counts *completions* — an abandoned session earns
/// nothing — and restarts once the long break is taken.
@MainActor
@Suite struct LongBreakTests {

    @Test func defaultLongBreakIsFifteenMinutes() {
        #expect(Settings().longBreakMinutes == 15)
    }

    @Test func longBreakLengthSurvivesReload() {
        let (m, url) = makeModel()
        m.settings.longBreakMinutes = 25
        #expect(AppModel(storeURL: url).settings.longBreakMinutes == 25)
    }

    @Test func theFourthBreakIsLong() {
        let (m, _) = makeModel()
        m.settings.breakMinutes = 5
        m.settings.longBreakMinutes = 20
        m.settings.autoStartBreak = true

        for session in 1...3 {
            m.startWork()
            m.forceCompleteForTesting()
            #expect(abs(m.remaining - 5 * 60) <= 1, "break after session \(session) should be short")
            m.reset()
        }

        m.startWork()
        m.forceCompleteForTesting()
        #expect(abs(m.remaining - 20 * 60) <= 1, "the fourth break should be long")
    }

    @Test func aManualBreakWithNoCompletedSessionsIsShort() {
        let (m, _) = makeModel()
        m.settings.breakMinutes = 5
        m.settings.longBreakMinutes = 20
        m.startBreak()
        #expect(abs(m.remaining - 5 * 60) <= 1)
    }

    /// Taking the long break restarts the cycle: the fifth session's break is
    /// short again.
    @Test func theCycleRestartsAfterALongBreak() {
        let (m, _) = makeModel()
        m.settings.breakMinutes = 5
        m.settings.longBreakMinutes = 20
        m.settings.autoStartBreak = true

        for _ in 1...4 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()
        }

        m.startWork()
        m.forceCompleteForTesting()
        #expect(abs(m.remaining - 5 * 60) <= 1, "the cycle should restart after the long break")
    }

    /// An abandoned session earns no progress towards the long break.
    @Test func anAbandonedSessionDoesNotAdvanceTheCycle() {
        let (m, _) = makeModel()
        m.settings.breakMinutes = 5
        m.settings.longBreakMinutes = 20
        m.settings.autoStartBreak = true

        for _ in 1...3 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()
        }
        m.startWork()
        m.reset()               // abandoned, not completed

        m.startWork()
        m.forceCompleteForTesting()
        #expect(abs(m.remaining - 20 * 60) <= 1,
                "three completions plus an abandonment then a completion is the fourth completion — long")
    }
}
