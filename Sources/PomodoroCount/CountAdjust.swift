import Foundation

/// Picks which record a subtract removes.
///
/// Pure and total over its inputs, so "today's newest in this category" is
/// testable without a store, a view or a clock the test has to fake — the same
/// shape as `CategoryAdvance.topUnmet` and `Reorder.destination`.
/// `AppModel.unlogToday` is the only caller.
enum CountAdjust {

    /// Index of today's most recent record filed under `category`, or nil when
    /// there is nothing to remove.
    ///
    /// `category` is a display name and is normalized here, exactly as
    /// `todayCount(inCategory:)` does it — a record stored as "Writing" has to
    /// be found from a row labelled "writing". `nil` means the fallback bucket,
    /// whose records carry no category at all, and it matches *only* those: a
    /// bucket subtract must never reach into a named category.
    ///
    /// Newest by timestamp rather than last in the array, because those are not
    /// the same thing — a session completion can be appended after a manual log
    /// that was backdated, and the user means the newest one.
    static func newestTodayIndex(in records: [Record], category: String?) -> Int? {
        let wanted = category.map(Category.normalized)
        let calendar = Calendar.current
        return records.indices
            .filter {
                calendar.isDateInToday(records[$0].at)
                    && records[$0].category.map(Category.normalized) == wanted
            }
            .max { records[$0].at < records[$1].at }
    }
}
