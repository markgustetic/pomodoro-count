import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryManagementTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "Work", dailyGoal: 4)
        m.addCategory(name: "Music", dailyGoal: 1)
        return m
    }

    // MARK: Adding

    @Test func addingAppendsInOrder() {
        let m = configured()
        #expect(m.settings.categories.map(\.name) == ["Work", "Music"])
    }

    @Test func addingTrimsWhitespace() {
        let (m, _) = makeModel()
        m.addCategory(name: "  Work  ", dailyGoal: 4)
        #expect(m.settings.categories.first?.name == "Work")
    }

    @Test func aDuplicateNameIsRejected() {
        let m = configured()
        #expect(!m.addCategory(name: "  WORK ", dailyGoal: 2))
        #expect(m.settings.categories.count == 2)
    }

    @Test func aNameCollidingWithTheBucketIsRejected() {
        let m = configured()
        #expect(!m.addCategory(name: "general", dailyGoal: 2))
        #expect(m.settings.categories.count == 2)
    }

    @Test func anEmptyNameIsRejected() {
        let m = configured()
        #expect(!m.addCategory(name: "   ", dailyGoal: 2))
        #expect(m.settings.categories.count == 2)
    }

    @Test func goalsAreClampedToTheAllowedRange() {
        let (m, _) = makeModel()
        m.addCategory(name: "Low", dailyGoal: -5)
        m.addCategory(name: "High", dailyGoal: 99)
        #expect(m.settings.categories.map(\.dailyGoal) == [0, 20])
    }

    // MARK: Renaming

    @Test func renamingRewritesItsRecords() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: Date(), source: "manual", category: "Music"),
        ]
        let workID = m.settings.categories[0].id
        #expect(m.renameCategory(id: workID, to: "Deep work"))
        #expect(m.settings.categories[0].name == "Deep work")
        #expect(m.records.map(\.category) == ["Deep work", "Music"])
    }

    @Test func renamingOrphansNothingEvenWithOddCasing() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "work")]
        m.renameCategory(id: m.settings.categories[0].id, to: "Deep work")
        #expect(m.todayCount(inCategory: "Deep work") == 1)
    }

    @Test func renamingToAnExistingNameIsRejected() {
        let m = configured()
        #expect(!m.renameCategory(id: m.settings.categories[0].id, to: "Music"))
        #expect(m.settings.categories[0].name == "Work")
    }

    @Test func renamingToItsOwnNameIsAllowed() {
        let m = configured()
        #expect(m.renameCategory(id: m.settings.categories[0].id, to: "Work"))
    }

    @Test func renamingIsPersisted() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "Work", dailyGoal: 4)
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        m.renameCategory(id: m.settings.categories[0].id, to: "Deep work")

        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.settings.categories.first?.name == "Deep work")
        #expect(reloaded.records.first?.category == "Deep work")
    }

    // MARK: Archiving

    @Test func removingKeepsItsRecords() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Music")]
        m.removeCategory(id: m.settings.categories[1].id)
        #expect(m.settings.categories.map(\.name) == ["Work"])
        #expect(m.totalCount == 1)
        #expect(m.records.first?.category == "Music")
    }

    @Test func readdingTheSameNameReunitesItsHistory() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Music")]
        m.removeCategory(id: m.settings.categories[1].id)
        m.addCategory(name: "Music", dailyGoal: 1)
        #expect(m.todayCount(inCategory: "Music") == 1)
    }

    @Test func anArchivedCategoryStopsReceivingNewPomodoros() {
        let m = configured()
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Music"
        m.removeCategory(id: m.settings.categories[1].id)
        m.logExternal()
        #expect(m.records.first?.category == "Work")
    }

    // MARK: Reordering

    @Test func reorderingChangesDisplayOrder() {
        let m = configured()
        m.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work"])
    }
}
