import Foundation

/// The arithmetic behind drag-to-reorder, deliberately free of SwiftUI so it can
/// be tested directly. Reordering goes wrong in exactly two places — rounding at
/// the midpoint between two slots, and running off either end of the list — so
/// both live in one function over plain numbers rather than a few lines buried
/// inside a gesture.
enum Reorder {

    /// How far past half a row the pointer must travel before a move commits,
    /// as a fraction of a row.
    ///
    /// Without it the boundary is a knife edge: a pointer moving slowly across
    /// it flips the rounding back and forth on every tremor, and each flip is a
    /// committed reorder — an array mutation, a store write and an animation. A
    /// slow crossing produced dozens, and the drag read as stuttering rather
    /// than moving. This makes the slot the row is in slightly sticky, so a
    /// crossing happens once and decisively.
    static let stickiness: CGFloat = 0.2

    /// The slot a dragged row now belongs in.
    ///
    /// - Parameters:
    ///   - startIndex: the index the drag was picked up from.
    ///   - currentIndex: the index the row occupies now. Equal to `startIndex`
    ///     until the drag has committed a move.
    ///   - translation: how far the pointer has moved vertically since the drag
    ///     began, in points, positive downward — i.e.
    ///     `DragGesture.Value.translation.height`.
    ///   - pitch: the distance from one row's top edge to the next: row height
    ///     plus the spacing between rows.
    ///   - count: how many rows there are.
    ///
    /// The row stays where it is until the pointer is clear of its current slot
    /// by more than half a row plus `stickiness`; then it moves to whichever
    /// slot the translation actually calls for, which may be several away if the
    /// pointer moved fast. Distance is measured from the *current* slot rather
    /// than from the boundary, which is what stops a move committing and
    /// immediately un-committing.
    ///
    /// Returns `currentIndex` unchanged when `pitch` is not positive or the list
    /// is empty: a row whose height has not been measured yet must not be able
    /// to produce a move.
    static func destination(from startIndex: Int,
                            current currentIndex: Int,
                            translation: CGFloat,
                            pitch: CGFloat,
                            count: Int) -> Int {
        guard pitch > 0, count > 0 else { return currentIndex }
        let travelled = translation / pitch                 // in rows, fractional
        let held = CGFloat(currentIndex - startIndex)       // rows already committed
        guard abs(travelled - held) > 0.5 + stickiness else { return currentIndex }
        let slots = Int(travelled.rounded())
        return min(max(startIndex + slots, 0), count - 1)
    }
}
