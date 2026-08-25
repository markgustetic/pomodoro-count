import SwiftUI
import AppKit

/// Flags set from the command line to shape what `--preview` renders — hover
/// state, theme, whether rendering is even happening, whether a break is
/// armed — none of which have any effect in the running app.
enum PreviewOverrides {
    nonisolated(unsafe) static var forceHover = false
    /// Overrides the persisted theme when rendering a preview.
    nonisolated(unsafe) static var theme: ThemeChoice?
    /// True while `--preview` is rendering. A screenshot run must not start the
    /// updater or reach the network.
    nonisolated(unsafe) static var isRendering = false
    /// Arms a break on the preview's throwaway model before rasterising, so the
    /// `.breakReady` panel can be looked at without sitting out a real focus
    /// session.
    nonisolated(unsafe) static var armedBreak = false
    /// Forces a hovered day on the History graphs. No real pointer exists in a
    /// headless render, so without this the readout and the highlight can only
    /// be seen by hand.
    nonisolated(unsafe) static var hoveredGraphIndex: Int?
    /// The `ChartRange` raw value the History tab opens on when rendering.
    /// A string rather than the enum because `ChartRange` is nested in a view
    /// and this file has no business importing that isolation. Without it a
    /// preview only ever shows the Week chart, and the Year heatmap has no
    /// headless coverage at all.
    nonisolated(unsafe) static var historyRange: String?
}

private func applyCursor(_ inside: Bool) {
    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
}

// MARK: - Control state

/// Which of a control's four looks a button style draws.
///
/// Lifted out of the styles for the same reason `StatusIcon.glyph` is lifted
/// out of the drawing: a rendered button isn't assertable, the decision behind
/// it is. And the decision was wrong — every style branched on `pressed` and
/// `hovering` alone, so `.disabled(…)` changed nothing a user could see. The
/// Focus tab's stop button, disabled the whole time the timer is idle, sat
/// there looking live and did nothing when pressed.
enum ControlState: Equatable {
    case disabled, pressed, hovering, resting

    /// Disabled outranks everything else. `PreviewOverrides.forceHover` lights
    /// every control at once whatever the pointer is doing, and a dead button
    /// must not brighten under a real pointer either — so this precedence, not
    /// the hope that SwiftUI withholds hover from a disabled view, is what
    /// keeps it dark. Pressed outranks hovering because the pointer is
    /// necessarily inside the button it is pressing.
    static func of(enabled: Bool, pressed: Bool, hovering: Bool) -> ControlState {
        if !enabled { return .disabled }
        if pressed { return .pressed }
        if hovering { return .hovering }
        return .resting
    }
}

extension View {
    /// The app's one disabled treatment: fade the finished control — fill,
    /// border, glyph and shadow together — by the palette's own `DisabledLook`.
    /// Applied last in each style's chain so it dims the whole assembly rather
    /// than one layer of it, and shared so the three styles can't drift into
    /// three different ideas of what "off" looks like.
    func dimmed(_ state: ControlState, _ palette: Palette) -> some View {
        opacity(palette.disabled.opacity(in: state))
    }
}

// MARK: - Filled gradient button

