# Categories with Daily Goals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user group pomodoros into named categories with daily goals, assigned by tapping a row in the menu bar panel, entirely optional and off by default.

**Architecture:** Records reference a category by **name** (`String?`, `nil` = fallback bucket) so re-adding a name reunites it with its history; renaming rewrites records in one pass. All category maths lives in a new `Category.swift`; the panel rows live in `CategoryRows.swift`. Two oversized view files are split first to make room.

**Tech Stack:** Swift 5.9 / SwiftUI / AppKit, macOS 14+, swift-testing, no new dependencies.

**Spec:** [`docs/superpowers/specs/2026-07-27-categories-design.md`](../specs/2026-07-27-categories-design.md)

## Global Constraints

Every task's requirements implicitly include these.

- **Feature is opt-in.** With `settings.categoriesEnabled == false`, `statusText`, panel content, and the History tab must be identical to today.
- **No `schemaVersion` bump.** `Record.category` is optional, so old `data.json` files decode unchanged. `AppModel.currentSchemaVersion` stays `1`.
- **No new third-party dependencies.** Sparkle remains the only one.
- **Goal range is `0...20`.** `0` means "track it, no goal" and renders a bare count.
- **Dots threshold is 8.** `goal > 0 && goal <= 8` draws dots; a goal above 8 draws a progress bar.
- **Names are unique** across categories *and* `fallbackName`, compared case-insensitively after trimming whitespace.
- **Never destroy history.** Deleting a category archives it; its records keep their name and stay in totals, History, and CSV.
- **Every interactive element is accessible** — real `Button`s, labels and values, decorative art hidden. Colour alone never conveys state.
- **Panel is 300pt wide.** Lists that can grow scroll inside a cap rather than growing the panel.
- Run the full suite with `just test`. Run a single test with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <name>` —
  `just test` does **not** forward arguments.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/PomodoroCount/Category.swift` | **New.** `Category`, `CategoryTarget`, `CategoryProgress`, `CategoryTotal`, and the `AppModel` extension holding routing, progress, management and breakdown maths |
| `Sources/PomodoroCount/CategoryRows.swift` | **New.** The tappable row list, row rendering, empty state |
| `Sources/PomodoroCount/HistoryTab.swift` | **New (moved).** `HistoryTab`, later gains the grouping control |
| `Sources/PomodoroCount/SettingsTab.swift` | **New (moved).** `SettingsTab`, later gains the Categories section |
| `Sources/PomodoroCount/Model.swift` | `Record` gains `category`; `Settings` gains seven fields; `csvExport` gains a column |
| `Sources/PomodoroCount/RootView.swift` | Focus tab swaps hero button for rows; timer card gains the target pill |

---

### Task 1: Split HistoryTab and SettingsTab into their own files

A pure move with no behaviour change, done first so later tasks edit small files.

**Files:**
- Create: `Sources/PomodoroCount/HistoryTab.swift`
- Create: `Sources/PomodoroCount/SettingsTab.swift`
- Modify: `Sources/PomodoroCount/RootView.swift` (delete lines 226-469, the two `MARK` sections)

**Interfaces:**
- Consumes: nothing
- Produces: `HistoryTab` and `SettingsTab` unchanged in their own files

- [ ] **Step 1: Capture the current render as a baseline**

```bash
cd /Users/markgustetic/Programming/local-apps/pomodoro-count
./build-app.sh >/dev/null 2>&1
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview /tmp/before-split.png --theme classic
shasum -a 256 /tmp/before-split.png
```

Note the hash. A pure move must not change a single pixel.

- [ ] **Step 2: Move `HistoryTab` to its own file**

Cut everything from `// MARK: - History` (line 226) through the end of `struct HistoryTab` (line 382) out of `RootView.swift` and into a new `Sources/PomodoroCount/HistoryTab.swift`, prefixed with the imports it needs:

```swift
import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers
```

Do not change a character of the struct body.

- [ ] **Step 3: Move `SettingsTab` to its own file**

Cut `// MARK: - Settings` through the end of `struct SettingsTab` out of `RootView.swift` into `Sources/PomodoroCount/SettingsTab.swift`, prefixed with:

```swift
import SwiftUI
import AppKit
```

- [ ] **Step 4: Trim now-unused imports from RootView**

`RootView.swift` no longer needs `Charts` or `UniformTypeIdentifiers` (both were only used by `HistoryTab`). Its import block becomes:

```swift
import SwiftUI
import AppKit
```

- [ ] **Step 5: Build and run the full suite**

```bash
just test
```

Expected: `Test run with 104 tests in 13 suites passed`. No test should change.

- [ ] **Step 6: Verify the render is byte-identical**

```bash
./build-app.sh >/dev/null 2>&1
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview /tmp/after-split.png --theme classic
shasum -a 256 /tmp/after-split.png
```

Expected: the same hash as Step 1. If it differs, something changed that shouldn't have — diff the two files rather than proceeding.

- [ ] **Step 7: Commit**

```bash
git add Sources/PomodoroCount/
git commit -m "Split HistoryTab and SettingsTab into their own files

A pure move ahead of the categories work: RootView.swift was 469 lines with
three tabs inline. Verified by rendering the panel before and after and
comparing hashes -- byte-identical."
```

---

### Task 2: The Category type and its Settings fields

**Files:**
- Create: `Sources/PomodoroCount/Category.swift`
- Modify: `Sources/PomodoroCount/Model.swift` (the `Settings` struct and its `init(from:)`)
- Test: `Tests/PomodoroCountTests/CategoryTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `struct Category: Codable, Identifiable, Equatable { var id: UUID; var name: String; var dailyGoal: Int }`
  - `static func Category.normalized(_ name: String) -> String`
  - `Settings.categoriesEnabled: Bool`, `.categories: [Category]`, `.usesFallbackBucket: Bool`, `.fallbackName: String`, `.fallbackGoal: Int`, `.defaultCategoryName: String?`, `.sessionTargetName: String?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryTests
```

Expected: FAIL — `cannot find 'Category' in scope`.

- [ ] **Step 3: Create the Category type**

Create `Sources/PomodoroCount/Category.swift`:

```swift
import Foundation

/// A named bucket for pomodoros, with an optional daily goal.
///
/// Records reference a category by `name`, never by `id` — re-adding a category
/// with a previous name has to reunite it with that history. `id` exists so
/// SwiftUI list editing and reordering animate correctly.
struct Category: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// 0...20. Zero means the category is tracked without a target: its row
    /// shows a bare count and no dots.
    var dailyGoal: Int

    /// The form used for uniqueness comparisons. Names are compared
    /// case-insensitively with surrounding whitespace ignored, so "  Work " and
    /// "work" are the same category as far as the user is concerned.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
