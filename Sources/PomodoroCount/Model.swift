import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import Carbon.HIToolbox

// MARK: - Data types

/// A single completed pomodoro. `source` is "timer" (finished in-app) or
/// "manual" (logged from external hardware — the whole point of this app).
struct Record: Codable, Identifiable {
    var id = UUID()
    var at: Date
    var source: String
    /// The category NAME, or nil for the fallback bucket. Optional so that
    /// Swift's synthesized decoder treats it as decodeIfPresent and every
    /// existing data.json still loads.
    var category: String?
}

/// A global hotkey combination. Modifiers are stored as Carbon masks (as
/// `RegisterEventHotKey` wants); `label` is the human-readable key captured
/// when it was recorded (e.g. "P", "Space", "⏎").
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String

    static let `default` = Shortcut(
        keyCode: 35,   // ANSI 'P'
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        label: "P")

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + label
    }

    /// `display` in words. VoiceOver reads the modifier symbols inconsistently
    /// or not at all, so "⌃⌥⌘P" needs spelling out.
    var spokenDisplay: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("control") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("option") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("shift") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("command") }
        parts.append(label)
        return parts.joined(separator: " ")
    }
}

/// Which colour palette the UI uses.
enum ThemeChoice: String, Codable, CaseIterable {
    case classic = "Classic"
    case synthwave = "Synthwave"

    var palette: Palette { self == .synthwave ? .synthwave : .classic }
}

struct Settings: Codable {
    var workMinutes = 50
    var breakMinutes = 10
    var autoStartBreak = true
    var soundEnabled = true
    var globalShortcutEnabled = true
    var shortcut = Shortcut.default
    var theme: ThemeChoice = .classic
    /// When off, the menu bar item is just the icon while idle. The countdown
    /// still appears during a session — that's when the width earns its place.
    var showsCountInMenuBar = true

    // MARK: Categories (all opt-in; defaults reproduce today's behaviour exactly)

    /// The whole feature is off until the user turns it on.
    var categoriesEnabled = false
    /// The user's categories, in display order.
    var categories: [Category] = []
    /// The always-present bucket that catches untapped pomodoros.
    var usesFallbackBucket = true
    var fallbackName = "General"
    var fallbackGoal = 0
    /// Destination for untapped pomodoros when the bucket is switched off.
    var defaultCategoryName: String?
    /// Remembered target for the built-in timer. nil means the bucket.
    var sessionTargetName: String?

    init() {}

    // Decode field-by-field so a data.json written by an older version (missing
    // newer keys) still loads and keeps its records instead of failing to decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workMinutes           = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 50
        breakMinutes          = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 10
        autoStartBreak        = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? true
        soundEnabled          = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        globalShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true
        shortcut              = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .default
        theme                 = try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? .classic
        showsCountInMenuBar   = try c.decodeIfPresent(Bool.self, forKey: .showsCountInMenuBar) ?? true
        categoriesEnabled     = try c.decodeIfPresent(Bool.self, forKey: .categoriesEnabled) ?? false
        categories            = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        usesFallbackBucket    = try c.decodeIfPresent(Bool.self, forKey: .usesFallbackBucket) ?? true
        fallbackName          = try c.decodeIfPresent(String.self, forKey: .fallbackName) ?? "General"
        fallbackGoal          = try c.decodeIfPresent(Int.self, forKey: .fallbackGoal) ?? 0
        defaultCategoryName   = try c.decodeIfPresent(String.self, forKey: .defaultCategoryName)
        sessionTargetName     = try c.decodeIfPresent(String.self, forKey: .sessionTargetName)
    }
}

enum Phase: Equatable {
    case idle, work, breakTime
}

