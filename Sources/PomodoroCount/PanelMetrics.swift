import AppKit
import SwiftUI

/// How tall a tab's content may grow inside the menu bar panel.
///
/// The panel sizes itself to its content: SwiftUI proposes no height, so a
/// `ScrollView` inside it reports its content's full height and the panel grows
/// to match. Nothing in the layout knows about the screen, so left alone a long
/// tab would run off the bottom of the display — which is why the Settings tab
/// carries an explicit cap at all.
///
/// That cap used to be a hardcoded number, and every settings row added since
/// has been paid for by scrolling inside a box that stopped well short of the
/// screen's edge. It is computed here instead: the display's usable height,
/// less the chrome the panel draws around the tab, less a margin.
enum PanelMetrics {

    /// Everything `RootView` draws around a tab: its 14pt padding top and
    /// bottom, the tab picker, the hairline rule and the footer, plus the 12pt
    /// gaps between them.
    ///
    /// Measured, not derived — rendering the panel with a zero-height Settings
    /// tab produced a 108pt panel. It only shifts if that surround changes, and
    /// the margin below absorbs a few points of drift either way.
    static let chrome: CGFloat = 108

    /// Space left between the panel's bottom edge and the bottom of the screen,
    /// so a full-height panel reads as a panel rather than as something jammed
    /// into the corner.
    static let bottomMargin: CGFloat = 24

    /// The shortest a tab may be capped at, whatever the screen says. A display
    /// small enough to push the cap below this is better served by scrolling a
    /// usable pane than by a pane too short to show a row.
    static let minimum: CGFloat = 320

    /// The tallest a tab's scrolling content may be on a screen whose usable
    /// height — `NSScreen.visibleFrame.height`, which already excludes the menu
    /// bar — is `visibleHeight`.
    static func tabHeightCap(visibleHeight: CGFloat) -> CGFloat {
        max(minimum, visibleHeight - chrome - bottomMargin)
    }

    /// The cap for the screen the panel is on. Falls back to a 900pt screen —
    /// roughly a laptop display — if AppKit reports no screen at all, which it
    /// does when nothing is on screen yet.
    @MainActor static var tabHeightCap: CGFloat {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900
        return tabHeightCap(visibleHeight: visible)
    }
}

/// The scroller every long tab sits in.
///
/// A cap alone is not enough in the real panel. The `MenuBarExtra` window
/// sizes itself to its content's *ideal* height, and a bare `ScrollView`'s
/// ideal is next to nothing — measured with the accessibility API: tabs
/// wrapped in one collapsed the panel to 255pt while the Focus tab, which has
/// no scroller, stood at 537. (`--preview` and the harness window never
/// showed it: both propose generous heights the panel does not.) So the
/// content is measured and the scroller's height pinned to exactly what the
/// screen can afford of it: the content's own height when it fits, the
/// screen-derived cap when it doesn't — never blank space, never a collapse.
struct PanelTabScroller<Content: View>: View {
    @ViewBuilder var content: Content

    /// Measured at layout time; zero until the first pass has run, in which
    /// case the frame stays unconstrained for that one frame.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content.background {
                GeometryReader { geo in
                    // `.task(id:)` runs after the layout that produced the
                    // height, so this write cannot land mid-view-update —
                    // same pattern the category list uses for row height.
                    Color.clear.task(id: geo.size.height) { contentHeight = geo.size.height }
                }
            }
        }
        .frame(height: contentHeight > 0 ? min(contentHeight, PanelMetrics.tabHeightCap) : nil)
    }
}
