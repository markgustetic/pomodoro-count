import Testing
import Foundation
import Carbon.HIToolbox
@testable import PomodoroCount

/// The strings VoiceOver actually speaks. Labels attached in the view layer
/// can't be asserted headlessly, but the text they're built from can.
@MainActor
@Suite struct AccessibilityTests {

    // MARK: Spoken durations

    @Test(arguments: [
        (0.0, "0 seconds"),
        (1.0, "1 second"),
        (45.0, "45 seconds"),
        (60.0, "1 minute"),
        (120.0, "2 minutes"),
        (3000.0, "50 minutes"),
        (65.0, "1 minute 5 seconds"),
        (-5.0, "0 seconds"),       // never speak negative time
    ])
    func durationsAreSpokenInWords(seconds: TimeInterval, expected: String) {
        #expect(AppModel.spokenDuration(seconds) == expected)
    }

    @Test func spokenDurationRoundsUpLikeTheVisibleClock() {
        // The clock shows 1:00 at 59.5s, so VoiceOver must not say 59 seconds.
        #expect(AppModel.mmss(59.5) == "1:00")
        #expect(AppModel.spokenDuration(59.5) == "1 minute")
    }

    // MARK: Menu bar item

    @Test func idleStatusAnnouncesTheCount() {
        let (m, _) = makeModel()
        #expect(m.statusDescription.contains("0 pomodoros today"))
        m.logExternal()
        #expect(m.statusDescription.contains("1 pomodoro today"))
        m.logExternal()
        #expect(m.statusDescription.contains("2 pomodoros today"))
    }

    @Test func runningStatusAnnouncesPhaseAndTimeRemaining() {
        let (m, _) = makeModel()
        m.startWork()
        #expect(m.statusDescription.hasPrefix("Focus:"))
        #expect(m.statusDescription.contains("remaining"))

        m.startBreak()
        #expect(m.statusDescription.hasPrefix("Break:"))
    }

    @Test func pausedStatusSaysSo() {
        let (m, _) = makeModel()
        m.startWork()
        m.pause()
        #expect(m.statusDescription.contains("paused"))
    }

    /// The drawn text is "3"; the image must not fall back to announcing that.
    @Test func statusImageCarriesTheDescriptionNotTheDigits() {
        let (m, _) = makeModel()
        m.logExternal()
        let described = m.statusImage.accessibilityDescription
        #expect(described == m.statusDescription)
        #expect(described != m.statusText)
    }

    @Test func statusIconFallsBackToItsTextWithoutADescription() {
        let image = StatusIcon.render(phase: .idle, running: false, text: "7")
        #expect(image.accessibilityDescription == "7")
    }

    // MARK: Shortcuts

    @Test func shortcutModifiersAreSpelledOut() {
        #expect(Shortcut.default.spokenDisplay == "control option command P")
    }

    @Test func spokenShortcutCoversEveryModifier() {
        let all = Shortcut(
            keyCode: 49,
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            label: "Space")
        #expect(all.spokenDisplay == "control option shift command Space")
    }

    @Test func spokenShortcutContainsNoSymbolGlyphs() {
        let spoken = Shortcut.default.spokenDisplay
        for glyph in ["⌃", "⌥", "⇧", "⌘"] {
            #expect(!spoken.contains(glyph), "\(glyph) would be read out as a symbol")
        }
    }
}
