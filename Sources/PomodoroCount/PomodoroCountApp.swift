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
