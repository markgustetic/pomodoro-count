import Foundation

/// The arithmetic behind drag-to-reorder, deliberately free of SwiftUI so it can
/// be tested directly. Reordering goes wrong in exactly two places — rounding at
/// the midpoint between two slots, and running off either end of the list — so
/// both live in one function over plain numbers rather than a few lines buried
/// inside a gesture.
enum Reorder {

    /// The slot a dragged row now belongs in.
    ///
    /// - Parameters:
    ///   - startIndex: the index the drag was picked up from.
    ///   - translation: how far the pointer has moved vertically since, in
    ///     points, positive downward — i.e. `DragGesture.Value.translation.height`.
    ///   - pitch: the distance from one row's top edge to the next: row height
    ///     plus the spacing between rows.
    ///   - count: how many rows there are.
    ///
    /// Half a pitch is the boundary. `rounded()` rounds half away from zero, so
    /// dragging down exactly half a row moves down one slot and dragging up
    /// exactly half a row moves up one.
    ///
    /// Returns `startIndex` unchanged when `pitch` is not positive or the list is
    /// empty: a row whose height has not been measured yet must not be able to
    /// produce a move.
    static func destination(from startIndex: Int,
                            translation: CGFloat,
                            pitch: CGFloat,
                            count: Int) -> Int {
        guard pitch > 0, count > 0 else { return startIndex }
        let slots = Int((translation / pitch).rounded())
        return min(max(startIndex + slots, 0), count - 1)
    }
}
