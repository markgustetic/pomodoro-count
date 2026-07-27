import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: never show a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        // Register the global hotkey now that the app event loop is up.
        AppModel.shared.syncGlobalShortcut()
        // Roll today's count back to 0 when the calendar day changes.
        AppModel.shared.startDayMonitoring()
    }
}

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            MainActor.assumeIsolated { SelfTest.run() }   // runs checks, then exits
        }
        // --preview <path> renders the popover UI to a PNG and exits (no window).
        // Add --hover to render buttons in their hover state.
        if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
            PreviewOverrides.forceHover = args.contains("--hover")
            if let t = args.firstIndex(of: "--theme"), t + 1 < args.count {
                PreviewOverrides.theme = ThemeChoice(rawValue: args[t + 1].capitalized)
            }
            MainActor.assumeIsolated { PreviewRenderer.render(to: args[i + 1]) }
        }
        // --store <path> points the app at an alternate data file (for testing
        // against a throwaway file instead of the real Application Support one).
        if let i = args.firstIndex(of: "--store"), i + 1 < args.count {
            AppModel.overrideStoreURL = URL(fileURLWithPath: args[i + 1])
        }
        PomodoroCountApp.main()
    }
}

struct PomodoroCountApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(model)
        } label: {
            Image(nsImage: model.statusImage)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The panel the menu bar item drops down.
///
/// SwiftUI offers no public way to close a `.window`-style `MenuBarExtra` from
/// inside its own content — `@Environment(\.dismiss)` does nothing there. The
/// obvious AppKit workaround, closing the panel window directly, does close it
/// but leaves SwiftUI still believing the panel is presented, so the next click
/// on the menu bar item is swallowed toggling that stale state and it takes two
/// clicks to reopen. (`orderOut` and `NSApp.hide` are worse: measurably stuck or
/// no-ops.) So dismiss the way the user would: find the status item's own button
/// and click it. That runs SwiftUI's real toggle, and the panel reopens on the
/// very next click.
@MainActor
enum MenuBarPanel {
    static func dismiss() {
        statusItemButton?.performClick(nil)
    }

    /// The `NSStatusBarButton` behind our menu bar item. SwiftUI keeps the status
    /// item private, but its window is a normal `NSStatusBarWindow` in `NSApp.windows`
    /// (the button sits some way down that window's view tree, not at its root).
    private static var statusItemButton: NSStatusBarButton? {
        func search(_ view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            return view.subviews.lazy.compactMap(search).first
        }
        return NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .lazy
            .compactMap { $0.contentView.flatMap(search) }
            .first
    }
}
