import Testing
import Foundation
@testable import PomodoroCount

/// The hover readout card floating over the History graphs. Naming a day is
/// `dayLabel`'s job and is pinned in `PresentationTests`; these pin the
/// composition around it, so a stub label keeps the assertions free of the
/// machine's locale.
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

    /// No noun: at 300pt "Jun 2 · 5 pomodoros" is twice the width of
    /// "Jun 2 · 5", and that difference is what makes a floating card viable
    /// here instead of a line with a whole row to itself.
    @Test func theTooltipNamesTheDayAndItsCount() {
        #expect(HistoryReadout.tooltip(hoveredIndex: 1, series: series([3, 5, 2]),
                                       dayLabel: stub) == "Jun 2 · 5")
    }

    /// A day off is a real answer — the heatmap draws those cells, so hovering
    /// one has to say something.
    @Test func theTooltipStillReadsOnADayOff() {
        #expect(HistoryReadout.tooltip(hoveredIndex: 0, series: series([0]),
                                       dayLabel: stub) == "Jun 1 · 0")
    }

    @Test func nothingHoveredIsNoTooltip() {
        #expect(HistoryReadout.tooltip(hoveredIndex: nil, series: series([3, 5]),
                                       dayLabel: stub) == nil)
    }

    /// The range picker swaps the series out from under a live pointer. A
    /// stale index has to read as no hover, not trap.
    @Test func anOutOfRangeIndexIsNoTooltip() {
        #expect(HistoryReadout.tooltip(hoveredIndex: 9, series: series([3, 5]),
                                       dayLabel: stub) == nil)
    }
}