```

- [ ] **Step 4: Add the Settings fields**

In `Sources/PomodoroCount/Model.swift`, add to `struct Settings` immediately after `var showsCountInMenuBar = true`:

```swift
    // MARK: Categories (all opt-in; defaults reproduce today's behaviour exactly)

    /// The whole feature is off until the user turns it on.
    var categoriesEnabled = false
    /// The user's categories, in display order.
    var categories: [Category] = []
    /// The always-present bucket that catches untapped pomodoros.
    var usesFallbackBucket = true
    var fallbackName = "General"
    var fallbackGoal = 0
    /// Destination for untapped pomodoros when the bucket is switched off.
    var defaultCategoryName: String?
    /// Remembered target for the built-in timer. nil means the bucket.
    var sessionTargetName: String?
```

- [ ] **Step 5: Decode them field-by-field**

In the same file, add to `Settings.init(from:)` immediately after the `showsCountInMenuBar` line:

```swift
        categoriesEnabled     = try c.decodeIfPresent(Bool.self, forKey: .categoriesEnabled) ?? false
        categories            = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        usesFallbackBucket    = try c.decodeIfPresent(Bool.self, forKey: .usesFallbackBucket) ?? true
        fallbackName          = try c.decodeIfPresent(String.self, forKey: .fallbackName) ?? "General"
        fallbackGoal          = try c.decodeIfPresent(Int.self, forKey: .fallbackGoal) ?? 0
        defaultCategoryName   = try c.decodeIfPresent(String.self, forKey: .defaultCategoryName)
        sessionTargetName     = try c.decodeIfPresent(String.self, forKey: .sessionTargetName)
```

- [ ] **Step 6: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryTests
```

Expected: PASS, 5 tests.

- [ ] **Step 7: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add Sources/PomodoroCount/Category.swift Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/CategoryTests.swift
git commit -m "Add the Category type and its settings