/// Glossy gradient button: fill + top gloss + bright top edge + layered
/// shadows. Hover brightens and lifts; press sinks. In a neon palette the
/// tinted shadow becomes a bloom.
struct GradientButtonStyle: ButtonStyle {
    var tint: ButtonTint
    var cornerRadius: CGFloat = 13
    var vPadding: CGFloat = 11
    var elevation: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, tint: tint,
                  cornerRadius: cornerRadius, vPadding: vPadding, elevation: elevation)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let tint: ButtonTint
        let cornerRadius: CGFloat
        let vPadding: CGFloat
        let elevation: CGFloat
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled
        @State private var hover = false

        var body: some View {
            let state = ControlState.of(enabled: isEnabled, pressed: configuration.isPressed,
                                        hovering: hover || PreviewOverrides.forceHover)
            let pressed = state == .pressed
            let hovering = state == .hovering
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let neon = palette.neon

            // Neon palettes bloom; the classic one keeps a restrained lift.
            let tintOpacity = pressed ? (neon ? 0.30 : 0.12)
                                      : (hovering ? (neon ? 0.90 : 0.36) : (neon ? 0.55 : 0.26))
            let tintRadius = pressed ? elevation * (neon ? 0.6 : 0.4)
                                     : (hovering ? elevation * (neon ? 2.2 : 1.4) : elevation * (neon ? 1.4 : 1.0))
            let tintY: CGFloat = neon ? (pressed ? 1 : 2) : (pressed ? 2 : (hovering ? 6 : 4))

            configuration.label
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.20), radius: 0.5, y: 0.5)  // crisp text
                .frame(maxWidth: .infinity)
                .padding(.vertical, vPadding)
                .padding(.horizontal, 14)
                .background {
                    shape
                        .fill(LinearGradient(colors: [tint.top, tint.bottom],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay {
                            shape.fill(LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(hovering ? 0.36 : 0.26), location: 0.0),
                                    .init(color: .white.opacity(0.05), location: 0.45),
                                    .init(color: .clear, location: 0.85),
                                ],
                                startPoint: .top, endPoint: .bottom))
                        }
                        .overlay {
                            shape.strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(hovering ? 0.50 : 0.35), .white.opacity(0.07)],
                                    startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                        }
                }
                .shadow(color: .black.opacity(pressed ? (neon ? 0.20 : 0.10) : (neon ? 0.30 : 0.15)),
                        radius: pressed ? 1.5 : 3, x: 0, y: pressed ? 1 : 2)
                .shadow(color: tint.shadow.opacity(tintOpacity), radius: tintRadius, x: 0, y: tintY)
                .scaleEffect(pressed ? 0.97 : (hovering ? 1.015 : 1.0))
                .brightness(pressed ? -0.04 : (hovering ? 0.06 : 0.0))
                .dimmed(state, palette)
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: pressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0; applyCursor($0 && isEnabled) }
        }
    }
}

// MARK: - Soft secondary (icon) button

/// Neutral, low-emphasis button for secondary icon actions.
struct SoftIconButtonStyle: ButtonStyle {
    var width: CGFloat = 46
    var height: CGFloat = 42

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, width: width, height: height)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let width: CGFloat
        let height: CGFloat
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled
        @State private var hover = false

        var body: some View {
            let state = ControlState.of(enabled: isEnabled, pressed: configuration.isPressed,
                                        hovering: hover || PreviewOverrides.forceHover)
            let pressed = state == .pressed
            let hovering = state == .hovering
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let neon = palette.neon
            let base = palette.cool
            let fill = pressed ? (neon ? 0.15 : 0.16) : (hovering ? (neon ? 0.12 : 0.14) : (neon ? 0.07 : 0.08))
            let stroke = neon ? base.opacity(hovering ? 0.65 : 0.45) : Color.primary.opacity(0.06)
            // Neon rests on a dimmed accent rather than `textDim`: these sit
            // beside the hero button as peers, and a muted purple glyph in a
            // faintly-outlined well didn't read as a control at all.
            let glyph = neon ? base.opacity(0.85) : palette.textDim

            configuration.label
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hovering ? base : glyph)
                .frame(width: width, height: height)
                .background {
                    shape
                        .fill(base.opacity(fill))
                        .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
                }
                .neonGlow(base, enabled: neon && hovering, radius: 8, opacity: 0.55)
                .scaleEffect(pressed ? 0.95 : (hovering ? 1.03 : 1.0))
                // This is the row where it mattered first: `.idle` and
                // `.breakReady` are two stopped phases the user toggles between
                // with the stop button, and it was the only control in the row
                // that gave no reading of its own liveness.
                .dimmed(state, palette)
                .animation(.spring(response: 0.24, dampingFraction: 0.6), value: pressed)
                .animation(.easeOut(duration: 0.13), value: hover)
                .onHover { hover = $0; applyCursor($0 && isEnabled) }
        }
    }
}

// MARK: - Text / link button

/// Low-chrome text button (Undo, Quit, Export) that brightens on hover.
struct HoverTextButtonStyle: ButtonStyle {
    enum Emphasis {
        /// Carries the palette's interactive colour at rest. In a neon palette
        /// these labels used to rest at `textDim` — the same colour as the
        /// caption text beside them, on a panel of a closely related hue — so
        /// nothing marked them as clickable until the pointer was already on
        /// them.
        case action
        /// Quiet until hovered, then warns. For destructive controls, which
        /// shouldn't advertise themselves.
        case destructive
    }

