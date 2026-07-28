import AppKit
import SwiftUI

/// Debug-only: hosts the panel's UI in an ordinary window (`--reorder-window`).
///
/// Synthetic mouse events cannot drive the menu bar panel's drag gesture — the
/// UI test target documents this — so the drag's behaviour there can only be
/// watched by hand. This window exists to let an automated run reproduce and
/// measure the *dynamics* of a drag that is already in progress: the gesture,
/// layout and animation code is identical, only the window differs.
///
/// It must not be used to claim a reorder *mechanism* works in the real panel:
/// an ordinary key window is permissive in exactly the way that made two
/// AppKit-drag mechanisms look plausible while being dead there. Reproducing a
/// failure here is evidence; reproducing a success is not.
@MainActor
enum ReorderHarness {
    private static var delegate: Delegate?

    static func run() {
        let app = NSApplication.shared
        let delegate = Delegate()
        Self.delegate = delegate      // NSApplication does not retain its delegate
        app.delegate = delegate
        app.run()
    }

    private final class Delegate: NSObject, NSApplicationDelegate {
        var window: NSWindow?

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApp.setActivationPolicy(.regular)
            let host = NSHostingController(
                rootView: RootView(initialTab: .settings)
                    .environmentObject(AppModel.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Reorder Harness"
            // Sized and placed by hand: left alone, the hosting controller
            // collapsed the window to 140pt and the category list was laid out
            // below the visible frame — synthetic events aimed at it landed in
            // whatever window sat behind.
            w.setContentSize(NSSize(width: 300, height: 950))
            w.setFrameTopLeftPoint(NSPoint(x: 60, y: (NSScreen.main?.frame.maxY ?? 1400) - 40))
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window = w
        }
    }
}
