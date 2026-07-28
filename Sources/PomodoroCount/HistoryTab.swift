import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers

// MARK: - History

struct HistoryTab: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette
    @State private var range: ChartRange = .week

    enum ChartRange: String, CaseIterable {
        case week = "Week", month = "Month"
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        let stats = model.history()
        VStack(spacing: 10) {
            SegmentedControl(
                items: ChartRange.allCases.map { (value: $0, label: $0.rawValue) },
                selection: $range,
                accessibilityLabel: "Chart range")

            chart

            HStack(spacing: 8) {
                statTile("This week", model.weekCount)
                statTile("All time", model.totalCount)
            }

            if model.totalCount > 0 {
                Button("Export CSV…", action: exportCSV)
                    .buttonStyle(HoverTextButtonStyle())
                    .font(.caption)
                    .accessibilityHint("Saves your whole history as a spreadsheet file")
            }

            if stats.isEmpty {
                Text("No pomodoros logged yet.")
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                let maxCount = max(1, stats.map(\.count).max() ?? 1)
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(stats) { s in
                            HStack(spacing: 8) {
                                Text(model.dayLabel(s.date))
                                    .font(.caption)
                                    .foregroundStyle(palette.textDim)
                                    .frame(width: 84, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [palette.accent, palette.accent2],
                                            startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(4, geo.size.width * CGFloat(s.count) / CGFloat(maxCount)))
                                        .frame(maxHeight: .infinity, alignment: .center)
                                        .neonGlow(palette.accent, enabled: palette.neon, radius: 4, opacity: 0.5)
                                }
                                .frame(height: 10)
                                Text("\(s.count)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 24, alignment: .trailing)
                            }
                            // One stop per day rather than label, bar, number.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(model.dayLabel(s.date))
                            .accessibilityValue("\(s.count) \(s.count == 1 ? "pomodoro" : "pomodoros")")
                        }
                    }
                }
                .frame(maxHeight: 190)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(value == 1 ? "pomodoro" : "pomodoros")")
    }
}
