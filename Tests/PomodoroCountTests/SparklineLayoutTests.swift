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
}
