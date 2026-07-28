import SwiftUI

/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row logs one pomodoro to that category.
struct CategoryRows: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let rows = model.todayProgress
        VStack(spacing: 5) {
            if rows.isEmpty {
                Text("Add a category in Settings")
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                // Six rows is roughly 200pt; past that the list scrolls so the
                // panel stops growing, the same rule the History day-list uses.
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(rows) { row in
                            CategoryRow(progress: row) {
                                model.logExternal(to: row.isFallback ? .fallback : .named(row.name))
                            }
                        }
                    }
                }
                .frame(maxHeight: rows.count > 6 ? 200 : .infinity)
                .fixedSize(horizontal: false, vertical: rows.count <= 6)
            }
        }
    }
}

/// One tappable category. A real Button, so VoiceOver and the keyboard reach it.
struct CategoryRow: View {
    let progress: CategoryProgress
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(progress.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if progress.showsDots {
                    dots
                } else if progress.goal > 0 {
                    bar
                }

                Text(progress.goal > 0 ? "\(progress.done)/\(progress.goal)" : "\(progress.done)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(progress.isMet ? palette.accent : palette.textDim)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.cardFill.opacity(hover ? 1.6 : 1.0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(palette.cardStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.name)
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityHint("Logs one pomodoro")
    }

    /// One dot per goal unit, filled up to what's done. Decorative — the count
    /// beside it carries the same information for VoiceOver.
    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(0..<progress.goal, id: \.self) { index in
                Circle()
                    .fill(index < progress.done ? palette.accent : palette.hairline)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        GeometryReader { geo in
            let fraction = min(1, Double(progress.done) / Double(max(1, progress.goal)))
            Capsule()
                .fill(palette.hairline)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [palette.accent, palette.accent2],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction)
                }
        }
        .frame(width: 60, height: 6)
        .accessibilityHidden(true)
    }
}
