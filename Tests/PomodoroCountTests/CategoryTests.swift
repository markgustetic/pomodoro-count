import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryTests {

    @Test func categoriesAreOffByDefault() {
        let (m, _) = makeModel()
        #expect(!m.settings.categoriesEnabled)
        #expect(m.settings.categories.isEmpty)
        #expect(m.settings.usesFallbackBucket)
        #expect(m.settings.fallbackName == "General")
        #expect(m.settings.fallbackGoal == 0)
        #expect(m.settings.defaultCategoryName == nil)
        #expect(m.settings.sessionTargetName == nil)
    }

    @Test func categoriesSurviveReload() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.settings.categoriesEnabled)
        #expect(reloaded.settings.categories.map(\.name) == ["Work", "Music"])
        #expect(reloaded.settings.categories.map(\.dailyGoal) == [4, 1])
    }

    /// A data.json from before this feature must load with categories off.
    @Test func olderFilesDefaultToCategoriesOff() throws {
        let url = try storeURL(containing: #"{"records":[],"settings":{"workMinutes":25}}"#)
        let m = AppModel(storeURL: url)
        #expect(!m.settings.categoriesEnabled)
        #expect(m.settings.categories.isEmpty)
        #expect(m.settings.fallbackName == "General")
    }

    @Test func normalizedNameTrimsAndLowercases() {
        #expect(Category.normalized("  Work  ") == "work")
        #expect(Category.normalized("AI Study") == "ai study")
        #expect(Category.normalized("WORK") == Category.normalized("work"))
    }

    @Test func categoriesGetDistinctIdentities() {
        let a = Category(name: "Work", dailyGoal: 4)
        let b = Category(name: "Work", dailyGoal: 4)
        #expect(a.id != b.id)
    }
}
