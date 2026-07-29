import Testing
import Foundation
@testable import PomodoroCount

/// A focus session that keeps burning while the Mac is locked produces
/// dishonest data — the timer says 50 minutes of focus happened, the chair
/// was empty. Locking pauses; resuming is the user's call, because only they
/// know whether the time away should count.
@MainActor
@Suite struct ScreenLockTests {

    @Test func lockingTheScreenPausesARunningSession() {
        let (m, _) = makeModel()
        m.startWork()
        let before = m.remaining
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(abs(m.remaining - before) <= 1, "pausing must keep the time on the clock")
    }

    @Test func lockingWhileIdleDoesNothing() {
        let (m, _) = makeModel()
        m.handleScreenLocked()
        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func lockingAnAlreadyPausedSessionChangesNothing() {
        let (m, _) = makeModel()
        m.startWork()
        m.pause()
        let before = m.remaining
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(abs(m.remaining - before) <= 1)
    }

    @Test func breaksPauseToo() {
        let (m, _) = makeModel()
        m.startBreak()
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .breakTime)
    }
}
