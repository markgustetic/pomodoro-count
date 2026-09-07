import Testing
@testable import PomodoroCount

/// The words the stop button's confirmation says, per phase. A type rather
/// than an `if` in the view for the same reason `StatusIcon.glyph` is: a
/// phase arriving without its own wording fails here, not in the panel.
@Suite struct StopConfirmationTests {

    @Test func skippingAnArmedBreakSaysTheSessionIsSafe() {
        let p = StopConfirmation.prompt(phase: .breakReady)
        #expect(p.title == "Skip the break?")
        #expect(p.note == "The session is already logged.")
        #expect(p.verb == "Skip")
    }

    @Test func abandoningAFocusSessionSaysNothingIsLogged() {
        let p = StopConfirmation.prompt(phase: .work)
        #expect(p.title == "Abandon this session?")
        #expect(p.note == "Nothing is logged.")
        #expect(p.verb == "Abandon")
    }

    @Test func cuttingABreakShortSaysTheSessionStaysLogged() {
        let p = StopConfirmation.prompt(phase: .breakTime)
        #expect(p.title == "Cut the break short?")
        #expect(p.note == "Back to idle; the session stays logged.")
        #expect(p.verb == "Stop")
    }

    /// The stop button is disabled while idle, so this wording is never shown;
    /// it exists so the switch stays exhaustive and a caller never gets nil.
    @Test func idleStillHasWords() {
        let p = StopConfirmation.prompt(phase: .idle)
        #expect(!p.title.isEmpty)
        #expect(!p.verb.isEmpty)
    }

    @Test func restingNowSaysTheSessionCountsAsDone() {
        let p = StopConfirmation.restNowPrompt
        #expect(p.title == "End the session early?")
        #expect(p.note == "It counts as done, and the break starts.")
        #expect(p.verb == "Log and rest")
    }

    /// Only a mid-session press changes the count, so only that one asks.
    @Test(arguments: [(Phase.idle, false), (.work, true), (.breakTime, false), (.breakReady, false)])
    func restNowAsksOnlyDuringAFocusSession(phase: Phase, asks: Bool) {
        #expect(StopConfirmation.restNowAsks(phase: phase) == asks)
    }
}
