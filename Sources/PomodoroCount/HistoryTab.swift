import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers

// MARK: - History

struct HistoryTab: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette
    // Week unless a preview asked for another: the Year heatmap is otherwise
    // unreachable headlessly, since nothing can drive the picker in a render.
    @State private var range: ChartRange =
        PreviewOverrides.historyRange.flatMap(ChartRange.init(rawValue:)) ?? .week
    @State private var grouping: Grouping = .day

    enum ChartRange: String, CaseIterable {
        case week = "Week", month = "Month", year = "Year"
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            }
        }
    }

    enum Grouping: String, CaseIterable { case day = "By day", category = "By category" }

    var body: some View {
        // Only the visible grouping's query runs — each is a full pass over
        // the window's records, and body re-evaluates on every model change:
        // a log, an undo, any settings edit. (Not on the timer tick — that
        // publishes from SessionClock, which this tab doesn't observe.)
        let showsCategoryBreakdown = grouping == .category && model.settings.categoriesEnabled
        let stats = showsCategoryBreakdown ? [] : model.history(days: range.days)
        let categoryTotals = showsCategoryBreakdown ? model.categoryTotals(days: range.days) : []
        let isEmpty = showsCategoryBreakdown ? categoryTotals.isEmpty : stats.isEmpty
        PanelTabScroller {
            // 14 rather than the panel's usual 10: this tab is dense with
            // distinct sections — picker, chart, tiles, picker, list — and
            // they read as one slab without the extra air between them.
            VStack(spacing: 14) {
            SegmentedControl(
                items: ChartRange.allCases.map { (value: $0, label: $0.rawValue) },
                selection: $range,
                accessibilityLabel: "Chart range")

            // A year of daily bars is texture pretending to be data; the
            // heatmap grid is the honest form at that scale.
            if range == .year {
                HeatmapView(stats: model.dailySeries(days: range.days))
            } else {
                chart
            }

            HStack(spacing: 8) {
                statTile("This week", model.weekCount)
                statTile("All time", model.totalCount)
            }

            if model.totalCount > 0 {
                Button("Export CSV…", action: exportCSV)
                    .buttonStyle(HoverTextButtonStyle())
                    .font(.caption)
                    .help("Save your whole history as a spreadsheet")
                    .accessibilityHint("Saves your whole history as a spreadsheet file")
            }

            if model.settings.categoriesEnabled {
                SegmentedControl(
                    items: Grouping.allCases.map { (value: $0, label: $0.rawValue) },
                    selection: $grouping,
                    accessibilityLabel: "Group history by")
            }

            if isEmpty {
                Text("No pomodoros logged yet.")
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                // No scroller of its own and no hand-picked cap any more: the
                // whole tab scrolls inside the screen-derived frame below, the
                // way Settings does, so the list gets whatever height the
                // display can spare. Lazy because Year puts 365 rows here.
                LazyVStack(spacing: 10) {
                    if showsCategoryBreakdown {
                        let maxCount = max(1, categoryTotals.map(\.count).max() ?? 1)
                        ForEach(categoryTotals) { t in
                            HistoryBar(label: t.name, count: t.count, maxCount: maxCount)
                        }
                    } else {
                        let maxCount = max(1, stats.map(\.count).max() ?? 1)
                        ForEach(stats) { s in
                            HistoryBar(label: model.dayLabel(s.date),
                                       count: s.count, maxCount: maxCount)
                        }
                    }
                }
            }
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.csvFilename
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        // A menu-bar-only app is never the active app, so without this the save
        // sheet opens behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.csvExport().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't save the export"
            alert.runModal()
        }
    }

    @ViewBuilder private var chart: some View {
        let series = model.dailySeries(days: range.days)
        Chart(series) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Pomodoros", day.count)
            )
            .cornerRadius(3)
            .foregroundStyle(LinearGradient(
                colors: [palette.accent, palette.accent2],
                startPoint: .top, endPoint: .bottom))
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(palette.hairline)
                AxisValueLabel().foregroundStyle(palette.textDim)
            }
        }
        .accessibilityLabel("Pomodoros per day, last \(range.days) days")
        .chartXAxis {
            if range == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(palette.textDim)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine().foregroundStyle(palette.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(palette.textDim)
                }
            }
        }
        .frame(height: 108)
    }

    private func statTile(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(palette.neon ? palette.cool : palette.text)
                .neonGlow(palette.cool, enabled: palette.neon, radius: 6, opacity: 0.5)
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .cardBackground(cornerRadius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(value == 1 ? "pomodoro" : "pomodoros")")
    }
}

/// One bar row in the History list — used by both groupings so they stay
/// visually identical.
private struct HistoryBar: View {
    let label: String
    let count: Int
    let maxCount: Int
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.textDim)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            GeometryReader { geo in
                Capsule()
                    .fill(LinearGradient(colors: [palette.accent, palette.accent2],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                    .frame(maxHeight: .infinity, alignment: .center)
                    .neonGlow(palette.accent, enabled: palette.neon, radius: 4, opacity: 0.5)
            }
            .frame(height: 11)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(count) \(count == 1 ? "pomodoro" : "pomodoros")")
    }
}
