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

    /// The pixel geometry of the grid: the square each day gets, the gap
    /// between squares, and the origin the grid starts drawing at.
    ///
    /// Extracted from the draw loop so the hit test can read the same numbers.
    /// A hit test that recomputed this independently could drift by a fraction
    /// of a point and name a different day than the one it highlights — which
    /// is exactly the failure a hover readout would make invisible.
    ///
    /// `size` is inset by 1.0pt on every side before the grid is laid out;
    /// `origin` is that inset rectangle's top-left corner. The margin exists
    /// for the hover ring, and its value is derived from the ring's own
    /// geometry, not chosen: the ring path is the square expanded by 0.5pt
    /// (`insetBy(dx: -0.5, dy: -0.5)`), then stroked with `lineWidth: 1`
    /// *centred* on that path, so another 0.5pt extends outward beyond it —
    /// 1.0pt of total protrusion past the square's tight edge. Reserving only
    /// the 0.5pt path expansion and forgetting the stroke's outward half
    /// leaves `Canvas` clipping the outer shoulder of the ring on row 0,
    /// column 0, and the last column: the stroke reads as thinner there than
    /// on its inward-facing edges, which is easy to miss at a glance since
    /// the ring still looks closed. Without any reservation,
    /// `columns*cell + (columns-1)*gap == size.width` by construction — the
    /// outermost squares would touch the canvas edge exactly, and the whole
    /// ring would clip on those edges. Both axes get the margin, even though
    /// the 40pt-tall frame only needs it on rare short series, so the ring
    /// closes on row 0 too and this stays one rule instead of two.
    static func metrics(columns: Int, size: CGSize) -> (cell: CGFloat, gap: CGFloat, origin: CGPoint) {
        let gap: CGFloat = 1
        let margin: CGFloat = 1.0
        let origin = CGPoint(x: margin, y: margin)
        guard columns > 0 else { return (0, gap, origin) }
        let insetSize = CGSize(width: size.width - margin * 2, height: size.height - margin * 2)
        let cell = min((insetSize.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                       (insetSize.height - gap * 6) / 7)
        // A narrow width proposal (a nil-width GeometryReader reports 10pt)
        // pushes this negative before there's a single column's worth of
        // room; hitTest's `cell > 0` guard depends on this clamp landing on
        // zero rather than a negative cell size, not on the case being rare.
        return (max(0, cell), gap, origin)
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
        let (cell, gap, origin) = metrics(columns: columns, size: size)
        // The grid starts at origin, not (0, 0) — the margin `metrics`
        // reserves for the ring is nobody's day either.
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard cell > 0, local.x >= 0, local.y >= 0 else { return nil }
        let step = cell + gap
        let column = Int(local.x / step)
        let row = Int(local.y / step)
        guard column < columns, row < 7 else { return nil }
        // Past the square is the gap, and the gap is nobody's day.
        guard local.x - CGFloat(column) * step <= cell,
              local.y - CGFloat(row) * step <= cell else { return nil }
        return cells.firstIndex { $0.column == column && $0.row == row }
    }

    /// The centre of a cell, in canvas coordinates — `hitTest` run backwards.
    ///
    /// A headless render has no pointer, so this is where `--hover-graph` puts
    /// the tooltip. Reads the same `metrics` as the draw loop and the hit
    /// test, so all three agree about where a square is; a round-trip test
    /// pins that.
    static func center(of index: Int, cells: [HeatmapCell],
                       columns: Int, size: CGSize) -> CGPoint? {
        guard cells.indices.contains(index) else { return nil }
        let (cell, gap, origin) = metrics(columns: columns, size: size)
        guard cell > 0 else { return nil }
        let step = cell + gap
        return CGPoint(x: origin.x + CGFloat(cells[index].column) * step + cell / 2,
                       y: origin.y + CGFloat(cells[index].row) * step + cell / 2)
    }
}

/// A year of days as a GitHub-style grid: one cell per day, weekday rows,
/// week columns, ink proportional to the count. At 365 bars the bar chart is
/// texture pretending to be data; the grid is honest about being texture and
/// legible for exactly that reason.
struct HeatmapView: View {
    let stats: [DayStat]
    @Binding var hovered: Int?
    @Binding var hoverPoint: CGPoint?
    @Environment(\.palette) private var palette

    var body: some View {
        let cells = HeatmapLayout.cells(for: stats)
        let columns = (cells.map(\.column).max() ?? 0) + 1
        let maxCount = max(1, cells.map(\.count).max() ?? 1)
        let total = stats.reduce(0) { $0 + $1.count }
        let highlight = hovered ?? PreviewOverrides.hoveredGraphIndex

        GeometryReader { geo in
            Canvas { context, size in
                let (cell, gap, origin) = HeatmapLayout.metrics(columns: columns, size: size)
                for (index, c) in cells.enumerated() {
                    let rect = CGRect(x: origin.x + CGFloat(c.column) * (cell + gap),
                                      y: origin.y + CGFloat(c.row) * (cell + gap),
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
                    hoverPoint = point
                case .ended:
                    hovered = nil
                    hoverPoint = nil
                }
            }
            // A render has no pointer, so a forced hover gets the cell's own
            // centre. `onAppear` rather than a computed value: writing state
            // during layout is how SwiftUI gets an update loop.
            .onAppear {
                if let forced = PreviewOverrides.hoveredGraphIndex {
                    hoverPoint = HeatmapLayout.center(of: forced, cells: cells,
                                                      columns: columns, size: geo.size)
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year of daily pomodoros")
        .accessibilityValue("\(total) \(total == 1 ? "pomodoro" : "pomodoros") in the last year")
    }
}
