import CoreGraphics

/// The Focus header sparkline's column arithmetic: which bar the pointer is
/// over, and where a bar sits when there is no pointer.
///
/// Pure and free of SwiftUI for the same reason `HeatmapLayout.hitTest` is —
/// a rendered strip isn't assertable, the arithmetic behind it is.
///
/// It deliberately **ignores the gaps the HStack draws**. The strip is 78pt
/// carrying seven capsules with six 3pt gaps, so 18pt of it — nearly a
/// quarter — is not capsule at all, and a zero-count day is a 3pt stub.
/// Hit-testing the drawn shape would make a day off unreachable, which is
/// exactly the value a reader cannot guess by eye, and would blink the card
/// off in every gap the pointer crossed. Equal columns put a boundary within
/// just over 1pt of the true capsule edge, worst case at the two ends and
/// exact in the middle; that is what "nearest bar" means, not an error.
enum SparklineLayout {

    /// The bar index under `x`, or nil outside the strip.
    static func index(atX x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0, x >= 0, x < width else { return nil }
        // The `min` guards the floating-point case where x/column rounds up
        // to `count` at the last representable x below `width`.
        return min(count - 1, Int(x / (width / CGFloat(count))))
    }

    /// The horizontal centre of a column, in the strip's coordinates —
    /// `index` run backwards.
    ///
    /// A headless render has no pointer, so this is where `--hover-graph`
    /// puts the tooltip. It derives the column width the same way `index`
    /// does, so the two cannot disagree about where a bar is; a round-trip
    /// test pins that.
    static func centerX(ofColumn index: Int, width: CGFloat, count: Int) -> CGFloat? {
        guard count > 0, width > 0, (0..<count).contains(index) else { return nil }
        return (CGFloat(index) + 0.5) * (width / CGFloat(count))
    }
}