All seven settings decode field-by-field with defaults that reproduce today's
behaviour, so an existing data.json loads with the feature off."
```

---

### Task 3: Record gains an optional category

**Files:**
- Modify: `Sources/PomodoroCount/Model.swift` (`struct Record`)
- Test: `Tests/PomodoroCountTests/CategoryMigrationTests.swift`

**Interfaces:**
- Consumes: `Category` (Task 2)
- Produces: `Record.category: String?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryMigrationTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryMigrationTests {

    /// Every pomodoro logged before this feature existed belongs to the bucket.
    @Test func oldRecordsDecodeWithNoCategory() throws {
        let url = try storeURL(containing: """
        {"records":[{"id":"E0E4B0A0-0000-0000-0000-000000000000",\
        "at":"2026-07-01T10:00:00Z","source":"manual"}],"settings":{}}
        """)
        let m = AppModel(storeURL: url)
        #expect(m.totalCount == 1)
        #expect(m.records.first?.category == nil)
    }

    @Test func categoriesSurviveTheRoundTrip() {
        let (m, url) = makeModel()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        #expect(AppModel(storeURL: url).records.first?.category == "Work")
    }

    @Test func aNilCategoryStaysNilThroughTheRoundTrip() {
        let (m, url) = makeModel()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(AppModel(storeURL: url).records.first?.category == nil)
    }

    /// The optional field must not force a schema bump.
    @Test func schemaVersionIsUnchanged() {
        #expect(AppModel.currentSchemaVersion == 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryMigrationTests
```

Expected: FAIL — `extra argument 'category' in call`.

- [ ] **Step 3: Add the field**

In `Sources/PomodoroCount/Model.swift`, change `struct Record`:

```swift
/// A single completed pomodoro. `source` is "timer" (finished in-app) or
/// "manual" (logged from external hardware — the whole point of this app).
struct Record: Codable, Identifiable {
    var id = UUID()
    var at: Date
    var source: String
    /// The category NAME, or nil for the fallback bucket. Optional so that
    /// Swift's synthesized decoder treats it as decodeIfPresent and every
    /// existing data.json still loads.
    var category: String?
}
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryMigrationTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/CategoryMigrationTests.swift
git commit -m "Give Record an optional category

Optional so the synthesized decoder treats it as decodeIfPresent -- every
existing data.json loads untouched and no schemaVersion bump is needed."
```

---

### Task 4: Routing — where an untapped pomodoro goes

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift` (add the `AppModel` extension)
- Modify: `Sources/PomodoroCount/Model.swift` (`logExternal`, and `complete()`'s timer record)
- Test: `Tests/PomodoroCountTests/CategoryRoutingTests.swift`

**Interfaces:**
- Consumes: `Category`, `Settings.categories`, `.usesFallbackBucket`, `.defaultCategoryName` (Task 2); `Record.category` (Task 3)
- Produces:
  - `enum CategoryTarget: Equatable { case automatic, fallback, named(String) }`
  - `AppModel.resolve(_ target: CategoryTarget) -> String?`
  - `AppModel.automaticCategoryName: String?` (computed; the default chain).
    Deliberately **not** named `defaultCategoryName` — that is the stored
    `Settings` field this computed property consults.
  - `AppModel.categoryExists(_ name: String) -> Bool`
  - `AppModel.logExternal(to target: CategoryTarget = .automatic, announce: Bool = false)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryRoutingTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryRoutingTests
```

Expected: FAIL — `cannot find 'CategoryTarget' in scope`.

- [ ] **Step 3: Add the target type and the resolution chain**

Append to `Sources/PomodoroCount/Category.swift`:

```swift
/// Where a pomodoro should be filed.
///
/// `.automatic` means "work it out" — used by the global hotkey and by a timer
/// session with no target. `.fallback` is an explicit request for the bucket,
/// which is not the same thing: with the bucket switched off, `.automatic`
/// resolves to a real category while `.fallback` still means the bucket.
enum CategoryTarget: Equatable {
    case automatic
    case fallback
    case named(String)
}

@MainActor
extension AppModel {

    /// The category a pomodoro lands in when nothing was chosen.
    ///
    /// Order: the marked default when the bucket is off and it still exists;
    /// then the bucket; then the first category in display order; then the
    /// bucket regardless. The last two exist so archiving the marked default can
    /// never leave a pomodoro with nowhere to go.
    var automaticCategoryName: String? {
        guard settings.categoriesEnabled else { return nil }
        guard !settings.usesFallbackBucket else { return nil }

        if let marked = settings.defaultCategoryName, categoryExists(marked) {
            return marked
        }
        return settings.categories.first?.name
    }

    func resolve(_ target: CategoryTarget) -> String? {
        switch target {
        case .automatic:      return automaticCategoryName
        case .fallback:       return nil
        case .named(let name): return settings.categoriesEnabled ? name : nil
        }
    }

    /// True when a category with this name is currently in the list. Archived
    /// names return false — they hold history but receive nothing new.
    func categoryExists(_ name: String) -> Bool {
        let wanted = Category.normalized(name)
        return settings.categories.contains { Category.normalized($0.name) == wanted }
    }
}
```

- [ ] **Step 4: Route logExternal through it**

In `Sources/PomodoroCount/Model.swift`, replace the body of `logExternal`:

```swift
    /// Records a pomodoro completed outside the app, e.g. on a physical timer.
    /// `announce` (used by the global hotkey) also posts a confirmation banner,
    /// since the panel may not be open to show the count change.
    func logExternal(to target: CategoryTarget = .automatic, announce: Bool = false) {
        records.append(Record(at: Date(), source: "manual", category: resolve(target)))
        play(.countUp)
        if announce {
            notify("Pomodoro logged", "That's \(todayCount) today.")
        }
    }
```

The global hotkey in `syncGlobalShortcut()` already calls `logExternal(announce: true)`, which now means `.automatic` — exactly the spec's rule that the hotkey ignores the session target. Leave that call site alone.

- [ ] **Step 5: Route the timer's completion the same way**

In `complete()`, change the timer's record so it is categorised too. Task 8 will make this honour `sessionTargetName`; for now `.automatic` keeps it consistent:

```swift
            records.append(Record(at: Date(), source: "timer", category: resolve(.automatic)))
```

- [ ] **Step 6: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryRoutingTests
```

Expected: PASS, 8 tests.

- [ ] **Step 7: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add Sources/PomodoroCount/Category.swift Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/CategoryRoutingTests.swift
git commit -m "Route pomodoros to a category

The default chain ends at the bucket twice over, so archiving the marked
default can never leave a pomodoro with nowhere to go. .automatic and
.fallback are deliberately distinct: with the bucket off, .automatic picks a
real category while .fallback still means the bucket."
```

---

### Task 5: Progress — counts, goals, and what a row shows

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift`
- Test: `Tests/PomodoroCountTests/CategoryProgressTests.swift`

**Interfaces:**
- Consumes: `Category`, `CategoryTarget`, `AppModel.categoryExists` (Task 4)
- Produces:
  - `struct CategoryProgress: Identifiable { let id: String; let name: String; let done: Int; let goal: Int; let isFallback: Bool; var isMet: Bool; var showsDots: Bool; var accessibilityValue: String }`
  - `AppModel.todayCount(inCategory name: String?) -> Int`
  - `AppModel.todayProgress: [CategoryProgress]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryProgressTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryProgressTests {

    private func configured(bucket: Bool = true) -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.usesFallbackBucket = bucket
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "AI study", dailyGoal: 1),
        ]
        return m
    }

    @Test func countsOnlyTodaysPomodorosInThatCategory() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: Date(), source: "manual", category: "AI study"),
            Record(at: .daysAgo(1), source: "manual", category: "Work"),
        ]
        #expect(m.todayCount(inCategory: "Work") == 2)
        #expect(m.todayCount(inCategory: "AI study") == 1)
    }

    @Test func theBucketCountsRecordsWithNoCategory() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual"),
            Record(at: Date(), source: "manual", category: "Work"),
        ]
        #expect(m.todayCount(inCategory: nil) == 1)
    }

    @Test func categoryNamesMatchCaseInsensitively() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "work")]
        #expect(m.todayCount(inCategory: "Work") == 1)
    }

    @Test func progressListsEveryCategoryThenTheBucket() {
        let m = configured()
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study", "General"])
        #expect(m.todayProgress.last?.isFallback == true)
    }

    @Test func theBucketIsAbsentWhenSwitchedOffAndEmpty() {
        let m = configured(bucket: false)
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study"])
    }

    /// Switching the bucket off keeps it visible while it still holds pomodoros.
    @Test func theBucketStaysWhileItHoldsPomodoros() {
        let m = configured(bucket: false)
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.todayProgress.map(\.name) == ["Work", "AI study", "General"])
    }

    @Test func aGoalIsMetOnlyWhenReached() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "AI study")]
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(ai.isMet)
        #expect(!work.isMet)
    }

    @Test func overshootingKeepsCounting() {
        let m = configured()
        m.records = (0..<6).map { _ in Record(at: Date(), source: "manual", category: "Work") }
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.done == 6)
        #expect(work.goal == 4)
        #expect(work.isMet)
    }

    @Test func aGoalOfZeroIsNeverMetAndDrawsNoDots() {
        let m = configured()
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.goal == 0)
        #expect(!bucket.isMet)
        #expect(!bucket.showsDots)
    }

    @Test(arguments: [(1, true), (8, true), (9, false), (20, false)])
    func dotsGiveWayToABarAboveEight(goal: Int, expectsDots: Bool) {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.usesFallbackBucket = false
        m.settings.categories = [Category(name: "X", dailyGoal: goal)]
        #expect(m.todayProgress.first?.showsDots == expectsDots)
    }

    @Test func accessibilityValueSpellsOutProgress() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.accessibilityValue == "1 of 4 pomodoros")
    }

    /// A met goal must be conveyed in the value, not by colour alone.
    @Test func accessibilityValueSaysWhenAGoalIsMet() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "AI study")]
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        #expect(ai.accessibilityValue == "1 of 1 pomodoros, goal met")
    }

    @Test func accessibilityValueForAGoallessCategoryIsJustTheCount() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual")]
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.accessibilityValue == "1 pomodoro")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryProgressTests
```

Expected: FAIL — `value of type 'AppModel' has no member 'todayCount(inCategory:)'`.

- [ ] **Step 3: Add the progress type and computation**

Append to `Sources/PomodoroCount/Category.swift`:

```swift
/// One row in the panel: a category, how it is doing today, and how to say so.
struct CategoryProgress: Identifiable {
    let id: String
    let name: String
    let done: Int
    let goal: Int
    /// True for the fallback bucket, whose records carry no category name.
    let isFallback: Bool

    /// A goal of 0 means "no target", so it can never be met.
    var isMet: Bool { goal > 0 && done >= goal }

