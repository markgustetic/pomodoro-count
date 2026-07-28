import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryProgressTests {

    private func configured(bucket: Bool = true) -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.usesFallbackBucket = bucket
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

    @Test func theBucketIsAbsentWhenSwitchedOffAndEmpty() {
        let m = configured(bucket: false)
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study"])
    }

    /// Switching the bucket off keeps it visible while it still holds pomodoros.
    @Test func theBucketStaysWhileItHoldsPomodoros() {
        let m = configured(bucket: false)
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study", "General"])
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
        m.settings.usesFallbackBucket = false
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
}
