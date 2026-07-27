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

    var isSupported: Bool { controller != nil }

    private init() {
        controller = Self.isConfigured
            ? SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    /// Sparkle needs both a feed to read and a public key to verify what it
    /// downloads. Without the key it would refuse the update anyway, so don't
    /// start it — better no button than a button that always fails.
    private static var isConfigured: Bool {
        guard !PreviewOverrides.isRendering,
              let info = Bundle.main.infoDictionary,
              let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return false }
        return true
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
