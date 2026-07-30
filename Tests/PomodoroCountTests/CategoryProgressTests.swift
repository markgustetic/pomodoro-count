import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryProgressTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "AI study", dailyGoal: 1),
        ]
        return m
    }

    @Test func countsOnlyTodaysPomodorosInThatCategory() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: Date(), source: "manual", category: "AI study"),
            Record(at: .daysAgo(1), source: "manual", category: "Work"),
        ]
        #expect(m.todayCount(inCategory: "Work") == 2)
        #expect(m.todayCount(inCategory: "AI study") == 1)
    }

    @Test func theBucketCountsRecordsWithNoCategory() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual"),
            Record(at: Date(), source: "manual", category: "Work"),
        ]
        #expect(m.todayCount(inCategory: nil) == 1)
    }

    @Test func categoryNamesMatchCaseInsensitively() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "work")]
        #expect(m.todayCount(inCategory: "Work") == 1)
    }

    @Test func progressListsEveryCategoryThenTheBucket() {
        let m = configured()
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study", "General"])
        #expect(m.todayProgress.last?.isFallback == true)
    }

    /// The bucket is always the last row, empty or not. It is the only tap
    /// target for a pomodoro that belongs to none of the categories, so it
    /// cannot come and go with its own count.
    @Test func theBucketIsAlwaysPresentEvenAtZero() {
        let m = configured()
        #expect(m.todayProgress.last?.name == "General")
        #expect(m.todayProgress.last?.done == 0)
        #expect(m.todayProgress.last?.isFallback == true)
    }

    @Test func theBucketCountsWhatCarriesNoCategory() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study", "General"])
        #expect(m.todayProgress.last?.done == 1)
    }

    /// It is the *rows* that hide when categories are off, not the routing:
    /// records logged in that state still carry no category.
    @Test func noRowsAtAllWhileCategoriesAreOff() {
        let m = configured()
        m.settings.categoriesEnabled = false
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.todayProgress.isEmpty)
    }

    @Test func aGoalIsMetOnlyWhenReached() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "AI study")]
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(ai.isMet)
        #expect(!work.isMet)
    }

    @Test func overshootingKeepsCounting() {
        let m = configured()
        m.records = (0..<6).map { _ in Record(at: Date(), source: "manual", category: "Work") }
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.done == 6)
        #expect(work.goal == 4)
        #expect(work.isMet)
    }

    // MARK: countText — shared between the row's trailing column and the popover

    @Test func countTextShowsGoalAsAFraction() {
        let progress = CategoryProgress(id: "work", name: "Work", done: 2, goal: 4,
                                         isFallback: false, isTarget: false)
        #expect(progress.countText == "2/4")
    }

    @Test func countTextIsBareForAGoallessCategory() {
        let progress = CategoryProgress(id: "general", name: "General", done: 3, goal: 0,
                                         isFallback: true, isTarget: false)
        #expect(progress.countText == "3")
    }

    /// `done` can run past `goal` (overshoot is allowed, not clamped — see
    /// `overshootingKeepsCounting` above), and the text must keep growing
    /// rather than clip at the goal.
    @Test func countTextKeepsGrowingPastTheGoal() {
        let progress = CategoryProgress(id: "work", name: "Work", done: 6, goal: 4,
                                         isFallback: false, isTarget: false)
        #expect(progress.countText == "6/4")
    }

    @Test func aGoalOfZeroIsNeverMetAndDrawsNoDots() {
        let m = configured()
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.goal == 0)
        #expect(!bucket.isMet)
        #expect(!bucket.showsDots)
    }

    @Test(arguments: [(1, true), (8, true), (9, false), (20, false)])
    func dotsGiveWayToABarAboveEight(goal: Int, expectsDots: Bool) {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "X", dailyGoal: goal)]
        #expect(m.todayProgress.first?.showsDots == expectsDots)
    }

    @Test func accessibilityValueSpellsOutProgress() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.accessibilityValue == "1 of 4 pomodoros")
    }

    /// A met goal and the target mark are both conveyed in the value, not by
    /// colour alone. The outline is colour; this is what VoiceOver gets.
    @Test func accessibilityValueNamesTheTarget() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.accessibilityValue.hasSuffix(", session target"))
    }

    @Test func accessibilityValueSaysWhenAGoalIsMet() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "AI study")]
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        #expect(ai.accessibilityValue == "1 of 1 pomodoros, goal met")
    }

    @Test func accessibilityValueForAGoallessCategoryIsJustTheCount() {
        let m = configured()
        // Aim elsewhere: unset, the bucket is itself the automatic target,
        // which would append the target suffix this test isn't about.
        m.sessionTarget = .named("Work")
        m.records = [Record(at: Date(), source: "manual")]
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.accessibilityValue == "1 pomodoro")
    }

    // MARK: Target mark

    @Test func isTargetMarksOnlyTheTargetCategory() {
        let m = configured()
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        #expect(work.isTarget)
        #expect(!ai.isTarget)
    }

    @Test func isTargetMarksTheBucketWhenThatIsTheTarget() {
        let m = configured()   // sessionTarget unset -> automatic -> bucket
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.isTarget)
    }

    /// The three tests below asserted the opposite until the rows became how
    /// the target is *chosen*. A row you click to select has to show its
    /// selection before Start is pressed, so the mark has to survive every
    /// state a not-yet-running session can be in.
    @Test func isTargetSurvivesWithNoSessionRunning() {
        let m = configured()
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.isTarget)
    }

    @Test func isTargetSurvivesABreak() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.breakMinutes = 1
        m.startBreak()
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.isTarget)
        m.reset()
    }

    @Test func isTargetSurvivesAPause() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.workMinutes = 1
        m.startWork()
        m.pause()
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.isTarget)
        m.reset()
    }
}
