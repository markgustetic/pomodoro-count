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

    @Test func groupsRecordsByDay() {
        #expect(seeded().history().count == 3)
    }

    @Test func mostRecentDayComesFirst() {
        let history = seeded().history()
        #expect(history.first?.count == 2)
        #expect(Calendar.current.isDateInToday(history.first!.date))
    }

    @Test func historyIsSortedNewestFirst() {
        let dates = seeded().history().map(\.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func talliesUseTheRightWindows() {
        let m = seeded()
        #expect(m.todayCount == 2)
        #expect(m.weekCount == 3)     // excludes the 10-day-old one
        #expect(m.totalCount == 4)    // counts everything
    }

    @Test func historyRespectsItsLimit() {
        let (m, _) = makeModel()
        m.records = (0..<40).map { Record(at: .daysAgo($0), source: "manual") }
        #expect(m.history().count == 30)          // default limit
        #expect(m.history(limit: 5).count == 5)
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
        #expect(m.history().count == 1)
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
}
