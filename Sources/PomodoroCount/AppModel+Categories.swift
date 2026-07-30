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

        // One tally pass over the records, not one full scan per category —
        // the per-category scans grew with both the category count and the
        // age of the store. Bucketless records tally under "" — same
        // convention `categoryTotals` uses.
        let cal = Calendar.current
        var doneToday: [String: Int] = [:]
        for record in records where cal.isDateInToday(record.at) {
            doneToday[record.category.map(Category.normalized) ?? "", default: 0] += 1
        }

        var rows = settings.categories.map { category in
            CategoryProgress(
                id: category.id.uuidString,
                name: category.name,
                done: doneToday[Category.normalized(category.name)] ?? 0,
                goal: category.dailyGoal,
                isFallback: false,
                isSessionTarget: sessionRunning && normalizedTarget == Category.normalized(category.name))
        }

        // Unconditional: it is the only row that can take a pomodoro belonging
        // to none of the categories, so it must not vanish at zero.
        rows.append(CategoryProgress(
            id: "fallback",
            name: settings.fallbackName,
            done: doneToday[""] ?? 0,
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
    ///
    /// A pin does not survive its own category leaving. The `sessionTarget`
    /// getter resolves a name no longer in the list to `.fallback`, so a pin
    /// left standing would silently pin the bucket — a category the user never
    /// asked to overshoot in.
    func removeCategory(id: UUID) {
        let leaving = settings.categories.first { $0.id == id }
            .map { Category.normalized($0.name) }
        var updated = settings
        updated.categories.removeAll { $0.id == id }
        if let leaving, updated.sessionTargetName.map(Category.normalized) == leaving {
            updated.targetPinned = false
        }
        settings = updated
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

// MARK: - The day's whole goal

@MainActor
extension AppModel {

    /// Every category's daily goal plus the bucket's, i.e. the number the day
    /// is aiming at. Zero while categories are off — goals are invisible then
    /// and must not drive anything.
    var todayGoalTotal: Int {
        guard settings.categoriesEnabled else { return 0 }
        return settings.categories.reduce(0) { $0 + $1.dailyGoal } + settings.fallbackGoal
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

        let cutoff = windowStart(days: days)
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

// MARK: - Following the day's plan

@MainActor
extension AppModel {

    /// Keeps the session target pointed at the day's plan.
    ///
    /// Two automatic triggers live here because they share every check around
    /// them. The start-of-day reset comes first and returns: at the start of a
    /// day nothing is met, so falling through to the advance could only ever be
    /// a no-op, and returning says so instead of leaving a reader to work it out.
    ///
    /// Called after every record is appended — a completed session and every
    /// external log — because a goal is met by whichever of those fills the last
    /// slot, and external hardware is this app's headline source. Also at launch
    /// and from the day-change/wake notification, which is where a new day gets
    /// noticed while the app is idle.
    ///
    /// Nothing re-checks this when a session starts, and that is deliberate: it
    /// is what lets a hand-picked target stick until its own goal is met.
    func realignTarget() {
        guard settings.categoriesEnabled, settings.autoAdvanceTarget else { return }
        // Don't re-aim a session that is actually in flight: an external log
        // that backfills the running target's last slot must not hand the
        // credit to wherever the target moves next — the record that finishes
        // this session still has to land on what Start was pressed against.
        // This does *not* block the advance at completion: `complete()` sets
        // `isRunning = false` before it appends the record and calls here, so a
        // session that meets its own goal still credits the right category and
        // only then hands the target on. Nor does it lose a start-of-day reset:
        // the stamp stays stale, and `complete()` is itself one of the points
        // that re-checks it. `phase == .work && isRunning` is deliberately the
        // same "actually running, not idle or paused" test `todayProgress` uses
        // for `isSessionTarget` — a paused session's target row isn't held
        // still either, so neither trigger should be.
        guard !(phase == .work && isRunning) else { return }

        // A stamp from an earlier day (or none at all, on a store written
        // before this feature existed) means the app has not aimed the target
        // today. Counts have reset, so the plan restarts at the top and
        // yesterday's pin is stale.
        guard Calendar.current.isDateInToday(settings.targetAimedOn ?? .distantPast)
        else { return restartFromTopOfRanking() }

        guard let next = CategoryAdvance.next(after: sessionTarget,
                                              in: todayProgress,
                                              pinned: settings.targetPinned)
        else { return }
        sessionTarget = next
    }

    /// Clears the pin, aims at the highest-ranked category with a goal left, and
    /// stamps today.
    ///
    /// Shared by the start-of-day reset above and by *Follow the order* in the
    /// target menu, which want exactly the same thing for different reasons.
    ///
    /// The stamp is written even when there is nothing to aim at — no category
    /// carries a goal, so `topUnmet` is nil. That makes this a start-of-day
    /// event rather than a lazy one: adding a goal at noon must not make the
    /// reset fire retroactively and move a target the user has been using all
    /// morning.
    ///
    /// One assignment to `settings`, not three. Each mutation of `settings` is
    /// its own `didSet` and its own synchronous write to disk, and the
    /// alternative — bracketing in `suspendSaves()`/`resumeSaves()` — would add
    /// call sites to a mechanism whose comment in Store.swift enumerates the
    /// existing ones by name and explains why each needs its own resume.
    func restartFromTopOfRanking() {
        var updated = settings
        updated.targetPinned = false
        updated.targetAimedOn = Date()
        if let top = CategoryAdvance.topUnmet(in: todayProgress) {
            updated.aim(at: top)
        }
        settings = updated
    }

    /// Aims the target where the user asked, and records which of the two kinds
    /// of pick it was.
    ///
    /// Picking a category that is **already met** can only mean "let me
    /// overshoot here", so it pins and the advance stops firing until the day
    /// turns over or the user hands control back. Picking one with a goal
    /// **left** just says "work here next" and needs no pin: the advance only
    /// fires on a met target, so the pick holds until the goal is reached and
    /// then rejoins the ranking on its own.
    ///
    /// Pinning *every* hand pick was the obvious design and is the wrong one. It
    /// gives the same overshoot, but one pick in the morning then leaves the
    /// ranking switched off for the rest of the day with only the user able to
    /// switch it back on — which is the papercut the advance exists to remove,
    /// reintroduced behind a single click.
    ///
    /// A goal-0 category needs no special case: `isMet` is false for it forever,
    /// so it never pins — and the advance can never fire on it either, so it
    /// holds regardless.
    ///
    /// The stamp matters as much as the pin. Without it a pick made this
    /// afternoon would still carry this morning's date only by luck, and a pick
    /// made on a store last touched yesterday would be wiped by the very next
    /// realign.
    func pickTarget(_ target: CategoryTarget) {
        var updated = settings
        updated.aim(at: target)
        updated.targetPinned = CategoryAdvance.isMet(target, in: todayProgress)
        updated.targetAimedOn = Date()
        settings = updated
    }

    /// Hands control back to the ranking, from the target menu's first entry.
    ///
    /// Deliberately not routed through `realignTarget()`, whose advance guards
    /// on the *current* target being met: handing control back has to work from
    /// an unfinished target too, and from a pinned one, which is precisely the
    /// case that guard would refuse. It also skips `realignTarget()`'s other
    /// guards — `categoriesEnabled`, `autoAdvanceTarget`, and `phase == .work &&
    /// isRunning` — and that is just as deliberate: this is a hand action, the
    /// same as the pill's category buttons, which have always been free to
    /// re-aim a session already in flight.
    func followTheOrder() {
        restartFromTopOfRanking()
    }
}
