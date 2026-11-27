import Foundation
import Carbon.HIToolbox

// MARK: - Data types

/// A single completed pomodoro. `source` is "timer" (finished in-app) or
/// "manual" (logged from external hardware — the whole point of this app).
struct Record: Codable, Identifiable {
    var id = UUID()
    var at: Date
    var source: String
    /// The category NAME, or nil for the fallback bucket. Optional so that
    /// Swift's synthesized decoder treats it as decodeIfPresent and every
    /// existing data.json still loads.
    var category: String?
}

/// A global hotkey combination. Modifiers are stored as Carbon masks (as
/// `RegisterEventHotKey` wants); `label` is the human-readable key captured
/// when it was recorded (e.g. "P", "Space", "⏎").
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String

    static let `default` = Shortcut(
        keyCode: 35,   // ANSI 'P'
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        label: "P")

    /// Whether a combo is safe to register as a system-wide hotkey.
    ///
    /// A registered hotkey swallows its keystroke in every app, so the rule is
    /// about what the combo would take away from typing. The recorder used to
    /// ask only for "some modifier", which let ⇧P through — and ⇧ and ⌥ are how
    /// ordinary characters are typed (a capital P, a π), so every capital P on
    /// the machine logged a pomodoro instead of appearing. ⌘ or ⌃ is what makes
    /// a combo a command rather than a character.
    ///
    /// Function keys are the exception that keeps this from being a blunt
    /// instrument: they type nothing, so ⇧F5 or ⌥F13 costs nobody a character,
    /// and those are the combos a keypad or a Stream Deck is likeliest to send
    /// — external hardware being this app's whole reason to exist. A bare key
    /// with no modifier at all stays refused, as it always was.
    ///
    /// Pure and here rather than in `ShortcutRecorder` so it is tested, and so
    /// "what may be a shortcut" has one answer. It guards recording only: a
    /// combo already saved in data.json is left to load as it is.
    static func canBeGlobal(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        if carbonModifiers & UInt32(cmdKey | controlKey) != 0 { return true }
        guard carbonModifiers & UInt32(shiftKey | optionKey) != 0 else { return false }
        return functionKeys.contains(Int(keyCode))
    }

    /// F1–F20. Listed, not a range: the virtual key codes are not contiguous.
    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
        kVK_F20,
    ]

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + label
    }

    /// `display` in words. VoiceOver reads the modifier symbols inconsistently
    /// or not at all, so "⌃⌥⌘P" needs spelling out.
    var spokenDisplay: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("control") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("option") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("shift") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("command") }
        parts.append(label)
        return parts.joined(separator: " ")
    }
}

/// Which colour palette the UI uses.
enum ThemeChoice: String, Codable, CaseIterable {
    case classic = "Classic"
    case synthwave = "Synthwave"

    var palette: Palette { self == .synthwave ? .synthwave : .classic }
}

struct Settings: Codable {
    var workMinutes = 50
    var breakMinutes = 10
    /// Every fourth completed focus session earns a break of this length —
    /// the classic pomodoro rhythm.
    var longBreakMinutes = 15
    var autoStartBreak = true
    /// Whether a running focus session pauses when the screen locks or the
    /// displays sleep. Off by default: this app exists to count pomodoros
    /// finished somewhere else, so an unattended Mac is not evidence that focus
    /// stopped. On, focus means time at this keyboard and a lock stops the
    /// clock. A break runs through a lock either way — see `handleScreenLocked`.
    var pausesOnScreenLock = false
    var soundEnabled = true
    var globalShortcutEnabled = true
    var shortcut = Shortcut.default
    var theme: ThemeChoice = .classic
    /// When off, the menu bar item is just the icon while idle. The countdown
    /// still appears during a session — that's when the width earns its place.
    var showsCountInMenuBar = true

    // MARK: Categories (all opt-in; defaults reproduce today's behaviour exactly)

