import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryBreakdownTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        return m
    }

    @Test func totalsRespectTheRange() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: .daysAgo(3), source: "manual", category: "Work"),
            Record(at: .daysAgo(20), source: "manual", category: "Work"),
        ]
        #expect(m.categoryTotals(days: 7).first { $0.name == "Work" }?.count == 2)
        #expect(m.categoryTotals(days: 30).first { $0.name == "Work" }?.count == 3)
    }

    /// A neglected category should be visible, not absent.
    @Test func currentCategoriesAppearEvenWithZeroInRange() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        let names = m.categoryTotals(days: 7).map(\.name)
        #expect(names.contains("Music"))
        #expect(m.categoryTotals(days: 7).first { $0.name == "Music" }?.count == 0)
    }

    @Test func archivedNamesAppearWhileTheyHaveRecordsInRange() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Painting")]
        #expect(m.categoryTotals(days: 7).first { $0.name == "Painting" }?.count == 1)
    }

    @Test func archivedNamesVanishOnceOutOfRange() {
        let m = configured()
        m.records = [Record(at: .daysAgo(20), source: "manual", category: "Painting")]
        #expect(!m.categoryTotals(days: 7).contains { $0.name == "Painting" })
    }

    @Test func theBucketAppearsUnderItsName() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.categoryTotals(days: 7).first { $0.name == "General" }?.count == 1)
    }

    @Test func orderIsDisplayOrderThenArchivedAlphabetically() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Zebra"),
            Record(at: Date(), source: "manual", category: "Antique"),
            Record(at: Date(), source: "manual"),
        ]
        let names = m.categoryTotals(days: 7).map(\.name)
        #expect(names.prefix(2) == ["Work", "Music"])
        #expect(names.dropFirst(2) == ["General", "Antique", "Zebra"])
    }

    @Test func totalsMatchTheDailySeriesTotal() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: .daysAgo(2), source: "manual", category: "Music"),
            Record(at: .daysAgo(2), source: "manual"),
        ]
        let breakdown = m.categoryTotals(days: 7).map(\.count).reduce(0, +)
        let daily = m.dailySeries(days: 7).map(\.count).reduce(0, +)
        #expect(breakdown == daily)
    }
}