    /// One dot per goal unit is legible up to 8 and absurd at 20, so beyond
    /// that the row draws a bar in the same space.
    var showsDots: Bool { goal > 0 && goal <= 8 }

    /// What VoiceOver reads. A met goal is stated here rather than being left to
    /// the accent colour.
    var accessibilityValue: String {
        guard goal > 0 else {
            return "\(done) \(done == 1 ? "pomodoro" : "pomodoros")"
        }
        return "\(done) of \(goal) pomodoros" + (isMet ? ", goal met" : "")
    }
}

@MainActor
extension AppModel {

    /// Today's count for one category. Pass nil for the fallback bucket.
    func todayCount(inCategory name: String?) -> Int {
        let wanted = name.map(Category.normalized)
        return records.filter { record in
            guard Calendar.current.isDateInToday(record.at) else { return false }
            return record.category.map(Category.normalized) == wanted
        }.count
    }

    /// The panel's rows: every category in display order, then the fallback
    /// bucket. The bucket appears when it is switched on, and also while it
    /// still holds pomodoros after being switched off — the same rule an
    /// archived category follows.
    var todayProgress: [CategoryProgress] {
        var rows = settings.categories.map { category in
            CategoryProgress(
                id: category.id.uuidString,
                name: category.name,
                done: todayCount(inCategory: category.name),
                goal: category.dailyGoal,
                isFallback: false)
        }

        let bucketCount = todayCount(inCategory: nil)
        if settings.usesFallbackBucket || bucketCount > 0 {
            rows.append(CategoryProgress(
                id: "fallback",
                name: settings.fallbackName,
                done: bucketCount,
                goal: settings.fallbackGoal,
                isFallback: true))
        }
        return rows
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryProgressTests
```

Expected: PASS, 0 failures.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/Category.swift Tests/PomodoroCountTests/CategoryProgressTests.swift
git commit -m "Compute per-category progress for today

A goal of 0 can never be met and draws no dots, which is what lets the
fallback bucket be an ordinary row. Beyond a goal of 8 the row swaps dots for
a bar so it never reflows. A met goal is stated in the accessibility value
rather than left to the accent colour."
```

---

### Task 6: Managing categories — add, rename, archive, uniqueness

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift`
- Test: `Tests/PomodoroCountTests/CategoryManagementTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2-5
- Produces:
  - `AppModel.isCategoryNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool`
  - `@discardableResult AppModel.addCategory(name: String, dailyGoal: Int) -> Bool`
  - `@discardableResult AppModel.renameCategory(id: UUID, to newName: String) -> Bool`
  - `AppModel.removeCategory(id: UUID)`
  - `AppModel.moveCategories(fromOffsets: IndexSet, toOffset: Int)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryManagementTests.swift`:

```swift
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
        m.settings.usesFallbackBucket = false
        m.settings.defaultCategoryName = "Music"
        m.removeCategory(id: m.settings.categories[1].id)
        m.logExternal()
        #expect(m.records.first?.category == "Work")
    }

    // MARK: Reordering

    @Test func reorderingChangesDisplayOrder() {
        let m = configured()
        m.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryManagementTests
```

Expected: FAIL — `value of type 'AppModel' has no member 'addCategory'`.

- [ ] **Step 3: Implement the operations**

Append to `Sources/PomodoroCount/Category.swift`:

```swift
@MainActor
extension AppModel {

    /// Names must be unique across the user's categories and the fallback name.
    /// `excluding` lets a category keep its own name while being renamed.
    func isCategoryNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let wanted = Category.normalized(name)
        guard !wanted.isEmpty else { return false }
        guard wanted != Category.normalized(settings.fallbackName) else { return false }
        return !settings.categories.contains {
            $0.id != id && Category.normalized($0.name) == wanted
        }
    }

    /// Returns false and changes nothing when the name is empty or taken.
    @discardableResult
    func addCategory(name: String, dailyGoal: Int) -> Bool {
        guard isCategoryNameAvailable(name) else { return false }
        settings.categories.append(Category(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            dailyGoal: min(max(dailyGoal, 0), 20)))
        return true
    }

    /// Rewrites every record that referenced the old name, in one pass, so no
    /// history is orphaned. Returns false and changes nothing when the new name
    /// is empty or taken by a different category.
    @discardableResult
    func renameCategory(id: UUID, to newName: String) -> Bool {
        guard let index = settings.categories.firstIndex(where: { $0.id == id }),
              isCategoryNameAvailable(newName, excluding: id)
        else { return false }

        let old = Category.normalized(settings.categories[index].name)
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        for i in records.indices where records[i].category.map(Category.normalized) == old {
            records[i].category = trimmed
        }
        settings.categories[index].name = trimmed

        if settings.defaultCategoryName.map(Category.normalized) == old {
            settings.defaultCategoryName = trimmed
        }
        if settings.sessionTargetName.map(Category.normalized) == old {
            settings.sessionTargetName = trimmed
        }
        return true
    }

    /// Archives rather than deletes: the category leaves the list but its
    /// records keep their name, so History, totals and CSV are unchanged.
    func removeCategory(id: UUID) {
        settings.categories.removeAll { $0.id == id }
    }

    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        settings.categories.move(fromOffsets: source, toOffset: destination)
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryManagementTests
```

Expected: PASS, 16 tests.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/Category.swift Tests/PomodoroCountTests/CategoryManagementTests.swift
git commit -m "Add, rename, archive and reorder categories

Renaming rewrites every record that referenced the old name in one pass, plus
the marked default and session target, so nothing is orphaned. Removing
archives: the category leaves the list, its records keep their name, and
re-adding the name reunites them."
```

---

### Task 7: The category rows in the panel

**Files:**
- Create: `Sources/PomodoroCount/CategoryRows.swift`
- Modify: `Sources/PomodoroCount/RootView.swift` (the `logButton` computed property)
- Test: manual render check (the view layer has no headless test path)

**Interfaces:**
- Consumes: `CategoryProgress`, `AppModel.todayProgress` (Task 5); `CategoryTarget`, `logExternal(to:)` (Task 4)
- Produces: `struct CategoryRows: View` — takes no parameters, reads `AppModel` from the environment

- [ ] **Step 1: Create the rows view**

Create `Sources/PomodoroCount/CategoryRows.swift`:

```swift
import SwiftUI

/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row logs one pomodoro to that category.
struct CategoryRows: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let rows = model.todayProgress
        VStack(spacing: 5) {
            if rows.isEmpty {
                Text("Add a category in Settings")
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                // Six rows is roughly 200pt; past that the list scrolls so the
                // panel stops growing, the same rule the History day-list uses.
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(rows) { row in
                            CategoryRow(progress: row) {
                                model.logExternal(to: row.isFallback ? .fallback : .named(row.name))
                            }
                        }
                    }
                }
                .frame(maxHeight: rows.count > 6 ? 200 : .infinity)
                .fixedSize(horizontal: false, vertical: rows.count <= 6)
            }
        }
    }
}

