import Testing
import Foundation
@testable import PomodoroCount

/// `--preview` rasterises whatever model it is handed, so *which* model it
/// builds is the whole of what can go wrong with it. A preview of the wrong
/// state is worse than no preview at all, because it looks like an answer:
/// this renderer used to hardcode its demo categories and ignore `--store`
/// outright, so three renders against three seeded stores came back
/// byte-identical and anything concluded from them was about the demo data.
@MainActor
@Suite struct PreviewModelTests {

    @Test func withoutAStoreThePreviewShowsItsOwnDemoState() throws {
        let model = try PreviewRenderer.model(storePath: nil)

        #expect(model.settings.categories.map(\.name) == ["Work", "AI study", "Music"])
        #expect(model.records.isEmpty == false)
    }

    @Test func aStoreReplacesTheDemoStateEntirely() throws {
        let (seed, url) = makeModel()
        seed.settings.categoriesEnabled = true
        seed.settings.categories = [Category(name: "Thesis", dailyGoal: 3)]
        seed.records = [Record(at: Date(), source: "manual", category: "Thesis")]

        let model = try PreviewRenderer.model(storePath: url.path)

        #expect(model.settings.categories.map(\.name) == ["Thesis"])
        #expect(model.totalCount == 1)
    }

    /// The render mutates the model it renders — `--armed-break` completes a
    /// whole focus session, `--theme` writes a setting — and `AppModel` saves
    /// on `didSet`. Aimed straight at the file, previewing a store would edit
    /// the state you asked it to show, and previewing the real store would log
    /// a pomodoro into the user's own history.
    @Test func previewingAStoreDoesNotWriteBackToIt() throws {
        let (seed, url) = makeModel()
        seed.settings.categories = [Category(name: "Thesis", dailyGoal: 3)]
        let before = try Data(contentsOf: url)

        let model = try PreviewRenderer.model(storePath: url.path)
        model.settings.theme = .synthwave
        model.records.append(Record(at: Date(), source: "manual"))

        #expect(try Data(contentsOf: url) == before)
    }

    /// The failure this flag path exists to end is a silently wrong render, so
    /// a store that isn't there has to say so. Falling back to the demo model
    /// would rebuild the original bug one typo at a time.
    @Test func aStoreThatIsNotThereIsAnErrorRatherThanTheDemoModel() {
        let missing = temporaryStoreURL().path

        #expect(throws: PreviewRenderer.StoreError.self) {
            _ = try PreviewRenderer.model(storePath: missing)
        }
    }
}
