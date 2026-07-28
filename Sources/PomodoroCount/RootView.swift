import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab

    enum Tab: String, CaseIterable { case focus = "Focus", history = "History", settings = "Settings" }

    init(initialTab: Tab = .focus) {
        _tab = State(initialValue: initialTab)
    }

    private var palette: Palette { model.settings.theme.palette }

    /// Today's count and the rows that log into it. They belong to Focus, and
    /// only to Focus: History already charts today's count and lists it as its
    /// first row, and Settings has nothing to do with logging. On both, all
    /// they did was push the content the tab was opened for a card and four
    /// buttons further down — Settings ran to around 930pt with them.
    @ViewBuilder private var todaySection: some View {
        if tab == .focus {
            logButton
            header
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            todaySection

            SegmentedControl(
                items: Tab.allCases.map { (value: $0, label: $0.rawValue) },
                selection: $tab,
                accessibilityLabel: "View")

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
        .themed(palette)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(model.todayCount)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.neon ? palette.accent : palette.text)
                .neonGlow(palette.accent, enabled: palette.neon, radius: 10, opacity: 0.7)
                .accessibilityLabel("Today, \(model.shortDateString)")
                .accessibilityValue("\(model.todayCount) \(model.todayCount == 1 ? "pomodoro" : "pomodoros")")

            VStack(alignment: .leading, spacing: 1) {
                Text(model.todayCount == 1 ? "pomodoro" : "pomodoros")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(model.shortDateString)
                    .font(.caption2)
                    .foregroundStyle(palette.textDim)
            }
            // Otherwise VoiceOver reads "4", "pomodoros", "Mon, Jul 27" as three
            // unrelated stops.
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge
                Sparkline(values: model.dailySeries(days: 7).map(\.count),
                          accent: palette.accent,
                          accent2: palette.accent2,
                          neon: palette.neon)
                    .frame(width: 78)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .cardBackground(cornerRadius: 14)
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
            if model.settings.categoriesEnabled {
                CategoryRows()
            } else {
                // Logging is a one-tap errand: record it and get the panel out of
                // the way. The menu bar count updates behind it as confirmation.
                LogButton {
                    model.logExternal()
                    MenuBarPanel.dismiss()
                }
                .help("Record a pomodoro you finished on external hardware")
            }

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
        let target = model.settings.categoriesEnabled ? " · \(model.sessionTargetLabel)" : ""
        switch model.phase {
        case .idle: return "Focus session · \(model.settings.workMinutes) min"
        case .work: return model.isRunning ? "Focus in progress\(target)" : "Paused"
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
                // "50:00" is read as digits; say it in words instead.
                .accessibilityLabel(phaseSubtitle)
                .accessibilityValue(AppModel.spokenDuration(model.displayRemaining))
            Text(phaseSubtitle)
                .font(.caption)
                .foregroundStyle(palette.textDim)
                .accessibilityHidden(true)

            if model.settings.categoriesEnabled {
                Menu {
                    Button(model.settings.fallbackName) { model.sessionTarget = .fallback }
                    ForEach(model.settings.categories) { category in
                        Button(category.name) { model.sessionTarget = .named(category.name) }
                    }
                } label: {
                    // No decorative dot here, and it isn't an oversight.
                    // `.menuStyle(.borderlessButton)` draws this label through
                    // NSPopUpButton, which drops arbitrary Shape content entirely
                    // (a Circle rendered as nothing) and paints an Image in the
                    // control's own text colour, ignoring foregroundStyle. So a
                    // dot can only ever be a black bullet that matches neither
                    // palette. The text and the chevron carry the meaning.
                    HStack(spacing: 4) {
                        Text("towards \(model.sessionTargetLabel)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // The Menu below is `.fixedSize()`, so without a cap
                            // here a long category name would push the pill past
                            // the panel's edge instead of truncating.
                            .frame(maxWidth: 160, alignment: .leading)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Session target")
                .accessibilityValue(model.sessionTargetLabel)
            }

            HStack(spacing: 8) {
                Button(model.primaryTitle) { model.toggle() }
                    .buttonStyle(GradientButtonStyle(tint: timerTint, cornerRadius: 12, vPadding: 9, elevation: 5))

                Button { model.reset() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(SoftIconButtonStyle())
                .disabled(model.phase == .idle)
                .help("Stop and reset")
                .accessibilityLabel("Stop and reset")

                if model.phase != .breakTime {
                    Button { model.startBreak() } label: {
                        Image(systemName: "cup.and.saucer.fill")
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help("Start a break now")
                    .accessibilityLabel("Start a break now")
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .cardBackground(cornerRadius: 16)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Pomodoro Count \(model.versionString)")
                .font(.caption2)
                .foregroundStyle(palette.textDim.opacity(0.7))
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(HoverTextButtonStyle())
                .font(.caption)
        }
    }
}
