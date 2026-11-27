import Foundation

/// The rules that make a one-time task leave, and keep it above the standing
/// categories while it is here. Pure, so the day-change sweep and the reorder
/// guard are tested without an `AppModel`.
enum TaskExpiry {

    /// The categories that survive into `today` (any instant on that day):
    /// every standing category, and every task whose day is not yet over.
    /// Order is preserved.
    static func surviving(_ categories: [Category], today: Date) -> [Category] {
        categories.filter { category in
            guard let day = category.expiresOn else { return true }
            // Day granularity, not <= on instants: a caller handing in a raw
            // Date() rather than a start-of-day must not sweep a task added
            // this morning.
            return Calendar.current.compare(today, to: day, toGranularity: .day) != .orderedDescending
        }
    }

    /// Whether moving the row at `from` to `to` keeps every task above every
    /// standing category. Tasks enter at the top (`addTask` inserts at index
    /// 0) and moves are the only other way a row changes position, so the
    /// block of tasks stays contiguous — which means "both ends are the same
    /// kind" is the whole test: a task landing on a task's slot stays in the
    /// task block, and likewise for categories. Out-of-range indices are
    /// refused rather than trapped so the function is total, like
    /// `TargetPick.action`: `nudgeCategory` hands `moveCategory` an
    /// `index + delta` that can run off the end, and `moveCategory` checks
    /// that first, but a pure rule should not depend on its caller's guard.
    static func moveKeepsTasksOnTop(_ categories: [Category], from: Int, to: Int) -> Bool {
        guard categories.indices.contains(from), categories.indices.contains(to)
        else { return false }
        return categories[from].isTask == categories[to].isTask
    }

    /// How far towards `to` the row at `from` may travel: up to the last slot
    /// held by a row of its own kind, and not into the other block.
    ///
    /// For the drag, which asks for wherever the pointer is and must be told
    /// where the row may actually go. Refusing an over-long move outright —
    /// which is all `moveKeepsTasksOnTop` can say — would leave a row that was
    /// dragged fast past the boundary sitting where it started, although every
    /// slot up to the boundary was open to it. Walking the path rather than
    /// comparing the two ends also means the answer does not lean on the task
    /// block being contiguous.
    ///
    /// Total, like its neighbour: a `to` off either end is clamped into the
    /// list, and a `from` that names no row is returned unchanged, which a
    /// caller reads as "nowhere to go".
    static func reachableDestination(_ categories: [Category], from: Int, towards to: Int) -> Int {
        guard categories.indices.contains(from) else { return from }
        let target = min(max(to, 0), categories.count - 1)
        let step = target > from ? 1 : -1
        var reached = from
        while reached != target, categories[reached + step].isTask == categories[from].isTask {
            reached += step
        }
        return reached
    }
}
