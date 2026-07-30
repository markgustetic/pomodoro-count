import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategorySessionTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        // Stamped "aimed today": an unstamped fixture reads as a new day, which
        // would silently reroute every advance test that uses this helper into
        // the start-of-day reset branch instead of the met-goal advance it means
        // to exercise. Tests that want the reset branch set their own stamp
        // afterward, overriding this one.
        m.settings.targetAimedOn = Date()
        return m
    }

    @Test func anUnsetTargetIsTheBucket() {
        let m = configured()
        #expect(m.sessionTarget == .fallback)
        #expect(m.resolve(m.sessionTarget) == nil)
        #expect(m.sessionTargetLabel == m.settings.fallbackName)
    }

    @Test func settingTheTargetPersistsIt() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.sessionTarget = .named("Work")
        #expect(AppModel(storeURL: url).settings.sessionTargetName == "Work")
    }

    @Test func aFinishedSessionCreditsItsTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.records.last?.source == "timer")
    }

    /// An archived target must not keep receiving pomodoros, and must not
    /// strand the session's one either. It falls to the bucket, the only
    /// destination an unset target has.
    @Test func anArchivedTargetCreditsTheBucket() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categories.removeAll { $0.name == "Music" }
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == nil)
    }

    @Test func aBreakCreditsNothing() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.startBreak()
        m.forceCompleteForTesting()
        #expect(m.records.isEmpty)
    }

    // MARK: Advancing to the next unfinished category

    /// The session that meets the goal still credits the target it ran against;
    /// only the *next* one goes somewhere new.
    @Test func meetingAGoalMovesTheTargetOnButNotThisRecord() {
        let m = configured()
        m.sessionTarget = .named("Music")        // goal 1, so this session meets it
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.sessionTarget == .named("Work"))
    }

    /// External hardware is the headline way pomodoros arrive here, so a log
    /// that fills the last slot has to move the target just as a session does.
    @Test func anExternalLogThatMeetsTheGoalMovesTheTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A re-pick used to buy exactly one pomodoro: the next record found the
    /// target met all over again and moved it on. Now the pin holds, and Task 4
    /// is what sets it — here it stands in for that, so this test stays about
    /// the advance rather than about how the pin arrives.
    @Test func aRePickedFinishedCategoryKeepsTheNextSession() {
        let m = configured()
        m.logExternal(to: .named("Music"))       // Music met
        m.sessionTarget = .named("Music")        // the user insists
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.sessionTarget == .named("Music"))
    }

    /// The day's whole plan is met, so there is nowhere to advance to and
    /// further pomodoros overshoot where they are.
    @Test func theTargetStaysPutWhenEveryGoalIsMet() {
        let m = configured()
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 1),
            Category(name: "Music", dailyGoal: 1),
        ]
        m.sessionTarget = .named("Work")
        m.logExternal(to: .named("Music"))       // Music met
        m.logExternal(to: .named("Work"))        // Work met, nothing left
        #expect(m.sessionTarget == .named("Work"))
    }

    /// Goals are invisible while categories are off and must not drive
    /// anything — the same rule `todayGoalTotal` follows.
    @Test func nothingAdvancesWhileCategoriesAreOff() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categoriesEnabled = false
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Music"))
    }

    @Test func nothingAdvancesWhenTheSettingIsOff() {
        let m = configured()
        m.settings.autoAdvanceTarget = false
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Music"))
    }

    // MARK: A running session is not re-aimed

    /// A log that backfills the *running* session's own goal must not hand its
    /// credit to wherever the target advances next — Start already chose the
    /// destination, and only the next session should see the move. The advance
    /// itself isn't disabled, though: it still fires the moment `complete()`
    /// appends its own record, because `isRunning` is false by then — this is
    /// the assertion that would catch a guard "simplified" into blocking
    /// `complete()` too.
    @Test func anExternalLogMidSessionDoesNotReAimTheRunningTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")        // goal 1
        m.startWork()
        m.logExternal(to: .named("Music"))       // meets Music's goal while running
        #expect(m.sessionTarget == .named("Music"))
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A paused session is not "actually running" — the same test
    /// `todayProgress` applies to `isSessionTarget` — so, unlike the running
    /// case above, a log that meets its goal while paused advances the target
    /// immediately.
    @Test func aPausedSessionDoesNotBlockTheAdvance() {
        let m = configured()
        m.sessionTarget = .named("Music")        // goal 1
        m.startWork()
        m.pause()
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Work"))
    }

    // MARK: realignTarget — the start-of-day reset and the met-goal advance

    /// The ranking's payoff at model level: Music is met, Work is not, and Work
    /// ranks above it. The old rotation would have looked *past* Work.
    @Test func aMetGoalHandsOffUpTheRanking() {
        let m = configured()
        m.settings.categories.append(Category(name: "Admin", dailyGoal: 2))
        m.sessionTarget = .named("Music")            // goal 1, ranks second
        m.settings.targetAimedOn = Date()            // not a new day
        m.logExternal(to: .named("Music"))           // meets Music
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A stale stamp means the app has not aimed the target today: counts have
    /// reset, so the plan restarts at the top and yesterday's pin is stale.
    @Test func aNewDayRestartsAtTheTopOfTheRanking() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.realignTarget()
        #expect(m.sessionTarget == .named("Work"))
        #expect(!m.settings.targetPinned)
        #expect(Calendar.current.isDateInToday(m.settings.targetAimedOn ?? .distantPast))
    }

    /// Same day, so the reset must not fire — it would wipe a pick the user
    /// made half an hour ago.
    @Test func aSameDayStampLeavesTheTargetAlone() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))
        #expect(m.settings.targetPinned)
    }

    /// The reset is a start-of-day event, not a lazy one: it stamps even when
    /// there is nothing to aim at, so adding a goal at noon does not make it
    /// fire retroactively.
    @Test func theDailyResetStampsEvenWithNothingToAimAt() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 0)]
        m.settings.targetAimedOn = nil
        m.realignTarget()
        #expect(Calendar.current.isDateInToday(m.settings.targetAimedOn ?? .distantPast))
    }

    /// A pin suppresses the advance, so an overshoot lasts as long as the user
    /// wants rather than exactly one pomodoro.
    @Test func aPinnedTargetSurvivesRepeatedOvershoots() {
        let m = configured()
        m.sessionTarget = .named("Music")            // goal 1
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        for _ in 0..<3 { m.logExternal(to: .named("Music")) }
        #expect(m.sessionTarget == .named("Music"))
        #expect(m.todayCount(inCategory: "Music") == 3)
    }

    /// A session in flight is never re-aimed, the daily reset included: the
    /// record that finishes it has to land where Start pointed.
    @Test func aRunningSessionDefersTheDailyReset() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.settings.workMinutes = 1
        m.startWork()
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))  // deferred, not lost
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music") // Start's promise kept
        #expect(m.sessionTarget == .named("Work"))   // and only then, the reset
    }

    /// Turning the rule off freezes both automatic triggers. Someone who opted
    /// out wants a target that never moves on its own, and an overnight re-aim
    /// violates that exactly as much as a met-goal one does.
    @Test func theOptOutFreezesTheDailyResetToo() {
        let m = configured()
        m.settings.autoAdvanceTarget = false
        m.sessionTarget = .named("Music")
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))
    }

    // MARK: Persistence

    /// The `suspendSaves()`/`resumeSaves()` bracket around the advance is new
    /// behaviour on this path, and its failure mode is silent: a lost resume
    /// would leave every other test passing while the pill simply forgot where
    /// it advanced to on relaunch. Reloading from disk is what proves the
    /// resume actually flushed the pending write.
    @Test func anAdvancedTargetSurvivesAReload() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4),
                                 Category(name: "Music", dailyGoal: 1)]
        // Built from makeModel() rather than configured(), so it needs its own
        // stamp for the same reason configured() carries one: unstamped reads
        // as a new day and this test means to exercise the advance, not the
        // start-of-day reset.
        m.settings.targetAimedOn = Date()
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(AppModel(storeURL: url).settings.sessionTargetName == "Work")
    }
}
