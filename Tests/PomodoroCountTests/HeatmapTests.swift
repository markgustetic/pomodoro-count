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
    /// 53 squares plus 52 gaps have to fit across the canvas, inside the
    /// 1.0pt-per-side margin reserved for the hover ring.
    @Test func metricsFitAYearAcrossTheCanvas() {
        let (cell, gap, _) = HeatmapLayout.metrics(columns: 53, size: canvas)
        #expect(gap == 1)
        #expect(abs(cell - (276 - 2 - 52) / 53) < 0.001)
        #expect(53 * cell + 52 * gap <= 274.001)
    }

    /// With few columns there is width to spare, so the seven weekday rows are
    /// what binds instead.
    @Test func aShortSeriesIsBoundByHeight() {
        let (cell, _, _) = HeatmapLayout.metrics(columns: 1, size: canvas)
        #expect(abs(cell - (40 - 2 - 6) / 7) < 0.001)
    }

    /// No days, no grid — and no division by zero.
    @Test func anEmptyGridHasNoCell() {
        #expect(HeatmapLayout.metrics(columns: 0, size: canvas).cell == 0)
    }

    /// A width proposal too narrow for even one column (a nil-width
    /// GeometryReader reports 10pt) drives the raw cell size negative before
    /// the clamp — this is live defensive code, not dead code, and
    /// `hitTest`'s `cell > 0` guard depends on it landing at zero.
    @Test func aNarrowProposalClampsToZeroInsteadOfGoingNegative() {
        #expect(HeatmapLayout.metrics(columns: 53, size: CGSize(width: 10, height: 40)).cell == 0)
    }

    /// The grid sits inside the canvas with a 1.0pt margin on every side —
    /// the ring's 0.5pt path expansion plus the 0.5pt outward half of its
    /// centred 1pt stroke — so the hover ring has room to close on every
    /// edge without `Canvas` clipping it.
    @Test func theGridLeavesMarginForTheRingOnAllSides() {
        let columns = 53
        let m = HeatmapLayout.metrics(columns: columns, size: canvas)
        #expect(m.origin.x >= 1.0 && m.origin.y >= 1.0)
        #expect(m.origin.x + CGFloat(columns) * m.cell + CGFloat(columns - 1) * m.gap + 1.0 <= canvas.width)
        #expect(m.origin.y + 7 * m.cell + 6 * m.gap + 1.0 <= canvas.height)
    }

    /// The centre of the square at (column, row), in canvas coordinates.
    private func centre(column: Int, row: Int, columns: Int) -> CGPoint {
        let (cell, gap, origin) = HeatmapLayout.metrics(columns: columns, size: canvas)
        let step = cell + gap
        return CGPoint(x: origin.x + CGFloat(column) * step + cell / 2,
                       y: origin.y + CGFloat(row) * step + cell / 2)
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
        let (cell, _, origin) = HeatmapLayout.metrics(columns: 2, size: canvas)
        let inTheGap = CGPoint(x: origin.x + cell + 0.5, y: origin.y + cell / 2)
        #expect(HeatmapLayout.hitTest(inTheGap, cells: cells, columns: 2, size: canvas) == nil)
    }

    @Test func aPointOutsideTheGridHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 275, y: 5),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: -1, y: 5),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 2, y: -1),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 2, y: 41),
                                      cells: cells, columns: 2, size: canvas) == nil)
    }

    /// `columns: 0` drives `metrics` to `cell == 0`, the other branch of
    /// `hitTest`'s `cell > 0` guard from the narrow-width case above.
    @Test func aZeroColumnGridHitsNothing() {
        #expect(HeatmapLayout.hitTest(.zero, cells: [], columns: 0, size: canvas) == nil)
    }

    /// A short series leaves the tail of its last column empty. Those slots are
    /// grid positions with no day behind them.
    @Test func anEmptySlotInTheGridHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 3), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 0, row: 5, columns: 1),
                                      cells: cells, columns: 1, size: canvas) == nil)
    }

    /// `center` is `hitTest` run backwards, so the strongest check is that the
    /// round trip closes: the point a cell reports must hit that same cell.
    @Test func aCellsCentreHitsThatCell() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        for index in [0, 7, 9, 13] {
            let point = HeatmapLayout.center(of: index, cells: cells, columns: 2, size: canvas)
            #expect(point != nil)
            #expect(HeatmapLayout.hitTest(point!, cells: cells, columns: 2, size: canvas) == index)
        }
    }

    /// It must agree with the test helper that derives centres independently,
    /// or one of the two is lying about where the grid is.
    @Test func aCellsCentreMatchesTheGridArithmetic() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        let point = HeatmapLayout.center(of: 9, cells: cells, columns: 2, size: canvas)
        let expected = centre(column: 1, row: 2, columns: 2)
        #expect(abs(point!.x - expected.x) < 0.001)
        #expect(abs(point!.y - expected.y) < 0.001)
    }

    @Test func anIndexOutsideTheCellsHasNoCentre() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 3), calendar: mondayFirst)
        #expect(HeatmapLayout.center(of: 9, cells: cells, columns: 1, size: canvas) == nil)
        #expect(HeatmapLayout.center(of: -1, cells: cells, columns: 1, size: canvas) == nil)
    }
}
