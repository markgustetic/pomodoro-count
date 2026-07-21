import SwiftUI
import AppKit
import Charts

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab

    enum Tab: String, CaseIterable { case focus = "Focus", history = "History", settings = "Settings" }

    init(initialTab: Tab = .focus) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 12) {
            logButton
            header

            SegmentedControl(
                items: Tab.allCases.map { (value: $0, label: $0.rawValue) },
                selection: $tab)

            switch tab {
            case .focus:    focusTab
            case .history:  HistoryTab()
            case .settings: SettingsTab()
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(model.todayCount)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
                Text(model.todayCount == 1 ? "pomodoro" : "pomodoros")
                    .font(.headline)
                Text(model.todayDateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .work:
            badge(model.isRunning ? "Focus" : "Paused", .red)
        case .breakTime:
            badge(model.isRunning ? "Break" : "Paused", .green)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: Headline external-log button

    private var logButton: some View {
        VStack(spacing: 6) {
            LogButton { model.logExternal() }
                .help("Record a pomodoro you finished on external hardware")

            if model.todayCount > 0 {
                Button("Undo last", action: model.undoLast)
                    .buttonStyle(HoverTextButtonStyle())
                    .font(.caption)
            }
        }
    }

    // MARK: Focus tab

    private var phaseColor: Color {
        switch model.phase {
        case .idle: return .secondary
        case .work: return .pomodoro
        case .breakTime: return Color(red: 0.20, green: 0.52, blue: 0.24)
        }
    }

    private var timerTint: ButtonTint {
        switch model.phase {
        case .idle: return .graphite
        case .work: return .tomato
        case .breakTime: return .grass
        }
    }

    private var phaseSubtitle: String {
        switch model.phase {
        case .idle: return "Focus session · \(model.settings.workMinutes) min"
        case .work: return model.isRunning ? "Focus in progress" : "Paused"
        case .breakTime: return model.isRunning ? "Break time" : "Paused"
        }
    }

    private var focusTab: some View {
        VStack(spacing: 12) {
            Text(AppModel.mmss(model.displayRemaining))
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phaseColor)
            Text(phaseSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(model.primaryTitle) { model.toggle() }
                    .buttonStyle(GradientButtonStyle(tint: timerTint, cornerRadius: 12, vPadding: 9, elevation: 5))

                Button { model.reset() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(SoftIconButtonStyle())
                .disabled(model.phase == .idle)
                .help("Stop and reset")

                if model.phase != .breakTime {
                    Button { model.startBreak() } label: {
                        Image(systemName: "cup.and.saucer.fill")
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help("Start a break now")
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Pomodoro Count")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(HoverTextButtonStyle())
                .font(.caption)
        }
    }
}

// MARK: - History

struct HistoryTab: View {
    @EnvironmentObject var model: AppModel
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
                selection: $range)

            chart

            HStack(spacing: 8) {
                statTile("This week", model.weekCount)
                statTile("All time", model.totalCount)
            }

            if stats.isEmpty {
                Text("No pomodoros logged yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                let maxCount = max(1, stats.map(\.count).max() ?? 1)
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(stats) { s in
                            HStack(spacing: 8) {
                                Text(model.dayLabel(s.date))
                                    .font(.caption)
                                    .frame(width: 84, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.pomodoro.opacity(0.8))
                                        .frame(width: max(4, geo.size.width * CGFloat(s.count) / CGFloat(maxCount)))
                                        .frame(maxHeight: .infinity, alignment: .center)
                                }
                                .frame(height: 10)
                                Text("\(s.count)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
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
            .foregroundStyle(Color.pomodoro.gradient)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .chartXAxis {
            if range == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $model.settings.workMinutes, in: 1...180) {
                Text("Focus: **\(model.settings.workMinutes)** min")
            }
            Stepper(value: $model.settings.breakMinutes, in: 1...60) {
                Text("Break: **\(model.settings.breakMinutes)** min")
            }
            Toggle("Auto-start break after focus", isOn: $model.settings.autoStartBreak)
            Toggle("Play sound on complete", isOn: $model.settings.soundEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { model.settings.globalShortcutEnabled },
                    set: { model.setGlobalShortcut($0) }
                )) {
                    Text("Global shortcut")
                }
                if model.settings.globalShortcutEnabled {
                    HStack(spacing: 6) {
                        ShortcutRecorder(shortcut: Binding(
                            get: { model.settings.shortcut },
                            set: { model.updateShortcut($0) }
                        ))
                        Button {
                            model.updateShortcut(.default)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset to ⌃⌥⌘P")
                    }
                }
                Text("Logs a pomodoro from any app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if model.isBundled {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
            }
        }
        .toggleStyle(.switch)
        .font(.callout)
    }
}
