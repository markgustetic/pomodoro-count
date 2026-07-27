import SwiftUI
import Sparkle

/// Wraps Sparkle so the rest of the app doesn't have to know about it.
///
/// The updater only runs from a properly built, configured app bundle. Running
/// from source (`swift run`) or rendering a preview has no bundle keys and no
/// business phoning home, so `isSupported` is false there and the UI hides the
/// controls rather than offering something that can't work.
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// Mirrors Sparkle's own setting so SwiftUI can bind to it.
    @Published var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    /// Whether to show the updater controls at all.
    ///
    /// Deliberately not `controller != nil`: a preview render should draw the
    /// real UI without starting an updater that would reach the network, so the
    /// two questions are kept apart.
    var isSupported: Bool { Self.isConfigured }

    private override init() {
        checksAutomatically = true
        super.init()

        guard Self.isConfigured, !PreviewOverrides.isRendering else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? true
    }

    // MARK: SPUStandardUserDriverDelegate

    /// This app has no Dock icon and is never the active application, so
    /// Sparkle's windows would otherwise open behind whatever the user is
    /// working in — an update prompt nobody sees is an update nobody installs.
    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: true) }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: true) }
    }

    private static var isConfigured: Bool { isConfigured(Bundle.main.infoDictionary) }

    /// Sparkle needs both a feed to read and a public key to verify what it
    /// downloads. Without the key it would refuse every update anyway, so the
    /// app hides the controls — better no button than one that always fails.
    static func isConfigured(_ info: [String: Any]?) -> Bool {
        guard let info,
              let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return false }
        return true
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
