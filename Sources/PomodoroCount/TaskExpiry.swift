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
}
