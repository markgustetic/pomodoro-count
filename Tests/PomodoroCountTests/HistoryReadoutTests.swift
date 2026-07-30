import Testing
import Foundation
@testable import PomodoroCount

/// The hover readout under the History graphs. Naming a day is `dayLabel`'s
/// job and is pinned in `PresentationTests`; these pin the composition around
/// it, so a stub label keeps the assertions free of the machine's locale.
@Suite struct HistoryReadoutTests {

    private let cal = Calendar(identifier: .gregorian)

    /// Consecutive days from 2026-06-01, one per count.
    private func series(_ counts: [Int]) -> [DayStat] {
        let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        return counts.enumerated().map { offset, count in
            DayStat(date: cal.date(byAdding: .day, value: offset, to: start)!, count: count)
        }
    }

    private func stub(_ date: Date) -> String { "Jun \(cal.component(.day, from: date))" }

    @Test func restingTextTotalsTheWindow() {
        #expect(HistoryReadout.text(hoveredIndex: nil, series: series([3, 5, 2]),
                                    days: 7, dayLabel: stub)
                == "10 pomodoros in the last 7 days")
    }

    @Test func oneIsSingularInTheTotalToo() {
        #expect(HistoryReadout.text(hoveredIndex: nil, series: series([1]),
                                    days: 30, dayLabel: stub)
                == "1 pomodoro in the last 30 days")
    }

    /// 365 is spelled as a year. "in the last 365 days" is arithmetic, not
    /// English.
    @Test func aYearIsSpelledAsAYear() {
        #expect(HistoryReadout.text(hoveredIndex: nil, series: series([2, 2]),
                                    days: 365, dayLabel: stub)
                == "4 pomodoros in the last year")
    }

    @Test func hoverNamesTheDayAndItsCount() {
        #expect(HistoryReadout.text(hoveredIndex: 1, series: series([3, 5, 2]),
                                    days: 7, dayLabel: stub)
                == "Jun 2 · 5 pomodoros")
    }

    @Test func oneIsSingular() {
        #expect(HistoryReadout.text(hoveredIndex: 0, series: series([1]),
                                    days: 7, dayLabel: stub)
                == "Jun 1 · 1 pomodoro")
    }

    /// A day off is a real answer, not an empty one — the heatmap draws those
    /// cells, so hovering one has to say something.
    @Test func aDayOffStillReads() {
        #expect(HistoryReadout.text(hoveredIndex: 0, series: series([0]),
                                    days: 7, dayLabel: stub)
                == "Jun 1 · 0 pomodoros")
    }

    /// The range picker swaps the series out from under a live hover. A stale
    /// index has to fall back to the resting line, not trap.
    @Test func anOutOfRangeIndexFallsBackToTheTotal() {
        #expect(HistoryReadout.text(hoveredIndex: 9, series: series([3, 5]),
                                    days: 7, dayLabel: stub)
                == "8 pomodoros in the last 7 days")
    }

    @Test func indexFindsTheMatchingDay() {
        let s = series([3, 5, 2])
        let noon = cal.date(byAdding: .hour, value: 12, to: s[1].date)!
        #expect(HistoryReadout.index(for: noon, in: s, calendar: cal) == 1)
    }

    @Test func indexMissesDatesOutsideTheSeries() {
        let s = series([3, 5, 2])
        let before = cal.date(byAdding: .day, value: -1, to: s[0].date)!
        let after = cal.date(byAdding: .day, value: 1, to: s[2].date)!
        #expect(HistoryReadout.index(for: before, in: s, calendar: cal) == nil)
        #expect(HistoryReadout.index(for: after, in: s, calendar: cal) == nil)
    }

    @Test func indexOfAnEmptySeriesIsNil() {
        #expect(HistoryReadout.index(for: Date(), in: [], calendar: cal) == nil)
    }
}
