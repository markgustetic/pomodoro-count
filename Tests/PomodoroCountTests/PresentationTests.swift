import Testing
import Foundation
import AppKit
@testable import PomodoroCount

/// What the user actually sees: menu bar text and icon, themes, and formatting.
@MainActor
@Suite struct PresentationTests {

    // MARK: Menu bar status

    @Test func statusTextShowsTodaysCountWhenIdle() {
        let (m, _) = makeModel()
        m.logExternal()
        m.logExternal()
        #expect(m.statusText == "2")
    }

    @Test func statusTextShowsTheClockWhileASessionRuns() {
        let (m, _) = makeModel()
        m.startWork()
        #expect(m.statusText.contains(":"))
        m.startBreak()
        #expect(m.statusText.contains(":"))
    }

    @Test func statusImageIsATemplateSoMacOSCanTintIt() {
        let (m, _) = makeModel()
        let image = m.statusImage
        #expect(image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test(arguments: [Phase.idle, .work, .breakTime])
    func statusIconRendersForEveryPhase(phase: Phase) {
        for running in [true, false] {
            let image = StatusIcon.render(phase: phase, running: running, text: "12")
            #expect(image.size.width > 0)
            #expect(image.isTemplate)
        }
    }

    /// A longer count needs a wider menu bar item, or the text gets clipped.
    @Test func statusIconWidensWithItsText() {
        let narrow = StatusIcon.render(phase: .idle, running: false, text: "1")
        let wide = StatusIcon.render(phase: .idle, running: false, text: "888")
        #expect(wide.size.width > narrow.size.width)
    }

    // MARK: Themes

    @Test func classicIsPlainAndSynthwaveIsNeon() {
        #expect(!ThemeChoice.classic.palette.neon)
        #expect(ThemeChoice.synthwave.palette.neon)
        #expect(ThemeChoice.synthwave.palette.paintsBackground)
    }

    /// A palette that paints its own dark background has to pin the appearance
    /// of the AppKit-backed controls too. Without this, a light-mode Mac drew
    /// white text fields and near-black stepper arrows on Synthwave's near-black
    /// panel — SwiftUI can't restyle those controls, only pick their variant.
    @Test func aPaletteThatPaintsItsOwnBackgroundPinsTheControlAppearance() {
        #expect(Palette.synthwave.chrome == .dark)
        // Classic paints nothing of its own, so its controls should keep
        // following whatever the user set system-wide.
        #expect(Palette.classic.chrome == nil)
        #expect(!Palette.classic.paintsBackground)
    }

    @Test func themeChoicePersists() {
        let (m, url) = makeModel()
        #expect(m.settings.theme == .classic)
        m.settings.theme = .synthwave
        #expect(AppModel(storeURL: url).settings.theme == .synthwave)
    }

    @Test func everyThemeIsSelectableByName() {
        #expect(ThemeChoice.allCases.count == 2)
        for theme in ThemeChoice.allCases {
            #expect(ThemeChoice(rawValue: theme.rawValue) == theme)
        }
    }

    // MARK: Formatting

    @Test(arguments: [
        (3000.0, "50:00"),
        (545.0, "9:05"),
        (0.0, "0:00"),
        (-3.0, "0:00"),      // never show negative time
        (59.5, "1:00"),      // rounds up, so the clock never sits on 0:00 early
        (3600.0, "60:00"),   // an hour-long focus stays in minutes
    ])
    func mmssFormatsTheClock(seconds: TimeInterval, expected: String) {
        #expect(AppModel.mmss(seconds) == expected)
    }

    @Test func dayLabelsUseFriendlyNamesForRecentDays() {
        let (m, _) = makeModel()
        #expect(m.dayLabel(Date()) == "Today")
        #expect(m.dayLabel(.daysAgo(1)) == "Yesterday")
        let older = m.dayLabel(.daysAgo(5))
        #expect(older != "Today" && older != "Yesterday")
        #expect(older.contains(","))     // e.g. "Wed, Jul 22"
    }

    // MARK: Sound

    /// Every feedback sound must resolve on the system, or a count would change
    /// silently. Resolved, not played — a test run should stay quiet.
    @Test(arguments: [AppModel.Sound.countUp, .countDown, .sessionDone, .breakOver])
    func feedbackSoundsExist(sound: AppModel.Sound) {
        #expect(NSSound(named: sound.rawValue) != nil)
    }

    @Test func soundsCanBeTurnedOff() {
        let (m, url) = makeModel()
        m.settings.soundEnabled = false
        #expect(!AppModel(storeURL: url).settings.soundEnabled)
    }
}
