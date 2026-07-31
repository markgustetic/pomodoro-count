import AppKit
import UserNotifications

// MARK: - Notifications & sound

@MainActor
extension AppModel {

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

    /// Whether this process may touch the notification centre at all.
    ///
    /// `isBundled`: UNUserNotificationCenter needs a real bundle.
    /// `isRendering`: a `--preview` run drives a real session to completion, and
    /// taking a screenshot must neither post a banner, raise the authorization
    /// prompt, nor reach into the real user's Notification Center and clear it.
    /// `Updater` guards its network call the same way.
    private var canUseNotificationCenter: Bool {
        isBundled && !PreviewOverrides.isRendering
    }

    /// Clears every banner and Notification Center entry this app has posted.
    ///
    /// Called when the panel opens, because the panel *is* the answer to
    /// whatever the banner was announcing — the new count, the armed break, the
    /// goal still to go. Leaving it up behind the panel only makes the user
    /// dismiss the same news a second time.
    func clearNotifications() {
        guard canUseNotificationCenter else { return }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func notify(_ title: String, _ body: String) {
        guard canUseNotificationCenter else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }
}