    /// The whole feature is off until the user turns it on.
    var categoriesEnabled = false
    /// The user's categories, in display order.
    var categories: [Category] = []
    /// The bucket that catches every pomodoro not aimed at a category. Always
    /// present while categories are on — it is the terminal case of routing, so
    /// making it optional only ever meant "route somewhere else *usually*", and
    /// the paths that still produced an uncategorised record didn't go away.
    var fallbackName = "General"
    var fallbackGoal = 0
    /// Remembered target for the built-in timer. nil means the bucket.
    var sessionTargetName: String?
    /// When on, a target whose goal is met hands off to the next category that
    /// still has one. Defaults on: it can only ever fire once the user has set
    /// goals, and the panel's "towards …" text shows it happen.
    var autoAdvanceTarget = true
    /// True when the user aimed the target at a category that was *already*
    /// met. The only reading of such a pick is "let me overshoot here", so it
    /// suppresses the met-goal advance until the day turns over or the user
    /// hands control back. A pick of an unfinished category leaves this false:
    /// it needs no pin, because the advance only ever fires on a met target.
    var targetPinned = false
    /// The day the target was last aimed, so the start-of-day reset survives a
    /// quit or a long sleep. `NSCalendarDayChanged` only fires while the app is
    /// running, so a reset driven by that notification alone would be missed by
    /// anyone who closes their laptop overnight. A stamp is checked whenever the
    /// app next looks, however it finds out the day turned over.
    var targetAimedOn: Date?
    /// The hour (0–23) of the end-of-day reminder. nil means no reminder.
    var nudgeHour: Int?

    init() {}

    // Decode field-by-field so a data.json written by an older version (missing
    // newer keys) still loads and keeps its records instead of failing to decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workMinutes           = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 50
        breakMinutes          = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 10
        longBreakMinutes      = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        autoStartBreak        = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? true
        pausesOnScreenLock    = try c.decodeIfPresent(Bool.self, forKey: .pausesOnScreenLock) ?? false
        soundEnabled          = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        globalShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true
        shortcut              = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .default
        theme                 = try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? .classic
        showsCountInMenuBar   = try c.decodeIfPresent(Bool.self, forKey: .showsCountInMenuBar) ?? true
        categoriesEnabled     = try c.decodeIfPresent(Bool.self, forKey: .categoriesEnabled) ?? false
        categories            = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        fallbackName          = try c.decodeIfPresent(String.self, forKey: .fallbackName) ?? "General"
        fallbackGoal          = try c.decodeIfPresent(Int.self, forKey: .fallbackGoal) ?? 0
        sessionTargetName     = try c.decodeIfPresent(String.self, forKey: .sessionTargetName)
        autoAdvanceTarget     = try c.decodeIfPresent(Bool.self, forKey: .autoAdvanceTarget) ?? true
        targetPinned          = try c.decodeIfPresent(Bool.self, forKey: .targetPinned) ?? false
        targetAimedOn         = try c.decodeIfPresent(Date.self, forKey: .targetAimedOn)
        nudgeHour             = try c.decodeIfPresent(Int.self, forKey: .nudgeHour)
        // `usesFallbackBucket` and `defaultCategoryName` were dropped. Decoding
        // is key-by-key, so a data.json still carrying them just ignores them.
    }
}

extension Settings {
    /// Writes a session target into the settings value.
    ///
    /// `AppModel.sessionTarget`'s setter is the usual way in, but the paths that
    /// change the target *and* the pin *and* the day stamp have to batch all
    /// three into one assignment — each separate mutation of `settings` is its
    /// own `didSet` and its own write to disk. They need this mapping on a local
    /// copy, so it lives here and the setter calls it rather than the two
    /// keeping their own copies of the same switch.
    mutating func aim(at target: CategoryTarget) {
        switch target {
        case .named(let name): sessionTargetName = name
        case .fallback: sessionTargetName = nil
        }
    }
}

enum Phase: Equatable {
    /// `.breakReady` is a fourth state, not a flavour of idle: a focus session
    /// has finished and its break is armed at the configured length, waiting to
    /// be started or skipped. Reusing `.idle` would have left the panel
    /// previewing the *focus* length with no sign a break was owed; reusing a
    /// paused `.breakTime` would have let `startBreak()` spend the earned long
    /// break at arm time, so skipping it would silently cancel it.
    case idle, work, breakTime, breakReady
}

/// One day's tally, used by the history view.
struct DayStat: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}
