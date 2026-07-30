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

    func notify(_ title: String, _ body: String) {
        // `isBundled`: UNUserNotificationCenter needs a real bundle.
        // `isRendering`: a `--preview` run drives a real session to completion,
        // and taking a screenshot must not post a banner or raise the
        // authorization prompt. `Updater` guards its network call the same way.
        guard isBundled, !PreviewOverrides.isRendering else { return }
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
