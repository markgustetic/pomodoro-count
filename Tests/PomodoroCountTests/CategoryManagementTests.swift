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

    /// Three categories, so a move can be tested as something other than a swap
    /// of two — the direction-dependent off-by-one only shows up with three.
    private func threeCategories() -> AppModel {
        let m = configured()
        m.addCategory(name: "Admin", dailyGoal: 2)
        return m       // Work, Music, Admin
    }

    @Test func movingACategoryDownLandsInTheTargetSlot() {
        let m = threeCategories()
        m.moveCategory(from: 0, to: 2)
        #expect(m.settings.categories.map(\.name) == ["Music", "Admin", "Work"])
    }

    /// The `toOffset` off-by-one, pinned: `move(fromOffsets:toOffset:)` measures
    /// its offset before the removal, so passing the destination unadjusted here
    /// would leave the order untouched and the row would look stuck.
    @Test func movingACategoryDownByOneActuallyMovesIt() {
        let m = threeCategories()
        m.moveCategory(from: 0, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work", "Admin"])
    }

    @Test func movingACategoryUpLandsInTheTargetSlot() {
        let m = threeCategories()
        m.moveCategory(from: 2, to: 0)
        #expect(m.settings.categories.map(\.name) == ["Admin", "Work", "Music"])
    }

    @Test func movingToTheSlotItAlreadyOccupiesChangesNothing() {
        let m = threeCategories()
        m.moveCategory(from: 1, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    @Test func outOfRangeIndicesChangeNothing() {
        let m = threeCategories()
        m.moveCategory(from: 5, to: 0)
        m.moveCategory(from: 0, to: 9)
        m.moveCategory(from: -1, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    @Test func reorderingLeavesTheRecordsAlone() {
        let m = threeCategories()
        m.records = [Record(at: Date(), source: "manual", category: "Music")]
        m.moveCategory(from: 1, to: 0)
        #expect(m.todayCount(inCategory: "Music") == 1)
    }

    @Test func thePanelFollowsTheNewOrderWithTheBucketStillLast() {
        let m = threeCategories()
        m.moveCategory(from: 2, to: 0)
        #expect(m.todayProgress.map(\.name) == ["Admin", "Work", "Music", "General"])
    }

    @Test func theNewOrderSurvivesAReload() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "Work", dailyGoal: 4)
        m.addCategory(name: "Music", dailyGoal: 1)
        m.moveCategory(from: 1, to: 0)

        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.settings.categories.map(\.name) == ["Music", "Work"])
    }

    /// A reorder must not disturb the session target. The coupling between
    /// them is by name, not index — there is nothing to keep in sync, but
    /// that is exactly the kind of invariant a future index-based change
    /// could break without any existing test noticing.
    @Test func reorderingLeavesTheSessionTargetPointingAtTheSameCategory() {
        let m = threeCategories()   // Work, Music, Admin
        m.settings.sessionTargetName = "Music"
        m.moveCategory(from: 1, to: 0)   // Music moves to the front
        #expect(m.resolve(m.sessionTarget) == "Music")
    }

    // MARK: Drag replay

    /// Four categories, so a drag can cross three slot boundaries — enough
    /// for several ticks to land in the same slot before the next one commits.
    private func fourCategories() -> AppModel {
        let m = threeCategories()
        m.addCategory(name: "Reading", dailyGoal: 1)
        return m   // Work, Music, Admin, Reading
    }

    /// `pitch` matches `ReorderTests`: one row's height plus the gap to the
    /// next, so 16 is the rounding boundary between two slots.
    private let pitch: CGFloat = 32

    /// Every seam here is unit-tested alone — `Reorder.destination` in
    /// `ReorderTests`, `moveCategory` above — but nothing previously proved
    /// the two agree on which index is "from". `CategoryList.dragGesture`
    /// passes `startIndex` to `Reorder.destination` and `currentIndex` to
    /// `moveCategory`, three lines apart; this replays that exact bookkeeping
    /// against the real implementations of both, tick by tick, the way a
    /// mouse drag would drive it.
    ///
    /// Also pins the invariant that keeps the row under the pointer: the drawn
    /// offset — translation minus the distance already absorbed by committed
    /// moves — never exceeds the sticky band, which is the furthest the row is
    /// allowed to get from its slot before the move commits.
    @discardableResult
    private func replayDrag(on m: AppModel, from startIndex: Int, through translations: [CGFloat]) -> Int {
        var currentIndex = startIndex
        for translation in translations {
            let destination = Reorder.destination(
                from: startIndex, current: currentIndex, translation: translation, pitch: pitch,
                count: m.settings.categories.count)
            if destination != currentIndex {
                m.moveCategory(from: currentIndex, to: destination)
                currentIndex = destination
            }
            let drawnOffset = abs(translation - CGFloat(currentIndex - startIndex) * pitch)
            #expect(drawnOffset <= (0.5 + Reorder.stickiness) * pitch)
        }
        return currentIndex
    }

    @Test func aDownwardDragReplaysTheSameOrderAMouseDragWould() {
        let m = fourCategories()   // Work, Music, Admin, Reading
        // Steps of 9pt, well short of the 32pt pitch, so several ticks land in
        // the same slot before the next boundary. With the sticky band those
        // boundaries are at 22.4, 54.4 and 86.4pt, and no tick lands on one.
        let end = replayDrag(on: m, from: 0, through: [0, 9, 18, 27, 36, 45, 54, 63, 72, 81, 90, 99])
        #expect(end == 3)
        #expect(m.settings.categories.map(\.name) == ["Music", "Admin", "Reading", "Work"])
    }

    /// The downward case in reverse: same tick size, crossing two boundaries
    /// instead of three, moving the opposite way.
    @Test func anUpwardDragReplaysTheSameOrderAMouseDragWould() {
        let m = fourCategories()   // Work, Music, Admin, Reading
        let end = replayDrag(on: m, from: 3, through: [0, -9, -18, -27, -36, -45, -54, -63])
        #expect(end == 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Reading", "Music", "Admin"])
    }

    /// The stutter this stickiness exists to stop: a pointer easing across a
    /// boundary and wavering there. Every one of these ticks sits within the
    /// band around the slot the row moved into, so the drag must commit exactly
    /// one reorder rather than one per tremor.
    @Test func waveringAtABoundaryCommitsOnlyOneMove() {
        let m = fourCategories()
        let end = replayDrag(on: m, from: 0, through: [0, 20, 23, 21, 24, 20, 25, 22, 26])
        #expect(end == 1)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work", "Admin", "Reading"])
    }

    // MARK: Nudging (keyboard and VoiceOver)

    @Test func nudgingMovesACategoryOneSlot() {
        let m = threeCategories()
        let admin = m.settings.categories[2].id
        m.nudgeCategory(id: admin, by: -1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Admin", "Music"])
        m.nudgeCategory(id: admin, by: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    /// The row at either end has nowhere to go, and says so by doing nothing
    /// rather than by needing a special case at the call site.
    @Test func nudgingPastEitherEndChangesNothing() {
        let m = threeCategories()
        m.nudgeCategory(id: m.settings.categories[0].id, by: -1)
        m.nudgeCategory(id: m.settings.categories[2].id, by: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    @Test func nudgingAnUnknownCategoryChangesNothing() {
        let m = threeCategories()
        m.nudgeCategory(id: UUID(), by: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
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
