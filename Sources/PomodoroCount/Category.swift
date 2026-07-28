import Foundation

/// A named bucket for pomodoros, with an optional daily goal.
///
/// Records reference a category by `name`, never by `id` — re-adding a category
/// with a previous name has to reunite it with that history. `id` exists so
/// SwiftUI list editing and reordering animate correctly.
struct Category: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// 0...20. Zero means the category is tracked without a target: its row
    /// shows a bare count and no dots.
    var dailyGoal: Int

    /// The form used for uniqueness comparisons. Names are compared
    /// case-insensitively with surrounding whitespace ignored, so "  Work " and
    /// "work" are the same category as far as the user is concerned.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Where a pomodoro should be filed: a named category, or the bucket.
///
/// There used to be a third case, `.automatic`, meaning "work it out" — for the
/// global hotkey and for a session with no target picked. It differed from
/// `.fallback` only while the bucket could be switched off, when it resolved to
/// a real category instead. That setting is gone and the bucket is always
/// there, so the two cases had identical behaviour and one of them had to go:
/// the panel's label read `.automatic` as "the bucket" while `resolve` sent it
/// somewhere else, and the panel promised a destination it didn't deliver.
enum CategoryTarget: Equatable {
    case fallback
    case named(String)
}

/// One row in the panel: a category, how it is doing today, and how to say so.
struct CategoryProgress: Identifiable {
    let id: String
    let name: String
    let done: Int
    let goal: Int
    /// True for the fallback bucket, whose records carry no category name.
    let isFallback: Bool
    /// True while a focus session is actually running and aimed at this
    /// category — not merely while one is paused or idle.
    let isSessionTarget: Bool

    /// A goal of 0 means "no target", so it can never be met.
    var isMet: Bool { goal > 0 && done >= goal }

    /// One dot per goal unit is legible up to 8 and absurd at 20, so beyond
    /// that the row draws a bar in the same space.
    var showsDots: Bool { goal > 0 && goal <= 8 }

    /// What VoiceOver reads. A met goal is stated here rather than being left to
    /// the accent colour.
    var accessibilityValue: String {
        guard goal > 0 else {
            return "\(done) \(done == 1 ? "pomodoro" : "pomodoros")"
        }
        return "\(done) of \(goal) pomodoros" + (isMet ? ", goal met" : "")
    }
}

/// One row of the History breakdown.
struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let count: Int
}
