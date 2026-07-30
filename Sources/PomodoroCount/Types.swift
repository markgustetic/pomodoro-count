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
    /// goals, and the panel's "towards …" pill shows it happen.
    var autoAdvanceTarget = true
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
        nudgeHour             = try c.decodeIfPresent(Int.self, forKey: .nudgeHour)
        // `usesFallbackBucket` and `defaultCategoryName` were dropped. Decoding
        // is key-by-key, so a data.json still carrying them just ignores them.
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
