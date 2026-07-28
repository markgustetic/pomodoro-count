import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryRoutingTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        return m
    }

    @Test func tappingACategoryCreditsIt() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        #expect(m.records.first?.category == "Music")
    }

    /// Anything that wasn't aimed at a category lands in the bucket. There is no
    /// longer a second answer to this question — the bucket is always there.
    @Test func anUntargetedPomodoroGoesToTheBucket() {
        let m = configured()
        m.logExternal()
        #expect(m.records.first?.category == nil)
    }

    @Test func withNoCategoriesAtAllItStillHasSomewhereToGo() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.logExternal()
        #expect(m.records.first?.category == nil)
    }

    /// Removing the last category leaves the panel with no log rows, but the
    /// hotkey and a running session can both still fire. Neither may drop a
    /// pomodoro on the floor.
    @Test func emptyingTheCategoryListStillLeavesTheBucket() {
        let m = configured()
        for category in m.settings.categories { m.removeCategory(id: category.id) }
        m.logExternal()
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.count == 2)
        #expect(m.records.allSatisfy { $0.category == nil })
        #expect(m.todayProgress.map(\.name) == [m.settings.fallbackName])
    }

    @Test func explicitFallbackMeansTheBucket() {
        let m = configured()
        m.logExternal(to: .fallback)
        #expect(m.records.first?.category == nil)
    }

    /// The panel's "towards …" control must name the category the pomodoro will
    /// actually be credited to. These drifted apart once before: the label
    /// assumed an unset target meant the bucket while `resolve` sent it to a
    /// real category, so the panel read "towards General" while outlining Work
    /// and filing the pomodoro under Work.
    @Test func theTargetLabelIsWhereThePomodoroActuallyLands() {
        for target in [CategoryTarget.fallback, .named("Work"), .named("Music")] {
            let m = configured()
            m.sessionTarget = target
            let promised = m.sessionTargetLabel      // what the panel says
            m.startWork()
            m.forceCompleteForTesting()
            let landed = m.records.last?.category ?? m.settings.fallbackName
            #expect(promised == landed)
        }
    }

    /// The same must hold for a target that has since been archived.
    @Test func theTargetLabelIsHonestAfterItsCategoryIsArchived() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categories.removeAll { $0.name == "Music" }

        let promised = m.sessionTargetLabel
        m.startWork()
        m.forceCompleteForTesting()
        #expect(promised == (m.records.last?.category ?? m.settings.fallbackName))
        #expect(promised == m.settings.fallbackName)
    }

    /// The hotkey never uses the timer's target.
    @Test func theHotkeyIgnoresTheSessionTarget() {
        let m = configured()
        m.settings.sessionTargetName = "Music"
        m.logExternal(announce: false)
        #expect(m.records.first?.category == nil)
    }

    @Test func withTheFeatureOffEverythingIsUncategorised() {
        let (m, _) = makeModel()
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.logExternal()
        #expect(m.records.first?.category == nil)
    }

    /// Switching categories off hides the bucket rather than exposing a lone
    /// "General" row: with the feature off the panel shows the plain log
    /// button, and nothing should be offering category rows behind it.
    @Test func theBucketIsHiddenWhileCategoriesAreOff() {
        let (m, _) = makeModel()
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.logExternal()   // lands in the bucket, but must not surface one
        #expect(m.todayProgress.isEmpty)
        #expect(m.categoryTotals(days: 7).isEmpty)
    }

    /// Undo stays global — it removes the newest pomodoro whatever category it
    /// is in, rather than the newest within some current category.
    @Test func undoRemovesTheNewestRegardlessOfCategory() {
        let m = configured()
        m.records = [
            Record(at: .daysAgo(1), source: "manual", category: "Work"),
            Record(at: Date(), source: "manual", category: "Music"),
        ]
        m.undoLast()
        #expect(m.records.map(\.category) == ["Work"])
    }

    // MARK: resolve(.named:)

    /// A non-canonical spelling must never enter a record — `resolve` returns
    /// the category's own stored name whenever one matches.
    @Test func resolveNamedReturnsTheCanonicalStoredSpelling() {
        let m = configured()   // "Work" is the stored spelling
        #expect(m.resolve(.named("wORk")) == "Work")
        #expect(m.resolve(.named("  work  ")) == "Work")
    }

    @Test func resolveNamedWithTheFeatureOffResolvesToNil() {
        let (m, _) = makeModel()
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        // categoriesEnabled left at its default (false).
        #expect(m.resolve(.named("Work")) == nil)
    }
}
