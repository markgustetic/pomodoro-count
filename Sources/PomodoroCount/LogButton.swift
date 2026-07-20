import SwiftUI

/// The primary action: log a pomodoro completed elsewhere. A large, tactile
/// "tomato" button — gradient fill matching the app icon, a soft top gloss,
/// a colored drop shadow for lift, and a springy press response.
struct LogButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.22))
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .heavy))
                }
                .frame(width: 38, height: 38)

                Text("Log completed pomodoro")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
        }
        .buttonStyle(TomatoButtonStyle())
    }
}

/// Tomato-red gradient button style with gloss, edge highlight, drop shadow,
/// and a press animation.
struct TomatoButtonStyle: ButtonStyle {
    // Matches the app icon's tomato body gradient.
    private let top = Color(red: 1.00, green: 0.45, blue: 0.37)
    private let bottom = Color(red: 0.82, green: 0.16, blue: 0.17)
    private let shadowColor = Color(red: 0.80, green: 0.15, blue: 0.15)

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)

        configuration.label
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.20), radius: 0.5, y: 0.5)  // crisp text
            .background {
                shape
                    .fill(LinearGradient(colors: [top, bottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // Soft top gloss that fades out gently past the middle.
                        shape.fill(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.26), location: 0.0),
                                .init(color: .white.opacity(0.05), location: 0.45),
                                .init(color: .clear, location: 0.85),
                            ],
                            startPoint: .top, endPoint: .bottom))
                    }
                    .overlay {
                        // Fine edge highlight, brighter on top.
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    }
            }
            // Tight contact shadow + a soft tinted lift (not a glow).
            .shadow(color: .black.opacity(pressed ? 0.10 : 0.16),
                    radius: pressed ? 1.5 : 3, x: 0, y: pressed ? 1 : 2)
            .shadow(color: shadowColor.opacity(pressed ? 0.12 : 0.26),
                    radius: pressed ? 3 : 7, x: 0, y: pressed ? 2 : 5)
            .scaleEffect(pressed ? 0.97 : 1)
            .brightness(pressed ? -0.04 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.62), value: pressed)
    }
}
