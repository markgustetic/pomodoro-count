import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct TimerTests {

    @Test func beginsIdle() {
        let (m, _) = makeModel()
        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func startWorkRunsAConfiguredFocusSession() {
        let (m, _) = makeModel()
        m.startWork()
        #expect(m.phase == .work)
        #expect(m.isRunning)
        #expect(abs(m.remaining - 50 * 60) <= 1.0)
    }

    @Test func startBreakRunsAConfiguredBreak() {
        let (m, _) = makeModel()
        m.startBreak()
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
        #expect(abs(m.remaining - 10 * 60) <= 1.0)
    }

    @Test func sessionLengthsFollowSettings() {
        let (m, _) = makeModel()
        m.settings.workMinutes = 25
        m.settings.breakMinutes = 3
        m.startWork()
        #expect(abs(m.remaining - 25 * 60) <= 1.0)
        m.startBreak()
        #expect(abs(m.remaining - 3 * 60) <= 1.0)
    }

    @Test func pauseKeepsPhaseAndStopsTheClock() {
        let (m, _) = makeModel()
        m.startWork()
        m.pause()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(m.remaining > 0)
    }

    @Test func resumeRestartsAPausedSession() {
        let (m, _) = makeModel()
        m.startWork()
        m.pause()
        m.resume()
        #expect(m.isRunning)
        #expect(m.phase == .work)
    }

    @Test func resumeFromIdleDoesNothing() {
        let (m, _) = makeModel()
        m.resume()
        #expect(!m.isRunning)
        #expect(m.phase == .idle)
    }

    @Test func pauseWhenNotRunningDoesNothing() {
        let (m, _) = makeModel()
        m.pause()
        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func resetReturnsToIdle() {
        let (m, _) = makeModel()
        m.startWork()
        m.reset()
        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func toggleCyclesStartPauseResume() {
        let (m, _) = makeModel()
        m.toggle()                       // idle → running work
        #expect(m.phase == .work && m.isRunning)
        m.toggle()                       // → paused
        #expect(m.phase == .work && !m.isRunning)
        m.toggle()                       // → resumed
        #expect(m.phase == .work && m.isRunning)
    }

    @Test func primaryTitleDescribesTheNextAction() {
        let (m, _) = makeModel()
        #expect(m.primaryTitle == "Start focus")
        m.startWork()
        #expect(m.primaryTitle == "Pause")
        m.pause()
        #expect(m.primaryTitle == "Resume")
    }

    /// Idle previews the configured focus length rather than showing 0:00.
    @Test func displayRemainingPreviewsFocusLengthWhenIdle() {
        let (m, _) = makeModel()
        m.settings.workMinutes = 42
        #expect(m.displayRemaining == 42 * 60)
        m.startBreak()
        #expect(m.displayRemaining == m.remaining)
    }
}
