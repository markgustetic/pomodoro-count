import Foundation

// MARK: - One-time tasks

@MainActor
extension AppModel {

    /// Adds a one-time task at the top of the ranking and aims the target at
    /// it. Returns false and changes nothing when the name is empty or taken —
    /// the same rule as `addCategory`, so a task cannot shadow a category, the
    /// bucket, or another task — or when the goal is zero: a task with nothing
    /// to count is not a task.
    ///
    /// One assignment to `settings`, not an insert followed by `pickTarget`.
    /// Each mutation of `settings` is its own write to disk, and the
    /// alternative — a `suspendSaves()` pair — would add a call site to a
    /// mechanism whose comment in Store.swift enumerates the existing ones by
    /// name. The pin is computed the way `pickTarget` computes it, against
    /// today's records under this name: a re-added name reunites with its
    /// archived history, so a task can be met on arrival.
    @discardableResult
    func addTask(name: String, goal: Int, now: Date = Date()) -> Bool {
        guard isCategoryNameAvailable(name), goal > 0 else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = settings
        updated.categories.insert(
            Category(name: trimmed, dailyGoal: min(goal, 20),
                     expiresOn: Calendar.current.startOfDay(for: now)),
            at: 0)
        // Aim at the new task unless a session is actually in flight, in which
        // case the record that finishes it must still land on what Start was
        // pressed against — the same guard `realignTarget()` keeps. The task
        // still sits on top; a click aims it once the session is done.
        if !(phase == .work && isRunning) {
            updated.aim(at: .named(trimmed))
            // Computed, not cleared: a re-added name reunites with today's
            // archived records (categories are archived, not deleted), so a
            // task can be met the moment it is added, and picking a met
            // category is a pin — the one reading `pickTarget` gives it.
            updated.targetPinned = todayCount(inCategory: trimmed) >= updated.categories[0].dailyGoal
            updated.targetAimedOn = now
        }
        settings = updated
        return true
    }

    /// Drops every one-time task whose day is over. Records are untouched:
    /// the name stays on them, which is how History keeps a finished task —
    /// the same archiving `removeCategory` does. If the session target was
    /// one of the leavers its pin goes with it, again as `removeCategory`
    /// does; the target *name* is left alone, exactly as `removeCategory`
    /// leaves it: with auto-advance on, `realignTarget()` runs next and the
    /// earlier-day stamp restarts the plan at the top of the ranking; with it
    /// off, the name no longer resolves and the target reads as the bucket
    /// until the user picks again — the same state removing a category by
    /// hand leaves.
    ///
    /// Idempotent and cheap, so it is called on every `handleDayChange` and
    /// from `load()` — the latter for models built without a launch (tests,
    /// `--preview`, the reorder harness), which never see a day change.
    /// Writes nothing when nothing expires: this runs on every wake.
    func expireTasks(now: Date = Date()) {
        // Not while a session is actually in flight — the same guard as
        // `realignTarget()`, for the same reason: the record that finishes
        // this session has to land on what Start was pressed against, and
        // sweeping its task out from under it would send that record to the
        // bucket. Order-dependent too: on a wake that crosses midnight the
        // day-change notification and the overdue timer fire in unspecified
        // order. The sweep is idempotent, so the next wake or launch does it.
        guard !(phase == .work && isRunning) else { return }

        let today = Calendar.current.startOfDay(for: now)
        let surviving = TaskExpiry.surviving(settings.categories, today: today)
        guard surviving.count != settings.categories.count else { return }
        let leaving = Set(settings.categories.map { Category.normalized($0.name) })
            .subtracting(surviving.map { Category.normalized($0.name) })
        var updated = settings
        updated.categories = surviving
        if let target = updated.sessionTargetName.map(Category.normalized),
           leaving.contains(target) {
            updated.targetPinned = false
        }
        settings = updated
    }
}
