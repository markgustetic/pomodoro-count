import Testing
import Foundation
@testable import PomodoroCount

/// The year heatmap's grid arithmetic: days map to (column, row) where rows
/// are weekdays and a new column starts on each first-of-week. Pure layout,
/// tested with an explicit calendar so no machine's locale can move the rows.
@MainActor
@Suite struct HeatmapTests {

    /// Monday-first gregorian calendar, independent of the machine's locale.
    private var mondayFirst: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }

    /// `count` consecutive days starting at 2026-06-01, a Monday.
    private func week(startingMonday count: Int) -> [DayStat] {
        let cal = mondayFirst
        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        return (0..<count).map { offset in
            DayStat(date: cal.date(byAdding: .day, value: offset, to: monday)!, count: offset)
        }
    }

    @Test func everyDayGetsACell() {
        #expect(HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst).count == 14)
    }

    @Test func rowsFollowTheWeekday() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 7), calendar: mondayFirst)
        #expect(cells.map(\.row) == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func aNewColumnStartsEachWeek() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(cells.prefix(7).allSatisfy { $0.column == 0 })
        #expect(cells.suffix(7).allSatisfy { $0.column == 1 })
    }

    /// A series that starts mid-week still lands its first day on the right
    /// row, and the column advances at the next week boundary.
    @Test func aMidWeekStartKeepsItsWeekday() {
        let cal = mondayFirst
        let thursday = cal.date(from: DateComponents(year: 2026, month: 6, day: 4))!
        let stats = (0..<7).map { offset in
            DayStat(date: cal.date(byAdding: .day, value: offset, to: thursday)!, count: 0)
        }
        let cells = HeatmapLayout.cells(for: stats, calendar: cal)
        #expect(cells.first?.row == 3)          // Thursday, Monday-first
        #expect(cells.map(\.column) == [0, 0, 0, 0, 1, 1, 1])
    }

    @Test func countsRideAlong() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 3), calendar: mondayFirst)
        #expect(cells.map(\.count) == [0, 1, 2])
    }

    @Test func theYearRangeCoversThreeSixtyFive() {
        #expect(HistoryTab.ChartRange.year.days == 365)
    }
}
