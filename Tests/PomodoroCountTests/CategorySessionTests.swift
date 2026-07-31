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

    /// A paused session is not "actually running" — `realignTarget`'s guard is
    /// `phase == .work && isRunning`, not just `phase == .work` — so, unlike
    /// the running case above, a log that meets its goal while paused advances
    /// the target immediately.
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
    /// would leave every other test passing while the target simply forgot
    /// where it advanced to on relaunch. Reloading from disk is what proves
    /// the resume actually flushed the pending write.
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

    // MARK: pickTarget — telling the two kinds of hand pick apart

    /// The rule, both halves. Picking a finished category can only mean "let me
    /// overshoot here" and pins; picking one with a goal left just says "work
    /// here next" and needs no pin, because the advance only fires on a met
    /// target and will hand back to the ranking once the goal is reached.
    @Test func pickingAFinishedCategoryPinsAndPickingAnUnfinishedOneDoesNot() {
        let m = configured()
        m.logExternal(to: .named("Music"))       // Music (goal 1) is now met
        m.pickTarget(.named("Music"))
        #expect(m.settings.targetPinned)
        m.pickTarget(.named("Work"))             // goal 4, nothing logged
        #expect(!m.settings.targetPinned)
    }

    /// The unpinned half, end to end: a hand pick holds while it is unfinished,
    /// then rejoins the ranking on its own — at the *top*, not at the row below.
    @Test func anUnfinishedHandPickHandsBackToTheTopWhenItIsMet() {
        let m = configured()
        m.settings.categories.append(Category(name: "Admin", dailyGoal: 1))
        m.pickTarget(.named("Admin"))            // ranks last, goal 1
        #expect(m.sessionTarget == .named("Admin"))
        m.logExternal(to: .named("Admin"))       // meets it
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A hand pick stamps today, or the next realign would read the target as
    /// yesterday's and wipe a pick made moments ago.
    ///
    /// Music rather than Work on purpose: Work is the top of the ranking, so a
    /// missing stamp would send `restartFromTopOfRanking()` to the same place
    /// the pick did and the assertion could not tell the two apart.
    @Test func aHandPickStampsToday() {
        let m = configured()
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.pickTarget(.named("Music"))
        #expect(Calendar.current.isDateInToday(m.settings.targetAimedOn ?? .distantPast))
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))
    }

    /// A goal of 0 can never be met, so picking one never pins — and the advance
    /// can never fire on it either, so it holds anyway. Both halves of "no
    /// special case needed".
    @Test func pickingAGoalLessCategoryNeitherPinsNorMoves() {
        let m = configured()
        m.settings.categories.append(Category(name: "Reading", dailyGoal: 0))
        m.pickTarget(.named("Reading"))
        #expect(!m.settings.targetPinned)
        m.logExternal(to: .named("Reading"))
        #expect(m.sessionTarget == .named("Reading"))
    }

    /// Handing control back has to work from an unfinished target too, which is
    /// why it does not route through the advance and its met-target guard.
    @Test func followingTheOrderClearsThePinAndAimsAtTheTop() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))            // pinned, and Music is met
        m.followTheOrder()
        #expect(!m.settings.targetPinned)
        #expect(m.sessionTarget == .named("Work"))
    }

    /// The getter resolves an archived name to `.fallback`, so a pin that
    /// outlived its category would silently pin the bucket instead.
    @Test func archivingThePinnedCategoryClearsThePin() {
        let m = configured()
        let music = m.settings.categories[1]
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        #expect(m.settings.targetPinned)
        m.removeCategory(id: music.id)
        #expect(!m.settings.targetPinned)
    }

    /// Archiving some *other* category is not the pinned one's business.
    @Test func archivingAnotherCategoryLeavesThePinAlone() {
        let m = configured()
        let work = m.settings.categories[0]
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        m.removeCategory(id: work.id)
        #expect(m.settings.targetPinned)
    }

    /// Two different promises, not a mode indicator: one says the ranking will
    /// move on when this is done, the other says it won't.
    @Test func theDescriptionSaysWhichPromiseIsInForce() {
        let m = configured()
        #expect(m.sessionTargetDescription == "towards \(m.settings.fallbackName)")
        m.pickTarget(.named("Work"))
        #expect(m.sessionTargetDescription == "towards Work")
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        #expect(m.sessionTargetDescription == "pinned to Music")
    }

    /// With the rule off there is no automatic behaviour for a pin to hold out
    /// against, so the distinction stops being worth showing. The flag is still
    /// recorded, so turning the rule back on restores what
    /// `sessionTargetDescription` already promised.
    @Test func theDescriptionDropsThePinWhileTheRuleIsOff() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        m.settings.autoAdvanceTarget = false
        #expect(m.sessionTargetDescription == "towards Music")
        #expect(m.settings.targetPinned)
    }

    // MARK: selectTarget — what a click on a category row does

    @Test func clickingAnotherRowAimsAtIt() {
        let m = configured()
        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
    }

    /// `pickTarget`'s pin rule is unchanged and still reached: picking a
    /// category that is already met reads as "let me overshoot here".
    @Test func clickingAMetRowPinsIt() {
        let m = configured()
        m.logExternal(to: .named("Music"))      // Music's goal is 1, so this meets it
        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
        #expect(m.settings.targetPinned)
    }

    /// The handback the dropdown's "Follow the order" entry used to carry.
    /// Work is first in the ranking and unmet, so the release lands there.
    @Test func clickingThePinnedRowAgainHandsControlBack() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.selectTarget(.named("Music"))
        #expect(m.settings.targetPinned)

        m.selectTarget(.named("Music"))
        #expect(!m.settings.targetPinned)
        #expect(m.sessionTargetLabel == "Work")
    }

    /// The case a naive implementation gets wrong: re-clicking an *unpinned*
    /// target must not run the handback, which would aim at the top unmet
    /// category and move the target off the row that was just clicked.
    @Test func clickingAnUnpinnedTargetRowAgainChangesNothing() {
        let m = configured()
        m.selectTarget(.named("Music"))
        #expect(!m.settings.targetPinned)

        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
    }

    /// With the ranking off there is nothing to hand back to, so the pin
    /// stands and the target stays put.
    @Test func clickingThePinnedRowAgainDoesNothingWhileTheRuleIsOff() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.selectTarget(.named("Music"))
        m.settings.autoAdvanceTarget = false

        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
        #expect(m.settings.targetPinned)
    }

    /// The bucket is a row like any other, and it is identified by `.fallback`
    /// rather than by name — its label is whatever the user called it.
    @Test func clickingTheBucketRowAimsAtIt() {
        let m = configured()
        m.selectTarget(.named("Work"))
        m.selectTarget(.fallback)
        #expect(m.sessionTargetLabel == m.settings.fallbackName)
    }
}
