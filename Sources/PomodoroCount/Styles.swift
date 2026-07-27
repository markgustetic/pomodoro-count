import SwiftUI
import AppKit

/// Lets `--preview --hover` render buttons in their hover state (ImageRenderer
/// has no real cursor). No effect in the running app.
enum PreviewOverrides {
    nonisolated(unsafe) static var forceHover = false
    /// Overrides the persisted theme when rendering a preview.
    nonisolated(unsafe) static var theme: ThemeChoice?
}

private func applyCursor(_ inside: Bool) {
    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
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
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let hovering = (hover || PreviewOverrides.forceHover) && !pressed
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
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: pressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0; applyCursor($0) }
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
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let hovering = (hover || PreviewOverrides.forceHover) && !pressed
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let neon = palette.neon
            let base = palette.cool
            let fill = pressed ? (neon ? 0.15 : 0.16) : (hovering ? (neon ? 0.12 : 0.14) : (neon ? 0.07 : 0.08))
            let stroke = neon ? base.opacity(hovering ? 0.65 : 0.28) : Color.primary.opacity(0.06)

            configuration.label
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hovering ? base : palette.textDim)
                .frame(width: width, height: height)
                .background {
                    shape
                        .fill(base.opacity(fill))
                        .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
                }
                .neonGlow(base, enabled: neon && hovering, radius: 8, opacity: 0.55)
                .scaleEffect(pressed ? 0.95 : (hovering ? 1.03 : 1.0))
                .animation(.spring(response: 0.24, dampingFraction: 0.6), value: pressed)
                .animation(.easeOut(duration: 0.13), value: hover)
                .onHover { hover = $0; applyCursor($0) }
        }
    }
}

// MARK: - Text / link button

/// Low-chrome text button (Undo, Quit) that brightens on hover.
struct HoverTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.palette) private var palette
        @State private var hover = false

        var body: some View {
            let hovering = hover || PreviewOverrides.forceHover
            let active = palette.neon ? palette.cool : palette.text
            configuration.label
                .foregroundStyle(hovering ? active : palette.textDim)
                .neonGlow(active, enabled: palette.neon && hovering, radius: 6, opacity: 0.6)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0; applyCursor($0) }
        }
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
