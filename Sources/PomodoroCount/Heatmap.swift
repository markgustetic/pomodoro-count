import SwiftUI

/// One day's spot in the year grid.
struct HeatmapCell: Equatable {
    let column: Int
    let row: Int
    let count: Int
}

/// The grid arithmetic behind the year heatmap, free of SwiftUI so it can be
/// tested directly: rows are weekdays (respecting the calendar's first day of
/// the week), and a new column starts each time the week wraps.
enum HeatmapLayout {
    static func cells(for stats: [DayStat], calendar: Calendar = .current) -> [HeatmapCell] {
        var out: [HeatmapCell] = []
        var column = 0
        for (index, stat) in stats.enumerated() {
            let weekday = calendar.component(.weekday, from: stat.date)
            let row = (weekday - calendar.firstWeekday + 7) % 7
            if index > 0 && row == 0 { column += 1 }
            out.append(HeatmapCell(column: column, row: row, count: stat.count))
        }
        return out
    }

    /// The pixel geometry of the grid: the square each day gets, and the gap
    /// between squares.
    ///
    /// Extracted from the draw loop so the hit test can read the same numbers.
    /// A hit test that recomputed this independently could drift by a fraction
    /// of a point and name a different day than the one it highlights — which
    /// is exactly the failure a hover readout would make invisible.
    static func metrics(columns: Int, size: CGSize) -> (cell: CGFloat, gap: CGFloat) {
        let gap: CGFloat = 1
        guard columns > 0 else { return (0, gap) }
        let cell = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                       (size.height - gap * 6) / 7)
        return (max(0, cell), gap)
    }

    /// The index of the cell under `point`, or nil for a point in the gap
    /// between squares, outside the grid, or on a grid slot no day occupies.
    ///
    /// Reads its geometry from `metrics`, so it can only ever name the square
    /// the draw loop actually drew. The returned index addresses `cells` —
    /// which `cells(for:)` builds 1:1 and in order from its `[DayStat]` — so
    /// it is equally an index into that series.
    ///
    /// The linear search is 365 comparisons on a pointer move, which is
    /// nothing next to the redraw it triggers; a lookup table would be a
    /// second copy of the layout to keep in sync.
    static func hitTest(_ point: CGPoint, cells: [HeatmapCell],
                        columns: Int, size: CGSize) -> Int? {
        let (cell, gap) = metrics(columns: columns, size: size)
        guard cell > 0, point.x >= 0, point.y >= 0 else { return nil }
        let step = cell + gap
        let column = Int(point.x / step)
        let row = Int(point.y / step)
        guard column < columns, row < 7 else { return nil }
        // Past the square is the gap, and the gap is nobody's day.
        guard point.x - CGFloat(column) * step <= cell,
              point.y - CGFloat(row) * step <= cell else { return nil }
        return cells.firstIndex { $0.column == column && $0.row == row }
    }
}

/// A year of days as a GitHub-style grid: one cell per day, weekday rows,
/// week columns, ink proportional to the count. At 365 bars the bar chart is
/// texture pretending to be data; the grid is honest about being texture and
/// legible for exactly that reason.
struct HeatmapView: View {
    let stats: [DayStat]
    @Binding var hovered: Int?
    @Environment(\.palette) private var palette

    var body: some View {
        let cells = HeatmapLayout.cells(for: stats)
        let columns = (cells.map(\.column).max() ?? 0) + 1
        let maxCount = max(1, cells.map(\.count).max() ?? 1)
        let total = stats.reduce(0) { $0 + $1.count }
        let highlight = hovered ?? PreviewOverrides.hoveredGraphIndex

        GeometryReader { geo in
            Canvas { context, size in
                let (cell, gap) = HeatmapLayout.metrics(columns: columns, size: size)
                for (index, c) in cells.enumerated() {
                    let rect = CGRect(x: CGFloat(c.column) * (cell + gap),
                                      y: CGFloat(c.row) * (cell + gap),
                                      width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.2)
                    if c.count == 0 {
                        // Present but empty — an absent cell would read as a hole
                        // in the calendar rather than a day off.
                        context.fill(path, with: .color(palette.hairline.opacity(0.35)))
                    } else {
                        let fraction = Double(c.count) / Double(maxCount)
                        context.fill(path, with: .color(palette.accent.opacity(0.25 + 0.75 * fraction)))
                    }
                    if index == highlight {
                        // Drawn expanded, so the 1pt stroke lands in the 1pt
                        // gap rather than eating into the ~4pt square it
                        // marks. An inset ring at this size leaves nothing to
                        // see — measured, not assumed.
                        let ring = Path(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5),
                                        cornerRadius: cell * 0.2 + 0.5)
                        context.stroke(ring, with: .color(palette.text), lineWidth: 1)
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovered = HeatmapLayout.hitTest(point, cells: cells,
                                                    columns: columns, size: geo.size)
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year of daily pomodoros")
        .accessibilityValue("\(total) \(total == 1 ? "pomodoro" : "pomodoros") in the last year")
    }
}
