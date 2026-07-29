import Testing
import AppKit
@testable import PomodoroCount

/// The Settings tab's height cap. It used to be a hardcoded number that the tab
/// outgrew; these pin down that it now follows the screen instead.
@Suite struct PanelMetricsTests {

    /// A 13" laptop's usable height. The cap has to leave room for the panel's
    /// own surround, so it lands well below the screen but well above the old
    /// fixed 700.
    @Test func theCapFillsTheScreenLessTheChromeAndMargin() {
        let cap = PanelMetrics.tabHeightCap(visibleHeight: 923)
        #expect(cap == 923 - PanelMetrics.chrome - PanelMetrics.bottomMargin)
        #expect(cap > 700)
    }

    /// The whole point: a taller display gives the tab more room, one point for
    /// one point, with no ceiling of its own.
    @Test func atallerScreenRaisesTheCap() {
        let laptop = PanelMetrics.tabHeightCap(visibleHeight: 923)
        let studio = PanelMetrics.tabHeightCap(visibleHeight: 1523)
        #expect(studio - laptop == 600)
    }

    /// A panel that fits on the screen: the tab, plus everything drawn around
    /// it, must still clear the bottom edge.
    @Test func theWholePanelFitsOnTheScreen() {
        let visible: CGFloat = 923
        let panel = PanelMetrics.tabHeightCap(visibleHeight: visible) + PanelMetrics.chrome
        #expect(panel <= visible)
    }

    /// A short screen — or a stray zero from a display that has just woken —
    /// must not collapse the tab to nothing. Scrolling a usable pane beats a
    /// pane too short to show a row.
    @Test func aTinyScreenFallsBackToTheMinimum() {
        #expect(PanelMetrics.tabHeightCap(visibleHeight: 400) == PanelMetrics.minimum)
        #expect(PanelMetrics.tabHeightCap(visibleHeight: 0) == PanelMetrics.minimum)
    }

    /// The screen-reading property agrees with the arithmetic for whatever
    /// display the tests happen to run on, and never returns something absurd.
    @MainActor
    @Test func theLiveCapMatchesTheScreenItIsRunningOn() {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900
        #expect(PanelMetrics.tabHeightCap == PanelMetrics.tabHeightCap(visibleHeight: visible))
        #expect(PanelMetrics.tabHeightCap >= PanelMetrics.minimum)
    }
}
