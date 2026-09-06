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
}