/// One tappable category. A real Button, so VoiceOver and the keyboard reach it.
struct CategoryRow: View {
    let progress: CategoryProgress
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(progress.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if progress.showsDots {
                    dots
                } else if progress.goal > 0 {
                    bar
                }

                Text(progress.goal > 0 ? "\(progress.done)/\(progress.goal)" : "\(progress.done)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(progress.isMet ? palette.accent : palette.textDim)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.cardFill.opacity(hover ? 1.6 : 1.0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(palette.cardStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.name)
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityHint("Logs one pomodoro")
    }

    /// One dot per goal unit, filled up to what's done. Decorative — the count
    /// beside it carries the same information for VoiceOver.
    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(0..<progress.goal, id: \.self) { index in
                Circle()
                    .fill(index < progress.done ? palette.accent : palette.hairline)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        GeometryReader { geo in
            let fraction = min(1, Double(progress.done) / Double(max(1, progress.goal)))
            Capsule()
                .fill(palette.hairline)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [palette.accent, palette.accent2],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction)
                }
        }
        .frame(width: 60, height: 6)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Swap the hero button for the rows when categories are on**

In `Sources/PomodoroCount/RootView.swift`, replace the `logButton` computed property:

```swift
    private var logButton: some View {
        VStack(spacing: 6) {
            if model.settings.categoriesEnabled {
                CategoryRows()
            } else {
                // Logging is a one-tap errand: record it and get the panel out of
                // the way. The menu bar count updates behind it as confirmation.
                LogButton {
                    model.logExternal()
                    MenuBarPanel.dismiss()
                }
                .help("Record a pomodoro you finished on external hardware")
            }

            if model.todayCount > 0 {
                Button("Undo last", action: model.undoLast)
                    .buttonStyle(HoverTextButtonStyle())
                    .font(.caption)
            }
        }
    }
```

Note the panel deliberately stays open after tapping a row — unlike the single hero button, you may well be logging more than one.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -2
```

Expected: `Build complete!`

- [ ] **Step 4: Render the panel with categories on**

Temporarily seed categories in the preview renderer to check the layout. In `Sources/PomodoroCount/PreviewRenderer.swift`, after `model.records = seeded`, add:

```swift
        model.settings.categoriesEnabled = true
        model.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "AI study", dailyGoal: 1),
            Category(name: "Music", dailyGoal: 1),
        ]
```

Then:

```bash
./build-app.sh >/dev/null 2>&1
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview /tmp/rows.png --theme classic
open /tmp/rows.png
```

Check: three rows plus General, dots filled correctly, counts right-aligned and not clipped, nothing overflowing 300pt.

- [ ] **Step 5: Keep the seeding — it is what the README screenshots need**

Leave the preview seeding in place. Task 12 regenerates the published screenshots from it.

- [ ] **Step 6: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/PomodoroCount/CategoryRows.swift Sources/PomodoroCount/RootView.swift Sources/PomodoroCount/PreviewRenderer.swift
git commit -m "Show tappable category rows in the panel

Each row is a real Button carrying its own accessibility label and value, so
the primary logging surface is reachable by VoiceOver and the keyboard. Dots
up to a goal of 8, a bar above that, and the panel scrolls past six rows
rather than growing."
```

---

### Task 8: The session target pill

**Files:**
- Modify: `Sources/PomodoroCount/RootView.swift` (`focusTab`, `phaseSubtitle`)
- Modify: `Sources/PomodoroCount/Model.swift` (`complete()`)
- Test: `Tests/PomodoroCountTests/CategorySessionTests.swift`

**Interfaces:**
- Consumes: `CategoryTarget`, `resolve(_:)`, `categoryExists(_:)` (Task 4); `Settings.sessionTargetName` (Task 2)
- Produces: `AppModel.sessionTarget: CategoryTarget` (get/set, persisted via `settings.sessionTargetName`)

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategorySessionTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategorySessionTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        return m
    }

    @Test func theTargetDefaultsToTheBucket() {
        let m = configured()
        #expect(m.sessionTarget == .fallback)
    }

    @Test func settingTheTargetPersistsIt() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.sessionTarget = .named("Work")
        #expect(AppModel(storeURL: url).settings.sessionTargetName == "Work")
    }

    @Test func aFinishedSessionCreditsItsTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.records.last?.source == "timer")
    }

    /// An archived target must not strand the session's pomodoro.
    @Test func anArchivedTargetFallsBackToTheDefaultChain() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categories.removeAll { $0.name == "Music" }
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == nil)   // bucket is on
    }

    @Test func aBreakCreditsNothing() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.startBreak()
        m.forceCompleteForTesting()
        #expect(m.records.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategorySessionTests
```

Expected: FAIL — `value of type 'AppModel' has no member 'sessionTarget'`.

- [ ] **Step 3: Expose the target and a test hook for completion**

In `Sources/PomodoroCount/Model.swift`, add inside `AppModel` next to the other timer members:

```swift
    /// Which category a finished focus session credits. Persisted so it survives
    /// relaunch — re-picking it every day would be a papercut.
    var sessionTarget: CategoryTarget {
        get {
            guard let name = settings.sessionTargetName, categoryExists(name) else {
                return .fallback
            }
            return .named(name)
        }
        set {
            switch newValue {
            case .named(let name): settings.sessionTargetName = name
            case .fallback, .automatic: settings.sessionTargetName = nil
            }
        }
    }

    /// Drives the timer to completion immediately. Tests only — a real session
    /// takes 50 minutes.
    func forceCompleteForTesting() {
        remaining = 0
        complete()
    }
```

- [ ] **Step 4: Credit the target on completion**

In `complete()`, change the line added in Task 4 from `.automatic` to the session's target. `sessionTarget` already degrades to `.fallback` when the target was archived, and `.fallback` resolves to the bucket:

```swift
            records.append(Record(at: Date(), source: "timer",
                                  category: resolve(sessionTarget)))
```

- [ ] **Step 5: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategorySessionTests
```

Expected: PASS, 5 tests.

- [ ] **Step 6: Add the pill to the timer card**

In `Sources/PomodoroCount/RootView.swift`, inside `focusTab`, insert between the `phaseSubtitle` `Text` and the `HStack` of buttons:

