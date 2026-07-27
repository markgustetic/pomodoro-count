import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct VersionTests {

    @Test func readsTheVersionFromABundleInfoDictionary() {
        #expect(AppModel.version(from: ["CFBundleShortVersionString": "1.2.3"]) == "1.2.3")
    }

    /// Running from source (`swift run`) has no bundle to read.
    @Test func reportsDevWithoutABundle() {
        #expect(AppModel.version(from: nil) == "dev")
    }

    @Test(arguments: [[:], ["CFBundleShortVersionString": ""], ["CFBundleShortVersionString": 1.0]] as [[String: Any]])
    func fallsBackToDevOnUnusableInfo(info: [String: Any]) {
        #expect(AppModel.version(from: info) == "dev")
    }

    /// The VERSION file drives the bundle version and the release tag, so it has
    /// to stay a plain semver string.
    @Test func versionFileIsSemver() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PomodoroCountTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let version = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3, "VERSION must be MAJOR.MINOR.PATCH, got '\(version)'")
        #expect(parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) },
                "VERSION components must all be numeric, got '\(version)'")
    }
}
