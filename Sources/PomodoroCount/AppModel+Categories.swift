import Foundation

// MARK: - Resolution & routing

@MainActor
extension AppModel {

    func resolve(_ target: CategoryTarget) -> String? {
        switch target {
        case .fallback: return nil
        case .named(let name):
            guard settings.categoriesEnabled else { return nil }
            // Return the canonical stored spelling when one matches, so a
            // non-canonical spelling (different case, stray whitespace) can
            // never enter a record.
            let wanted = Category.normalized(name)
            return settings.categories.first { Category.normalized($0.name) == wanted }?.name ?? name
        }
    }

    /// True when a category with this name is currently in the list. Archived
    /// names return false — they hold history but receive nothing new.
    func categoryExists(_ name: String) -> Bool {
        let wanted = Category.normalized(name)
        return settings.categories.contains { Category.normalized($0.name) == wanted }
    }
}

// MARK: - Progress

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

    /// The panel's rows: every category in display order, then the bucket.
    ///
    /// Empty while categories are off. Records logged in that state still carry
    /// no category — they are in the bucket as far as storage is concerned — but
    /// a user who has never turned categories on should not meet a lone
    /// "General" row explaining a feature they aren't using.
    var todayProgress: [CategoryProgress] {
        guard settings.categoriesEnabled else { return [] }

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

        // Unconditional: it is the only row that can take a pomodoro belonging
        // to none of the categories, so it must not vanish at zero.
        rows.append(CategoryProgress(
            id: "fallback",
            name: settings.fallbackName,
            done: todayCount(inCategory: nil),
            goal: settings.fallbackGoal,
            isFallback: true,
            isSessionTarget: sessionRunning && targetName == nil))
        return rows
    }
}

// MARK: - Add / rename / archive / reorder

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

    /// Moves one category to a destination index.
    ///
    /// `Array.move(fromOffsets:toOffset:)` takes an *insertion offset measured
    /// before the removal*, not a destination index: moving a row down by one
    /// needs `to + 1`, and passing `to` unadjusted moves nothing at all — the
    /// row looks stuck to anything dragging it. That adjustment lives here so no
    /// caller has to know about it.
    ///
    /// Out-of-range indices, and a move to the slot the category already
    /// occupies, change nothing — so a drag that ends where it began writes
    /// nothing to the store.
    func moveCategory(from source: Int, to destination: Int) {
        let indices = settings.categories.indices
        guard indices.contains(source), indices.contains(destination),
              source != destination
        else { return }
        settings.categories.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination > source ? destination + 1 : destination)
    }

    /// Moves a category one slot up (`-1`) or down (`+1`), for the keyboard and
    /// VoiceOver, which have no drag to offer. A category at either end simply
    /// stays put: `moveCategory` already ignores a destination off the end, so
    /// this needs no special case for it.
    func nudgeCategory(id: UUID, by delta: Int) {
        guard let index = settings.categories.firstIndex(where: { $0.id == id })
        else { return }
        moveCategory(from: index, to: index + delta)
    }
}

// MARK: - History breakdown

@MainActor
extension AppModel {

    /// Totals per category over the last `days` days, ending today.
    ///
    /// Current categories come first in display order and appear even at zero —
    /// a neglected category should be visible, not absent. Then the bucket, then
    /// any archived names that still have records in range, alphabetically.
    func categoryTotals(days: Int) -> [CategoryTotal] {
        guard settings.categoriesEnabled else { return [] }

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

        totals.append(CategoryTotal(id: "fallback",
                                    name: settings.fallbackName,
                                    count: counts.removeValue(forKey: "") ?? 0))

        // Whatever is left is archived: it has records in range but no category.
        // Their display name comes from the first record that used it, so the
        // user's original capitalisation survives.
        let archivedNames = Dictionary(
            grouping: inRange.compactMap(\.category),
            by: Category.normalized)
        for (normalized, count) in counts.sorted(by: {
            $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }) {
            let display = archivedNames[normalized]?.first ?? normalized
            totals.append(CategoryTotal(id: "archived-\(normalized)", name: display, count: count))
        }

        return totals
    }
}
