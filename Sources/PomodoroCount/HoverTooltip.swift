import SwiftUI

/// Where a hover tooltip's card goes, given the cursor and the space available.
///
/// Pure and free of SwiftUI for the same reason `HeatmapLayout.cells` is: at a
/// 300pt panel the horizontal clamp is load-bearing rather than a formality —
/// a card centred on the last heatmap column would leave the window — and the
/// edges where it matters are exactly the ones a pointer is least likely to
/// land on while someone checks by hand.
enum TooltipPlacement {

    /// The card's top-left corner, in the container's coordinate space.
    ///
    /// Horizontally the card centres on the cursor and clamps to the
    /// container. Vertically it prefers `offset` above the cursor and flips to
    /// `offset` below when it would not fit above — which on the 108pt chart
    /// is nearly never and on the 40pt heatmap is nearly always.
    ///
    /// The vertical result is deliberately **not** clamped. A flipped card
    /// overhangs the graph and covers the tiles beneath, and that is correct:
    /// the overlay drawing it isn't clipped, and pulling it back inside would
    /// park it under the pointer, hiding the square it describes.
    static func origin(cursor: CGPoint, tooltip: CGSize, in container: CGSize,
                       offset: CGFloat = 10) -> CGPoint {
        // The second `max(0,)` is what keeps a card wider than its container
        // pinned to the leading edge instead of being pushed off to the left.
        let x = min(max(0, cursor.x - tooltip.width / 2),
                    max(0, container.width - tooltip.width))
        let above = cursor.y - offset - tooltip.height
        return CGPoint(x: x, y: above >= 0 ? above : cursor.y + offset)
    }
}

/// The hover card: one line, sized by its content.
///
/// Backed by `bgBottom` *under* `cardFill` so it is opaque whatever alpha the
/// theme gives the fill — a card you can read the graph through defeats the
/// point of putting it in front of the graph.
struct HoverTooltip: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.bgBottom)
                    .overlay { RoundedRectangle(cornerRadius: 6).fill(palette.cardFill) }
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(palette.cardStroke) }
            }
            .fixedSize()
    }
}

/// Reports the card's measured size back up so `TooltipPlacement` can clamp it.
/// Measured rather than hand-set because the label runs from "Today" to
/// "Wednesday" and a fixed width would clamp the wrong edge for one of them.
struct TooltipSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
