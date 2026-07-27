import Testing
import Foundation
@testable import PomodoroCount

/// The updater refuses to run half-configured. Sparkle replaces the app binary
/// on disk, so shipping it without the key that verifies downloads would be
/// worse than shipping no updater at all.
@MainActor
@Suite struct UpdaterTests {

    private static let feed = "https://example.com/appcast.xml"
    private static let key = "Qq7XPmEKCxAvWMU3NSidZ65/+3tHL/p9nzQ0PfmWF0Q="

    @Test func bothFeedAndKeyMeansConfigured() {
        #expect(Updater.isConfigured(["SUFeedURL": Self.feed, "SUPublicEDKey": Self.key]))
    }

    /// Running from source has no bundle at all.
    @Test func noBundleMeansNotConfigured() {
        #expect(!Updater.isConfigured(nil))
        #expect(!Updater.isConfigured([:]))
    }

    @Test func aFeedWithoutAKeyIsNotEnough() {
        #expect(!Updater.isConfigured(["SUFeedURL": Self.feed]))
    }

    @Test func aKeyWithoutAFeedIsNotEnough() {
        #expect(!Updater.isConfigured(["SUPublicEDKey": Self.key]))
    }

    /// build-app.sh omits the keys entirely when unset, but an empty string is
    /// what a misconfigured CI variable produces.
    @Test(arguments: [["SUFeedURL": "", "SUPublicEDKey": Self.key],
                      ["SUFeedURL": Self.feed, "SUPublicEDKey": ""],
                      ["SUFeedURL": "", "SUPublicEDKey": ""]])
    func emptyValuesCountAsMissing(info: [String: String]) {
        #expect(!Updater.isConfigured(info))
    }

    @Test func wrongTypesDoNotCrashOrPass() {
        #expect(!Updater.isConfigured(["SUFeedURL": 42, "SUPublicEDKey": Self.key]))
    }
}
