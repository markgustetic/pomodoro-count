import Testing
import Foundation
@testable import PomodoroCount

/// The drag arithmetic, tested without a UI. `pitch` is 32 throughout — one
/// row's height plus the gap to the next — so a translation of 32 is exactly one
/// slot. The slot the row sits in is sticky: it takes half a row *plus*
/// `Reorder.stickiness` to leave it, so with this pitch the commit threshold is
/// 0.7 × 32 = 22.4pt rather than 16pt.
@Suite struct ReorderTests {

    private let pitch: CGFloat = 32

    /// The distance from the current slot at which a move commits, in points.
    private var threshold: CGFloat { (0.5 + Reorder.stickiness) * pitch }

    @Test func noMovementStaysPut() {
        #expect(Reorder.destination(from: 2, current: 2, translation: 0, pitch: pitch, count: 5) == 2)
    }

    @Test func draggingDownMovesOneSlotPerRow() {
        #expect(Reorder.destination(from: 0, current: 0, translation: 32, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 0, current: 0, translation: 96, pitch: pitch, count: 5) == 3)
    }

    @Test func draggingUpMovesOneSlotPerRow() {
        #expect(Reorder.destination(from: 4, current: 4, translation: -32, pitch: pitch, count: 5) == 3)
        #expect(Reorder.destination(from: 4, current: 4, translation: -96, pitch: pitch, count: 5) == 1)
    }

    /// The row commits a move only once it has travelled far enough to have
    /// properly changed places with a neighbour.
    @Test func shortOfTheThresholdDoesNotMove() {
        #expect(Reorder.destination(from: 1, current: 1, translation: 22, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 1, current: 1, translation: -22, pitch: pitch, count: 5) == 1)
    }

    /// Half a row on its own is no longer enough — `stickiness` is what stops a
    /// pointer easing across the boundary from flipping the row back and forth.
    @Test func halfARowIsNotEnoughOnItsOwn() {
        #expect(Reorder.destination(from: 1, current: 1, translation: 16, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 1, current: 1, translation: -16, pitch: pitch, count: 5) == 1)
    }

    /// 22 and 23 straddle the 22.4pt threshold, so this pair and
    /// `shortOfTheThresholdDoesNotMove` pin it from either side.
    @Test func pastTheThresholdCommitsTheMove() {
        #expect(threshold > 22 && threshold < 23)
        #expect(Reorder.destination(from: 1, current: 1, translation: 23, pitch: pitch, count: 5) == 2)
        #expect(Reorder.destination(from: 1, current: 1, translation: -23, pitch: pitch, count: 5) == 0)
    }

    /// The point of the whole mechanism: having committed a move, easing back
    /// towards where it came from must not immediately undo it. Without this,
    /// a slow crossing commits a reorder on every tremor of the pointer.
    @Test func aCommittedMoveDoesNotImmediatelyUnCommit() {
        // The drag started at 0 and has committed a move into slot 1.
        for translation in [CGFloat(23), 20, 16, 12, 10] {
            #expect(Reorder.destination(
                from: 0, current: 1, translation: translation, pitch: pitch, count: 5) == 1)
        }
    }

    /// It is sticky, not one-way: come back far enough and the row does return.
    @Test func comingBackPastTheThresholdMovesBack() {
        #expect(Reorder.destination(from: 0, current: 1, translation: 9, pitch: pitch, count: 5) == 0)
    }

    /// The band is symmetric about whichever slot the row is in, not about
    /// where the drag began. This row started at 4 and has committed a move up
    /// into slot 3, so the band now sits around 3.
    @Test func theStickyBandFollowsTheSlotTheRowIsIn() {
        #expect(Reorder.destination(from: 4, current: 3, translation: -23, pitch: pitch, count: 5) == 3)
        #expect(Reorder.destination(from: 4, current: 3, translation: -12, pitch: pitch, count: 5) == 3)
        // Eased back far enough to leave the band: the row returns to slot 4.
        #expect(Reorder.destination(from: 4, current: 3, translation: -9, pitch: pitch, count: 5) == 4)
    }

    /// A pointer that moves fast crosses several slots between ticks, and the
    /// row must follow all the way rather than one slot at a time.
    @Test func aFastDragCrossesSeveralSlotsAtOnce() {
        #expect(Reorder.destination(from: 0, current: 0, translation: 128, pitch: pitch, count: 6) == 4)
    }

    @Test func draggingPastTheTopClampsToTheFirstSlot() {
        #expect(Reorder.destination(from: 1, current: 1, translation: -500, pitch: pitch, count: 5) == 0)
    }

    @Test func draggingPastTheBottomClampsToTheLastSlot() {
        #expect(Reorder.destination(from: 1, current: 1, translation: 500, pitch: pitch, count: 5) == 4)
    }

    /// Held against the end of the list, further travel in the same direction
    /// must keep resolving to the same slot rather than churning.
    @Test func holdingPastTheEndStaysClamped() {
        #expect(Reorder.destination(from: 0, current: 4, translation: 300, pitch: pitch, count: 5) == 4)
        #expect(Reorder.destination(from: 0, current: 4, translation: 500, pitch: pitch, count: 5) == 4)
    }

    /// Rows report their height at layout time, so pitch is zero until the first
    /// layout has run. A drag in that window must not be able to reorder.
    @Test func anUnmeasuredPitchNeverMoves() {
        #expect(Reorder.destination(from: 2, current: 2, translation: 200, pitch: 0, count: 5) == 2)
        #expect(Reorder.destination(from: 2, current: 2, translation: 200, pitch: -8, count: 5) == 2)
    }

    @Test func anEmptyListNeverMoves() {
        #expect(Reorder.destination(from: 0, current: 0, translation: 200, pitch: pitch, count: 0) == 0)
    }
}
