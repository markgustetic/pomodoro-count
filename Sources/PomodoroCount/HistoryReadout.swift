import Foundation

/// The History graphs' hover readout: which day the pointer is over, and the
/// line of text that names it.
///
/// Pure and free of SwiftUI for the same reason `StatusIcon.glyph` and
/// `HeatmapLayout.cells` are — a rendered line isn't assertable, the wording
/// behind it is, and both graphs have to phrase the same day identically.
enum HistoryReadout {

    /// The series index for `date`, matched on the calendar day. The chart
    /// hands back a `Date` interpolated from a pointer position, so it lands
    /// anywhere inside the day rather than on its midnight.
    static func index(for date: Date, in series: [DayStat],
                      calendar: Calendar = .current) -> Int? {
        series.firstIndex { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The readout line: the hovered day and its count, or the window's total
    /// when nothing is hovered.
    ///
    /// An out-of-range index reads as no hover rather than trapping — the
    /// range picker swaps the series under a live pointer, and a stale index
    /// must not take the panel down with it.
    static func text(hoveredIndex: Int?, series: [DayStat], days: Int,
                     dayLabel: (Date) -> String) -> String {
        if let i = hoveredIndex, series.indices.contains(i) {
            return "\(dayLabel(series[i].date)) · \(pomodoros(series[i].count))"
        }
        let total = series.reduce(0) { $0 + $1.count }
        return "\(pomodoros(total)) in the last \(days == 365 ? "year" : "\(days) days")"
    }

    /// Matches the pluralisation the tab's accessibility values already use, so
    /// a day off reads "0 pomodoros" rather than inventing a word for zero.
    private static func pomodoros(_ count: Int) -> String {
        "\(count) \(count == 1 ? "pomodoro" : "pomodoros")"
    }
}
