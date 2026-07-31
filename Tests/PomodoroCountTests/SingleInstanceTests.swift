import Testing
import Foundation
@testable import PomodoroCount

/// The launch guard that keeps a second copy of the app from starting.
///
/// Clicking a notification asks Launch Services to open the app by bundle ID.
/// On a machine with more than one copy registered under that ID — an installed
/// one, a `build/` one, the copies Xcode leaves in DerivedData after a UI test
/// run — it opens whichever it prefers, which is not necessarily the copy
/// already running. The result is two menu bar icons and two processes writing
/// the same `data.json` on every `didSet`, so this guard is about history as
/// much as it is about tidiness.
@Suite struct SingleInstanceTests {

    private let id = "com.markg.pomodorocount"
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func running(_ entries: (pid_t, TimeInterval)...) -> [SingleInstance.Instance] {
        entries.map { .init(pid: $0.0, started: noon.addingTimeInterval($0.1)) }
    }

    // MARK: Handing off

    @Test func handsOffToTheCopyAlreadyRunning() {
        let roster = running((101, -60), (202, 0))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon) == 101)
    }

    @Test func staysWhenItIsTheOnlyCopyRunning() {
        let roster = running((202, 0))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon) == nil)
    }

    @Test func staysWhenLaunchServicesReportsNobodyAtAll() {
        #expect(SingleInstance.handoff(bundleID: id, running: [],
                                       me: 202, myStart: noon) == nil)
    }

    /// The roster comes back from AppKit including this process, so a guard that
    /// forgot to exclude itself would hand the app off to itself and exit — it
    /// would never start at all. The start times alone would not catch this:
    /// this process is never older than itself, but it is never younger either.
    @Test func neverHandsOffToItself() {
        let roster = running((202, 0))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon) != 202)
    }

    /// An unbundled build — `swift run`, and the `.build/debug` binary the
    /// drive-panel skill drives — has no bundle identifier. The whole headless
    /// verification workflow depends on running one of those *alongside* the
    /// installed app, so an unbundled process must never hand itself off.
    @Test func anUnbundledBuildNeverDefers() {
        let roster = running((101, -60), (202, 0))
        #expect(SingleInstance.handoff(bundleID: nil, running: roster,
                                       me: 202, myStart: noon) == nil)
    }

    // MARK: Picking exactly one survivor

    /// The whole point of comparing start times. Two copies launched in the same
    /// moment each see the other; if both stood down the user would be left with
    /// no app at all. The younger one defers…
    @Test func theYoungerOfTwoSimultaneousLaunchesStandsDown() {
        let roster = running((101, 0), (202, 1))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon.addingTimeInterval(1)) == 101)
    }

    /// …and the older one carries on, so exactly one app survives.
    @Test func theOlderOfTwoSimultaneousLaunchesCarriesOn() {
        let roster = running((101, 0), (202, 1))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 101, myStart: noon) == nil)
    }

    /// A copy that started *after* this one is not "already running", whatever
    /// order Launch Services happens to report the roster in.
    @Test func ignoresACopyThatStartedLater() {
        let roster = running((202, 0), (303, 30))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon) == nil)
    }

    /// With more than one older copy — which should not happen, but the roster
    /// is not ours to guarantee — talk to the one that has been up longest.
    /// It is the likeliest to be the app the user actually thinks of as running.
    @Test func picksTheOldestOfSeveralOlderCopies() {
        let roster = running((101, -10), (99, -600), (202, 0))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon) == 99)
    }

    /// Two copies really can report the same start instant, and every copy AppKit
    /// gives no launch date for is recorded as `.distantPast`, so ties are not
    /// hypothetical. The pid settles them: the lower one stays.
    @Test func atIdenticalStartTimesTheLowerPidStays() {
        let roster = running((101, 0), (202, 0))
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 202, myStart: noon) == 101)
        #expect(SingleInstance.handoff(bundleID: id, running: roster,
                                       me: 101, myStart: noon) == nil)
    }

    /// The property the whole ordering exists for, checked over every pairing of
    /// start times including the ties: of any two copies, exactly one stands
    /// down. Both standing down would leave the user with no app at all, and
    /// neither standing down is the duplicate this guard is here to prevent.
    @Test func ofAnyTwoCopiesExactlyOneStandsDown() {
        for firstOffset in [-30.0, 0.0, 30.0] {
            for secondOffset in [-30.0, 0.0, 30.0] {
                let roster = running((101, firstOffset), (202, secondOffset))
                let firstDefers = SingleInstance.handoff(
                    bundleID: id, running: roster,
                    me: 101, myStart: noon.addingTimeInterval(firstOffset)) != nil
                let secondDefers = SingleInstance.handoff(
                    bundleID: id, running: roster,
                    me: 202, myStart: noon.addingTimeInterval(secondOffset)) != nil
                #expect(firstDefers != secondDefers,
                        "offsets \(firstOffset)/\(secondOffset) left \(firstDefers)/\(secondDefers)")
            }
        }
    }

    /// Order in, order out: the roster arrives in Launch Services' order, not
    /// sorted, and the answer must not depend on that.
    @Test func theAnswerDoesNotDependOnRosterOrder() {
        let forwards = running((99, -600), (101, -10), (202, 0))
        let backwards = running((202, 0), (101, -10), (99, -600))
        let a = SingleInstance.handoff(bundleID: id, running: forwards, me: 202, myStart: noon)
        let b = SingleInstance.handoff(bundleID: id, running: backwards, me: 202, myStart: noon)
        #expect(a == b)
        #expect(a == 99)
    }
}
