import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab
    @State private var headerSize: CGSize = .zero

    enum Tab: String, CaseIterable { case focus = "Focus", history = "History", settings = "Settings" }

    init(initialTab: Tab = .focus) {
        _tab = State(initialValue: initialTab)
    }

    private var palette: Palette { model.settings.theme.palette }

    var body: some View {
        VStack(spacing: 12) {
            // The picker leads on every tab — it used to sit below the count
            // and log rows on Focus, which also meant it jumped position when
            // switching tabs.
            SegmentedControl(
                items: Tab.allCases.map { (value: $0, label: $0.rawValue) },
                selection: $tab,
                accessibilityLabel: "View")

            switch tab {
            case .focus:
                // Timer first — it is what this tab is for. The log rows and
                // the count follow; they belong to Focus and only to Focus:
                // History already charts today, and Settings has nothing to
                // do with logging.
                focusTab
                logButton
                header
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
        // Opening the panel answers whatever a banner was announcing, so take
        // it down rather than leaving the user the same news to dismiss twice.
        //
        // `onAppear` fires on *every* opening, not just the first — measured
        // against the running app, because SwiftUI keeps the panel's window
        // alive between openings and could just as easily have kept its content
        // alive too, which would have made this fire once and never again.
        .onAppear { model.clearNotifications() }
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
                Sparkline(days: model.dailySeries(days: 7),
                          accent: palette.accent,
                          accent2: palette.accent2,
                          neon: palette.neon,
                          dayLabel: model.dayLabel,
                          tooltipContainer: headerSize)
                    .frame(width: 78)
                // A one-day "streak" is just today; the flame appears once
                // there is actually a run to protect.
                if model.streakDays >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                        Text("\(model.streakDays)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(palette.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.streakDays) day streak")
                    .help("\(model.streakDays) days in a row")
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .cardBackground(cornerRadius: 14)
        // The sparkline's hover card is wider than the 78pt strip, so it is
        // placed against this card instead — see Sparkline.tooltip. Measured
        // rather than derived from the panel's 300pt, so a padding change
        // can't silently mis-clamp it.
        //
        // This is written on layout, never on a pointer move. The hover state
        // itself lives inside Sparkline precisely so that a 60Hz pointer does
        // not invalidate this view, which rebuilds dailySeries every pass.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { headerSize = geo.size }
                    .onChange(of: geo.size) { headerSize = geo.size }
            }
        }
        .coordinateSpace(name: Sparkline.headerSpace)
    }

    @ViewBuilder private var statusBadge: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .breakReady:
            badge("Break ready", palette.breakColor)
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
                    .help("Take back the most recent pomodoro")
            }
        }
    }

    // MARK: Focus tab

    private var phaseColor: Color {
        switch model.phase {
        case .idle: return palette.idleColor
        case .work: return palette.focusColor
        case .breakTime, .breakReady: return palette.breakColor
        }
    }

    private var timerTint: ButtonTint {
        switch model.phase {
        case .idle: return palette.idleButton
        case .work: return palette.focusButton
        case .breakTime, .breakReady: return palette.breakButton
        }
    }

    /// What the big button will do, for its tooltip — the title alone says
    /// "Resume" without saying what of.
    private var primaryHelp: String {
        if model.isRunning { return "Pause the timer" }
        switch model.phase {
        case .idle: return "Start a \(model.settings.workMinutes)-minute focus session"
        case .breakReady: return "Start your \(model.armedBreakMinutes)-minute break"
        case .work, .breakTime: return "Resume where you left off"
        }
    }

    private var phaseSubtitle: String {
        let target = model.settings.categoriesEnabled ? " · \(model.sessionTargetLabel)" : ""
        switch model.phase {
        case .idle: return "Focus session · \(model.settings.workMinutes) min"
        case .breakReady:
            // `nextBreakIsLong`, not `currentBreakIsLong`: nothing has started
            // running yet, so the only truthful source is the one that reads
            // `focusSessionsThisCycle` live.
            return model.nextBreakIsLong
                ? "Long break — earned · \(model.armedBreakMinutes) min"
                : "Break · \(model.armedBreakMinutes) min"
        case .work: return model.isRunning ? "Focus in progress\(target)" : "Paused"
        case .breakTime:
            guard model.isRunning else { return "Paused" }
            // `currentBreakIsLong`, not `nextBreakIsLong`: `startBreak()` zeroes
            // `focusSessionsThisCycle` the moment a long break starts, so by the
            // time this case runs `nextBreakIsLong` has already gone false —
            // reading it here would silently drop "Long break — earned" the
            // instant the break it describes actually begins.
            return model.currentBreakIsLong ? "Long break — earned" : "Break time"
        }
    }

    private var focusTab: some View {
        VStack(spacing: 12) {
            CountdownText(model: model, clock: model.clock,
                          color: phaseColor, neon: palette.neon, subtitle: phaseSubtitle)
            Text(phaseSubtitle)
                .font(.caption)
                .foregroundStyle(palette.textDim)
                .accessibilityHidden(true)

            if model.settings.categoriesEnabled {
                // Plain text, not a control. The category rows below are what
                // aims the target now, and a second picker listing those same
                // categories without any of the counts that make one worth
                // picking is what this stopped being.
                //
                // `.lineLimit`/`.truncationMode` do the job here that the
                // deleted pill-shortening helper had to do by hand:
                // `NSPopUpButton` ignored SwiftUI frames on its content, so the
                // string had to be cut to a measured width before it ever
                // reached the label. A `Text`
                // truncates at the width it is actually given, and `.tail` cuts
                // the name while leaving the promise — "towards" versus "pinned
                // to" — which is the one property that shortening existed to
                // guarantee.
                //
                // `palette.text`, not `textDim`: this replaced a control drawn
                // at control-text weight, and dropping it to `textDim` would
                // merge it with the identically-sized subtitle directly above.
                Text(model.sessionTargetDescription)
                    .font(.caption)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("Which category a finished session credits — click a category below to change it")
                    .accessibilityLabel("Session target")
                    .accessibilityValue(model.sessionTargetDescription)
            }

            HStack(spacing: 8) {
                Button(model.primaryTitle) { model.toggle() }
                    .buttonStyle(GradientButtonStyle(tint: timerTint, cornerRadius: 12, vPadding: 9, elevation: 5))
                    .help(primaryHelp)

                Button { model.reset() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(SoftIconButtonStyle())
                .disabled(!model.offersReset)
                // Says what the label doesn't: the hint and the tooltip share
                // this string, and repeating the label would double-speak.
                // Phase-dependent since an armed break has a logged session
                // behind it — see `AppModel.resetHelp`.
                .help(model.resetHelp)
                .accessibilityLabel("Stop and reset")

                if model.offersManualBreak {
                    Button { model.startBreak() } label: {
                        Image(systemName: "cup.and.saucer.fill")
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help("Rest now — an unfinished focus session isn't logged")
                    .accessibilityLabel("Start a break now")
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .cardBackground(cornerRadius: 16)
    }

    // MARK: Countdown

    /// The big timer readout — the one view in the panel that displays
    /// seconds, so the one view that observes `SessionClock` and re-renders
    /// on its half-second tick. Everything phase-shaped (colour, subtitle)
    /// arrives as plain values from the parent, which still re-renders on
    /// real model changes.
    private struct CountdownText: View {
        let model: AppModel
        @ObservedObject var clock: SessionClock
        let color: Color
        let neon: Bool
        let subtitle: String

        var body: some View {
            Text(AppModel.mmss(model.displayRemaining))
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .neonGlow(color, enabled: neon, radius: 12, opacity: 0.65)
                // "50:00" is read as digits; say it in words instead.
                .accessibilityLabel(subtitle)
                .accessibilityValue(AppModel.spokenDuration(model.displayRemaining))
        }
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
                .help("Quit Pomodoro Count")
        }
    }
}
