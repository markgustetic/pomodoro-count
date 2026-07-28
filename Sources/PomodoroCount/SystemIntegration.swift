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

// MARK: - Daily rollover

@MainActor
extension AppModel {

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
}
