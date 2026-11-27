import Testing
import Foundation
@testable import PomodoroCount

@Suite struct TaskExpiryTests {

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: today)! }

    // Module-qualified: under @testable import, Foundation's Category typedef makes the bare name ambiguous as a return type.
    private func standing(_ name: String) -> PomodoroCount.Category {
        Category(name: name, dailyGoal: 1)
    }

    private func task(_ name: String, addedOn day: Date) -> PomodoroCount.Category {
        Category(name: name, dailyGoal: 1, expiresOn: day)
    }

    @Test func aStandingCategoryIsNeverATask() {
        #expect(!standing("Work").isTask)
        #expect(task("Report", addedOn: today).isTask)
    }

    @Test func aStandingCategorySurvivesAnyDay() {
        let list = [standing("Work")]
        let farFuture = cal.date(byAdding: .year, value: 10, to: today)!
        #expect(TaskExpiry.surviving(list, today: farFuture).map(\.name) == ["Work"])
    }

    @Test func aTaskAddedTodaySurvivesToday() {
        let list = [task("Report", addedOn: today)]
        #expect(TaskExpiry.surviving(list, today: today).map(\.name) == ["Report"])
    }

    @Test func aTaskAddedYesterdayIsGoneToday() {
        let list = [task("Report", addedOn: yesterday), standing("Work")]
        #expect(TaskExpiry.surviving(list, today: today).map(\.name) == ["Work"])
    }

    /// "Today" is the day it was added, right up to midnight — a task added at
    /// 23:59 is stamped with that day's start, and 00:00 of the next is later.
    @Test func aTaskAddedLateLastNightIsGoneAtMidnight() {
        let lateLastNight = cal.date(bySettingHour: 23, minute: 59, second: 0, of: yesterday)!
        let stamped = cal.startOfDay(for: lateLastNight)
        let list = [task("Report", addedOn: stamped)]
        #expect(TaskExpiry.surviving(list, today: today).isEmpty)
    }

    /// Reachable through a hand-edited store or a clock set back; a future day is not over.
    @Test func aTaskDatedTomorrowSurvivesToday() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let list = [task("Report", addedOn: tomorrow)]
        #expect(TaskExpiry.surviving(list, today: today).map(\.name) == ["Report"])
    }

    @Test func onlyTheStaleTaskIsDroppedFromAMixedList() {
        let list = [task("A", addedOn: today), task("B", addedOn: yesterday),
                    standing("Work"), task("C", addedOn: today)]
        #expect(TaskExpiry.surviving(list, today: today).map(\.name) == ["A", "Work", "C"])
    }

    @Test func orderIsPreservedAndNothingExpiringReturnsTheInput() {
        let list = [task("A", addedOn: today), task("B", addedOn: today),
                    standing("Work"), standing("Music")]
        let kept = TaskExpiry.surviving(list, today: today)
        #expect(kept.map(\.name) == ["A", "B", "Work", "Music"])
        #expect(kept.map(\.id) == list.map(\.id))
    }

    // MARK: Reorder guard

    private var mixed: [PomodoroCount.Category] {
        [task("A", addedOn: today), task("B", addedOn: today),
         standing("Work"), standing("Music")]
    }

    @Test func taskToTaskAndCategoryToCategoryMovesAreAllowed() {
        #expect(TaskExpiry.moveKeepsTasksOnTop(mixed, from: 0, to: 1))
        #expect(TaskExpiry.moveKeepsTasksOnTop(mixed, from: 3, to: 2))
    }

    @Test func crossingTheBoundaryEitherWayIsRefused() {
        #expect(!TaskExpiry.moveKeepsTasksOnTop(mixed, from: 1, to: 2))
        #expect(!TaskExpiry.moveKeepsTasksOnTop(mixed, from: 2, to: 0))
    }

    @Test func aListOfOneKindAllowsAnyMove() {
        let onlyCategories = [standing("Work"), standing("Music"), standing("Art")]
        #expect(TaskExpiry.moveKeepsTasksOnTop(onlyCategories, from: 0, to: 2))
        let onlyTasks = [task("A", addedOn: today), task("B", addedOn: today)]
        #expect(TaskExpiry.moveKeepsTasksOnTop(onlyTasks, from: 1, to: 0))
    }

    @Test func anIndexOffTheEndIsRefused() {
        #expect(!TaskExpiry.moveKeepsTasksOnTop(mixed, from: 0, to: 4))
        #expect(!TaskExpiry.moveKeepsTasksOnTop(mixed, from: -1, to: 0))
    }

    // MARK: How far a drag may carry a row

    @Test func aMoveInsideTheRowsOwnBlockReachesItsDestination() {
        #expect(TaskExpiry.reachableDestination(mixed, from: 0, towards: 1) == 1)
        #expect(TaskExpiry.reachableDestination(mixed, from: 3, towards: 2) == 2)
    }

    /// The row goes as far as its own kind extends and no further — it stops
    /// at the boundary rather than refusing to move at all, so a fast drag
    /// that overshoots still lands on the last legal slot.
    @Test func aMoveAcrossTheBoundaryStopsAtIt() {
        #expect(TaskExpiry.reachableDestination(mixed, from: 0, towards: 3) == 1)
        #expect(TaskExpiry.reachableDestination(mixed, from: 3, towards: 0) == 2)
    }

    @Test func aRowAlreadyAtTheBoundaryStaysPut() {
        #expect(TaskExpiry.reachableDestination(mixed, from: 1, towards: 2) == 1)
        #expect(TaskExpiry.reachableDestination(mixed, from: 2, towards: 0) == 2)
    }

    @Test func aDestinationOffTheEndIsClampedAndABadSourceIsReturnedUnchanged() {
        #expect(TaskExpiry.reachableDestination(mixed, from: 2, towards: 9) == 3)
        #expect(TaskExpiry.reachableDestination(mixed, from: 1, towards: -4) == 0)
        #expect(TaskExpiry.reachableDestination(mixed, from: 7, towards: 0) == 7)
        #expect(TaskExpiry.reachableDestination([], from: 0, towards: 1) == 0)
    }
}

