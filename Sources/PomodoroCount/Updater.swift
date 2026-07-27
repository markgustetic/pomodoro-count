import SwiftUI
import Sparkle

/// Wraps Sparkle so the rest of the app doesn't have to know about it.
///
/// The updater only runs from a properly built, configured app bundle. Running
/// from source (`swift run`) or rendering a preview has no bundle keys and no
/// business phoning home, so `isSupported` is false there and the UI hides the
/// controls rather than offering something that can't work.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

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

    private init() {
        controller = (Self.isConfigured && !PreviewOverrides.isRendering)
            ? SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? true
    }

    /// Sparkle needs both a feed to read and a public key to verify what it
    /// downloads. Without the key it would refuse every update anyway, so the
    /// app hides the controls — better no button than one that always fails.
    private static var isConfigured: Bool {
        guard let info = Bundle.main.infoDictionary,
              let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return false }
        return true
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