/// One day's tally, used by the history view.
struct DayStat: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

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

    private var endDate: Date?
    private var timer: Timer?
    private var hotKey: HotKeyManager?
    private var dayChangeObserver: NSObjectProtocol?
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

    func history(limit: Int = 30) -> [DayStat] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: records) { cal.startOfDay(for: $0.at) }
        return groups
            .map { DayStat(date: $0.key, count: $0.value.count) }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
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
            records.append(Record(at: Date(), source: "timer", category: resolve(.automatic)))
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

    // MARK: Export

    /// The whole history as CSV, one row per pomodoro, oldest first. Lossless,
    /// so a spreadsheet can group it however the reader likes.
    func csvExport() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["timestamp,source"]
        for record in records.sorted(by: { $0.at < $1.at }) {
            lines.append([formatter.string(from: record.at), record.source]
                .map(Self.csvField)
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `source` comes from a file the user can edit by hand, so quote defensively.
    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Suggested filename for an export.
    var csvFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "pomodoro-count-\(formatter.string(from: Date())).csv"
    }

    /// Removes the most recently added record (undo a mis-tap).
    func undoLast() {
        guard let idx = records.indices.max(by: { records[$0].at < records[$1].at }) else { return }
        records.remove(at: idx)
        play(.countDown)
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch-at-login toggle failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    // MARK: Version

    /// Shown in the panel footer so a bug report can name a version. Built app
    /// bundles carry the number from `VERSION`; running from source has no
    /// bundle to read, so it reports "dev".
    var versionString: String { Self.version(from: Bundle.main.infoDictionary) }

    static func version(from info: [String: Any]?) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return "dev" }
        return version
    }

    // MARK: Global keyboard shortcut (⌃⌥⌘P → log a pomodoro)

    /// Tears down any existing hotkey and re-registers it for the current
    /// setting + combo. Called at launch, when toggled, and when re-recorded.
    func syncGlobalShortcut() {
        hotKey = nil   // deinit unregisters the old one
        guard settings.globalShortcutEnabled else { return }
        hotKey = HotKeyManager(
            keyCode: settings.shortcut.keyCode,
            modifiers: settings.shortcut.carbonModifiers
        ) { [weak self] in
            MainActor.assumeIsolated { self?.logExternal(announce: true) }
        }
    }

    func setGlobalShortcut(_ enabled: Bool) {
        settings.globalShortcutEnabled = enabled
        syncGlobalShortcut()
    }

    // MARK: Daily rollover

    /// Today's count is derived from dated records, so it is always 0 at the
    /// start of a new day and older days stay in history. A long-running app,
    /// though, won't recompute on its own — so refresh the UI when the calendar
    /// day changes or the Mac wakes, rolling the visible count back to 0.
    func startDayMonitoring() {
        guard dayChangeObserver == nil else { return }
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)
    }

    func updateShortcut(_ shortcut: Shortcut) {
        settings.shortcut = shortcut
        syncGlobalShortcut()
    }

    // MARK: Notifications & sound

    /// System sounds used for feedback. Verified to exist by the test suite.
    enum Sound: String {
        case countUp = "Pop"        // a pomodoro was added
        case countDown = "Bottle"   // a pomodoro was removed (undo)
        case sessionDone = "Glass"  // a focus session finished
        case breakOver = "Tink"     // a break ended (no count change)
    }

    /// Plays a short feedback sound, unless the user turned sounds off.
    func play(_ sound: Sound) {
        guard settings.soundEnabled else { return }
        NSSound(named: sound.rawValue)?.play()
    }

    private func notify(_ title: String, _ body: String) {
        guard isBundled else { return }   // UNUserNotificationCenter needs a real bundle
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
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

    // MARK: Formatting helpers

    static func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(ceil(t)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The same duration in words, for VoiceOver — "50:00" would otherwise be
    /// read as bare digits.
    static func spokenDuration(_ t: TimeInterval) -> String {
        let total = max(0, Int(ceil(t)))
        let minutes = total / 60, seconds = total % 60
        let m = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        let s = "\(seconds) \(seconds == 1 ? "second" : "seconds")"
        if minutes == 0 { return s }
        if seconds == 0 { return m }
        return "\(m) \(s)"
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return Self.dayFormatter.string(from: date)
    }

    var todayDateString: String { Self.todayFormatter.string(from: Date()) }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var shortDateString: String { Self.shortDateFormatter.string(from: Date()) }
}
