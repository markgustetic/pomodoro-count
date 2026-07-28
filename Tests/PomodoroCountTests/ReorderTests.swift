import Testing
import Foundation
@testable import PomodoroCount

/// The drag arithmetic, tested without a UI. `pitch` is 32 throughout — one
/// row's height plus the gap to the next — so a translation of 32 is exactly
/// one slot and 16 is exactly the boundary between two.
@Suite struct ReorderTests {

    private let pitch: CGFloat = 32

    @Test func noMovementStaysPut() {
        #expect(Reorder.destination(from: 2, translation: 0, pitch: pitch, count: 5) == 2)
    }

    @Test func draggingDownMovesOneSlotPerRow() {
        #expect(Reorder.destination(from: 0, translation: 32, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 0, translation: 96, pitch: pitch, count: 5) == 3)
    }

    @Test func draggingUpMovesOneSlotPerRow() {
        #expect(Reorder.destination(from: 4, translation: -32, pitch: pitch, count: 5) == 3)
        #expect(Reorder.destination(from: 4, translation: -96, pitch: pitch, count: 5) == 1)
    }

    /// Short of half a row is still the same slot: the row commits a move only
    /// once it has travelled far enough to have changed places with a neighbour.
    @Test func lessThanHalfARowDoesNotMove() {
        #expect(Reorder.destination(from: 1, translation: 15, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 1, translation: -15, pitch: pitch, count: 5) == 1)
    }

    /// The boundary, pinned deliberately rather than left to whatever rounding
    /// happens to do: exactly half a row commits the move, in both directions.
    @Test func exactlyHalfARowCommitsTheMove() {
        #expect(Reorder.destination(from: 1, translation: 16, pitch: pitch, count: 5) == 2)
        #expect(Reorder.destination(from: 1, translation: -16, pitch: pitch, count: 5) == 0)
    }

    @Test func draggingPastTheTopClampsToTheFirstSlot() {
        #expect(Reorder.destination(from: 1, translation: -500, pitch: pitch, count: 5) == 0)
    }

    @Test func draggingPastTheBottomClampsToTheLastSlot() {
        #expect(Reorder.destination(from: 1, translation: 500, pitch: pitch, count: 5) == 4)
    }

    /// Rows report their height at layout time, so pitch is zero until the first
    /// layout has run. A drag in that window must not be able to reorder.
    @Test func anUnmeasuredPitchNeverMoves() {
        #expect(Reorder.destination(from: 2, translation: 200, pitch: 0, count: 5) == 2)
        #expect(Reorder.destination(from: 2, translation: 200, pitch: -8, count: 5) == 2)
    }

    @Test func anEmptyListNeverMoves() {
        #expect(Reorder.destination(from: 0, translation: 200, pitch: pitch, count: 0) == 0)
    }
}
