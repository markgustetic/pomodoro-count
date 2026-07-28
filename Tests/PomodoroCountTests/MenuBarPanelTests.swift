import Testing
import AppKit
@testable import PomodoroCount

/// The right-click menu on the status item. The event plumbing needs a running
/// app and a real status bar, but the menu it puts on screen is ordinary AppKit
/// and can be inspected directly.
@MainActor
@Suite struct MenuBarPanelTests {

    @Test func theMenuOffersExactlyOneWayOut() {
        let menu = MenuBarPanel.contextMenu()
        #expect(menu.items.count == 1)
        #expect(menu.items.first?.title == "Quit Pomodoro Count")
    }

    @Test func quitIsWiredToTheApplicationTerminateAction() {
        let item = MenuBarPanel.contextMenu().items.first
        #expect(item?.action == #selector(NSApplication.terminate(_:)))
    }

    /// No explicit target, so the action travels the responder chain to NSApp
    /// exactly as a Quit item in a normal app's menu bar does. A stale target
    /// here would silently disable the only item in the menu.
    @Test func quitHasNoExplicitTarget() {
        #expect(MenuBarPanel.contextMenu().items.first?.target == nil)
    }

    @Test func quitCarriesTheConventionalKeyEquivalent() {
        #expect(MenuBarPanel.contextMenu().items.first?.keyEquivalent == "q")
    }

    @Test func theItemIsEnabled() {
        #expect(MenuBarPanel.contextMenu().items.first?.isEnabled == true)
    }

    /// Each call builds a fresh menu — popping up a menu that is already on
    /// screen throws in AppKit.
    @Test func eachCallReturnsAFreshMenu() {
        #expect(MenuBarPanel.contextMenu() !== MenuBarPanel.contextMenu())
    }
}
