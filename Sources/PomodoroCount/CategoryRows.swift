import SwiftUI

/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row aims the session target at it, and the `±` on its trailing
/// edge opens a counter that adds to or subtracts from today's count.
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
                            // The same rule the click runs, so the tooltip
                            // cannot promise a handback the click won't
                            // perform.
                            let releases = TargetPick.action(
                                isAlreadyTarget: row.isTarget,
                                pinned: model.settings.targetPinned,
                                autoAdvance: model.settings.autoAdvanceTarget) == .release
                            CategoryRow(progress: row,
                                        clickReleasesPin: releases,
                                        onSelect: { model.selectTarget(target) },
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

/// One category, carrying two controls rather than one: the row itself aims the
/// session target, and the `±` at its trailing edge opens the count adjuster.
///
/// They are **siblings in a `ZStack`**, not a `±` nested inside the row's
/// label. A `Button` inside another `Button`'s label does not receive clicks on
/// macOS — the outer button's hit testing swallows them, so the inner control
/// looks live and does nothing. Drawn second, the `±` sits above the row in
/// z-order and takes its own hits; the row takes everything else.
struct CategoryRow: View {
    let progress: CategoryProgress
    /// Whether a click would hand control back to the ranking rather than aim.
    /// Computed by the parent from `TargetPick`, so it is the same rule the
    /// click itself runs.
    let clickReleasesPin: Bool
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onSubtract: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false
    @State private var showingCounter = false

    /// The `±`'s hit target, and the gap between it and the card's edge. The
    /// row's content reserves `10 + glyphWidth + glyphInset` on its trailing
    /// side — the same 10pt as its leading padding, plus the glyph's own width
    /// and the inset it sits at — so the count text can never slide underneath
    /// the glyph that is drawn on top of it.
    private static let glyphWidth: CGFloat = 22
    private static let glyphInset: CGFloat = 8

    var body: some View {
        ZStack(alignment: .trailing) {
            selectButton
            adjustButton
        }
    }

    private var selectButton: some View {
        Button(action: onSelect) {
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
            .padding(.leading, 10)
            .padding(.trailing, 10 + Self.glyphWidth + Self.glyphInset)
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
            // element has no `AXValue` attribute, the macOS bridge demoted
            // `accessibilityValue` to `AXValueDescription`. One cause, three
            // symptoms. Applied to the label, it collapses only the HStack, and
            // the Button wraps that in its own element — role, press, focus and
            // value all intact. Measured through the Accessibility API, not
            // assumed.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.name)
            .accessibilityValue(progress.accessibilityValue)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(selectHelp)
        .accessibilityHint("Sends finished pomodoros here")
    }

    /// What the row promises before it is clicked. Three readings, because a
    /// click on the row already aimed at is not the same act as a click on any
    /// other row, and a control that does nothing needs to say so rather than
    /// look broken.
    private var selectHelp: String {
        if clickReleasesPin {
            return "Pinned to \(progress.name) — click to follow the category order again"
        }
        if progress.isTarget {
            return "Finished pomodoros already land in \(progress.name)"
        }
        return "Send finished pomodoros to \(progress.name)"
    }

    private var adjustButton: some View {
        Button { showingCounter = true } label: {
            Image(systemName: "plusminus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: Self.glyphWidth, height: Self.glyphWidth)
                // The glyph draws at about 10pt. Without this the clickable
                // area *is* the glyph, which is a smaller target than a pointer
                // can reliably land on inside a 33pt row.
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Adjust today's count for \(progress.name)")
                .accessibilityValue(progress.countText)
        }
        // Not `SoftIconButtonStyle`: that draws a filled, stroked well, and a
        // well inside a card at 22pt reads as a second card sitting on the
        // first rather than as a mark on it. `HoverTextButtonStyle` is this
        // app's low-chrome control — resting at `textDim` under the classic
        // palette, at a dimmed `palette.cool` under a neon one (resting at
        // `textDim` there was the bug that style's own `.action` case was
        // written to fix — see its doc comment), and lighting up with a glow
        // only on hover or press, never at rest — and, like every style here,
        // it branches on `ControlState` and finishes with `.dimmed`.
        .buttonStyle(HoverTextButtonStyle(emphasis: .action))
        .padding(.trailing, Self.glyphInset)
        .help("Adjust today's count for \(progress.name)")
        // Says what the label doesn't: `.help` also sets the accessibility
        // hint on macOS (see RootView's stop/reset button), so a hint that
        // repeats the label would have VoiceOver read it, the value, then the
        // label again.
        .accessibilityHint("Opens a counter you can adjust")
        // The hint above and this adjustable action both stay on the Button
        // rather than moving inside the label with the rest of the AX setup:
        // both are additive, so they reach the Button's own element fine from
        // out here, whereas `.accessibilityElement(children: .ignore)` in the
        // label REPLACES the element it's applied to and so has to stay inside
        // it — the seam `CategoryRow.selectButton`'s own comment above walks
        // through, and the one that has already cost this project a real bug.
        //
        // Moved here from the row, which now means "select". Its reason is
        // unchanged: routing a count change through a popover would cost
        // VoiceOver three activations, and swipe up/down still does it in one.
        // Its home is the element that owns counting.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdd()
            case .decrement: onSubtract()
            @unknown default: break
            }
        }
        // Trailing, not bottom: the rows are a list, and a popover hanging off
        // the bottom edge covers the neighbours whose counts give this one its
        // context. Anchored on the `±` rather than the row so it hangs off the
        // control that opened it.
        .popover(isPresented: $showingCounter, arrowEdge: .trailing) {
            // A popover is its own window: it inherits the environment but not
            // the appearance, so the theme has to be applied again here.
            CategoryCountPopover(progress: progress, onAdd: onAdd, onSubtract: onSubtract)
                .themed(palette)
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
