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

    /// Whether a failed read means "there is no file", as opposed to "there is
    /// one and it could not be read". Only the first is a new install.
    ///
    /// Both spellings, because which one arrives depends on the call:
    /// `Data(contentsOf:)` reports a Cocoa error, and the POSIX one is what
    /// sits underneath it and what lower-level calls surface directly.
    nonisolated static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError
        case NSPOSIXErrorDomain:
            return error.code == Int(ENOENT)
        default:
            return false
        }
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        let data: Data
        do {
            data = try Data(contentsOf: storeURL)
        } catch {
            // No file is a new install, and the one quiet way out of here.
            guard !Self.isMissingFile(error) else { return }
            // Anything else means there is a file and this process has not
            // seen inside it — permissions, an I/O error. This used to read as
            // "no file" too, via `try?`, and the next save then replaced
            // history nobody had loaded. A rename needs no read access, so
            // move it out of the way of that save; if even that fails the
            // rescue stays owed, and `save()` will not write until it is paid.
            NSLog("data.json exists but could not be read: \(error)")
            unreadStoreNeedsRescue = !setAsideUnreadStore()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: data) else {
            // Starting empty is the easy half of surviving a corrupt file. The
            // hard half: the very next save re-encodes that empty state over
            // data.json, erasing the only copy of the user's history. Keep the
            // unreadable bytes first, exactly as the newer-schema path below
            // does — a decode failure must never cost anyone their data.
            // Timestamped so a later, unrelated corruption cannot overwrite
            // the evidence of this one.
            let backup = storeURL.deletingLastPathComponent()
                .appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970))-backup.json")
            try? data.write(to: backup, options: .atomic)
            NSLog("data.json failed to decode; original bytes kept in \(backup.lastPathComponent)")
            return
        }

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

        // A task added yesterday must not show today, and launch is not the
        // only way a model is built — tests, `--preview` and the reorder
        // harness never see a day change. `isLoading` is still true here, so
        // this triggers no save; the next real change writes the swept list.
        expireTasks()
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
    /// Bursts nest, so this counts depth rather than setting a flag, and only
    /// the outermost `resumeSaves()` writes. The three call sites are the drag
    /// reorder above and `complete()`/`logExternal()`, which bracket a record
    /// append with the target advance it may trigger — and the app's headline
    /// input paths (the global hotkey, the `pomodorocount://log` URL scheme)
    /// fire either of those two in the middle of a drag. A flag let that inner
    /// resume end the drag's suspension early, leaving every row crossing after
    /// it to encode the whole store and write it synchronously again.
    ///
    /// Not idempotent any more, then: each `suspendSaves()` needs its own
    /// `resumeSaves()`. A spare resume is still harmless — the drag resumes both
    /// when it ends and when it is cancelled, and `resumeSaves()` clamps at zero
    /// so the extra one does nothing. The opposite direction is the dangerous
    /// one: a suspend that never resumes silently stops the app persisting
    /// anything, and unlike the flag a count cannot heal itself (one resume used
    /// to clear a leak of any size). Only the drag can leak — the other two
    /// bracket straight-line synchronous code — so it resumes on its view going
    /// away mid-gesture as well.
    func suspendSaves() {
        suspendDepth += 1
    }

    /// Resumes writing, and performs the write that was held off, if any — once
    /// the outermost burst has ended.
    func resumeSaves() {
        // Clamped, so an extra resume stays harmless (see `suspendSaves()`): if
        // this went negative, the next `suspendSaves()` would only bring it back
        // to zero and quietly suspend nothing at all.
        suspendDepth = max(0, suspendDepth - 1)
        guard !savesSuspended else { return }
        guard savePending else { return }
        savePending = false
        save()
    }

    /// Moves a store this process could not read out of the path of the next
    /// save, keeping it beside the store under the same name a file that would
    /// not decode gets. Returns false while the file is still in the way.
    ///
    /// A file that has gone in the meantime counts as done: there is nothing
    /// left to protect, and treating it as a failure would stop the app saving
    /// for good.
    private func setAsideUnreadStore() -> Bool {
        let backup = storeURL.deletingLastPathComponent()
            .appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970))-backup.json")
        do {
            try FileManager.default.moveItem(at: storeURL, to: backup)
            NSLog("data.json set aside unread as \(backup.lastPathComponent)")
            return true
        } catch {
            if Self.isMissingFile(error) { return true }
            NSLog("data.json could not be set aside, so nothing will be saved over it: \(error)")
            return false
        }
    }

    func save() {
        guard !isLoading else { return }
        guard !savesSuspended else { savePending = true; return }
        // An unread store is still sitting at `storeURL`. Try the rescue again
        // — whatever blocked it at launch may have cleared — and write nothing
        // until it succeeds: losing this session's changes is the cheaper of
        // the two losses on offer.
        if unreadStoreNeedsRescue {
            guard setAsideUnreadStore() else { return }
            unreadStoreNeedsRescue = false
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(Persisted(records: records, settings: settings)) else { return }
        do {
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Said out loud rather than swallowed: a store that has stopped
            // saving looks exactly like one that is saving until the next
            // launch comes up short, and the log is the only witness.
            NSLog("data.json could not be saved: \(error)")
        }
    }
}
