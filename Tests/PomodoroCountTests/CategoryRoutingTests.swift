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

    @Test func automaticGoesToTheBucketByDefault() {
        let m = configured()
        m.logExternal()
        #expect(m.records.first?.category == nil)
    }

    @Test func automaticUsesTheMarkedDefaultWhenTheBucketIsOff() {
        let m = configured()
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Work"
        m.logExternal()
        #expect(m.records.first?.category == "Work")
    }

    /// Archiving the marked default must not leave a pomodoro nowhere to go.
    @Test func aMissingDefaultFallsBackToTheFirstCategory() {
        let m = configured()
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Deleted"
        m.logExternal()
        #expect(m.records.first?.category == "Work")
    }

    @Test func withNoCategoriesAtAllItUsesTheBucketRegardless() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Deleted"
        m.logExternal()
        #expect(m.records.first?.category == nil)
    }

    @Test func explicitFallbackAlwaysMeansTheBucket() {
        let m = configured()
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Work"
        m.logExternal(to: .fallback)
        #expect(m.records.first?.category == nil)
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
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Work"
        m.logExternal()
        #expect(m.records.first?.category == nil)
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
