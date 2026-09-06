import Foundation

/// The rules that make a one-time task leave, and keep it above the standing
/// categories while it is here. Pure, so the day-change sweep and the reorder
/// guard are tested without an `AppModel`.
enum TaskExpiry {

    /// The categories that survive into `today` (a start-of-day date): every
    /// standing category, and every task whose day is not yet over. Order is
    /// preserved.
    static func surviving(_ categories: [Category], today: Date) -> [Category] {
        categories.filter { category in
            guard let day = category.expiresOn else { return true }
            // Both sides are starts of days, so this is a whole-day comparison
            // without a calendar walk.
            return today <= day
        }
    }

    /// Whether moving the row at `from` to `to` keeps every task above every
    /// standing category. Tasks are inserted at the top and this is the only
    /// way a row changes position, so the block of tasks stays contiguous —
    /// which means "both ends are the same kind" is the whole test: a task
    /// landing on a task's slot stays in the task block, and likewise for
    /// categories. Out-of-range indices are refused rather than trapped,
    /// because the drag computes destinations that can run off the end.
    static func moveKeepsTasksOnTop(_ categories: [Category], from: Int, to: Int) -> Bool {
        guard categories.indices.contains(from), categories.indices.contains(to)
        else { return false }
        return categories[from].isTask == categories[to].isTask
    }
}