/// The drag, replayed against the model the way `CategoryList`'s gesture runs
/// it: one `Reorder.destination` and one `dragCategory` per pointer event.
///
/// These exist because the gesture used to advance its own idea of where the
/// row was even when the model refused the move. From then on it was steering
/// a different row: dragging a task down past two categories swapped the two
/// categories, and the store kept the swap.
@MainActor
@Suite struct TaskBoundaryDragTests {

    /// Thirty points a row; the pointer moves two points an event.
    private func drag(_ m: AppModel, from start: Int, by distance: CGFloat) {
        var current = start
        let step: CGFloat = distance < 0 ? -2 : 2
        for translation in stride(from: CGFloat(0), through: distance, by: step) {
            let wanted = Reorder.destination(from: start, current: current,
                                             translation: translation, pitch: 30,
                                             count: m.settings.categories.count)
            if wanted != current {
                current = m.dragCategory(from: current, towards: wanted)
            }
        }
    }

    private func names(_ m: AppModel) -> [String] { m.settings.categories.map(\.name) }

    @Test func draggingATaskDownPastTheCategoriesMovesNothing() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "A", dailyGoal: 1)
        m.addCategory(name: "B", dailyGoal: 1)
        m.addTask(name: "T", goal: 1)
        #expect(names(m) == ["T", "A", "B"], "precondition")

        drag(m, from: 0, by: 62)

        #expect(names(m) == ["T", "A", "B"])
    }

    @Test func draggingACategoryUpIntoTheTasksLeavesTheTasksInOrder() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "A", dailyGoal: 1)
        m.addCategory(name: "B", dailyGoal: 1)
        m.addTask(name: "T1", goal: 1)
        m.addTask(name: "T2", goal: 1)
        #expect(names(m) == ["T2", "T1", "A", "B"], "precondition")

        drag(m, from: 2, by: -62)

        #expect(names(m) == ["T2", "T1", "A", "B"])
    }

    /// The boundary stops the row; it does not pin it. A category dragged from
    /// the bottom to above the tasks still rises to the top of the categories.
    @Test func aCategoryDraggedPastTheBoundaryStopsAtTheTopOfItsBlock() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "A", dailyGoal: 1)
        m.addCategory(name: "B", dailyGoal: 1)
        m.addTask(name: "T", goal: 1)

        drag(m, from: 2, by: -62)

        #expect(names(m) == ["T", "B", "A"])
    }

    @Test func dragCategoryReportsWhereTheRowActuallyIs() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "A", dailyGoal: 1)
        m.addCategory(name: "B", dailyGoal: 1)
        m.addTask(name: "T", goal: 1)

        #expect(m.dragCategory(from: 0, towards: 2) == 0, "a task cannot leave the task block")
        #expect(m.dragCategory(from: 1, towards: 2) == 2)
        #expect(m.dragCategory(from: 9, towards: 0) == 9, "a bad index moves nothing")
    }
}