    var emphasis: Emphasis = .action

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, emphasis: emphasis)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let emphasis: Emphasis
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled
        @State private var hover = false

        var body: some View {
            let state = ControlState.of(enabled: isEnabled, pressed: configuration.isPressed,
                                        hovering: hover || PreviewOverrides.forceHover)
            // Pressing keeps the lit look here rather than dropping back to
            // rest — the pointer is on the label it is pressing, and the fade
            // below is what marks the press.
            let hovering = state == .hovering || state == .pressed
            let neon = palette.neon
            let active = switch emphasis {
            case .action:      neon ? palette.cool : palette.text
            case .destructive: palette.accent
            }
            let resting = switch emphasis {
            case .action:      neon ? palette.cool.opacity(0.8) : palette.textDim
            case .destructive: palette.textDim
            }
            configuration.label
                .foregroundStyle(hovering ? active : resting)
                .neonGlow(active, enabled: neon && hovering, radius: 6, opacity: 0.6)
                .opacity(state == .pressed ? 0.6 : 1)
                .dimmed(state, palette)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0; applyCursor($0 && isEnabled) }
        }
    }
}

// MARK: - Card background

/// The panel's shared card look: a filled, continuous rounded rect with a
/// hairline stroke. Used by the count header, the focus timer card, History's
/// stat tiles, and — composed with its own hover fill and selection ring — each
/// category row.
struct CardBackground: View {
    var cornerRadius: CGFloat
    var fillOpacity: Double = 1
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(palette.cardFill.opacity(fillOpacity))
            .overlay { shape.strokeBorder(palette.cardStroke, lineWidth: 1) }
    }
}

extension View {
    /// Applies the shared card background at the given corner radius.
    func cardBackground(cornerRadius: CGFloat) -> some View {
        background { CardBackground(cornerRadius: cornerRadius) }
    }
}

// MARK: - Sparkline

/// What the pointer is over, reported up to the card that draws it.
///
/// The strip reports; it does not draw. `cursor` is already in the header
/// card's coordinate space, so the header places the card with its own
/// geometry and nothing has to be translated back down again.
struct SparklineHover: Equatable {
    /// The card's line, e.g. "Yesterday · 1". Phrased at this end rather than
    /// up in the header because `HistoryReadout.tooltip` wants the series and
    /// the day labeller, and both already live here.
    let text: String
    /// The pointer, in `Sparkline.headerSpace`.
    let cursor: CGPoint
}

/// Carries the hover up from the strip to the header card.
///
/// A preference rather than a binding: a binding would park the pointer's
/// position in `RootView`'s `@State`, and writing that on every mouse move
/// would invalidate the whole Focus tab — which rebuilds `dailySeries` on
/// every pass. Same reasoning that split `SessionClock` out of `AppModel`.
struct SparklineHoverKey: PreferenceKey {
    static let defaultValue: SparklineHover? = nil
    static func reduce(value: inout SparklineHover?, nextValue: () -> SparklineHover?) {
        // Last non-nil wins. One strip exists in the panel, so this never
        // arbitrates between two reports — it only keeps a silent sibling
        // from erasing the one report there is.
        value = nextValue() ?? value
    }
}

/// A compact bar strip of recent daily counts. The last bar (today) is
/// full-strength; earlier days recede.
struct Sparkline: View {
    /// The header card is the space the hover is reported in — see
    /// `SparklineHoverCard`. Named, never `.local`: `.local` here is the 78pt
    /// strip, and the reorder post-mortem is about measuring in a frame your
    /// own effects move.
    static let headerSpace = "focusHeader"

    let days: [DayStat]
    var accent: Color
    var accent2: Color
    var neon: Bool
    var height: CGFloat = 22
    /// Names the hovered day. `AppModel.dayLabel`, so "Today" and "Yesterday"
    /// read as words here exactly as they do in History.
    var dayLabel: (Date) -> String

    @State private var hoveredIndex: Int?
    @State private var hoverPoint: CGPoint?

    /// The bars carry no information a screen reader can get at, so state the
    /// trend as one value instead of exposing seven unlabelled shapes.
    private var spokenValue: String {
        guard !days.isEmpty else { return "no data" }
        let total = days.reduce(0) { $0 + $1.count }
        return "\(total) in the last \(days.count) days, today \(days.last?.count ?? 0)"
    }

    /// The effective hover: a real pointer, or a preview's forced one.
    ///
    /// The forced index is range-checked here rather than left to the card.
    /// `--hover-graph` is shared with the History graphs, where 200 is a
    /// legitimate index into a year; unchecked, it would dim every bar on
    /// this seven-day strip with no card on screen to explain why.
    private var effectiveHover: Int? {
        if let hoveredIndex { return hoveredIndex }
        guard let forced = PreviewOverrides.hoveredGraphIndex,
              days.indices.contains(forced) else { return nil }
        return forced
    }

