import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct ExportTests {

    @Test func emptyHistoryExportsJustTheHeader() {
        let (m, _) = makeModel()
        #expect(m.csvExport() == "timestamp,source,category\n")
    }

    @Test func oneRowPerPomodoro() {
        let (m, _) = makeModel()
        m.logExternal()
        m.logExternal()
        let lines = m.csvExport().split(separator: "\n")
        #expect(lines.count == 3)          // header + 2
        #expect(lines[0] == "timestamp,source,category")
        #expect(lines.dropFirst().allSatisfy { $0.hasSuffix(",manual,General") })
    }

    @Test func rowsAreOldestFirstRegardlessOfStorageOrder() {
        let (m, _) = makeModel()
        m.records = [
            Record(at: Date(), source: "newest"),
            Record(at: .daysAgo(5), source: "oldest"),
            Record(at: .daysAgo(2), source: "middle"),
        ]
        let sources = m.csvExport().split(separator: "\n").dropFirst()
            .map { $0.split(separator: ",")[1] }
        #expect(sources == ["oldest", "middle", "newest"])
    }

    @Test func timestampsAreISO8601() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(timeIntervalSince1970: 1_800_000_000), source: "manual")]
        let row = m.csvExport().split(separator: "\n")[1]
        let timestamp = String(row.split(separator: ",")[0])
        #expect(ISO8601DateFormatter().date(from: timestamp) != nil)
    }

    /// `source` comes out of a file the user can edit, so a stray comma or quote
    /// must not shift every following column.
    @Test func fieldsNeedingQuotesAreQuoted() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "timer, interrupted")]
        #expect(m.csvExport().contains("\"timer, interrupted\""))
    }

    @Test func embeddedQuotesAreDoubled() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "said \"go\"")]
        #expect(m.csvExport().contains("\"said \"\"go\"\"\""))
    }

    @Test func plainFieldsAreNotQuoted() {
        let (m, _) = makeModel()
        m.logExternal()
        #expect(!m.csvExport().contains("\""))
    }

    @Test func exportEndsWithANewline() {
        let (m, _) = makeModel()
        m.logExternal()
        #expect(m.csvExport().hasSuffix("\n"))
    }

    @Test func filenameCarriesTodaysDate() {
        let (m, _) = makeModel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(m.csvFilename == "pomodoro-count-\(formatter.string(from: Date())).csv")
    }

    @Test func rowsCarryTheirCategory() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        #expect(m.csvExport().contains(",manual,Work"))
    }

    /// Bucket pomodoros — including everything logged before categories existed
    /// — read as the bucket's name rather than blank.
    @Test func uncategorisedRowsUseTheFallbackName() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.csvExport().contains(",manual,General"))
    }

    @Test func aRenamedFallbackShowsInTheExport() {
        let (m, _) = makeModel()
        m.settings.fallbackName = "Everything else"
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.csvExport().contains(",manual,Everything else"))
    }

    /// Category names are user-entered, so a comma must not shift the columns.
    @Test func aCategoryNameWithACommaIsQuoted() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual", category: "Work, admin")]
        #expect(m.csvExport().contains("\"Work, admin\""))
    }
}

@MainActor
@Suite struct SchemaVersionTests {

    @Test func savedFilesCarryTheCurrentSchemaVersion() throws {
        let (m, url) = makeModel()
        m.logExternal()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(json?["schemaVersion"] as? Int == AppModel.currentSchemaVersion)
    }

    /// Files written before versioning existed have no field and are version 1.
    @Test func filesWithoutAVersionStillLoad() throws {
        let url = try storeURL(containing: """
        {"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
        "at":"2026-07-01T10:00:00Z","source":"manual"}],"settings":{}}
        """)
        #expect(AppModel(storeURL: url).totalCount == 1)
    }

    /// Opening a file from a newer build must not quietly cost the user data
    /// when this build saves over it in the older format.
    @Test func newerSchemaIsBackedUpBeforeBeingOverwritten() throws {
        let url = try storeURL(containing: """
        {"schemaVersion":99,"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
        "at":"2026-07-01T10:00:00Z","source":"manual"}],"settings":{},\
        "somethingFromTheFuture":{"a":1}}
        """)
        let m = AppModel(storeURL: url)
        #expect(m.totalCount == 1)   // reads what it understands

        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("data-v99-backup.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))

        let preserved = try String(contentsOf: backup, encoding: .utf8)
        #expect(preserved.contains("somethingFromTheFuture"),
                "the backup must be the original bytes, not a re-encode")
    }

    @Test func sameOrOlderSchemaIsNotBackedUp() throws {
        let url = try storeURL(containing: """
        {"schemaVersion":1,"records":[],"settings":{}}
        """)
        _ = AppModel(storeURL: url)
        let dir = url.deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!files.contains { $0.contains("backup") })
    }
}