```swift
            if model.settings.categoriesEnabled {
                Menu {
                    Button(model.settings.fallbackName) { model.sessionTarget = .fallback }
                    ForEach(model.settings.categories) { category in
                        Button(category.name) { model.sessionTarget = .named(category.name) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 7, height: 7)
                        Text("towards \(sessionTargetLabel)")
                            .font(.caption)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Session target")
                .accessibilityValue(sessionTargetLabel)
            }
```

And add the label helper next to `phaseSubtitle`:

```swift
    private var sessionTargetLabel: String {
        if case .named(let name) = model.sessionTarget { return name }
        return model.settings.fallbackName
    }
```

- [ ] **Step 7: Say where a running session is headed**

Change `phaseSubtitle` so a running session names its target:

```swift
    private var phaseSubtitle: String {
        let target = model.settings.categoriesEnabled ? " · \(sessionTargetLabel)" : ""
        switch model.phase {
        case .idle: return "Focus session · \(model.settings.workMinutes) min"
        case .work: return model.isRunning ? "Focus in progress\(target)" : "Paused"
        case .breakTime: return model.isRunning ? "Break time" : "Paused"
        }
    }
```

- [ ] **Step 8: Build, run everything, and eyeball the pill**

```bash
just test
./build-app.sh >/dev/null 2>&1
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview /tmp/pill.png --theme classic
open /tmp/pill.png
```

Expected: all tests pass, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add Sources/PomodoroCount/Model.swift Sources/PomodoroCount/RootView.swift Tests/PomodoroCountTests/CategorySessionTests.swift
git commit -m "Aim a focus session at a category

The target is visible before you press Start, and a running session names it
in the subtitle. Archiving the target degrades to the fallback chain rather
than stranding the session's pomodoro."
```

---

### Task 9: Managing categories in Settings

**Files:**
- Modify: `Sources/PomodoroCount/SettingsTab.swift`
- Test: manual render check

**Interfaces:**
- Consumes: `addCategory`, `renameCategory`, `removeCategory`, `moveCategories`, `isCategoryNameAvailable` (Task 6)
- Produces: no new API

- [ ] **Step 1: Make the Settings content scroll**

The tab is already the longest and this adds to it. In `SettingsTab.body`, wrap the existing `VStack(alignment: .leading, spacing: 12) { … }` in a `ScrollView` with a cap, matching the History day-list pattern:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // …existing content unchanged…
            }
        }
        .frame(maxHeight: 340)
        .toggleStyle(.switch)
        .tint(palette.accent)
        .font(.callout)
    }
```

Move the three trailing modifiers off the `VStack` and onto the `ScrollView` as shown.

- [ ] **Step 2: Add the Categories section**

Insert before the `if model.isBundled` block:

```swift
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Use categories", isOn: $model.settings.categoriesEnabled)

                if model.settings.categoriesEnabled {
                    ForEach(model.settings.categories) { category in
                        CategorySettingsRow(category: category)
                    }
                    .onMove { model.moveCategories(fromOffsets: $0, toOffset: $1) }

                    Button {
                        addCategory()
                    } label: {
                        Label("Add category", systemImage: "plus")
                    }
                    .buttonStyle(HoverTextButtonStyle())
                    .font(.caption)

                    Divider()

                    Toggle("Fallback category", isOn: $model.settings.usesFallbackBucket)
                    if model.settings.usesFallbackBucket {
                        HStack(spacing: 6) {
                            TextField("Name", text: $model.settings.fallbackName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Fallback category name")
                            Stepper(value: $model.settings.fallbackGoal, in: 0...20) {
                                Text("\(model.settings.fallbackGoal)")
                                    .font(.caption.monospacedDigit())
                            }
                            .accessibilityLabel("Fallback daily goal")
                        }
                    } else {
                        Picker("Default", selection: Binding(
                            get: { model.settings.defaultCategoryName ?? "" },
                            set: { model.settings.defaultCategoryName = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(model.settings.categories) { category in
                                Text(category.name).tag(category.name)
                            }
                        }
                        .accessibilityLabel("Default category for untapped pomodoros")
                    }
                }
            }
```

- [ ] **Step 3: Add the per-category row and the add action**

Add to the same file, outside `SettingsTab`:

```swift
/// One editable category: rename in place, adjust its goal, or archive it.
struct CategorySettingsRow: View {
    let category: Category
    @EnvironmentObject var model: AppModel
    @State private var draftName: String = ""
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(rejected ? Color.red : Color.primary)
                .onSubmit(commit)
                .onAppear { draftName = category.name }
                .accessibilityLabel("Category name")

            Stepper(value: Binding(
                get: { category.dailyGoal },
                set: { goal in
                    guard let i = model.settings.categories.firstIndex(where: { $0.id == category.id })
                    else { return }
                    model.settings.categories[i].dailyGoal = goal
                }
            ), in: 0...20) {
                Text("\(category.dailyGoal)")
                    .font(.caption.monospacedDigit())
            }
            .accessibilityLabel("\(category.name) daily goal")

            Button {
                model.removeCategory(id: category.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove — its pomodoros stay in your history")
            .accessibilityLabel("Remove \(category.name)")
        }
    }

    /// Renaming can fail on a collision, so the field snaps back rather than
    /// silently keeping a name the model rejected.
    private func commit() {
        if model.renameCategory(id: category.id, to: draftName) {
            rejected = false
        } else {
            rejected = true
            draftName = category.name
        }
    }
}
```

And inside `SettingsTab`:

```swift
    /// Names a new category "Category 2", "Category 3"… so adding never fails
    /// on a collision the user did not choose.
    private func addCategory() {
        var index = model.settings.categories.count + 1
        while !model.addCategory(name: "Category \(index)", dailyGoal: 1) {
            index += 1
            if index > 99 { return }
        }
    }
```

- [ ] **Step 4: Build and check the layout**

```bash
swift build 2>&1 | tail -2
./build-app.sh >/dev/null 2>&1
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview /tmp/settings.png --theme classic
open /tmp/settings.png
```

Expected: the Settings tab shows the Categories section, scrolls within its cap, and the panel is no taller than before.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/SettingsTab.swift
git commit -m "Manage categories in Settings

The tab was already the longest, so its content now scrolls inside a cap
rather than growing the panel. A rejected rename snaps the field back instead
of leaving a name the model refused."
```

---

### Task 10: The per-category breakdown in History

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift` (add `CategoryTotal` and `categoryTotals(days:)`)
- Modify: `Sources/PomodoroCount/HistoryTab.swift`
- Test: `Tests/PomodoroCountTests/CategoryBreakdownTests.swift`

