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

    // MARK: Which window is the panel

    /// The window that hosts the menu bar item is always there and always
    /// visible. Mistaking it for the panel would make "is the panel open"
    /// permanently true.
    @Test func theStatusBarWindowIsNotThePanel() {
        #expect(!MenuBarPanel.isPanelWindow(className: "NSStatusBarWindow"))
    }

    /// The panel is recognised as "not the status bar window" rather than by
    /// SwiftUI's private class name, so a rename on Apple's side cannot switch
    /// off the banner clearing that hangs on this answer.
    @Test func anyOtherWindowCountsAsThePanel() {
        #expect(MenuBarPanel.isPanelWindow(className: "SwiftUI.MenuBarExtraWindow"))
        #expect(MenuBarPanel.isPanelWindow(className: "SomeFutureNameForThePanel"))
    }

    // MARK: How the panel is opened and closed from code

    /// macOS 27: SwiftUI drives the panel through the status item's expanded
    /// interface session, so that is what code has to ask for.
    @Test func aSessionDrivenItemOpensByRequestingASession() {
        #expect(MenuBarPanel.openRoute(sessionDriven: true, canRequestSession: true) == .requestSession)
    }

    @Test func aSessionDrivenItemClosesByCancellingItsSession() {
        #expect(MenuBarPanel.closeRoute(sessionDriven: true, hasSession: true) == .cancelSession)
    }

    /// The click is not a fallback there. Measured: it opens nothing, closes
    /// nothing, and leaves the button's state stuck on — so with no session
    /// call to make, the right move is none at all.
    @Test func aSessionDrivenItemIsNeverClicked() {
        #expect(MenuBarPanel.openRoute(sessionDriven: true, canRequestSession: false) == .nothing)
        #expect(MenuBarPanel.closeRoute(sessionDriven: true, hasSession: false) == .nothing)
    }

    /// Before macOS 27 the button's own action is SwiftUI's toggle, and
    /// clicking it is still the only way in or out.
    @Test func anItemWithoutSessionsIsStillClicked() {
        #expect(MenuBarPanel.openRoute(sessionDriven: false, canRequestSession: false) == .clickButton)
        #expect(MenuBarPanel.openRoute(sessionDriven: false, canRequestSession: true) == .clickButton)
        #expect(MenuBarPanel.closeRoute(sessionDriven: false, hasSession: false) == .clickButton)
    }
}
