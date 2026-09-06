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
}
