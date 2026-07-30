import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct HistoryTests {

    private func seeded() -> AppModel {
        let (m, _) = makeModel()
        m.records = [
            Record(at: Date(), source: "manual"),
            Record(at: Date(), source: "timer"),
            Record(at: .daysAgo(2), source: "manual"),
            Record(at: .daysAgo(10), source: "manual"),
        ]
        return m
    }

    @Test func talliesUseTheRightWindows() {
        let m = seeded()
        #expect(m.todayCount == 2)
        #expect(m.weekCount == 3)     // excludes the 10-day-old one
        #expect(m.totalCount == 4)    // counts everything
    }

    /// Yesterday's pomodoros must not count toward today, but must stay in history —
    /// this is the daily rollover the menu bar count depends on.
    @Test func yesterdayRollsOutOfTodayButStaysInHistory() {
        let (m, _) = makeModel()
        m.records = [
            Record(at: .daysAgo(1), source: "manual"),
            Record(at: .daysAgo(1), source: "timer"),
        ]
        #expect(m.todayCount == 0)
        #expect(m.totalCount == 2)
        #expect(m.history(days: 30).count == 1)
    }

    // MARK: history(days:) — the range-scoped day list

    /// This backs the History tab's day list, which the Week/Month control must
    /// govern the same way it already governs the chart and category breakdown.

    @Test func historyDaysIncludesARecordInsideTheRange() {
        let (m, _) = makeModel()
        m.records = [Record(at: .daysAgo(3), source: "manual")]
        #expect(m.history(days: 7).count == 1)
    }

    @Test func historyDaysExcludesARecordOutsideTheRange() {
        let (m, _) = makeModel()
        m.records = [Record(at: .daysAgo(10), source: "manual")]
        #expect(m.history(days: 7).isEmpty)
    }

    @Test func historyDaysWeekAndMonthDifferForTheSameData() {
        let (m, _) = makeModel()
        m.records = [Record(at: .daysAgo(20), source: "manual")]
        #expect(m.history(days: 7).isEmpty)
        #expect(m.history(days: 30).count == 1)
    }

    /// Unlike `dailySeries`, the day list has never padded in empty days — it
    /// only lists days you actually logged something. Sparse data over a
    /// 7-day window should come back as 2 rows, not 7.
    @Test func historyDaysDoesNotPadEmptyDays() {
        let (m, _) = makeModel()
        m.records = [
            Record(at: Date(), source: "manual"),
            Record(at: .daysAgo(3), source: "manual"),
        ]
        #expect(m.history(days: 7).count == 2)
    }

    @Test(arguments: [7, 30]) func dailySeriesIsZeroFilledAndExactlyNDays(days: Int) {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual")]
        let series = m.dailySeries(days: days)
        #expect(series.count == days)
        #expect(series.dropLast().allSatisfy { $0.count == 0 })
    }

    @Test func dailySeriesRunsOldestFirstAndEndsToday() {
        let (m, _) = makeModel()
        let series = m.dailySeries(days: 7)
        #expect(series.map(\.date) == series.map(\.date).sorted())
        #expect(Calendar.current.isDateInToday(series.last!.date))
    }

    @Test func dailySeriesCountsMatchTheRecords() {
        let (m, _) = makeModel()
        m.records = [
            Record(at: Date(), source: "manual"),
            Record(at: Date(), source: "manual"),
            Record(at: .daysAgo(1), source: "timer"),
        ]
        let series = m.dailySeries(days: 7)
        #expect(series.last?.count == 2)
        #expect(series.dropLast().last?.count == 1)
        #expect(series.map(\.count).reduce(0, +) == 3)
    }

    /// A pomodoro older than the requested window must not leak into the chart.
    @Test func dailySeriesExcludesRecordsOutsideTheWindow() {
        let (m, _) = makeModel()
        m.records = [Record(at: .daysAgo(20), source: "manual")]
        #expect(m.dailySeries(days: 7).allSatisfy { $0.count == 0 })
        #expect(m.dailySeries(days: 30).map(\.count).reduce(0, +) == 1)
    }

    /// `HistoryTab` derives its day list from `dailySeries(days:)` instead of
    /// calling `history(days:)` a second time on every pointer move — both
    /// read `windowStart(days:)` and bucket by `startOfDay`, but this pins
    /// that the substitution is exact rather than merely plausible. Records
    /// land on the window's first and last day, with a zero-record gap day
    /// (2 days ago) inside it.
    @Test func historyMatchesDailySeriesReversedAndFilteredToNonZeroDays() {
        let (m, _) = makeModel()
        m.records = [
            Record(at: Date(), source: "manual"),      // today: window's last day
            Record(at: .daysAgo(1), source: "manual"),
            Record(at: .daysAgo(1), source: "timer"),
            Record(at: .daysAgo(4), source: "manual"),
            Record(at: .daysAgo(6), source: "manual"), // window's first day (days: 7)
        ]
        let days = 7
        let history = m.history(days: days)
        let derived = m.dailySeries(days: days).reversed().filter { $0.count > 0 }
        #expect(history.map(\.date) == derived.map(\.date))
        #expect(history.map(\.count) == derived.map(\.count))
    }
}
