import Testing
import Foundation
@testable import PomodoroCount

/// Pausing on screen lock is opt-in, and off by default.
///
/// The app's premise is counting pomodoros finished somewhere else, so a
/// locked Mac is not evidence that focus stopped — pausing there would fight
/// the thing the app is for. The setting stays for people who want the timer
/// to mean time at *this* keyboard: for them a session burning through a lock
/// claims 50 minutes of focus at an empty chair. Either way there is no
/// auto-resume on unlock; only the user knows whether the time away counted,
/// and `pause()` already preserves what is on the clock.
@MainActor
@Suite struct ScreenLockTests {

    // MARK: Default — off

    @Test func lockingDoesNotPauseByDefault() {
        let (m, _) = makeModel()
        #expect(!m.settings.pausesOnScreenLock, "the setting must default to off")
        m.startWork()
        m.handleScreenLocked()
        #expect(m.isRunning, "the session must survive the lock")
        #expect(m.phase == .work)
    }

    @Test func lockingDoesNotPauseARunningBreakByDefault() {
        let (m, _) = makeModel()
        m.startBreak()
        m.handleScreenLocked()
        #expect(m.isRunning)
        #expect(m.phase == .breakTime)
    }

    // MARK: Opted in

    @Test func lockingTheScreenPausesARunningSession() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.startWork()
        let before = m.remaining
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(abs(m.remaining - before) <= 1, "pausing must keep the time on the clock")
    }

    @Test func lockingWhileIdleDoesNothing() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.handleScreenLocked()
        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func lockingAnAlreadyPausedSessionChangesNothing() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.startWork()
        m.pause()
        let before = m.remaining
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(abs(m.remaining - before) <= 1)
    }

    /// This asserted the opposite once (`breaksPauseToo`). The setting means
    /// "focus is time at this keyboard", and a break is the reverse of that:
    /// locking the screen and walking away is what taking one looks like. A
    /// break that paused on the lock never ended — no "Break over", and ten
    /// minutes later a paused timer with nearly all its time still on it.
    @Test func aBreakKeepsRunningThroughALock() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.startBreak()
        m.handleScreenLocked()
        #expect(m.isRunning, "walking away is the break, not an interruption of it")
        #expect(m.phase == .breakTime)
        m.reset()
    }
}
