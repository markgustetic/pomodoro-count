import Testing
import Foundation
@testable import PomodoroCount

/// Where the hover card lands. The numbers below are the real ones: a ~276pt
/// graph inside a 300pt panel, a 108pt chart and a 40pt heatmap, and a card
/// about 84x18 carrying "Sun, Jul 26 · 2" — `dayLabel`'s real `"EEE, MMM d"`
/// format, not the shorter `"MMM d"` guess an earlier measurement used.
@Suite struct TooltipPlacementTests {

    private let card = CGSize(width: 84, height: 18)
    private let chart = CGSize(width: 276, height: 108)
    private let heatmap = CGSize(width: 276, height: 40)

    @Test func theCardCentresOnTheCursor() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.x == CGFloat(100 - 42))
    }

    @Test func theCardSitsAboveTheCursorWhenThereIsRoom() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.y == CGFloat(60 - 10 - 18))
    }

    /// The 40pt heatmap almost never has room above, so the flip is the common
    /// case there rather than an edge case.
    @Test func theCardFlipsBelowWhenItWouldNotFitAbove() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 20),
                                        tooltip: card, in: heatmap)
        #expect(p.y == CGFloat(20 + 10))
    }

    @Test func theCardClampsAtTheLeftEdge() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 5, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.x == 0)
    }

    /// The load-bearing one: a card centred on the last heatmap column would
    /// otherwise leave the panel entirely.
    @Test func theCardClampsAtTheRightEdge() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 274, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.x == CGFloat(276 - 84))
        #expect(p.x + card.width <= chart.width)
    }

    @Test func aCardWiderThanItsContainerPinsToTheLeadingEdge() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 60),
                                        tooltip: CGSize(width: 300, height: 18), in: chart)
        #expect(p.x == 0)
    }

    /// A flipped card is allowed to overhang: the overlay drawing it isn't
    /// clipped, and pulling it back inside would park it under the pointer.
    @Test func aFlippedCardMayOverhangTheContainer() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 20),
                                        tooltip: card, in: heatmap)
        #expect(p.y + card.height > heatmap.height)
    }
}
