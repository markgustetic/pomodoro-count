import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct OneTimeTaskTests {

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: today)! }
    private func tomorrow() -> Date { cal.date(byAdding: .day, value: 1, to: Date())! }

    /// Categories on, two tasks above two standing categories.
    private func makeMixedModel() -> (AppModel, URL) {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Report", dailyGoal: 2, expiresOn: today),
            Category(name: "Bug", dailyGoal: 1, expiresOn: today),
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        return (m, url)
    }

    // MARK: Reorder

    @Test func aMoveAcrossTheTaskBoundaryChangesNothing() {
        let (m, _) = makeMixedModel()
        m.moveCategory(from: 1, to: 2)
        #expect(m.settings.categories.map(\.name) == ["Report", "Bug", "Work", "Music"])
        m.nudgeCategory(id: m.settings.categories[2].id, by: -1)
        #expect(m.settings.categories.map(\.name) == ["Report", "Bug", "Work", "Music"])
    }

    @Test func aMoveWithinTheTasksStillWorks() {
        let (m, _) = makeMixedModel()
        m.moveCategory(from: 0, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Bug", "Report", "Work", "Music"])
    }

    // MARK: Progress rows

    @Test func todayProgressMarksTasks() {
        let (m, _) = makeMixedModel()
        let rows = m.todayProgress
        #expect(rows.map(\.isTask) == [true, true, false, false, false])
    }

    @Test func aTaskRowSaysTodayOnlyToVoiceOver() {
        let row = CategoryProgress(id: "x", name: "Report", done: 1, goal: 2,
                                   isFallback: false, isTarget: true, isTask: true)
        #expect(row.accessibilityValue == "1 of 2 pomodoros, session target, today only")
        let standing = CategoryProgress(id: "y", name: "Work", done: 0, goal: 0,
                                        isFallback: false, isTarget: false)
        #expect(standing.accessibilityValue == "0 pomodoros")
    }
}
