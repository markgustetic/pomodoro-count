import SwiftUI

/// The primary action: log a pomodoro completed elsewhere. A large, tactile
/// tomato button (gradient matched to the app icon, gloss, colored lift, and a
/// springy press) built on the shared `GradientButtonStyle`.
struct LogButton: View {
    var action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.22))
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .heavy))
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)   // decorative; the text carries the label

                Text("Log completed pomodoro")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(GradientButtonStyle(tint: palette.hero, cornerRadius: 17, vPadding: 18, elevation: 7))
    }
}
