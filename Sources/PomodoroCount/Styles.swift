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

/// A compact bar strip of recent daily counts. The last bar (today) is
/// full-strength; earlier days recede.
struct Sparkline: View {
    let values: [Int]
    var accent: Color
    var accent2: Color
    var neon: Bool
    var height: CGFloat = 22

    /// The bars carry no information a screen reader can get at, so state the
    /// trend as one value instead of exposing seven unlabelled shapes.
    private var spokenValue: String {
        guard !values.isEmpty else { return "no data" }
        let total = values.reduce(0, +)
        return "\(total) in the last \(values.count) days, today \(values.last ?? 0)"
    }

    var body: some View {
        let peak = max(1, values.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isToday = index == values.count - 1
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent2],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(isToday ? 1.0 : 0.40)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(value) / CGFloat(peak) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .neonGlow(accent, enabled: neon, radius: 4, opacity: 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent activity")
        .accessibilityValue(spokenValue)
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
