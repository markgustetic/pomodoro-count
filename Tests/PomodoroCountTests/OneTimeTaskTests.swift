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

    // MARK: Adding

    @Test func addingATaskPutsItOnTopAndAimsAtIt() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.settings.sessionTargetName = "Work"

        #expect(m.addTask(name: "  Report ", goal: 2))
        #expect(m.settings.categories.map(\.name) == ["Report", "Work"])
        #expect(m.settings.categories[0].expiresOn == today)
        #expect(m.settings.categories[0].dailyGoal == 2)
        #expect(m.sessionTarget == .named("Report"))
        #expect(!m.settings.targetPinned)
        #expect(cal.isDateInToday(m.settings.targetAimedOn!))
    }

    @Test func aTaskCannotShadowACategoryOrTheBucket() {
        let (m, _) = makeMixedModel()
        #expect(!m.addTask(name: "work", goal: 1))
        #expect(!m.addTask(name: "General", goal: 1))
        #expect(!m.addTask(name: "report", goal: 1))
        #expect(m.settings.categories.count == 4)
    }

    @Test func aTaskNeedsAGoal() {
        let (m, _) = makeMixedModel()
        #expect(!m.addTask(name: "Nothing", goal: 0))
        #expect(m.addTask(name: "Lots", goal: 99))
        #expect(m.settings.categories[0].dailyGoal == 20)
    }

    @Test func addedTasksSurviveReload() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.addTask(name: "Report", goal: 2)
        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.settings.categories.map(\.name) == ["Report"])
        #expect(reloaded.settings.categories[0].isTask)
    }

    @Test func addingATaskDuringARunningSessionLeavesTheTargetAlone() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.settings.sessionTargetName = "Work"
        m.toggle()
        #expect(m.isRunning)

        #expect(m.addTask(name: "Report", goal: 1))
        #expect(m.settings.categories.map(\.name) == ["Report", "Work"])
        #expect(m.sessionTarget == .named("Work"))
    }

    @Test func aReaddedNameThatIsAlreadyMetPins() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        // "Report" is archived, not a current category — its two records are
        // history a re-added task should reunite with.
        m.records = [
            Record(at: Date(), source: "manual", category: "Report"),
            Record(at: Date(), source: "manual", category: "Report"),
        ]
        #expect(m.addTask(name: "Report", goal: 2))
        #expect(m.settings.targetPinned)
    }

    // MARK: Expiry

    @Test func expireTasksDropsYesterdaysAndKeepsTodays() {
        let (m, _) = makeMixedModel()
        m.settings.categories[0].expiresOn = yesterday
        m.records = [Record(at: .daysAgo(1), source: "manual", category: "Report")]
        m.expireTasks()
        #expect(m.settings.categories.map(\.name) == ["Bug", "Work", "Music"])
        #expect(m.records.map(\.category) == ["Report"], "records keep the name")
    }

    @Test func expiringThePinnedTargetClearsThePin() {
        let (m, _) = makeMixedModel()
        m.settings.categories[0].expiresOn = yesterday
        m.settings.sessionTargetName = "Report"
        m.settings.targetPinned = true
        m.expireTasks()
        #expect(!m.settings.targetPinned)
    }

    @Test func expiringSomethingElseLeavesThePinAlone() {
        let (m, _) = makeMixedModel()
        m.settings.categories[0].expiresOn = yesterday
        m.settings.sessionTargetName = "Work"
        m.settings.targetPinned = true
        m.expireTasks()
        #expect(m.settings.targetPinned)
    }

    @Test func aNewDayDropsTheTaskAndReaimsAtTheFirstStandingCategory() {
        let (m, _) = makeMixedModel()
        m.settings.sessionTargetName = "Report"
        // Aimed yesterday, as it will have been the morning after: the
        // earlier-day stamp is what makes `realignTarget()` restart at the
        // top of the ranking rather than leave an unknown name in place.
        m.settings.targetAimedOn = .daysAgo(1)
        m.handleDayChange(now: tomorrow())
        #expect(m.settings.categories.map(\.name) == ["Work", "Music"])
        #expect(m.sessionTarget == .named("Work"))
    }

    @Test func aStoreWithAnExpiredTaskLoadsWithoutIt() {
        let (m, url) = makeMixedModel()
        m.settings.categories[0].expiresOn = yesterday
        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.settings.categories.map(\.name) == ["Bug", "Work", "Music"])
    }

    @Test func aRemovedTaskStillCountsInHistory() {
        let (m, _) = makeMixedModel()
        m.records = [Record(at: Date(), source: "manual", category: "Report")]
        m.removeCategory(id: m.settings.categories[0].id)
        #expect(m.categoryTotals(days: 7).contains { $0.name == "Report" && $0.count == 1 })
    }

    @Test func aSessionRunningAcrossMidnightKeepsItsTask() {
        let (m, _) = makeMixedModel()
        m.settings.sessionTargetName = "Report"
        m.settings.targetAimedOn = Date()
        m.toggle()
        #expect(m.isRunning)

        m.handleDayChange(now: tomorrow())
        #expect(m.settings.categories.map(\.name).first == "Report",
               "the task survives a day change while its session is running")

        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Report",
               "the record that finishes the session lands on what Start was pressed against")
    }

    @Test func withAutoAdvanceOffAnExpiredTargetFallsToTheBucket() {
        let (m, _) = makeMixedModel()
        m.settings.autoAdvanceTarget = false
        m.settings.sessionTargetName = "Report"
        m.handleDayChange(now: tomorrow())
        #expect(m.sessionTarget == .fallback)
    }

    @Test func aFileWithoutExpiresOnLoadsStandingCategories() throws {
        let url = try storeURL(containing: #"""
        {"records":[],"settings":{"categoriesEnabled":true,
         "categories":[{"id":"1E1C0D2B-0000-4000-8000-000000000001","name":"Work","dailyGoal":2}]}}
        """#)
        let m = AppModel(storeURL: url)
        #expect(m.settings.categories.map(\.isTask) == [false])
    }
}
