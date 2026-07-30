import Foundation

/// Picks the session target that succeeds a finished one.
///
/// Pure and total over its inputs, so the ranking, the goal-0 skip, the pin and
/// every way of staying put are all testable without a timer, a store or a
/// view — the same shape as `Reorder.destination` and `HeatmapLayout.cells`.
/// `AppModel` is the only caller.
enum CategoryAdvance {

    /// The highest-ranked row with a goal left, or nil when the day's plan is
    /// done.
    ///
    /// `rows` is `AppModel.todayProgress`: every category in display order, then
    /// the fallback bucket. Display order *is* the ranking — this list is a
    /// priority order, not a rotation, so the search starts at the top rather
    /// than at whatever position the target happens to occupy. That is the whole
    /// change from the rule this replaced, and it is why the modulo arithmetic
    /// that used to live here is gone: searching from the top cannot hand a met
    /// target back to itself, so nothing has to stop the search one short of a
    /// full lap any more.
    ///
    /// Availability asks for a goal as well as an unmet one: `isMet` is false
    /// forever when the goal is 0, so a goal-0 category would be a sink nothing
    /// could ever leave. The bucket joins on the same terms, and ranks last.
    static func topUnmet(in rows: [CategoryProgress]) -> CategoryTarget? {
        guard let row = rows.first(where: { $0.goal > 0 && !$0.isMet })
        else { return nil }
        return row.isFallback ? .fallback : .named(row.name)
    }

    /// The target to move to, or nil to stay put.
    ///
    /// Returns nil unless `current` is one of `rows` *and* its goal is met — a
    /// goal met by some other category is not this rule's business.
    ///
    /// `pinned` suppresses it outright. A pin means the user aimed the target at
    /// a category that was already met, which can only mean "let me overshoot
    /// here"; without it a deliberate overshoot would last exactly one pomodoro,
    /// because the next record would find the target met all over again.
    static func next(after current: CategoryTarget,
                     in rows: [CategoryProgress],
                     pinned: Bool) -> CategoryTarget? {
        guard !pinned, isMet(current, in: rows) else { return nil }
        return topUnmet(in: rows)
    }

    /// True when `target`'s row has met its goal. A target with no row at all —
    /// categories switched off, so `todayProgress` is empty — is not met, which
    /// is what keeps both callers from doing anything in that state.
    ///
    /// Public because it answers a question `AppModel.pickTarget(_:)` has to
    /// ask: picking a met category pins, picking an unfinished one does not.
    /// Asking it here rather than there keeps row-matching in one place.
    static func isMet(_ target: CategoryTarget,
                      in rows: [CategoryProgress]) -> Bool {
        rows.first { matches(target, $0) }?.isMet ?? false
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
