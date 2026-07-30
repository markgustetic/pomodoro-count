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

    @Test(arguments: [Phase.idle, .work, .breakTime, .breakReady])
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

    /// The glyph decision, lifted out of the drawing code so it can be
    /// asserted — an `NSImage` of a tomato and an `NSImage` of a cup are
    /// equally "a non-empty template image". Pinned for all six existing
    /// combinations so a later phase cannot quietly change one.
    @Test func theMenuBarGlyphFollowsThePhase() {
        #expect(StatusIcon.glyph(phase: .idle, running: true) == .tomato)
        #expect(StatusIcon.glyph(phase: .idle, running: false) == .tomato)
        #expect(StatusIcon.glyph(phase: .work, running: true) == .tomato)
        #expect(StatusIcon.glyph(phase: .work, running: false) == .pause)
        #expect(StatusIcon.glyph(phase: .breakTime, running: true) == .cup)
        #expect(StatusIcon.glyph(phase: .breakTime, running: false) == .pause)
        #expect(StatusIcon.glyph(phase: .breakReady, running: false) == .cup)
        #expect(StatusIcon.glyph(phase: .breakReady, running: true) == .cup)
    }

    // MARK: Control state

    /// The precedence every button style draws by, lifted out of the styles
    /// for the same reason the glyph is: a rendered button is not assertable,
    /// the decision behind it is. `SoftIconButtonStyle` branched on pressed and
    /// hovering alone, so the disabled stop button drew pixel-identically to a
    /// live one.
    @Test func disabledOutranksEveryOtherControlState() {
        #expect(ControlState.of(enabled: false, pressed: false, hovering: false) == .disabled)
        #expect(ControlState.of(enabled: false, pressed: true, hovering: false) == .disabled)
        // `--preview --hover` forces hovering on every control at once, and a
        // dead button must stay dark under a real pointer too, so nothing but
        // this precedence keeps it from lighting up. Confirmed in a render:
        // the idle stop button is pixel-identical with and without `--hover`.
        #expect(ControlState.of(enabled: false, pressed: false, hovering: true) == .disabled)
    }

    /// Pressed outranks hovering because the pointer is necessarily inside the
    /// button it is pressing.
    @Test func aLiveControlPrefersPressedThenHoveringThenRest() {
        #expect(ControlState.of(enabled: true, pressed: true, hovering: true) == .pressed)
        #expect(ControlState.of(enabled: true, pressed: false, hovering: true) == .hovering)
        #expect(ControlState.of(enabled: true, pressed: false, hovering: false) == .resting)
    }

    // MARK: Themes

    /// The disabled dim routes through the palette like every other look
    /// decision. Both themes have to dim far enough to read as dead at a
    /// glance — the numbers themselves were picked against rendered previews —
    /// and no theme may dim a control that is merely pressed or hovered, which
    /// would put two ideas of emphasis on the same button.
    @Test(arguments: ThemeChoice.allCases)
    func everyPaletteDimsDisabledControlsAndOnlyThose(choice: ThemeChoice) {
        let disabled = choice.palette.disabled
        #expect(disabled.opacity(in: .disabled) > 0)
        #expect(disabled.opacity(in: .disabled) <= 0.45)
        for live in [ControlState.pressed, .hovering, .resting] {
            #expect(disabled.opacity(in: live) == 1)
        }
    }

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
