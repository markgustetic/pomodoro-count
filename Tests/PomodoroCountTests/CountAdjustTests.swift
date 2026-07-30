import Testing
import Foundation
@testable import PomodoroCount

/// Which record a subtract removes. Pure, so no store and no model.
@Suite struct CountAdjustTests {

    @Test func findsNothingInAnEmptyStore() {
        #expect(CountAdjust.newestTodayIndex(in: [], category: "Writing") == nil)
    }

    @Test func findsNothingWhenNoRecordMatches() {
        let records = [Record(at: .todayAt(hour: 12), source: "manual", category: "Admin")]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "Writing") == nil)
    }

    /// Newest by timestamp, not last in the array: a backdated manual log can be
    /// appended after a session completion, and the newest one is what the user
    /// means to drop. `undoLast` has the same rule for the same reason.
    @Test func findsTheNewestNotTheLastAppended() {
        let records = [
            Record(at: .todayAt(hour: 12), source: "timer", category: "Writing"),
            Record(at: .todayAt(hour: 9), source: "manual", category: "Writing"),
        ]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "Writing") == 0)
    }

    @Test func normalizesTheNameItLooksFor() {
        let records = [Record(at: .todayAt(hour: 12), source: "manual", category: "Writing")]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "  writing ") == 0)
    }

    /// nil means the bucket, and the bucket is not a wildcard: a named
    /// category's record must not answer a bucket query, or a subtract on the
    /// bucket would silently eat a pomodoro belonging to someone else's row.
    @Test func matchesTheBucketOnlyOnRecordsWithNoCategory() {
        let records = [
            Record(at: .todayAt(hour: 12), source: "manual", category: "Writing"),
            Record(at: .todayAt(hour: 9), source: "manual", category: nil),
        ]
        #expect(CountAdjust.newestTodayIndex(in: records, category: nil) == 1)
    }

    /// The row shows today, so the subtract adjusts today — even when today is
    /// empty and yesterday is not.
    @Test func ignoresEarlierDays() {
        let records = [Record(at: .daysAgo(1), source: "manual", category: "Writing")]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "Writing") == nil)
    }
}
