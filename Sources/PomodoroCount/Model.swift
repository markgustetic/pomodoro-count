import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import Carbon.HIToolbox

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    /// Shared instance used by the running app (so the AppDelegate and the
    /// global hotkey can reach the same model the UI observes).
    static let shared = AppModel()

    /// Set once at startup (via `--store`) to redirect persistence for testing.
    nonisolated(unsafe) static var overrideStoreURL: URL?

    @Published var records: [Record] = [] { didSet { save() } }
    @Published var settings = Settings() { didSet { save() } }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0

    /// Which category a finished focus session credits. Persisted so it survives
    /// relaunch — re-picking it every day would be a papercut.
    var sessionTarget: CategoryTarget {
        get {
            guard let name = settings.sessionTargetName, categoryExists(name) else {
                return .automatic
            }
            return .named(name)
        }
        set {
            switch newValue {
            case .named(let name): settings.sessionTargetName = name
            case .fallback, .automatic: settings.sessionTargetName = nil
            }
        }
    }

    /// Drives the timer to completion immediately. Tests only — a real session
    /// takes 50 minutes.
    func forceCompleteForTesting() {
        remaining = 0
        complete()
    }

    private var endDate: Date?
    private var timer: Timer?
    var hotKey: HotKeyManager?
    var dayChangeObserver: NSObjectProtocol?
    private let customStoreURL: URL?

    /// `storeURL` overrides the on-disk location (used by tests so they never
    /// touch the user's real data). Defaults to Application Support.
    init(storeURL: URL? = nil) {
        self.customStoreURL = storeURL ?? Self.overrideStoreURL
        // Checked before load(), which creates the containing directory.
        isFirstLaunch = !FileManager.default.fileExists(atPath: self.storeURL.path)
        load()
    }

    /// True when no data file exists yet, i.e. a brand-new install. Used once, to
    /// open the panel so launching the app does something visible.
    private(set) var isFirstLaunch = false

    /// Writes the store even though nothing has changed, so the next launch is
    /// not also a first launch. Without this the welcome would repeat until the
    /// user happened to log a pomodoro or change a setting.
    func markLaunched() {
        isFirstLaunch = false
        save()
    }

    // MARK: Derived values

    var todayCount: Int {
        records.filter { Calendar.current.isDateInToday($0.at) }.count
    }

    var weekCount: Int {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) else { return 0 }
        return records.filter { $0.at >= start }.count
    }

    var totalCount: Int { records.count }

    /// Time shown on the big timer. When idle, previews the configured focus length.
    var displayRemaining: TimeInterval {
        phase == .idle ? TimeInterval(settings.workMinutes * 60) : remaining
    }

    var primaryTitle: String {
        if isRunning { return "Pause" }
        switch phase {
        case .idle: return "Start focus"
        case .work, .breakTime: return "Resume"
        }
    }

    /// Days within the last `days` days (ending today) that have at least one
    /// record, newest first. Powers the History tab's day list, so the
    /// Week/Month control governs it the same way it governs `dailySeries` and
    /// `categoryTotals`. Unlike `dailySeries`, empty days are not padded in —
    /// the day list has always shown only days you actually logged something.
    func history(days: Int) -> [DayStat] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date()))!
        let groups = Dictionary(grouping: records.filter { $0.at >= cutoff }) { cal.startOfDay(for: $0.at) }
        return groups
            .map { DayStat(date: $0.key, count: $0.value.count) }
            .sorted { $0.date > $1.date }
    }

    /// Text shown next to the icon in the menu bar (count when idle, else clock).
    /// Empty means icon-only — see `Settings.showsCountInMenuBar`. The count is
    /// still announced to VoiceOver either way; this hides it visually only.
    var statusText: String {
        switch phase {
        case .idle:             return settings.showsCountInMenuBar ? "\(todayCount)" : ""
        case .work, .breakTime: return Self.mmss(remaining)
        }
    }

    /// The full menu bar item: custom icon + text, rendered as one template image.
    var statusImage: NSImage {
        StatusIcon.render(phase: phase, running: isRunning, text: statusText,
                          description: statusDescription)
    }

    /// What VoiceOver announces for the menu bar item.
    var statusDescription: String {
        switch phase {
        case .idle:
            return "Pomodoro Count: \(todayCount) \(todayCount == 1 ? "pomodoro" : "pomodoros") today"
        case .work:
            return "Focus\(isRunning ? "" : ", paused"): \(Self.spokenDuration(remaining)) remaining"
        case .breakTime:
            return "Break\(isRunning ? "" : ", paused"): \(Self.spokenDuration(remaining)) remaining"
        }
    }

    /// Exactly `days` consecutive days ending today, zero-filled, oldest first —
    /// for the weekly / monthly bar chart.
    func dailySeries(days: Int) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let counts = Dictionary(grouping: records) { cal.startOfDay(for: $0.at) }
            .mapValues { $0.count }
        return (0..<days).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayStat(date: d, count: counts[d] ?? 0)
        }
    }

    // MARK: Timer control

    func toggle() {
        if isRunning {
            pause()
        } else if phase == .idle {
            startWork()
        } else {
            resume()
        }
    }

    func startWork() {
        phase = .work
        remaining = TimeInterval(settings.workMinutes * 60)
        beginCountdown()
    }

    func startBreak() {
        phase = .breakTime
        remaining = TimeInterval(settings.breakMinutes * 60)
        beginCountdown()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        stopTimer()
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
        endDate = nil
    }

    func resume() {
        guard !isRunning, phase != .idle else { return }
        beginCountdown()
    }

    func reset() {
        stopTimer()
        isRunning = false
        phase = .idle
        endDate = nil
        remaining = 0
    }

    private func beginCountdown() {
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        stopTimer()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let endDate else { return }
        remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            remaining = 0
            complete()
        }
    }

    private func complete() {
        stopTimer()
        isRunning = false
        let finished = phase
        endDate = nil

        if finished == .work {
            records.append(Record(at: Date(), source: "timer",
                                  category: resolve(sessionTarget)))
            play(.sessionDone)
            notify("Pomodoro complete", "Nice — that's \(todayCount) today.")
            if settings.autoStartBreak {
                startBreak()
            } else {
                phase = .idle
            }
        } else {
            play(.breakOver)
            notify("Break over", "Ready for the next one?")
            phase = .idle
        }
    }

    // MARK: External / manual logging (the headline feature)

    /// Records a pomodoro completed outside the app, e.g. on a physical timer.
    /// `announce` (used by the global hotkey) also posts a confirmation banner,
    /// since the panel may not be open to show the count change.
    func logExternal(to target: CategoryTarget = .automatic, announce: Bool = false) {
        records.append(Record(at: Date(), source: "manual", category: resolve(target)))
        play(.countUp)
        if announce {
            notify("Pomodoro logged", "That's \(todayCount) today.")
        }
    }

    /// Removes the most recently added record (undo a mis-tap).
    func undoLast() {
        guard let idx = records.indices.max(by: { records[$0].at < records[$1].at }) else { return }
        records.remove(at: idx)
        play(.countDown)
    }

    // MARK: Persistence

    /// Bumped only for changes an older build could not read correctly. Additive
    /// fields don't need it — `Settings` decodes field-by-field with defaults.
    nonisolated static let currentSchemaVersion = 1

    private struct Persisted: Codable {
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

    private var storeURL: URL {
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

    private var isLoading = false

    private func load() {
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

    private func save() {
        guard !isLoading else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(Persisted(records: records, settings: settings)) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

}
