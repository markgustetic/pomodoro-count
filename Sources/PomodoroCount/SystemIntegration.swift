import AppKit
import ServiceManagement

// MARK: - Launch at login

@MainActor
extension AppModel {

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
}

// MARK: - Version

@MainActor
extension AppModel {

    /// Shown in the panel footer so a bug report can name a version. Built app
    /// bundles carry the number from `VERSION`; running from source has no
    /// bundle to read, so it reports "dev".
    var versionString: String { Self.version(from: Bundle.main.infoDictionary) }

    static func version(from info: [String: Any]?) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return "dev" }
        return version
    }
}

// MARK: - Global keyboard shortcut (⌃⌥⌘P → log a pomodoro)

@MainActor
extension AppModel {

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
}

// MARK: - URL commands (the hardware door)

/// What a `pomodorocount://` URL asks for. Logging from a Stream Deck button,
/// a Shortcuts automation, or a shell script is the app's whole reason to
/// exist; the URL is how they knock:
///
///     open "pomodorocount://log"
///     open "pomodorocount://log?category=Deep%20Work"
enum URLCommand: Equatable {
    case log(category: String?)

    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "pomodorocount",
              url.host?.lowercased() == "log" else { return nil }
        let category = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "category" }?.value
        return .log(category: category)
    }
}

@MainActor
extension AppModel {

    /// Carries out a `pomodorocount://` URL. A URL may not invent categories
    /// or attach names the list doesn't hold — an unknown name logs to the
    /// bucket, never a new label — and it announces, because the sender is by
    /// definition not looking at the panel.
    func handle(_ url: URL) {
        guard let command = URLCommand.parse(url) else { return }
        switch command {
        case .log(let name):
            let target: CategoryTarget =
                name.flatMap { categoryExists($0) ? .named($0) : nil } ?? .fallback
            logExternal(to: target, announce: true)
        }
    }
}

// MARK: - End-of-day nudge

@MainActor
extension AppModel {

    /// What the nudge would say right now, or nil for silence. With goals,
    /// silence once they're met; without goals there is still a day worth not
    /// losing, so an empty day nudges and a logged one doesn't.
    func nudgeMessage() -> String? {
        let goal = todayGoalTotal
        if goal > 0 {
            let left = goal - todayCount
            guard left > 0 else { return nil }
            return "\(left) to go to hit today's goal."
        }
        guard todayCount == 0 else { return nil }
        return "No pomodoros logged today."
    }

    /// The next time an `hour`-o'clock nudge should fire: later today if the
    /// hour is still ahead, otherwise tomorrow.
    static func nextNudgeDate(hour: Int, after now: Date,
                              calendar: Calendar = .current) -> Date {
        let todayAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
        if todayAt > now { return todayAt }
        return calendar.date(byAdding: .day, value: 1, to: todayAt)!
    }

    func setNudgeHour(_ hour: Int?) {
        settings.nudgeHour = hour
        scheduleNudge()
    }

    /// Arms the nudge and keeps it honest against a moving clock: a timezone
    /// or system-clock change re-derives the fire date, so "at 18:00" keeps
    /// meaning the user's local 18:00 rather than the one they left behind.
    func startNudgeMonitoring() {
        scheduleNudge()
        guard clockChangeObserver == nil else { return }
        let rearm: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleNudge() }
        }
        clockChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: rearm)
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: rearm)
    }

    /// (Re)arms the one-shot timer for the next nudge. The app runs for weeks,
    /// so each firing checks the goal *at that moment* and then arms the next
    /// day's — scheduling the message text in advance would bake in a count
    /// that the evening's pomodoros should have changed.
    func scheduleNudge() {
        nudgeTimer?.invalidate()
        nudgeTimer = nil
        guard let hour = settings.nudgeHour else { return }
        let t = Timer(fire: Self.nextNudgeDate(hour: hour, after: Date()),
                      interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let message = self.nudgeMessage() {
                    self.notify("Pomodoro Count", message)
                }
                self.scheduleNudge()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        nudgeTimer = t
    }
}

// MARK: - Screen lock

@MainActor
extension AppModel {

    /// Pauses a running session, if the user asked for that.
    ///
    /// Off by default — see `Settings.pausesOnScreenLock`. The guard lives here
    /// rather than in `startScreenLockMonitoring()` so the observers stay
    /// registered whatever the setting says: flipping the toggle then takes
    /// effect on the very next lock, with no teardown, and the "a second call
    /// can never mean a second pause per lock" guard over there is left alone.
    ///
    /// Deliberately no auto-resume on unlock — only the user knows whether the
    /// time away should count, and `pause()` already preserves what's on the
    /// clock.
    func handleScreenLocked() {
        guard settings.pausesOnScreenLock, isRunning else { return }
        pause()
    }

    /// Watches for the screen locking or the displays sleeping — the two ways
    /// a Mac goes unattended with the app still running. Distributed rather
    /// than workspace notifications for the lock itself: AppKit offers no
    /// public equivalent. Guarded like `startDayMonitoring`, so a second call
    /// can never mean a second pause per lock.
    func startScreenLockMonitoring() {
        guard screenLockObserver == nil else { return }
        let onLock: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleScreenLocked() }
        }
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main, using: onLock)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main, using: onLock)
    }
}

// MARK: - Daily rollover

@MainActor
extension AppModel {

    /// Everything the app does when it notices what day it is: from the two
    /// notifications below, and once at launch.
    ///
    /// Only the phase reset is gated on the day actually advancing.
    /// `realignTarget()` carries its own `targetAimedOn` stamp, and the
    /// repaint is the whole point of the wake notification — it is what makes
    /// a Mac opened after midnight show today's count rather than the one from
    /// before the lid shut.
    ///
    /// `>` rather than `!=` so a system-clock or timezone change that moves
    /// the date backwards doesn't read as a rollover.
    ///
    /// `now` is injectable so tests can advance the day without touching the
    /// system clock.
    func handleDayChange(now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        if day > lastSeenDay {
            lastSeenDay = day
            switch DayRollover.action(phase: phase,
                                      breakEnteredOn: breakEnteredOn,
                                      newDay: day) {
            case .resetToIdle: resetForNewDay()
            case .restartCycle: restartLongBreakCycle()
            case .none: break
            }
        }
        realignTarget()
        objectWillChange.send()
    }

    /// Today's count is derived from dated records, so it is always 0 at the
    /// start of a new day and older days stay in history. A long-running app,
    /// though, won't recompute on its own — so refresh the UI when the calendar
    /// day changes or the Mac wakes, rolling the visible count back to 0. A new
    /// day also ends a break that outlived it: see `handleDayChange`.
    func startDayMonitoring() {
        guard dayChangeObserver == nil else { return }
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDayChange() }
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
}
