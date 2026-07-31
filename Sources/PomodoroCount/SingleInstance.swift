import AppKit

// MARK: - The launch guard

/// Keeps a second copy of the app from starting alongside the one that is
/// already running.
///
/// This exists because clicking a notification does not talk to the running
/// app. The banner has no idea which process posted it; the click asks Launch
/// Services to open the *bundle identifier*, and Launch Services opens whichever
/// registered copy it prefers. One copy on the machine and that is the running
/// one, so nothing shows. More than one — an installed copy, a `build/` copy,
/// the copies Xcode leaves in DerivedData after a UI test run — and it is a coin
/// toss, which is how a notification click came to start a second app.
///
/// Two instances is worse than untidy: `records` and `settings` save to the same
/// `data.json` on `didSet`, so the two processes take turns overwriting each
/// other's history.
enum SingleInstance {

    /// Posted app-to-app by a copy that is standing down, so the copy that is
    /// staying can show itself. Without it the newcomer would exit silently and
    /// the notification click would look like it did nothing at all.
    static let showPanelNotification = Notification.Name("com.markg.pomodorocount.showPanel")

    /// One running copy of the app, as much of it as the decision needs.
    struct Instance: Equatable {
        let pid: pid_t
        let started: Date
    }

    /// The already-running copy this process should hand its launch to, or nil
    /// to carry on launching.
    ///
    /// `running` arrives from AppKit *including this process*, so excluding `me`
    /// is half the job: a guard that forgot would hand the app off to itself and
    /// it would never start at all.
    ///
    /// The other half is `myStart`. Only a copy that was here *before* this one
    /// counts as "already running" — otherwise two copies launched in the same
    /// moment each see the other, each politely stand down, and the user is left
    /// with no app at all.
    ///
    /// Start time alone does not settle that, because two copies really can
    /// report the same instant, and a copy AppKit gives no launch date for
    /// reports `.distantPast` — which ties with every other such copy. So the
    /// order is `(started, pid)`, which is *total*: of any two copies exactly
    /// one is the elder, both agree which, and neither outcome is "both exit".
    ///
    /// `myStart` is passed rather than looked up in `running` because this runs
    /// before the app has a scene, and a roster that has not caught up with this
    /// process yet must not silently disable the whole guard.
    static func handoff(bundleID: String?,
                        running: [Instance],
                        me: pid_t,
                        myStart: Date) -> pid_t? {
        // No bundle identifier means an unbundled build: `swift run`, or the
        // `.build/debug` binary the drive-panel skill drives. That workflow runs
        // one *alongside* the installed app on purpose, so never block it.
        guard bundleID != nil else { return nil }
        return running
            .filter { $0.pid != me && ($0.started, $0.pid) < (myStart, me) }
            .min { ($0.started, $0.pid) < ($1.started, $1.pid) }?
            .pid
    }
}

// MARK: - Standing down

@MainActor
extension SingleInstance {

    /// Hands this launch to the copy already running, if there is one. Returns
    /// true when it did, in which case the caller must return without starting
    /// the app.
    ///
    /// Nothing is waited for here. An earlier version held this process open for
    /// a couple of seconds to be sure the other copy was staying, and that was a
    /// mistake with a visible symptom: a newcomer still alive is still holding
    /// the activation it took to launch, so the panel it had just asked for lost
    /// key status and dismissed itself a few hundred milliseconds after opening.
    /// Standing down promptly *is* the cooperation. The waiting that does need
    /// doing happens on the other side, in `showPanelOnceAlone`.
    static func handOffIfAlreadyRunning() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier
        let running = bundleID.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        } ?? []

        // `.distantPast` for a missing launch date, never a dropped entry: a copy
        // left out of the roster is a copy this process will happily start
        // beside, so a nil there would silently switch the whole guard off. It
        // reads as "has been here as long as anyone", and the pid in the
        // ordering keeps that from tying.
        let roster = running.map {
            Instance(pid: $0.processIdentifier, started: $0.launchDate ?? .distantPast)
        }
        guard let pid = handoff(bundleID: bundleID,
                                running: roster,
                                me: ProcessInfo.processInfo.processIdentifier,
                                myStart: NSRunningApplication.current.launchDate ?? .distantPast),
              let other = running.first(where: { $0.processIdentifier == pid }),
              // A copy on its way out is no use to hand off to — that is how an
              // update's relaunch could leave the user with no app at all.
              !other.isTerminated
        else { return false }

        other.activate()
        DistributedNotificationCenter.default().postNotificationName(
            showPanelNotification, object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    /// Listens for a newcomer standing down, and shows the panel on its behalf.
    ///
    /// `DistributedNotificationCenter` rather than the URL scheme: a
    /// `pomodorocount://` URL would go back through Launch Services and could be
    /// handed to the very copy we are trying not to start.
    static func startHandoffMonitoring() {
        DistributedNotificationCenter.default().addObserver(
            forName: showPanelNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { showPanelOnceAlone() }
        }
    }

    /// Raises the panel, but not until the copy that stood down has actually
    /// gone.
    ///
    /// The panel dismisses whenever it loses key status, and the newcomer holds
    /// the activation it took to launch until the moment it exits. Presenting
    /// into that window opens the panel and loses it again: measured at
    /// `onAppear` 13:33:24.308, `onDisappear` 13:33:24.694. So wait for the
    /// condition that actually matters — being the only copy left — rather than
    /// for a guessed interval. Usually that is one or two turns.
    ///
    /// The retry cap is a backstop, not a timeout to tune: if some other copy is
    /// somehow here to stay, showing the panel late beats never showing it.
    private static func showPanelOnceAlone(retries: Int = 40) {
        let alone = Bundle.main.bundleIdentifier.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).count <= 1
        } ?? true
        guard !alone, retries > 0 else {
            MenuBarPanel.presentIfClosed()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { showPanelOnceAlone(retries: retries - 1) }
        }
    }
}
