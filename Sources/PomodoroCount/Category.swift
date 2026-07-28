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

/// Where a pomodoro should be filed.
///
/// `.automatic` means "work it out" — used by the global hotkey and by a timer
/// session with no target. `.fallback` is an explicit request for the bucket,
/// which is not the same thing: with the bucket switched off, `.automatic`
/// resolves to a real category while `.fallback` still means the bucket.
enum CategoryTarget: Equatable {
    case automatic
    case fallback
    case named(String)
}

@MainActor
extension AppModel {

    /// The category a pomodoro lands in when nothing was chosen.
    ///
    /// Order: the marked default when the bucket is off and it still exists;
    /// then the bucket; then the first category in display order; then the
    /// bucket regardless. The last two exist so archiving the marked default can
    /// never leave a pomodoro with nowhere to go.
    var automaticCategoryName: String? {
        guard settings.categoriesEnabled else { return nil }
        guard !settings.usesFallbackBucket else { return nil }

        if let marked = settings.defaultCategoryName, categoryExists(marked) {
            return marked
        }
        return settings.categories.first?.name
    }

    func resolve(_ target: CategoryTarget) -> String? {
        switch target {
        case .automatic:      return automaticCategoryName
        case .fallback:       return nil
        case .named(let name): return settings.categoriesEnabled ? name : nil
        }
    }

    /// True when a category with this name is currently in the list. Archived
    /// names return false — they hold history but receive nothing new.
    func categoryExists(_ name: String) -> Bool {
        let wanted = Category.normalized(name)
        return settings.categories.contains { Category.normalized($0.name) == wanted }
    }
}