    var body: some View {
        let peak = max(1, days.map(\.count).max() ?? 1)
        let hovered = effectiveHover
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                // While hovering, only the hovered bar is lit — today gives up
                // its marker for the duration, the way the History chart's
                // bars do. Nothing is lost: the card names the day outright,
                // which is more than the marker was saying.
                let lit = hovered == nil ? index == days.count - 1 : hovered == index
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent2],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(lit ? 1.0 : 0.40)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(day.count) / CGFloat(peak) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .neonGlow(accent, enabled: neon, radius: 4, opacity: 0.45)
        // On top, not behind: a bar is hit-testable and would otherwise eat
        // the hover before the tracker saw it. Nothing here is clickable, so
        // covering the strip costs nothing.
        .overlay { hoverTracker }
        .background { hoverReporter }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent activity")
        .accessibilityValue(spokenValue)
    }

    private var hoverTracker: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                // A tracking area, not a gesture — which is why this works in
                // the non-activating panel where drag sessions never start.
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoveredIndex = SparklineLayout.index(atX: point.x,
                                                             width: geo.size.width,
                                                             count: days.count)
                        hoverPoint = point
                    case .ended:
                        hoveredIndex = nil
                        hoverPoint = nil
                    }
                }
                // A render has no pointer, so a forced hover gets its column's
                // centre at mid-height. `onAppear` rather than a computed
                // value: writing state during layout is how SwiftUI gets an
                // update loop.
                .onAppear {
                    guard let forced = PreviewOverrides.hoveredGraphIndex,
                          let x = SparklineLayout.centerX(ofColumn: forced,
                                                          width: geo.size.width,
                                                          count: days.count)
                    else { return }
                    hoverPoint = CGPoint(x: x, y: geo.size.height / 2)
                }
        }
    }

    /// Reports the hover in the header's coordinates. Draws nothing.
    ///
    /// Two separate reasons the card belongs to the header rather than to this
    /// strip, and only the first was understood the first time round:
    ///
    /// 1. **Placement.** `TooltipPlacement.origin` clamps x to
    ///    `min(cursor.x - w/2, max(0, container.width - w))`. The card is
    ///    around 90pt and this strip is 78, so against the strip the second
    ///    term is 0 and the result is 0 for all seven bars — the card would
    ///    sit at the leading edge and never move, which is the one thing it
    ///    must do. Against the header's 272pt the clamp is live again.
    ///
    /// 2. **Paint order.** An overlay on *this* strip is not clipped, so it
    ///    does reach across the header — but it still paints as part of the
    ///    strip, and the strip's siblings in the header's VStack paint over
    ///    it. Measured, with an opaque probe card drawn from the strip's own
    ///    overlay: the status badge covers it. Note the badge is declared
    ///    *before* the strip and paints over it anyway, so declaration order
    ///    is not the lever — which is why both `.zIndex` on the strip and a
    ///    ZStack with the strip declared last changed nothing when they were
    ///    tried. An overlay on the header itself is above every one of the
    ///    header's children by construction, no ordering to argue with.
    ///    `HistoryTab` hangs its own card on the graph's container too — same
    ///    tactic, different reason: there the card's coordinates and the
    ///    cursor's must share one space, and the Canvas clips, so the card
    ///    can't live inside it.
    ///
    /// There was a *third* thing wrong, and it is the one that made this look
    /// unfixable: in Classic the card is all but transparent, so neither of
    /// the fixes above visibly changed a render. See `SparklineHoverCard`.
    private var hoverReporter: some View {
        GeometryReader { geo in
            Color.clear.preference(key: SparklineHoverKey.self,
                                   value: report(in: geo.frame(in: .named(Sparkline.headerSpace))))
        }
    }

    /// The hover, moved from this strip's coordinates into the header's.
    private func report(in strip: CGRect) -> SparklineHover? {
        guard let text = HistoryReadout.tooltip(hoveredIndex: effectiveHover,
                                                series: days, dayLabel: dayLabel),
              let cursor = hoverPoint else { return nil }
        return SparklineHover(text: text,
                              cursor: CGPoint(x: strip.minX + cursor.x,
                                              y: strip.minY + cursor.y))
    }
}

/// The sparkline's hover card, drawn by the header card it is placed against.
///
/// Its own `@State` for the measured size rather than `RootView`'s: the card
/// changes width when the hovered day's label does ("Today" to "Wed, Jul 29"),
/// and that must no more invalidate the Focus tab than the pointer does.
struct SparklineHoverCard: View {
    let hover: SparklineHover
    @Environment(\.palette) private var palette
    // Unlike HistoryTab's tooltipSize, which lives on the long-lived tab view
    // and so keeps its value across hovers, this @State lives on
    // SparklineHoverCard itself, which `if let hover { … }` tears down
    // whenever the pointer leaves — so `size` starts .zero on *every* hover
    // entry, not just the first. Each new card therefore lays out once at
    // the wrong placement before the preference below lands and corrects it.
    // Invisible at 60Hz — not a bug.
    @State private var size: CGSize = .zero

