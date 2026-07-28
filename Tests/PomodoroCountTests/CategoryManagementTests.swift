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

    /// Each element assignment to `records` used to fire a full save, so a
    /// rename of N records cost N encodes. This proves the rewrite still
    /// reaches every record (and both settings pointers) after collapsing
    /// that to one assignment.
    @Test func renamingManyRecordsAllFollow() {
        let m = configured()
        m.records = (0..<50).map { _ in Record(at: Date(), source: "manual", category: "Work") }
        m.settings.sessionTargetName = "Work"
        let workID = m.settings.categories[0].id

        #expect(m.renameCategory(id: workID, to: "Deep work"))

        #expect(m.records.count == 50)
        #expect(m.records.allSatisfy { $0.category == "Deep work" })
        #expect(m.settings.sessionTargetName == "Deep work")
    }

    /// Renaming "Admin" into "Work" must not succeed while "Work" is archived
    /// with records that were never this category's — that would silently
    /// absorb someone else's history, and a later rename away would
    /// permanently relabel it. Reunion stays available via delete-then-re-add.
    @Test func renamingIntoAnArchivedNameWithForeignRecordsIsRefused() {
        let m = configured()   // Work, Music
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        let workID = m.settings.categories[0].id
        m.removeCategory(id: workID)   // "Work" is now archived but still has a record
        m.addCategory(name: "Admin", dailyGoal: 0)
        let adminID = m.settings.categories.first { $0.name == "Admin" }!.id

        #expect(!m.renameCategory(id: adminID, to: "Work"))
        #expect(m.settings.categories.first { $0.id == adminID }?.name == "Admin")
        #expect(m.records.first?.category == "Work")   // untouched
    }

    /// A plain rename with nothing archived under the new name must still work
    /// — the refusal above should not become a blanket block on renaming.
    @Test func renamingWithNoArchivedCollisionStillWorks() {
        let m = configured()
        let musicID = m.settings.categories[1].id
        #expect(m.renameCategory(id: musicID, to: "Jazz"))
        #expect(m.settings.categories[1].name == "Jazz")
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
        m.settings.sessionTargetName = "Music"
        m.removeCategory(id: m.settings.categories[1].id)
        m.logExternal()
        #expect(m.records.first?.category == nil)   // the bucket, not Music
    }

    // MARK: Reordering

    @Test func reorderingChangesDisplayOrder() {
        let m = configured()
        m.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work"])
    }

    // MARK: Fallback name

    /// Uniqueness is binding across categories *and* the fallback — this is
    /// the fallback's half of that rule.
    @Test func fallbackNameCollidingWithACategoryIsUnavailable() {
        let m = configured()   // Work, Music
        #expect(!m.isFallbackNameAvailable("work"))
        #expect(!m.isFallbackNameAvailable("  MUSIC  "))
    }

    @Test func fallbackNameIsAvailableWhenItDoesNotCollide() {
        let m = configured()
        #expect(m.isFallbackNameAvailable("Errands"))
    }

    @Test func emptyOrWhitespaceOnlyFallbackNameIsUnavailable() {
        let m = configured()
        #expect(!m.isFallbackNameAvailable(""))
        #expect(!m.isFallbackNameAvailable("   "))
    }

    @Test func settingTheFallbackNameRejectsACollisionAndChangesNothing() {
        let m = configured()
        #expect(!m.setFallbackName("Work"))
        #expect(m.settings.fallbackName == "General")
    }

    @Test func settingTheFallbackNameTrimsAndSucceedsOtherwise() {
        let m = configured()
        #expect(m.setFallbackName("  Errands  "))
        #expect(m.settings.fallbackName == "Errands")
    }
}
