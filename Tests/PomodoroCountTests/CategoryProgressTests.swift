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

    /// A met goal must be conveyed in the value, not by colour alone.
    @Test func accessibilityValueSaysWhenAGoalIsMet() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "AI study")]
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        #expect(ai.accessibilityValue == "1 of 1 pomodoros, goal met")
    }

    @Test func accessibilityValueForAGoallessCategoryIsJustTheCount() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual")]
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.accessibilityValue == "1 pomodoro")
    }

    // MARK: Session-target outline

    @Test func isSessionTargetMarksOnlyTheRunningTargetCategory() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.workMinutes = 1
        m.startWork()
        let work = m.todayProgress.first { $0.name == "Work" }!
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        #expect(work.isSessionTarget)
        #expect(!ai.isSessionTarget)
    }

    @Test func isSessionTargetMarksTheBucketWhenThatIsTheRunningTarget() {
        let m = configured()   // sessionTarget unset -> automatic -> bucket (bucket on)
        m.settings.workMinutes = 1
        m.startWork()
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.isSessionTarget)
    }

    @Test func isSessionTargetIsFalseWithNoSessionRunning() {
        let m = configured()
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(!work.isSessionTarget)
    }

    @Test func isSessionTargetIsFalseDuringABreak() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.breakMinutes = 1
        m.startBreak()
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(!work.isSessionTarget)
    }

    @Test func isSessionTargetIsFalseWhilePaused() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.workMinutes = 1
        m.startWork()
        m.pause()
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(!work.isSessionTarget)
    }
}
