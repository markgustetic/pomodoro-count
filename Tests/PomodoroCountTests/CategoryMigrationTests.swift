import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryMigrationTests {

    /// Every pomodoro logged before this feature existed belongs to the bucket.
    @Test func oldRecordsDecodeWithNoCategory() throws {
        let url = try storeURL(containing: """
        {"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
        "at":"2026-07-01T10:00:00Z","source":"manual"}],"settings":{}}
        """)
        let m = AppModel(storeURL: url)
        #expect(m.totalCount == 1)
        #expect(m.records.first?.category == nil)
    }

    @Test func categoriesSurviveTheRoundTrip() {
        let (m, url) = makeModel()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        #expect(AppModel(storeURL: url).records.first?.category == "Work")
    }

    @Test func aNilCategoryStaysNilThroughTheRoundTrip() {
        let (m, url) = makeModel()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(AppModel(storeURL: url).records.first?.category == nil)
    }

    /// The optional field must not force a schema bump.
    @Test func schemaVersionIsUnchanged() {
        #expect(AppModel.currentSchemaVersion == 1)
    }
}