    /// What the card is opaque *against*.
    ///
    /// `HoverTooltip` backs itself with `bgBottom` under `cardFill` and calls
    /// the result opaque. That is true of Synthwave and false of Classic:
    /// Classic paints no panel background at all — `paintsBackground` is
    /// false and `bgBottom` is `.clear` — so its card is 5% `cardFill` over
    /// nothing. Over a sparse chart that still reads. Here the card lands on
    /// the status badge and the streak flame, and 5% is not a card, it is a
    /// tint: the badge's text shows straight through the day's name.
    ///
    /// This is why the first two attempts on this looked unfixable. There
    /// *is* a real z-order problem as well (see `Sparkline.hoverReporter`),
    /// but at 5% opacity fixing it alone changes nothing you can see: the
    /// badge shows through a card that is in front of it exactly as it shows
    /// through one that is behind. Every render came back identical, and the
    /// conclusion drawn was that the renderer could not depict text z-order.
    /// It can. Measured: in Synthwave, where `bgBottom` is a real colour,
    /// this same card covers the badge cleanly.
    ///
    /// The window's own background is what Classic is sitting on, so that is
    /// the ground — the same colour `PreviewRenderer` paints behind a
    /// non-Synthwave panel, and reached for the same way `SegmentedControl`
    /// reaches for `.controlColor`: it is the system's surface, not a
    /// hand-picked one that would drift from it in dark mode.
    private var ground: Color {
        palette.paintsBackground ? palette.bgBottom : Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        GeometryReader { geo in
            // `geo.size` is the header card's, and this overlay's origin is
            // the header's own — the very frame `Sparkline.headerSpace` names
            // — so the cursor arrives in these coordinates already and the
            // placement needs no translation back.
            let at = TooltipPlacement.origin(cursor: hover.cursor, tooltip: size, in: geo.size)
            HoverTooltip(text: hover.text)
                // Radius 6 to match the card's own corners in HoverTooltip —
                // a duplicated constant, and cheaper than the alternative of
                // a squared-off slab peeking out from under the rounding.
                .background { RoundedRectangle(cornerRadius: 6).fill(ground) }
                .background {
                    GeometryReader { card in
                        Color.clear.preference(key: TooltipSizeKey.self, value: card.size)
                    }
                }
                .offset(x: at.x, y: at.y)
        }
        .onPreferenceChange(TooltipSizeKey.self) { size = $0 }
        // Never intercept the pointer: the card would fight the hover that
        // summons it.
        .allowsHitTesting(false)
    }
}

// MARK: - Segmented control

/// A rounded pill segmented control with an animated selection chip.
///
/// Each segment is a real `Button` rather than a tappable `Text`. That costs
/// nothing visually — `.plain` adds no chrome — and it is the difference between
/// the app's main navigation being reachable by VoiceOver and the keyboard, and
/// being invisible to both.
struct SegmentedControl<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    /// Describes the group as a whole, e.g. "View" or "Appearance".
    var accessibilityLabel: String?
    @Environment(\.palette) private var palette
    @Namespace private var ns
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                let hovering = hovered == item.value && !selected
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        selection = item.value
                    }
                } label: {
                    Text(item.label)
                        .font(.system(.subheadline, design: .rounded).weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? palette.text
                                                  : (hovering ? (palette.neon ? palette.cool : palette.text)
                                                              : palette.textDim))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background { chip(selected: selected, hovering: hovering) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "")
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.trackFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(palette.trackStroke, lineWidth: 1)
                }
        )
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder
    private func chip(selected: Bool, hovering: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if selected {
            Group {
                if palette.neon {
                    shape
                        .fill(LinearGradient(
                            colors: [palette.accent.opacity(0.55), palette.accent2.opacity(0.45)],
                            startPoint: .top, endPoint: .bottom))
                        .overlay { shape.strokeBorder(palette.accent.opacity(0.8), lineWidth: 1) }
                        .shadow(color: palette.accent.opacity(0.6), radius: 6)
                } else {
                    shape
                        .fill(Color(nsColor: .controlColor))
                        .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                }
            }
            .matchedGeometryEffect(id: "segment", in: ns)
        } else if hovering {
            shape.fill((palette.neon ? palette.cool : Color.primary).opacity(palette.neon ? 0.10 : 0.06))
        }
    }
}
