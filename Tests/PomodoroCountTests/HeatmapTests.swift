import Testing
import Foundation
import CoreGraphics
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

    /// The real canvas: the panel is 300pt wide and `HeatmapView` is 40pt tall.
    private var canvas: CGSize { CGSize(width: 276, height: 40) }

    /// A year is ~53 week-columns, and at that count the width is what binds:
    /// 53 squares plus 52 gaps have to fit across the canvas.
    @Test func metricsFitAYearAcrossTheCanvas() {
        let (cell, gap) = HeatmapLayout.metrics(columns: 53, size: canvas)
        #expect(gap == 1)
        #expect(abs(cell - (276 - 52) / 53) < 0.001)
        #expect(53 * cell + 52 * gap <= 276.001)
    }

    /// With few columns there is width to spare, so the seven weekday rows are
    /// what binds instead.
    @Test func aShortSeriesIsBoundByHeight() {
        let (cell, _) = HeatmapLayout.metrics(columns: 1, size: canvas)
        #expect(abs(cell - (40 - 6) / 7) < 0.001)
    }

    /// No days, no grid — and no division by zero.
    @Test func anEmptyGridHasNoCell() {
        #expect(HeatmapLayout.metrics(columns: 0, size: canvas).cell == 0)
    }

    /// The centre of the square at (column, row), in canvas coordinates.
    private func centre(column: Int, row: Int, columns: Int) -> CGPoint {
        let (cell, gap) = HeatmapLayout.metrics(columns: columns, size: canvas)
        let step = cell + gap
        return CGPoint(x: CGFloat(column) * step + cell / 2,
                       y: CGFloat(row) * step + cell / 2)
    }

    @Test func hitTestFindsTheFirstCell() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 0, row: 0, columns: 2),
                                      cells: cells, columns: 2, size: canvas) == 0)
    }

    @Test func hitTestFindsTheLastCell() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 1, row: 6, columns: 2),
                                      cells: cells, columns: 2, size: canvas) == 13)
    }

    /// The index a hit test returns addresses the same day in the series the
    /// cells were built from. The readout formats from that series, so if this
    /// slips it names one day while ringing another.
    @Test func aHitIndexAddressesTheSameDayInTheSeries() {
        let stats = week(startingMonday: 14)
        let cells = HeatmapLayout.cells(for: stats, calendar: mondayFirst)
        let hit = HeatmapLayout.hitTest(centre(column: 1, row: 2, columns: 2),
                                        cells: cells, columns: 2, size: canvas)
        #expect(hit == 9)
        #expect(cells[9].count == stats[9].count)
        #expect(cells[9].column == 1)
        #expect(cells[9].row == 2)
    }

    /// The 1pt gap between squares belongs to no day.
    @Test func aPointInTheGapHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        let (cell, _) = HeatmapLayout.metrics(columns: 2, size: canvas)
        let inTheGap = CGPoint(x: cell + 0.5, y: cell / 2)
        #expect(HeatmapLayout.hitTest(inTheGap, cells: cells, columns: 2, size: canvas) == nil)
    }

    @Test func aPointOutsideTheGridHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 275, y: 5),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: -1, y: 5),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 2, y: 41),
                                      cells: cells, columns: 2, size: canvas) == nil)
    }

    /// A short series leaves the tail of its last column empty. Those slots are
    /// grid positions with no day behind them.
    @Test func anEmptySlotInTheGridHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 3), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 0, row: 5, columns: 1),
                                      cells: cells, columns: 1, size: canvas) == nil)
    }
}
