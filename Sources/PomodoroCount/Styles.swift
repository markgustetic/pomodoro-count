import SwiftUI
import AppKit

extension Color {
    /// Shared brand red, used for charts, bars, and the focus phase.
    static let pomodoro = Color(red: 0.88, green: 0.22, blue: 0.19)
}

/// Lets `--preview --hover` render buttons in their hover state (ImageRenderer
/// has no real cursor). No effect in the running app.
enum PreviewOverrides {
    nonisolated(unsafe) static var forceHover = false
}

private func applyCursor(_ inside: Bool) {
    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
}

// MARK: - Button tints

/// A two-stop gradient + matching shadow color for a filled button.
struct ButtonTint {
    let top: Color
    let bottom: Color
    let shadow: Color

    static let tomato = ButtonTint(
        top: Color(red: 1.00, green: 0.45, blue: 0.37),
        bottom: Color(red: 0.82, green: 0.16, blue: 0.17),
        shadow: Color(red: 0.80, green: 0.15, blue: 0.15))

    static let grass = ButtonTint(
        top: Color(red: 0.44, green: 0.78, blue: 0.40),
        bottom: Color(red: 0.20, green: 0.52, blue: 0.22),
        shadow: Color(red: 0.20, green: 0.48, blue: 0.20))

    static let graphite = ButtonTint(
        top: Color(red: 0.44, green: 0.47, blue: 0.52),
        bottom: Color(red: 0.25, green: 0.27, blue: 0.31),
        shadow: Color.black)
}

// MARK: - Filled gradient button

/// Glossy gradient button: fill + top gloss + bright top edge + layered
/// contact/tint shadows. Hover brightens and lifts it; press sinks it.
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
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let hovering = (hover || PreviewOverrides.forceHover) && !pressed
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
                .shadow(color: .black.opacity(pressed ? 0.10 : 0.15),
                        radius: pressed ? 1.5 : 3, x: 0, y: pressed ? 1 : 2)
                .shadow(color: tint.shadow.opacity(pressed ? 0.12 : (hovering ? 0.36 : 0.26)),
                        radius: pressed ? elevation * 0.4 : (hovering ? elevation * 1.4 : elevation),
                        x: 0, y: pressed ? 2 : (hovering ? 6 : 4))
                .scaleEffect(pressed ? 0.97 : (hovering ? 1.015 : 1.0))
                .brightness(pressed ? -0.04 : (hovering ? 0.06 : 0.0))
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: pressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0; applyCursor($0) }
        }
    }
}

// MARK: - Soft secondary (icon) button

/// Neutral, low-emphasis button for secondary icon actions. Hover deepens the
/// fill and promotes the icon from secondary to primary.
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
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let hovering = (hover || PreviewOverrides.forceHover) && !pressed
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let fill = pressed ? 0.16 : (hovering ? 0.14 : 0.08)

            configuration.label
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: width, height: height)
                .background {
                    shape
                        .fill(Color.primary.opacity(fill))
                        .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
                }
                .scaleEffect(pressed ? 0.95 : (hovering ? 1.03 : 1.0))
                .animation(.spring(response: 0.24, dampingFraction: 0.6), value: pressed)
                .animation(.easeOut(duration: 0.13), value: hover)
                .onHover { hover = $0; applyCursor($0) }
        }
    }
}

// MARK: - Text / link button

/// Low-chrome text button (Undo, Quit) that brightens from secondary to
/// primary on hover.
struct HoverTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @State private var hover = false

        var body: some View {
            let hovering = hover || PreviewOverrides.forceHover
            configuration.label
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0; applyCursor($0) }
        }
    }
}

// MARK: - Segmented control

/// A rounded pill segmented control with an animated selection chip. Hovering
/// an unselected segment previews it by brightening the label + a faint fill.
struct SegmentedControl<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var ns
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                let hovering = hovered == item.value && !selected
                Text(item.label)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(selected || hovering ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "segment", in: ns)
                        } else if hovering {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                            selection = item.value
                        }
                    }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.primary.opacity(0.07)))
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
