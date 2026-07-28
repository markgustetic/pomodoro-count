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

/// One row in the panel: a category, how it is doing today, and how to say so.
struct CategoryProgress: Identifiable {
    let id: String
    let name: String
    let done: Int
    let goal: Int
    /// True for the fallback bucket, whose records carry no category name.
    let isFallback: Bool

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

@MainActor
extension AppModel {

    /// Today's count for one category. Pass nil for the fallback bucket.
    func todayCount(inCategory name: String?) -> Int {
        let wanted = name.map(Category.normalized)
        return records.filter { record in
            guard Calendar.current.isDateInToday(record.at) else { return false }
            return record.category.map(Category.normalized) == wanted
        }.count
    }

    /// The panel's rows: every category in display order, then the fallback
    /// bucket. The bucket appears when it is switched on, and also while it
    /// still holds pomodoros after being switched off — the same rule an
    /// archived category follows.
    var todayProgress: [CategoryProgress] {
        var rows = settings.categories.map { category in
            CategoryProgress(
                id: category.id.uuidString,
                name: category.name,
                done: todayCount(inCategory: category.name),
                goal: category.dailyGoal,
                isFallback: false)
        }

        let bucketCount = todayCount(inCategory: nil)
        if settings.usesFallbackBucket || bucketCount > 0 {
            rows.append(CategoryProgress(
                id: "fallback",
                name: settings.fallbackName,
                done: bucketCount,
                goal: settings.fallbackGoal,
                isFallback: true))
        }
        return rows
    }
}
