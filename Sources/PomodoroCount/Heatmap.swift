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
}

/// A year of days as a GitHub-style grid: one cell per day, weekday rows,
/// week columns, ink proportional to the count. At 365 bars the bar chart is
/// texture pretending to be data; the grid is honest about being texture and
/// legible for exactly that reason.
struct HeatmapView: View {
    let stats: [DayStat]
    @Environment(\.palette) private var palette

    var body: some View {
        let cells = HeatmapLayout.cells(for: stats)
        let columns = (cells.map(\.column).max() ?? 0) + 1
        let maxCount = max(1, cells.map(\.count).max() ?? 1)
        let total = stats.reduce(0) { $0 + $1.count }

        Canvas { context, size in
            let gap: CGFloat = 1
            let cell = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                           (size.height - gap * 6) / 7)
            for c in cells {
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
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year of daily pomodoros")
        .accessibilityValue("\(total) \(total == 1 ? "pomodoro" : "pomodoros") in the last year")
    }
}
