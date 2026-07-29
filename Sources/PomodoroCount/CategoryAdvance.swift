import Foundation

/// Picks the session target that succeeds a finished one.
///
/// Pure and total over its inputs, so wrapping, the goal-0 skip and every way of
/// staying put are all testable without a timer, a store or a view — the same
/// shape as `Reorder.destination` and `HeatmapLayout.cells`.
/// `AppModel.advanceTargetIfMet()` is the only caller.
enum CategoryAdvance {

    /// The target to move to, or nil to stay put.
    ///
    /// `rows` is `AppModel.todayProgress`: every category in display order, then
    /// the fallback bucket. Returns nil unless `current` is one of those rows
    /// *and* its goal is met — a goal met by some other category is not this
    /// rule's business.
    static func next(after current: CategoryTarget,
                     in rows: [CategoryProgress]) -> CategoryTarget? {
        guard let start = rows.firstIndex(where: { matches(current, $0) }),
              rows[start].isMet
        else { return nil }

        // Wrap, so a met category at the end of the list looks back at
        // unfinished ones above it. The range stops one short of a full lap, so
        // a met target can never be handed back as its own successor.
        for offset in 1..<max(rows.count, 1) {
            let row = rows[(start + offset) % rows.count]
            // Availability has to ask for a goal as well as an unmet one:
            // `isMet` is false forever when the goal is 0, so a goal-0 category
            // would be a sink the rotation could never leave.
            guard row.goal > 0, !row.isMet else { continue }
            return row.isFallback ? .fallback : .named(row.name)
        }
        return nil
    }

    /// The bucket is identified by `isFallback` rather than by name: its row
    /// carries whatever the user called it, and `.fallback` names nothing.
    private static func matches(_ target: CategoryTarget,
                                _ row: CategoryProgress) -> Bool {
        switch target {
        case .fallback:
            return row.isFallback
        case .named(let name):
            return !row.isFallback
                && Category.normalized(row.name) == Category.normalized(name)
        }
    }
}
