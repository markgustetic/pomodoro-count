import Testing
import Foundation
@testable import PomodoroCount

/// A completed focus session with `autoStartBreak` off arms its break instead
/// of returning to idle: the panel previews the break at the length it will
/// actually run for, and waits to be told to start it or skip it.
@MainActor
@Suite struct BreakReadyTests {

    /// The state the whole feature hangs on.
    @Test func completingAFocusSessionArmsTheBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakReady)
        #expect(!m.isRunning)
    }

    /// The untouched path: auto-start still means auto-start. This is the
    /// regression guard on the behaviour every existing user has today.
    @Test func autoStartStillStartsTheBreakItself() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = true
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
    }

    /// Arming a break is not a substitute for logging the session.
    @Test func theSessionIsLoggedEitherWay() {
        for auto in [true, false] {
            let (m, _) = makeModel()
            m.settings.autoStartBreak = auto
            m.startWork()
            m.forceCompleteForTesting()
            #expect(m.records.count == 1, "autoStartBreak = \(auto)")
            #expect(m.records[0].source == "timer")
        }
    }

    @Test func theArmedBreakPreviewsTheShortBreakLength() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 7
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.displayRemaining == 7 * 60)
    }

    /// The fourth completion earns the long break, so that is the length the
    /// armed state has to offer — not the short one.
    @Test func theFourthArmedBreakPreviewsTheLongBreakLength() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 7
        m.settings.longBreakMinutes = 21

        for session in 1...3 {
            m.startWork()
            m.forceCompleteForTesting()
            #expect(m.displayRemaining == 7 * 60, "break after session \(session) should be short")
            m.reset()
        }

        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.nextBreakIsLong)
        #expect(m.displayRemaining == 21 * 60)
    }

    /// The preview is computed from settings, not stored, so a length edited
    /// while the break sits armed is both the length shown and the length that
    /// runs.
    @Test func editingTheBreakLengthWhileArmedUpdatesThePreview() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 7
        m.startWork()
        m.forceCompleteForTesting()

        m.settings.breakMinutes = 12
        #expect(m.displayRemaining == 12 * 60)
        m.toggle()
        #expect(abs(m.remaining - 12 * 60) <= 1)
    }

    @Test func theArmedBreakSaysStartBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.primaryTitle == "Start break")
    }

    /// The primary button must start the break, not resume a countdown that
    /// does not exist. `resume()` only guards against `.idle`, so getting this
    /// wrong ticks down from a stale `remaining` of zero.
    @Test func thePrimaryButtonStartsTheArmedBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 9
        m.startWork()
        m.forceCompleteForTesting()

        m.toggle()
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
        #expect(!m.currentBreakIsLong)
        #expect(abs(m.remaining - 9 * 60) <= 1)
    }

    /// There is no countdown behind an armed break, so `resume()` must stay
    /// inert there — `toggle()` is the only sanctioned way out, via
    /// `startBreak()`. Getting this wrong ticks down from a stale `remaining`
    /// of zero and "completes" a break that never ran.
    @Test func resumeIsInertWhileABreakIsArmed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()

        m.resume()
        #expect(m.phase == .breakReady)
        #expect(!m.isRunning)
    }

    @Test func theArmedLongBreakStartsLong() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 9
        m.settings.longBreakMinutes = 30

        for _ in 1...3 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()
        }
        m.startWork()
        m.forceCompleteForTesting()

        m.toggle()
        #expect(m.phase == .breakTime)
        #expect(m.currentBreakIsLong)
        #expect(abs(m.remaining - 30 * 60) <= 1)
    }

    /// The stop button's job in this phase: back to idle, previewing focus
    /// again.
    @Test func skippingTheArmedBreakReturnsToIdle() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.workMinutes = 40
        m.startWork()
        m.forceCompleteForTesting()

        m.reset()
        #expect(m.phase == .idle)
        #expect(m.primaryTitle == "Start focus")
        #expect(m.displayRemaining == 40 * 60)
    }

    /// Only *taking* the long break restarts the cycle, so a skipped long
    /// break is still owed and the next one offered is long again.
    @Test func skippingAnArmedLongBreakKeepsItOwed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 9
        m.settings.longBreakMinutes = 30

        for _ in 1...4 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()                       // skipped every time
        }
        #expect(m.nextBreakIsLong)

        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.displayRemaining == 30 * 60)
    }

    // MARK: Menu bar

    /// Nothing is counting while a break is armed, so the item keeps showing
    /// the count. A frozen clock up there would read as a paused timer.
    @Test func theMenuBarKeepsTheCountWhileABreakIsArmed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.statusText == "1")
        #expect(!m.statusText.contains(":"))
    }

    @Test func theArmedBreakRespectsTheIconOnlyMenuBar() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.showsCountInMenuBar = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.statusText == "")
    }

    /// `statusText` draws the count in this phase (see the menu-bar test
    /// above), and every other phase's `statusDescription` speaks a superset
    /// of what it draws — so a VoiceOver user with auto-start off must still
    /// hear the count here, not just the break's length.
    @Test func theArmedBreakIsAnnouncedWithItsLengthAndTheCount() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 10
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.statusDescription.contains("Break ready"))
        #expect(m.statusDescription.contains("10 minutes"))
        #expect(m.statusDescription.contains("1 pomodoro today"))
    }

    // MARK: The button row

    /// The cup stands down while a break is armed: the primary button already
    /// offers exactly that, and two controls doing one job in one row is worse
    /// than one. The three older phases keep the behaviour they had.
    @Test func theCupButtonStandsDownWhileABreakIsArmed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        #expect(m.offersManualBreak)          // idle — rest now, before starting
        m.startWork()
        #expect(m.offersManualBreak)          // mid-focus — cut it short and rest
        m.forceCompleteForTesting()
        #expect(!m.offersManualBreak)         // armed — the big button is the offer
        m.toggle()
        #expect(!m.offersManualBreak)         // already resting
    }

    /// "Abandons the session — nothing is logged" is false once a break is
    /// armed. The session *was* logged; that is why there is a break to skip.
    @Test func theStopButtonStopsPromisingNothingWasLogged() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        #expect(m.resetHelp.contains("nothing is logged"))
        m.forceCompleteForTesting()
        #expect(m.resetHelp.contains("Skip the break"))
        #expect(!m.resetHelp.contains("nothing is logged"))
    }

    /// The stop button is disabled only in `.idle`. `.breakReady` is the phase
    /// most worth pinning: it has no countdown running, so it would be easy to
    /// mistake for another "nothing to stop" state and disable the only
    /// control that skips an armed break.
    @Test func theStopButtonIsEnabledInEveryPhaseButIdle() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        #expect(!m.offersReset)                // idle
        m.startWork()
        #expect(m.offersReset)                 // work
        m.forceCompleteForTesting()
        #expect(m.offersReset)                 // breakReady
        m.toggle()
        #expect(m.offersReset)                 // breakTime
    }

    // MARK: The banner

    /// With auto-start off and the panel closed, this banner is the only thing
    /// that tells you a break is waiting.
    @Test func theBannerNamesTheWaitingBreak() {
        #expect(AppModel.completionBody(count: 4, breakArmed: true)
                == "That's 4 today — break's ready when you are.")
    }

    /// The auto-start path keeps the wording it has always had.
    @Test func theBannerIsUnchangedWhenTheBreakStartsItself() {
        #expect(AppModel.completionBody(count: 4, breakArmed: false)
                == "Nice — that's 4 today.")
    }

    // MARK: Persistence

    /// Nothing persists the phase — an architectural guarantee, not an
    /// accident: an armed break restored hours (or days) later would count a
    /// rest the user may never have taken. A fresh model reading the same
    /// store must come up idle no matter what phase the last one was in.
    @Test func anArmedBreakDoesNotSurviveRelaunch() {
        let (m, url) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakReady)

        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.phase == .idle)
    }
}
