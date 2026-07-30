import SwiftUI

/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row opens a counter that adds to or subtracts from its count.
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
                // panel stops growing. Deliberately NOT PanelTabScroller's
                // screen-derived cap: this list shares the Focus tab with the
                // timer card, which must stay in reach without scrolling.
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(rows) { row in
                            let target: CategoryTarget =
                                row.isFallback ? .fallback : .named(row.name)
                            CategoryRow(progress: row,
                                        onAdd: { model.logExternal(to: target) },
                                        onSubtract: { model.unlogToday(from: target) })
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
    let onAdd: () -> Void
    let onSubtract: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false
    @State private var showingCounter = false

    var body: some View {
        Button { showingCounter = true } label: {
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

                Text(progress.countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(progress.isMet ? palette.accent : palette.textDim)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                CardBackground(cornerRadius: 11, fillOpacity: hover ? 1.6 : 1.0)
                    .overlay {
                        // A met goal soaks the whole card in a wash of the
                        // accent — the count text already turns accent at the
                        // same moment, this just makes it readable from across
                        // the room. Under the target stroke, so both can show.
                        if progress.isMet {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(palette.accent.opacity(0.12))
                        }
                        // The target row stays outlined so it is clear where
                        // the next finished pomodoro lands, and — since the
                        // rows are what aim it — which row a click already
                        // selected.
                        if progress.isTarget {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(palette.accent.opacity(0.8), lineWidth: 1.5)
                        }
                    }
            }
            // Collapsed here, inside the label — NOT on the Button, which is
            // where these three sat until the AX tree was actually read back.
            // `.accessibilityElement(children: .ignore)` builds a fresh, plain
            // element and throws away the one it is applied to, so on the
            // Button it discarded the button itself: the row came out
            // `AXUnknown` with no `AXPress` and no focus, and because a plain
            // element has no `AXValue` attribute at all, the macOS bridge
            // demoted `accessibilityValue` to `AXValueDescription`. One cause,
            // three symptoms. Applied to the label, it collapses only the
            // HStack, and the Button wraps that in its own element — role,
            // press, focus and value all intact. Measured through the
            // Accessibility API, not assumed.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.name)
            .accessibilityValue(progress.accessibilityValue)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        // Trailing, not bottom: the rows are a list, and a popover hanging off
        // the bottom edge covers the neighbours whose counts give this one its
        // context.
        .popover(isPresented: $showingCounter, arrowEdge: .trailing) {
            // A popover is its own window: it inherits the environment but not
            // the appearance, so the theme has to be applied again here.
            CategoryCountPopover(progress: progress, onAdd: onAdd, onSubtract: onSubtract)
                .themed(palette)
        }
        .help(progress.isMet ? "\(progress.name): goal met — adjust today's count"
                             : "Adjust today's count for \(progress.name)")
        // The hint and the adjustable action stay on the Button: both are
        // additive, so they reach the button's own element rather than
        // replacing it.
        .accessibilityHint("Opens a counter you can adjust")
        // Restores what the popover would otherwise cost VoiceOver. The row used
        // to log in one activation; routing it through a popover would make that
        // three. Swipe up and down adjust the count without opening anything.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdd()
            case .decrement: onSubtract()
            @unknown default: break
            }
        }
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

/// The `−`/count/`+` strip a category row opens.
///
/// Takes its dependencies as parameters rather than reading them from the
/// environment — the rule every popover in this app follows, whether that
/// means the model itself (`AddCategoryForm`) or closures (
/// `RemoveCategoryConfirmation`, and this): `@EnvironmentObject` does not
/// reliably reach popover content, and it fails by *crashing* rather than by
/// looking wrong.
///
/// The name is deliberately not repeated here — the row that was tapped is
/// still on screen immediately beside this, and a second copy of the label in a
/// strip this small reads as clutter.
struct CategoryCountPopover: View {
    let progress: CategoryProgress
    let onAdd: () -> Void
    let onSubtract: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            // SoftIconButtonStyle, not a borderless style: it branches on
            // `ControlState`, so `.disabled` at zero actually looks dead. A
            // hand-rolled style here is how the dimming bug got in last time.
            Button(action: onSubtract) {
                Image(systemName: "minus")
            }
            .buttonStyle(SoftIconButtonStyle(width: 34, height: 30))
            .disabled(progress.done == 0)
            .help("Take one back from \(progress.name)")
            // Not just "Remove one pomodoro": the row beside this popover is
            // what makes the bare version unambiguous for a sighted user, and
            // that reasoning doesn't survive VoiceOver moving focus into a
            // separate popover window where the row is no longer what's read.
            .accessibilityLabel("Remove one pomodoro from \(progress.name)")

            Text(progress.countText)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(progress.isMet ? palette.accent : palette.text)
                // A minimum, not a fixed width: `done` can climb past `goal`
                // (a category logged 100 times against a goal of 20 still
                // reads "100/20"), and a fixed width would clip it. 48pt just
                // keeps the strip from jumping in place between one and two
                // digits at the common single-digit boundary.
                .frame(minWidth: 48)
                .accessibilityLabel(progress.accessibilityValue)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(SoftIconButtonStyle(width: 34, height: 30))
            .help("Log one pomodoro to \(progress.name)")
            .accessibilityLabel("Add one pomodoro to \(progress.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // `.themed(palette)`, applied by the caller (`CategoryRow`, since a
        // popover is its own window), only swaps the SwiftUI environment's
        // `colorScheme` — it does not repaint the NSPopover's own background
        // material, which is what actually shows through the padding above.
        // `RootView.swift`'s `.background { if palette.paintsBackground { … } }`
        // is the established fix for exactly this: Classic's `paintsBackground`
        // is false, so the system's own (light) material still shows there, but
        // Synthwave's is true because its look cannot be carried by any system
        // material. Without this, the popover stayed light-grey under Synthwave
        // and the disabled `−` — drawn from `palette.cool`, further dimmed —
        // disappeared into it.
        .foregroundStyle(palette.text)
        .background { if palette.paintsBackground { palette.background } }
    }
}