**Interfaces:**
- Consumes: `Category.normalized`, `Settings.categories`, `.fallbackName` (Tasks 2, 5)
- Produces:
  - `struct CategoryTotal: Identifiable { let id: String; let name: String; let count: Int }`
  - `AppModel.categoryTotals(days: Int) -> [CategoryTotal]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryBreakdownTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

@MainActor
@Suite struct CategoryBreakdownTests {

    private func configured() -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 4),
            Category(name: "Music", dailyGoal: 1),
        ]
        return m
    }

    @Test func totalsRespectTheRange() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: .daysAgo(3), source: "manual", category: "Work"),
            Record(at: .daysAgo(20), source: "manual", category: "Work"),
        ]
        #expect(m.categoryTotals(days: 7).first { $0.name == "Work" }?.count == 2)
        #expect(m.categoryTotals(days: 30).first { $0.name == "Work" }?.count == 3)
    }

    /// A neglected category should be visible, not absent.
    @Test func currentCategoriesAppearEvenWithZeroInRange() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        let names = m.categoryTotals(days: 7).map(\.name)
        #expect(names.contains("Music"))
        #expect(m.categoryTotals(days: 7).first { $0.name == "Music" }?.count == 0)
    }

    @Test func archivedNamesAppearWhileTheyHaveRecordsInRange() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual", category: "Painting")]
        #expect(m.categoryTotals(days: 7).first { $0.name == "Painting" }?.count == 1)
    }

    @Test func archivedNamesVanishOnceOutOfRange() {
        let m = configured()
        m.records = [Record(at: .daysAgo(20), source: "manual", category: "Painting")]
        #expect(!m.categoryTotals(days: 7).contains { $0.name == "Painting" })
    }

    @Test func theBucketAppearsUnderItsName() {
        let m = configured()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.categoryTotals(days: 7).first { $0.name == "General" }?.count == 1)
    }

    @Test func orderIsDisplayOrderThenArchivedAlphabetically() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Zebra"),
            Record(at: Date(), source: "manual", category: "Antique"),
            Record(at: Date(), source: "manual"),
        ]
        let names = m.categoryTotals(days: 7).map(\.name)
        #expect(names.prefix(2) == ["Work", "Music"])
        #expect(names.dropFirst(2) == ["General", "Antique", "Zebra"])
    }

    @Test func totalsMatchTheDailySeriesTotal() {
        let m = configured()
        m.records = [
            Record(at: Date(), source: "manual", category: "Work"),
            Record(at: .daysAgo(2), source: "manual", category: "Music"),
            Record(at: .daysAgo(2), source: "manual"),
        ]
        let breakdown = m.categoryTotals(days: 7).map(\.count).reduce(0, +)
        let daily = m.dailySeries(days: 7).map(\.count).reduce(0, +)
        #expect(breakdown == daily)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryBreakdownTests
```

Expected: FAIL — `value of type 'AppModel' has no member 'categoryTotals'`.

- [ ] **Step 3: Implement the breakdown**

Append to `Sources/PomodoroCount/Category.swift`:

```swift
/// One row of the History breakdown.
struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let count: Int
}

@MainActor
extension AppModel {

    /// Totals per category over the last `days` days, ending today.
    ///
    /// Current categories come first in display order and appear even at zero —
    /// a neglected category should be visible, not absent. Then the bucket, then
    /// any archived names that still have records in range, alphabetically.
    func categoryTotals(days: Int) -> [CategoryTotal] {
        let calendar = Calendar.current
        let cutoff = calendar.date(
            byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
        let inRange = records.filter { $0.at >= cutoff }

        var counts: [String: Int] = [:]     // normalized name (or "") -> count
        for record in inRange {
            counts[record.category.map(Category.normalized) ?? "", default: 0] += 1
        }

        var totals = settings.categories.map { category in
            CategoryTotal(
                id: category.id.uuidString,
                name: category.name,
                count: counts.removeValue(forKey: Category.normalized(category.name)) ?? 0)
        }

        if let bucket = counts.removeValue(forKey: ""), bucket > 0 {
            totals.append(CategoryTotal(id: "fallback", name: settings.fallbackName, count: bucket))
        } else if settings.usesFallbackBucket {
            totals.append(CategoryTotal(id: "fallback", name: settings.fallbackName, count: 0))
        }

        // Whatever is left is archived: it has records in range but no category.
        // Their display name comes from the first record that used it, so the
        // user's original capitalisation survives.
        let archivedNames = Dictionary(
            grouping: inRange.compactMap(\.category),
            by: Category.normalized)
        for (normalized, count) in counts.sorted(by: { $0.key < $1.key }) {
            let display = archivedNames[normalized]?.first ?? normalized
            totals.append(CategoryTotal(id: "archived-\(normalized)", name: display, count: count))
        }

        return totals
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryBreakdownTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Add the grouping control to History**

In `Sources/PomodoroCount/HistoryTab.swift`, add to `HistoryTab`:

```swift
    enum Grouping: String, CaseIterable { case day = "By day", category = "By category" }
    @State private var grouping: Grouping = .day
```

Insert above the day list, after the `Export CSV…` button:

```swift
            if model.settings.categoriesEnabled {
                SegmentedControl(
                    items: Grouping.allCases.map { (value: $0, label: $0.rawValue) },
                    selection: $grouping,
                    accessibilityLabel: "Group history by")
            }
