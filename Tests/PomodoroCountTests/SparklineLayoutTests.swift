import Testing
import Foundation
import CoreGraphics
@testable import PomodoroCount

/// The Focus header sparkline's column arithmetic. The numbers are the real
/// ones: a 78pt strip carrying seven days, drawn as 8.571pt capsules with
/// six 3pt gaps between them.
@Suite struct SparklineLayoutTests {

    private let width: CGFloat = 78
    private let count = 7

    @Test func eachColumnCentreFindsItsOwnBar() {
        for bar in 0..<count {
            let x = (CGFloat(bar) + 0.5) * (width / CGFloat(count))
            #expect(SparklineLayout.index(atX: x, width: width, count: count) == bar)
        }
    }

    /// 18 of the strip's 78pt are gap, and a zero-count day is a 3pt stub.
    /// A pointer in a gap must still name a bar, or the card blinks off
    /// between every pair of days and a day off is unreadable.
    ///
    /// The gap between bars 0 and 1 spans 8.571…11.571, so its midpoint is
    /// 10.071 — inside equal-column 0, which runs 0…11.143.
    @Test func aPointerInADrawnGapStillNamesABar() {
        #expect(SparklineLayout.index(atX: 10.071, width: width, count: count) == 0)
    }

    @Test func theLeadingEdgeIsTheFirstBar() {
        #expect(SparklineLayout.index(atX: 0, width: width, count: count) == 0)
    }

    @Test func theLastPointInsideTheStripIsTheLastBar() {
        #expect(SparklineLayout.index(atX: width - 0.001,
                                      width: width, count: count) == count - 1)
    }

    @Test func aPointerOutsideTheStripHoversNothing() {
        #expect(SparklineLayout.index(atX: -1, width: width, count: count) == nil)
        #expect(SparklineLayout.index(atX: width, width: width, count: count) == nil)
    }

    @Test func anEmptySeriesHoversNothing() {
        #expect(SparklineLayout.index(atX: 40, width: width, count: 0) == nil)
    }

    @Test func aStripWithNoWidthHoversNothing() {
        #expect(SparklineLayout.index(atX: 0, width: 0, count: count) == nil)
    }

    @Test func aSingleBarOwnsTheWholeStrip() {
        #expect(SparklineLayout.index(atX: 0, width: width, count: 1) == 0)
        #expect(SparklineLayout.index(atX: width - 0.001, width: width, count: 1) == 0)
    }

    /// The preview flag's forced hover has to land on the bar it names, or a
    /// headless render shows the card pointing at the wrong day — which is
    /// the one failure a render exists to catch and cannot report.
    @Test func aColumnCentreRoundTripsBackToItsOwnIndex() {
        for bar in 0..<count {
            let x = SparklineLayout.centerX(ofColumn: bar, width: width, count: count)
            #expect(x != nil)
            #expect(SparklineLayout.index(atX: x!, width: width, count: count) == bar)
        }
    }

    @Test func thereIsNoCentreForABarThatIsNotThere() {
        #expect(SparklineLayout.centerX(ofColumn: count, width: width, count: count) == nil)
        #expect(SparklineLayout.centerX(ofColumn: -1, width: width, count: count) == nil)
    }

    /// The property that actually makes equal-column hit-testing safe: every
    /// drawn capsule's edges fall strictly inside its own equal column, so no
    /// point genuinely on a capsule is ever attributed to a neighbour. The x
    /// values here come from the *drawn* layout (60/7pt capsules, 3pt gaps),
    /// not from `index`'s own width/count formula — deriving them that way
    /// would make this tautological.
    ///
    /// This passes today. It exists to fail if the 78pt strip width or the
    /// 3pt gap ever change enough that the equal columns and the drawn
    /// capsules diverge — the one regression the rest of this suite cannot
    /// see, since every other test here measures `index` against itself.
    @Test func everyCapsuleEdgeStaysInsideItsOwnColumn() {
        let capsuleWidth: CGFloat = 60.0 / 7.0
        let gap: CGFloat = 3
        let pitch = capsuleWidth + gap
        let epsilon: CGFloat = 0.01
        for bar in 0..<count {
            let left = pitch * CGFloat(bar)
            let right = left + capsuleWidth
            #expect(SparklineLayout.index(atX: left + epsilon, width: width, count: count) == bar)
            #expect(SparklineLayout.index(atX: right - epsilon, width: width, count: count) == bar)
        }
    }
}
