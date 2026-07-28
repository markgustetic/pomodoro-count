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
        // "Running" means an actual focus session in progress, not idle or
        // paused — a paused session's target row should not stay outlined.
        let sessionRunning = phase == .work && isRunning
        let targetName = sessionRunning ? resolve(sessionTarget) : nil
        let normalizedTarget = targetName.map(Category.normalized)

        var rows = settings.categories.map { category in
            CategoryProgress(
                id: category.id.uuidString,
                name: category.name,
                done: todayCount(inCategory: category.name),
                goal: category.dailyGoal,
                isFallback: false,
                isSessionTarget: sessionRunning && normalizedTarget == Category.normalized(category.name))
        }

        let bucketCount = todayCount(inCategory: nil)
        if settings.usesFallbackBucket || bucketCount > 0 {
            rows.append(CategoryProgress(
                id: "fallback",
                name: settings.fallbackName,
                done: bucketCount,
                goal: settings.fallbackGoal,
                isFallback: true,
                isSessionTarget: sessionRunning && targetName == nil))
        }
        return rows
    }
}

@MainActor
extension AppModel {

    /// Names must be unique across the user's categories and the fallback name.
    /// `excluding` lets a category keep its own name while being renamed.
    func isCategoryNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let wanted = Category.normalized(name)
        guard !wanted.isEmpty else { return false }
        guard wanted != Category.normalized(settings.fallbackName) else { return false }
        return !settings.categories.contains {
            $0.id != id && Category.normalized($0.name) == wanted
        }
    }

    /// Mirrors `isCategoryNameAvailable` from the fallback bucket's side: its
    /// name must be non-empty and not collide with any current category,
    /// case-insensitively with whitespace trimmed. Names are unique across
    /// categories *and* the fallback name — this is the other half of that
    /// rule, which nothing previously enforced.
    func isFallbackNameAvailable(_ name: String) -> Bool {
        let wanted = Category.normalized(name)
        guard !wanted.isEmpty else { return false }
        return !settings.categories.contains { Category.normalized($0.name) == wanted }
    }

    /// Returns false and changes nothing when the name is empty or collides
    /// with a current category.
    @discardableResult
    func setFallbackName(_ name: String) -> Bool {
        guard isFallbackNameAvailable(name) else { return false }
        settings.fallbackName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    /// True when records already carry this name but no *current* category
    /// owns it — i.e. the name belongs to something archived. Renaming into
    /// such a name would silently absorb that history and then, on a later
    /// rename away, permanently relabel it. The sanctioned way to reunite
    /// with archived history is to delete and re-add a category with the
    /// same name, not to rename over it.
    private func hasArchivedRecords(named name: String) -> Bool {
        guard !categoryExists(name) else { return false }
        let wanted = Category.normalized(name)
        return records.contains { $0.category.map(Category.normalized) == wanted }
    }

    /// Returns false and changes nothing when the name is empty or taken.
    @discardableResult
    func addCategory(name: String, dailyGoal: Int) -> Bool {
        guard isCategoryNameAvailable(name) else { return false }
        settings.categories.append(Category(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            dailyGoal: min(max(dailyGoal, 0), 20)))
        return true
    }

    /// Rewrites every record that referenced the old name, in one pass, so no
    /// history is orphaned. Returns false and changes nothing when the new
    /// name is empty, taken by a different category, or already has archived
    /// records under it that don't belong to this category.
    ///
    /// `records` and `settings` are each built up locally and assigned once,
    /// so a rename costs at most two saves total — not one per record.
    @discardableResult
    func renameCategory(id: UUID, to newName: String) -> Bool {
        guard let index = settings.categories.firstIndex(where: { $0.id == id }),
              isCategoryNameAvailable(newName, excluding: id),
              !hasArchivedRecords(named: newName)
        else { return false }

        let old = Category.normalized(settings.categories[index].name)
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        var updatedRecords = records
        for i in updatedRecords.indices where updatedRecords[i].category.map(Category.normalized) == old {
            updatedRecords[i].category = trimmed
        }
        records = updatedRecords

        var updatedSettings = settings
        updatedSettings.categories[index].name = trimmed
        if updatedSettings.defaultCategoryName.map(Category.normalized) == old {
            updatedSettings.defaultCategoryName = trimmed
        }
        if updatedSettings.sessionTargetName.map(Category.normalized) == old {
            updatedSettings.sessionTargetName = trimmed
        }
        settings = updatedSettings

        return true
    }

    /// Archives rather than deletes: the category leaves the list but its
    /// records keep their name, so History, totals and CSV are unchanged.
    func removeCategory(id: UUID) {
        settings.categories.removeAll { $0.id == id }
    }

    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        settings.categories.move(fromOffsets: source, toOffset: destination)
    }
}

/// One row of the History breakdown.
struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let count: Int
}

@MainActor
extension AppModel {

    /// Totals per category over the last `days` days, ending today.
    ///
    /// Current categories come first in display order and appear even at zero —
    /// a neglected category should be visible, not absent. Then the bucket, then
    /// any archived names that still have records in range, alphabetically.
    func categoryTotals(days: Int) -> [CategoryTotal] {
        let calendar = Calendar.current
        let cutoff = calendar.date(
            byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
        let inRange = records.filter { $0.at >= cutoff }

        var counts: [String: Int] = [:]     // normalized name (or "") -> count
        for record in inRange {
            counts[record.category.map(Category.normalized) ?? "", default: 0] += 1
        }

        var totals = settings.categories.map { category in
            CategoryTotal(
                id: category.id.uuidString,
                name: category.name,
                count: counts.removeValue(forKey: Category.normalized(category.name)) ?? 0)
        }

        if let bucket = counts.removeValue(forKey: ""), bucket > 0 {
            totals.append(CategoryTotal(id: "fallback", name: settings.fallbackName, count: bucket))
        } else if settings.usesFallbackBucket {
            totals.append(CategoryTotal(id: "fallback", name: settings.fallbackName, count: 0))
        }

        // Whatever is left is archived: it has records in range but no category.
        // Their display name comes from the first record that used it, so the
        // user's original capitalisation survives.
        let archivedNames = Dictionary(
            grouping: inRange.compactMap(\.category),
            by: Category.normalized)
        for (normalized, count) in counts.sorted(by: { $0.key < $1.key }) {
            let display = archivedNames[normalized]?.first ?? normalized
            totals.append(CategoryTotal(id: "archived-\(normalized)", name: display, count: count))
        }

        return totals
    }
}
