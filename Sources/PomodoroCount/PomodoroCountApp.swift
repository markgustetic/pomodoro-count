import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// pomodorocount:// URLs — see `URLCommand`. Launch Services starts the
    /// app if it isn't running and delivers here either way.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { AppModel.shared.handle(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: never show a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        // Register the global hotkey now that the app event loop is up.
        AppModel.shared.syncGlobalShortcut()
        // Roll today's count back to 0 when the calendar day changes.
        AppModel.shared.startDayMonitoring()
        // Catch a day that turned over while the app was quit or the lid was
        // shut, which the notification below can only report while running.
        AppModel.shared.realignTarget()
        // Pause a running session when the Mac goes unattended.
        AppModel.shared.startScreenLockMonitoring()
        // Arm the end-of-day reminder, if one is configured, and keep it
        // honest across timezone and clock changes.
        AppModel.shared.startNudgeMonitoring()
        // Start Sparkle now rather than lazily from the Settings tab, or its
        // scheduled background checks would never run for anyone who doesn't
        // open Settings — which is most people.
        _ = Updater.shared
        // Right-click the menu bar item to quit without opening the panel.
        MenuBarPanel.installContextMenu()

        // A menu-bar-only app launches to no window, no Dock icon, and no sign
        // it did anything. Open the panel once so a new user sees where it went.
        if AppModel.shared.isFirstLaunch {
            AppModel.shared.markLaunched()
            MenuBarPanel.present()
        }
    }
}

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        // --preview <path> renders the popover UI to a PNG and exits (no window).
        // Add --hover to render buttons in their hover state, or --armed-break
        // to render the Focus tab with a completed session's break waiting.
        //
        // --store composes with it, and reaches this path by hand rather than
        // through the `AppModel.overrideStoreURL` line below, which the render's
        // own exit means we never get to. Without it the renderer draws its demo
        // categories, so a state only a real store can express — a pinned
        // target, an archived category — has to be seeded and passed in.
        if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
            PreviewOverrides.isRendering = true
            PreviewOverrides.forceHover = args.contains("--hover")
            PreviewOverrides.armedBreak = args.contains("--armed-break")
            if let t = args.firstIndex(of: "--theme"), t + 1 < args.count {
                PreviewOverrides.theme = ThemeChoice(rawValue: args[t + 1].capitalized)
            }
            var storePath: String?
            if let s = args.firstIndex(of: "--store"), s + 1 < args.count {
                storePath = args[s + 1]
            }
            MainActor.assumeIsolated {
                PreviewRenderer.render(to: args[i + 1], storePath: storePath)
            }
        }
        // --store <path> points the app at an alternate data file (for testing
        // against a throwaway file instead of the real Application Support one).
        if let i = args.firstIndex(of: "--store"), i + 1 < args.count {
            AppModel.overrideStoreURL = URL(fileURLWithPath: args[i + 1])
        }
        // --seed-store <path> writes a store with known categories and exits,
        // so a UI test can start from a fixed state. See `StoreSeed`.
        if let i = args.firstIndex(of: "--seed-store"), i + 1 < args.count {
            StoreSeed.write(to: args[i + 1])
            return
        }
        // --reorder-window hosts the panel UI in a plain window for automated
        // drag reproduction. See `ReorderHarness` for what it may not be used
        // to prove.
        if args.contains("--reorder-window") {
            MainActor.assumeIsolated { ReorderHarness.run() }
            return
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
            StatusItemLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar item's image. Its own view because it is one of the two
/// places that display seconds: it observes the clock so the countdown keeps
/// moving, and the model so count and phase changes land. With `remaining`
/// split out of `AppModel`, nothing else in the app re-renders on a tick.
private struct StatusItemLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var clock: SessionClock

    init(model: AppModel) {
        self.model = model
        self.clock = model.clock
    }

    var body: some View {
        Image(nsImage: model.statusImage)
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

    /// Opens the panel shortly after launch.
    ///
    /// SwiftUI builds the status item asynchronously as the scene comes up, so
    /// at `applicationDidFinishLaunching` there is usually nothing to click yet.
    /// Retry briefly rather than guessing a delay, and give up quietly — a
    /// missing welcome is a far smaller problem than a click landing later on a
    /// panel the user has already opened themselves.
    static func present(retries: Int = 25) {
        if let button = statusItemButton {
            // Load-bearing, not belt-and-braces: without it the panel opens and
            // then closes a few seconds later as focus drifts back to whatever
            // was frontmost, because the panel dismisses when the app stops
            // being active. Measured, not assumed.
            NSApp.activate(ignoringOtherApps: true)
            button.performClick(nil)
            return
        }
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainActor.assumeIsolated { present(retries: retries - 1) }
        }
    }

    // MARK: Right-click menu

    private static var rightClickMonitor: Any?

    /// Makes right-clicking the menu bar item show a small menu, so the app can
    /// be quit without opening the panel first.
    ///
    /// `MenuBarExtra` owns the status item's target and action and exposes no
    /// hook for a secondary click, and giving the item an `NSMenu` outright
    /// would hijack the left click too — the panel would stop opening. So watch
    /// for right-clicks landing in the status bar window and handle them before
    /// SwiftUI sees them.
    ///
    /// Unlike `present()`, this needs no retry: the monitor looks the button up
    /// when an event arrives, by which point the status item certainly exists.
    static func installContextMenu() {
        guard rightClickMonitor == nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Returns a Bool rather than the event itself: `assumeIsolated`
            // requires a Sendable result, and NSEvent is not.
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let button = statusItemButton, event.window === button.window else {
                    return false
                }
                contextMenu().popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: button.bounds.maxY + 5),
                    in: button)
                return true
            }
            // nil consumes the event so SwiftUI never sees it; anything not ours
            // passes through untouched.
            return handled ? nil : event
        }
    }

    /// The right-click menu's contents.
    ///
    /// The item carries no target, so `terminate:` travels the responder chain
    /// to `NSApp` the way a menu item in a normal app's menu bar would.
    static func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Pomodoro Count",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return menu
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
