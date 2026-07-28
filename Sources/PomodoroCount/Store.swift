import Foundation

// MARK: - Persistence

@MainActor
extension AppModel {

    /// Bumped only for changes an older build could not read correctly. Additive
    /// fields don't need it — `Settings` decodes field-by-field with defaults.
    nonisolated static let currentSchemaVersion = 1

    /// Internal rather than private so `StoreSeed` can write a store in the
    /// app's own format, instead of a JSON fixture in the test target that
    /// would drift the first time this changed.
    struct Persisted: Codable {
        var schemaVersion: Int
        var records: [Record]
        var settings: Settings

        init(records: [Record], settings: Settings) {
            self.schemaVersion = AppModel.currentSchemaVersion
            self.records = records
            self.settings = settings
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Files written before versioning existed are version 1 by definition.
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            records = try c.decodeIfPresent([Record].self, forKey: .records) ?? []
            settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        }
    }

    var storeURL: URL {
        if let customStoreURL {
            try? FileManager.default.createDirectory(
                at: customStoreURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            return customStoreURL
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PomodoroCount", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("data.json")
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: data) else { return }

        // A newer build wrote this file. We'll read what we understand and then
        // save in our own older format, which would drop whatever we don't — so
        // keep a copy first. Downgrading should never cost anyone their history.
        if persisted.schemaVersion > Self.currentSchemaVersion {
            let backup = storeURL.deletingLastPathComponent()
                .appendingPathComponent("data-v\(persisted.schemaVersion)-backup.json")
            try? data.write(to: backup, options: .atomic)
            NSLog("data.json is schema v\(persisted.schemaVersion); backed up to \(backup.lastPathComponent)")
        }

        records = persisted.records
        settings = persisted.settings
    }

    /// Holds off the store write that each change to `records` or `settings`
    /// would otherwise trigger, until `resumeSaves()`.
    ///
    /// For a burst of related changes where only the end state matters. A drag
    /// reorder is the case this exists for: it moves the array every time the
    /// pointer crosses a row, and each move would otherwise encode the whole
    /// store and write it to disk synchronously, on the main actor, in the
    /// middle of a gesture — which the user could see.
    ///
    /// Idempotent, and safe to leave balanced by more than one `resumeSaves()`:
    /// the caller here resumes both when the drag ends and when it is cancelled,
    /// because a suspend that never resumed would silently stop persisting
    /// everything.
    func suspendSaves() {
        savesSuspended = true
    }

    /// Resumes writing, and performs the write that was held off, if any.
    func resumeSaves() {
        savesSuspended = false
        guard savePending else { return }
        savePending = false
        save()
    }

    func save() {
        guard !isLoading else { return }
        guard !savesSuspended else { savePending = true; return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(Persisted(records: records, settings: settings)) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