```

- [ ] **Step 6: Render the category rows when that grouping is chosen**

Replace the `if stats.isEmpty { … } else { … }` block's `else` branch so it switches on `grouping`. Extract the shared row into a small view in the same file so both groupings use identical rendering:

```swift
/// One bar row in the History list — used by both groupings so they stay
/// visually identical.
private struct HistoryBar: View {
    let label: String
    let count: Int
    let maxCount: Int
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.textDim)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            GeometryReader { geo in
                Capsule()
                    .fill(LinearGradient(colors: [palette.accent, palette.accent2],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                    .frame(maxHeight: .infinity, alignment: .center)
                    .neonGlow(palette.accent, enabled: palette.neon, radius: 4, opacity: 0.5)
            }
            .frame(height: 10)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(count) \(count == 1 ? "pomodoro" : "pomodoros")")
    }
}
```

Then the list body becomes:

```swift
                ScrollView {
                    VStack(spacing: 7) {
                        if grouping == .day || !model.settings.categoriesEnabled {
                            let maxCount = max(1, stats.map(\.count).max() ?? 1)
                            ForEach(stats) { s in
                                HistoryBar(label: model.dayLabel(s.date),
                                           count: s.count, maxCount: maxCount)
                            }
                        } else {
                            let totals = model.categoryTotals(days: range.days)
                            let maxCount = max(1, totals.map(\.count).max() ?? 1)
                            ForEach(totals) { t in
                                HistoryBar(label: t.name, count: t.count, maxCount: maxCount)
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)
```

- [ ] **Step 7: Build, test, and eyeball**

```bash
just test
./build-app.sh >/dev/null 2>&1
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview /tmp/history.png --theme classic
open /tmp/history.png
```

Expected: all tests pass, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add Sources/PomodoroCount/Category.swift Sources/PomodoroCount/HistoryTab.swift Tests/PomodoroCountTests/CategoryBreakdownTests.swift
git commit -m "Add a per-category breakdown to History

A By day / By category switch over the existing list, so the tab reuses space
rather than growing. Both groupings share one row view, so they can't drift
apart visually. Categories with zero in range still appear, and archived names
show up while they still have records in range."
```

---

### Task 11: The category column in CSV export

**Files:**
- Modify: `Sources/PomodoroCount/Model.swift` (`csvExport`)
- Test: `Tests/PomodoroCountTests/ExportTests.swift` (extend the existing suite)

**Interfaces:**
- Consumes: `Record.category` (Task 3), `Settings.fallbackName` (Task 2)
- Produces: no new API — `csvExport()` gains a third column

- [ ] **Step 1: Write the failing tests**

Append to the existing `ExportTests` suite in `Tests/PomodoroCountTests/ExportTests.swift`:

```swift
    @Test func theHeaderCarriesTheCategoryColumn() {
        let (m, _) = makeModel()
        #expect(m.csvExport() == "timestamp,source,category\n")
    }

    @Test func rowsCarryTheirCategory() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual", category: "Work")]
        #expect(m.csvExport().contains(",manual,Work"))
    }

    /// Bucket pomodoros — including everything logged before categories existed
    /// — read as the bucket's name rather than blank.
    @Test func uncategorisedRowsUseTheFallbackName() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.csvExport().contains(",manual,General"))
    }

    @Test func aRenamedFallbackShowsInTheExport() {
        let (m, _) = makeModel()
        m.settings.fallbackName = "Everything else"
        m.records = [Record(at: Date(), source: "manual")]
        #expect(m.csvExport().contains(",manual,Everything else"))
    }

    /// Category names are user-entered, so a comma must not shift the columns.
    @Test func aCategoryNameWithACommaIsQuoted() {
        let (m, _) = makeModel()
        m.records = [Record(at: Date(), source: "manual", category: "Work, admin")]
        #expect(m.csvExport().contains("\"Work, admin\""))
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ExportTests
```

Expected: FAIL — the header is still `timestamp,source`.

- [ ] **Step 3: Add the column**

In `Sources/PomodoroCount/Model.swift`, change `csvExport`:

```swift
    /// The whole history as CSV, one row per pomodoro, oldest first. Lossless,
    /// so a spreadsheet can group it however the reader likes.
    func csvExport() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["timestamp,source,category"]
        for record in records.sorted(by: { $0.at < $1.at }) {
            lines.append([formatter.string(from: record.at),
                          record.source,
                          record.category ?? settings.fallbackName]
                .map(Self.csvField)
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ExportTests
```

Expected: PASS. The pre-existing `plainFieldsAreNotQuoted` test still passes because "General" needs no quoting.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/ExportTests.swift
git commit -m "Add a category column to CSV export

Appended, so existing columns keep their positions. Bucket pomodoros read as
the bucket's name rather than blank, and the existing quoting handles category
names containing a comma."
```

---

### Task 12: Documentation and screenshots

**Files:**
- Modify: `README.md`, `CHANGELOG.md`
- Modify: `docs/panel-classic.png`, `docs/panel-synthwave.png`

**Interfaces:**
- Consumes: the finished feature
- Produces: nothing code depends on

- [ ] **Step 1: Add the feature to the README**

In `README.md`, after the paragraph beginning "**History** gives you a Week / Month chart", insert:

```markdown
**Categories** are optional. Turn them on in Settings and the log button becomes
one row per category, each with its own daily goal — Work 4, AI study 1, Music 1
— so a tap files the pomodoro and your progress is the first thing you see. Point
a focus session at one with the **towards…** picker, and History gains a **By
category** view. Deleting a category never deletes its history.
```

- [ ] **Step 2: Add a CHANGELOG entry**

Under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
### Added

- **Categories with daily goals.** Optional named categories, each with a daily
  goal. Tapping a category's row logs a pomodoro to it, focus sessions can be
  aimed at one, and History gains a By category breakdown. Deleting a category
  archives it — its pomodoros stay in your history, totals, and CSV export.
- CSV export gains a `category` column.
```

- [ ] **Step 3: Regenerate both screenshots**

The preview renderer already seeds categories from Task 7.

```bash
DUMMY="$(head -c 32 /dev/urandom | base64)"
SPARKLE_PUBLIC_KEY="$DUMMY" ./build-app.sh >/dev/null 2>&1
APP="build/Pomodoro Count.app"
"$APP/Contents/MacOS/PomodoroCount" --preview docs/panel-classic.png --theme classic
"$APP/Contents/MacOS/PomodoroCount" --preview docs/panel-synthwave.png --theme synthwave
./build-app.sh >/dev/null 2>&1   # leave the tree building without a key
open docs/panel-classic.png
```

Check both: rows render, the target pill is present, and Settings shows the Categories section.

- [ ] **Step 4: Full verification**

```bash
just test
swift build -c release 2>&1 | tail -1
./build-app.sh 2>&1 | grep -E "Done"
```

Expected: all tests pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md docs/
git commit -m "Document categories and refresh the screenshots"
```

---

## Verification Checklist

Run after Task 12:

- [ ] `just test` — all tests pass, 0 failures
- [ ] Turn categories **off** and confirm the panel is identical to today: hero button, no pill, no grouping control in History
- [ ] Turn them **on** with no categories and the bucket **off** — the empty-state row appears
- [ ] Add six categories and confirm the panel scrolls rather than growing
- [ ] Rename a category with history and confirm its count follows it
- [ ] Delete a category with history and confirm History and CSV still show it
- [ ] Set a goal of 20 and confirm the row draws a bar, not dots
- [ ] With VoiceOver on, tab through the rows and confirm each announces its name and progress
