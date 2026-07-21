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

    private var palette: Palette { model.settings.theme.palette }

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

            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(palette.text)
        .background { if palette.paintsBackground { palette.background } }
        .environment(\.palette, palette)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(model.todayCount)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.neon ? palette.accent : palette.text)
                .neonGlow(palette.accent, enabled: palette.neon, radius: 10, opacity: 0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.todayCount == 1 ? "pomodoro" : "pomodoros")
                    .font(.headline)
                Text(model.todayDateString)
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
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
            badge(model.isRunning ? "Focus" : "Paused", palette.focusColor)
        case .breakTime:
            badge(model.isRunning ? "Break" : "Paused", palette.breakColor)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(palette.neon ? 0.18 : 0.15)))
            .overlay {
                if palette.neon { Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1) }
            }
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
        case .idle: return palette.idleColor
        case .work: return palette.focusColor
        case .breakTime: return palette.breakColor
        }
    }

    private var timerTint: ButtonTint {
        switch model.phase {
        case .idle: return palette.idleButton
        case .work: return palette.focusButton
        case .breakTime: return palette.breakButton
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
                .neonGlow(phaseColor, enabled: palette.neon, radius: 12, opacity: 0.65)
            Text(phaseSubtitle)
                .font(.caption)
                .foregroundStyle(palette.textDim)

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
                .fill(palette.cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                }
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Pomodoro Count")
                .font(.caption2)
                .foregroundStyle(palette.textDim.opacity(0.7))
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
                selection: $range)

            chart

            HStack(spacing: 8) {
                statTile("This week", model.weekCount)
                statTile("All time", model.totalCount)
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
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Appearance")
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
                SegmentedControl(
                    items: ThemeChoice.allCases.map { (value: $0, label: $0.rawValue) },
                    selection: $model.settings.theme)
            }

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
                        .buttonStyle(SoftIconButtonStyle(width: 34, height: 26))
                        .help("Reset to ⌃⌥⌘P")
                    }
                }
                Text("Logs a pomodoro from any app.")
                    .font(.caption2)
                    .foregroundStyle(palette.textDim)
            }

            if model.isBundled {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
            }
        }
        .toggleStyle(.switch)
        .tint(palette.accent)
        .font(.callout)
    }
}
