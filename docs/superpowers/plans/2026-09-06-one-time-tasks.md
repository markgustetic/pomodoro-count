# One-Time Tasks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user add a named goal for today only from the Focus tab — it ranks above the standing categories, takes the session target, and is swept away at the next day change.

**Architecture:** A task is a `Category` with an `expiresOn` day, living in the same `settings.categories` array, so every existing consumer (routing, progress, auto-advance, History, CSV, the editor) works unchanged. The pure rules — which categories survive into a day, and which drags keep tasks above categories — live in a new `TaskExpiry` enum with unit tests. `AppModel` gains `addTask` and `expireTasks`; the sweep runs from `handleDayChange` (before its `realignTarget()`) and from `load()`.

**Tech Stack:** Swift Package Manager, SwiftUI + AppKit, swift-testing (`@Test`/`#expect`, not XCTest). Spec: `docs/superpowers/specs/2026-09-06-one-time-tasks-design.md`.

**Conventions that apply to every task:**

- Run one suite with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <SuiteName>`; the full suite is `just test`.
- Commit and push each task when its tests pass (`git push` after every commit — the maintainer's workflow).
- Comments record **why**. Every non-obvious line below carries its reason; keep them.
- Every colour goes through `palette`. No raw `Color`s.

---

## File map

| File | Change |
|---|---|
| `Sources/PomodoroCount/Category.swift` | `Category.expiresOn`, `Category.isTask`; `CategoryProgress.isTask` and its `accessibilityValue` |
| `Sources/PomodoroCount/TaskExpiry.swift` | **new** — `surviving(_:today:)`, `moveKeepsTasksOnTop(_:from:to:)` |
| `Sources/PomodoroCount/AppModel+Categories.swift` | `addTask`, `expireTasks`, guard in `moveCategory`, `isTask` in `todayProgress` |
| `Sources/PomodoroCount/SystemIntegration.swift` | `handleDayChange` calls `expireTasks` |
| `Sources/PomodoroCount/Store.swift` | `load()` calls `expireTasks` |
| `Sources/PomodoroCount/CategoryEditor.swift` | `AddCategoryForm.kind` (task mode with goal stepper); marker on `CategorySettingsRow` |
| `Sources/PomodoroCount/RootView.swift` | "+ Task" button and its popover |
| `Sources/PomodoroCount/CategoryRows.swift` | marker + tooltip on task rows; "Remove task" in `CategoryCountPopover` |
| `Tests/PomodoroCountTests/TaskExpiryTests.swift` | **new** — pure rules |
| `Tests/PomodoroCountTests/OneTimeTaskTests.swift` | **new** — model behaviour |
| `CHANGELOG.md`, `AGENTS.md` | entry; pure-logic list |

---

### Task 1: `Category.expiresOn` and `TaskExpiry.surviving`

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift`
- Create: `Sources/PomodoroCount/TaskExpiry.swift`
- Create: `Tests/PomodoroCountTests/TaskExpiryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import PomodoroCount

@Suite struct TaskExpiryTests {

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: today)! }

    private func standing(_ name: String) -> Category {
        Category(name: name, dailyGoal: 1)
    }

    private func task(_ name: String, addedOn day: Date) -> Category {
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
        let lateLastNight = yesterday.addingTimeInterval(23 * 3600 + 59 * 60)
        let stamped = cal.startOfDay(for: lateLastNight)
        let list = [task("Report", addedOn: stamped)]
        #expect(TaskExpiry.surviving(list, today: today).isEmpty)
    }

    @Test func orderIsPreservedAndNothingExpiringReturnsTheInput() {
        let list = [task("A", addedOn: today), task("B", addedOn: today),
                    standing("Work"), standing("Music")]
        let kept = TaskExpiry.surviving(list, today: today)
        #expect(kept.map(\.name) == ["A", "B", "Work", "Music"])
        #expect(kept.map(\.id) == list.map(\.id))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TaskExpiryTests`
Expected: compile error — `expiresOn`, `isTask`, `TaskExpiry` not found.

- [ ] **Step 3: Add the field and the enum**

In `Sources/PomodoroCount/Category.swift`, inside `struct Category`, after `var dailyGoal: Int`:

```swift
    /// The calendar day this category disappears at the start of, or nil for a
    /// standing category. Stored as the *start of the day it was added* — not
    /// the day after — so the test is "is today later than that day", which
    /// keeps a task visible for the rest of the day it was created on and not
    /// a moment of the next, including one added at 23:59.
    ///
    /// Optional so the synthesized decoder treats it as `decodeIfPresent` and
    /// every existing data.json loads with its categories standing.
    var expiresOn: Date? = nil

    /// A one-time task: a category that leaves at the next day change.
    var isTask: Bool { expiresOn != nil }
```

Create `Sources/PomodoroCount/TaskExpiry.swift`:

```swift
import Foundation

/// The rules that make a one-time task leave, and keep it above the standing
/// categories while it is here. Pure, so the day-change sweep and the reorder
/// guard are tested without an `AppModel`.
enum TaskExpiry {

    /// The categories that survive into `today` (a start-of-day date): every
    /// standing category, and every task whose day is not yet over. Order is
    /// preserved.
    static func surviving(_ categories: [Category], today: Date) -> [Category] {
        categories.filter { category in
            guard let day = category.expiresOn else { return true }
            // Both sides are starts of days, so this is a whole-day comparison
            // without a calendar walk.
            return today <= day
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TaskExpiryTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/Category.swift Sources/PomodoroCount/TaskExpiry.swift Tests/PomodoroCountTests/TaskExpiryTests.swift
git commit -m "Give a category an expiry day

A one-time task is a category that knows when to leave. Stored as the
start of the day it was added, so 'expired' is 'today is later than
that day'; optional, so older stores decode with every category standing.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 2: `TaskExpiry.moveKeepsTasksOnTop` and the `moveCategory` guard

**Files:**
- Modify: `Sources/PomodoroCount/TaskExpiry.swift`
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift` (`moveCategory`)
- Modify: `Tests/PomodoroCountTests/TaskExpiryTests.swift`
- Create: `Tests/PomodoroCountTests/OneTimeTaskTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `TaskExpiryTests`:

```swift
    // MARK: Reorder guard

    private var mixed: [Category] {
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
```

Create `Tests/PomodoroCountTests/OneTimeTaskTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "TaskExpiryTests|OneTimeTaskTests"`
Expected: compile error — `moveKeepsTasksOnTop` not found.

- [ ] **Step 3: Add the rule and the guard**

Append inside `enum TaskExpiry`:

```swift
    /// Whether moving the row at `from` to `to` keeps every task above every
    /// standing category. Tasks are inserted at the top and this is the only
    /// way a row changes position, so the block of tasks stays contiguous —
    /// which means "both ends are the same kind" is the whole test: a task
    /// landing on a task's slot stays in the task block, and likewise for
    /// categories. Out-of-range indices are refused rather than trapped,
    /// because the drag computes destinations that can run off the end.
    static func moveKeepsTasksOnTop(_ categories: [Category], from: Int, to: Int) -> Bool {
        guard categories.indices.contains(from), categories.indices.contains(to)
        else { return false }
        return categories[from].isTask == categories[to].isTask
    }
```

In `AppModel+Categories.swift`, change `moveCategory`'s guard:

```swift
    func moveCategory(from source: Int, to destination: Int) {
        let indices = settings.categories.indices
        guard indices.contains(source), indices.contains(destination),
              source != destination,
              // A one-time task ranks above every standing category — "today's
              // work first" is what its position means — so a drag may not carry
              // one below a category or a category above one. A refused move
              // changes nothing, which the drag already treats as "ended where it
              // began", and `nudgeCategory` inherits the refusal.
              TaskExpiry.moveKeepsTasksOnTop(settings.categories, from: source, to: destination)
        else { return }
        settings.categories.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination > source ? destination + 1 : destination)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "TaskExpiryTests|OneTimeTaskTests|ReorderTests|CategoryManagementTests"`
Expected: all pass (the existing reorder tests have no tasks, so the guard is a no-op for them).

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/TaskExpiry.swift Sources/PomodoroCount/AppModel+Categories.swift Tests/PomodoroCountTests/TaskExpiryTests.swift Tests/PomodoroCountTests/OneTimeTaskTests.swift
git commit -m "Keep one-time tasks above the standing categories

A drag or nudge that would carry a task below a category, or a
category above a task, is refused and the row stays put.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 3: `CategoryProgress.isTask`

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift` (`CategoryProgress`)
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift` (`todayProgress`)
- Modify: `Tests/PomodoroCountTests/OneTimeTaskTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OneTimeTaskTests`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OneTimeTaskTests`
Expected: compile error — no `isTask` on `CategoryProgress`.

- [ ] **Step 3: Add the field**

In `struct CategoryProgress`, after `let isTarget: Bool`:

```swift
    /// True for a one-time task. A `var` with a default rather than a `let`,
    /// so the memberwise initialiser the six existing call sites use keeps
    /// working without the argument.
    var isTask: Bool = false
```

Replace `accessibilityValue`:

```swift
    var accessibilityValue: String {
        let target = isTarget ? ", session target" : ""
        // Said here, not left to the sun glyph — the glyph is hidden from
        // VoiceOver, so this is the only place it can hear that the row leaves
        // tomorrow.
        let task = isTask ? ", today only" : ""
        guard goal > 0 else {
            return "\(done) \(done == 1 ? "pomodoro" : "pomodoros")" + target + task
        }
        return "\(done) of \(goal) pomodoros" + (isMet ? ", goal met" : "") + target + task
    }
```

In `todayProgress`, add the argument to the category rows' constructor:

```swift
        var rows = settings.categories.map { category in
            CategoryProgress(
                id: category.id.uuidString,
                name: category.name,
                done: doneToday[Category.normalized(category.name)] ?? 0,
                goal: category.dailyGoal,
                isFallback: false,
                isTarget: normalizedTarget == Category.normalized(category.name),
                isTask: category.isTask)
        }
```

- [ ] **Step 4: Run to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "OneTimeTaskTests|CategoryProgressTests|AccessibilityTests"`
Expected: all pass.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/Category.swift Sources/PomodoroCount/AppModel+Categories.swift Tests/PomodoroCountTests/OneTimeTaskTests.swift
git commit -m "Tell a progress row it is a one-time task

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 4: `addTask`

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift`
- Modify: `Tests/PomodoroCountTests/OneTimeTaskTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OneTimeTaskTests`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OneTimeTaskTests`
Expected: compile error — `addTask` not found.

- [ ] **Step 3: Implement**

In `AppModel+Categories.swift`, after `addCategory`:

```swift
    /// Adds a one-time task at the top of the ranking and aims the target at
    /// it. Returns false and changes nothing when the name is empty or taken —
    /// the same rule as `addCategory`, so a task cannot shadow a category, the
    /// bucket, or another task — or when the goal is zero: a task with nothing
    /// to count is not a task.
    ///
    /// One assignment to `settings`, not an insert followed by `pickTarget`.
    /// Each mutation of `settings` is its own write to disk, and the
    /// alternative — a `suspendSaves()` pair — would add a call site to a
    /// mechanism whose comment in Store.swift enumerates the existing ones by
    /// name. The pin is cleared outright rather than computed: a task with no
    /// pomodoros yet cannot be met, so `pickTarget` would have said the same.
    @discardableResult
    func addTask(name: String, goal: Int, now: Date = Date()) -> Bool {
        guard isCategoryNameAvailable(name), goal > 0 else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = settings
        updated.categories.insert(
            Category(name: trimmed, dailyGoal: min(goal, 20),
                     expiresOn: Calendar.current.startOfDay(for: now)),
            at: 0)
        updated.aim(at: .named(trimmed))
        updated.targetPinned = false
        updated.targetAimedOn = now
        settings = updated
        return true
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OneTimeTaskTests`
Expected: all pass.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/AppModel+Categories.swift Tests/PomodoroCountTests/OneTimeTaskTests.swift
git commit -m "Add a one-time task at the top of the ranking

Inserted first and aimed at in one settings write, so adding it is
one save. A freshly added task has nothing done, so the pick never pins.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 5: `expireTasks` from the day change and from load

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift`
- Modify: `Sources/PomodoroCount/SystemIntegration.swift:234-248`
- Modify: `Sources/PomodoroCount/Store.swift` (`load()`, after `settings = persisted.settings`)
- Modify: `Tests/PomodoroCountTests/OneTimeTaskTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OneTimeTaskTests`:

```swift
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

    @Test func aFileWithoutExpiresOnLoadsStandingCategories() throws {
        let url = try storeURL(containing: #"""
        {"records":[],"settings":{"categoriesEnabled":true,
         "categories":[{"id":"1E1C0D2B-0000-4000-8000-000000000001","name":"Work","dailyGoal":2}]}}
        """#)
        let m = AppModel(storeURL: url)
        #expect(m.settings.categories.map(\.isTask) == [false])
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OneTimeTaskTests`
Expected: compile error — `expireTasks` not found.

- [ ] **Step 3: Implement the sweep**

In `AppModel+Categories.swift`, after `addTask`:

```swift
    /// Drops every one-time task whose day is over. Records are untouched:
    /// the name stays on them, which is how History keeps a finished task —
    /// the same archiving `removeCategory` does. If the session target was
    /// one of the leavers its pin goes with it, again as `removeCategory`
    /// does; the target *name* is left for `realignTarget()` to re-aim, since
    /// an unknown name already resolves to the bucket and the earlier-day
    /// stamp already restarts the plan at the top of the ranking.
    ///
    /// Idempotent and cheap, so it is called on every `handleDayChange` and
    /// from `load()` — the latter for models built without a launch (tests,
    /// `--preview`, the reorder harness), which never see a day change.
    /// Writes nothing when nothing expires: this runs on every wake.
    func expireTasks(now: Date = Date()) {
        let today = Calendar.current.startOfDay(for: now)
        let surviving = TaskExpiry.surviving(settings.categories, today: today)
        guard surviving.count != settings.categories.count else { return }
        let leaving = Set(settings.categories.map { Category.normalized($0.name) })
            .subtracting(surviving.map { Category.normalized($0.name) })
        var updated = settings
        updated.categories = surviving
        if let target = updated.sessionTargetName.map(Category.normalized),
           leaving.contains(target) {
            updated.targetPinned = false
        }
        settings = updated
    }
```

In `SystemIntegration.swift`, `handleDayChange`, insert before `realignTarget()`:

```swift
        // Before the realign, so a target left pointing at a task that just
        // left is re-aimed by the rule below. Every call, not only on a new
        // day: the sweep is idempotent, and the wake that reports the new day
        // is the one that must find the task gone.
        expireTasks(now: now)
        realignTarget()
```

In `Store.swift`, `load()`, after `settings = persisted.settings`:

```swift
        // A task added yesterday must not show today, and launch is not the
        // only way a model is built — tests, `--preview` and the reorder
        // harness never see a day change. `isLoading` is still true here, so
        // this triggers no save; the next real change writes the swept list.
        expireTasks()
```

- [ ] **Step 4: Run to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "OneTimeTaskTests|DayRolloverTests|PersistenceTests"`
Expected: all pass.

- [ ] **Step 5: Run the whole suite**

Run: `just test`
Expected: all green.

- [ ] **Step 6: Commit and push**

```bash
git add Sources/PomodoroCount/AppModel+Categories.swift Sources/PomodoroCount/SystemIntegration.swift Sources/PomodoroCount/Store.swift Tests/PomodoroCountTests/OneTimeTaskTests.swift
git commit -m "Sweep expired tasks at the day change and on load

Before the realign, so a target pointing at a task that just left is
re-aimed by the existing start-of-day rule. Also on load, for the
models that are built without a launch.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 6: The add form's task mode and the "+ Task" button

**Files:**
- Modify: `Sources/PomodoroCount/CategoryEditor.swift:18-90` (`AddCategoryForm`)
- Modify: `Sources/PomodoroCount/RootView.swift:163-185` (`logButton`)

No unit test covers SwiftUI here (views are thin over tested logic); the check is a build plus a headless render in Task 9.

- [ ] **Step 1: Give `AddCategoryForm` a kind**

Replace the top of `AddCategoryForm` through the end of `body`'s `VStack` header, keeping everything else:

```swift
struct AddCategoryForm: View {
    /// What the form adds. Task mode differs in the caption, a goal stepper,
    /// and which model method Add calls; everything else — name field,
    /// availability check, the "taken" message, Cancel/Add, the Synthwave
    /// background fix — is identical, and should not exist twice.
    enum Kind { case category, task }

    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    var kind: Kind = .category

    @State private var name = ""
    /// Task mode only. Defaults to 1 rather than 0: a task with no goal is not
    /// a task, and the model refuses one.
    @State private var goal = 1
    @FocusState private var nameFocused: Bool
    @Environment(\.palette) private var palette
```

In `body`, change the caption:

```swift
            Text(kind == .task ? "Today's task" : "New category")
                .font(.caption)
                .foregroundStyle(palette.textDim)
```

Change the text field's accessibility label:

```swift
                .accessibilityLabel(kind == .task ? "Task name" : "New category name")
```

After the "already taken" `if` block and before the `HStack` of buttons, add:

```swift
            if kind == .task {
                Stepper(value: $goal, in: 1...20) {
                    Text("\(goal) \(goal == 1 ? "pomodoro" : "pomodoros")")
                        .font(.caption.monospacedDigit())
                }
                .accessibilityLabel("Pomodoros for this task")
            }
```

Replace `add()`:

```swift
    private func add() {
        let added: Bool
        switch kind {
        case .category: added = model.addCategory(name: name, dailyGoal: 1)
        case .task: added = model.addTask(name: name, goal: goal)
        }
        guard added else { return }
        name = ""
        goal = 1
        isPresented = false
    }
```

- [ ] **Step 2: Add the button to the Focus tab**

In `RootView`, add a state next to `@State private var tab: Tab`:

```swift
    @State private var addingTask = false
```

Replace `logButton`:

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

            HStack(spacing: 14) {
                if model.settings.categoriesEnabled {
                    // Here, under the rows it adds to, rather than in Settings:
                    // a task is a decision about today, not about how the app
                    // is set up. Shown even while the list is empty, so the
                    // empty caption's "Add a category in Settings" is not the
                    // only way forward.
                    Button("+ Task") { addingTask = true }
                        .buttonStyle(HoverTextButtonStyle())
                        .font(.caption)
                        .help("Add a goal for today only — it disappears tomorrow")
                        .accessibilityLabel("Add a task for today")
                        .popover(isPresented: $addingTask, arrowEdge: .bottom) {
                            // A popover is its own window: the model goes in as
                            // a parameter and the theme is applied again here.
                            AddCategoryForm(model: model, isPresented: $addingTask, kind: .task)
                                .themed(palette)
                        }
                }

                if model.todayCount > 0 {
                    Button("Undo last", action: model.undoLast)
                        .buttonStyle(HoverTextButtonStyle())
                        .font(.caption)
                        .help("Take back the most recent pomodoro")
                }
            }
        }
    }
```

- [ ] **Step 3: Build**

Run: `just build`
Expected: builds; `build/Pomodoro Count.app` produced.

- [ ] **Step 4: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryEditor.swift Sources/PomodoroCount/RootView.swift
git commit -m "Add a one-time task from the Focus tab

The add-category popover grows a task mode with a goal stepper, opened
by a '+ Task' button under the category rows.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 7: The task row's marker and "Remove task"

**Files:**
- Modify: `Sources/PomodoroCount/CategoryRows.swift` (`CategoryRows`, `CategoryRow`, `CategoryCountPopover`)

- [ ] **Step 1: Thread an `onRemove` closure**

In `CategoryRow`, after `let onSubtract: () -> Void`:

```swift
    /// Present for a one-time task only. Closures rather than the model,
    /// because it ends up inside the count popover — its own window, where
    /// `@EnvironmentObject` does not reliably reach.
    var onRemove: (() -> Void)? = nil
```

In `CategoryRows`, pass it:

```swift
                            CategoryRow(progress: row,
                                        clickReleasesPin: releases,
                                        onSelect: { model.selectTarget(target) },
                                        onAdd: { model.logExternal(to: target) },
                                        onSubtract: { model.unlogToday(from: target) },
                                        // `row.id` is the category's UUID string
                                        // for every row but the bucket, and the
                                        // bucket is never a task.
                                        onRemove: row.isTask
                                            ? { UUID(uuidString: row.id).map { model.removeCategory(id: $0) } }
                                            : nil)
```

- [ ] **Step 2: Mark the row**

In `CategoryRow.selectButton`, before `Text(progress.name)`:

```swift
                if progress.isTask {
                    // A sun for "today": the row leaves tomorrow, and nothing
                    // else about it says so. Hidden from VoiceOver, which hears
                    // "today only" in the row's value instead.
                    Image(systemName: "sun.max")
                        .font(.caption)
                        .foregroundStyle(palette.textDim)
                        .accessibilityHidden(true)
                }
```

Replace `selectHelp`:

```swift
    private var selectHelp: String {
        let suffix = progress.isTask ? " · Today only" : ""
        if clickReleasesPin {
            return "Pinned to \(progress.name) — click to follow the category order again" + suffix
        }
        if progress.isTarget {
            return "Finished pomodoros already land in \(progress.name)" + suffix
        }
        return "Send finished pomodoros to \(progress.name)" + suffix
    }
```

In `adjustButton`'s popover, pass the closure and close the popover on removal:

```swift
        .popover(isPresented: $showingCounter, arrowEdge: .trailing) {
            // A popover is its own window: it inherits the environment but not
            // the appearance, so the theme has to be applied again here.
            CategoryCountPopover(progress: progress, onAdd: onAdd, onSubtract: onSubtract,
                                 // Close first: the row this popover hangs off
                                 // is about to be removed from under it.
                                 onRemove: onRemove.map { remove in { showingCounter = false; remove() } })
                .themed(palette)
        }
```

- [ ] **Step 3: Add the button to the popover**

In `CategoryCountPopover`, after `let onSubtract: () -> Void`:

```swift
    /// A one-time task's way out before the day ends. nil for a category,
    /// which is removed from Settings behind a confirmation — a task is
    /// today's scratch note, and a mis-click costs a two-field form.
    var onRemove: (() -> Void)? = nil
```

After the `plus` button, still inside the `HStack`:

```swift
            if let onRemove {
                Button("Remove task", action: onRemove)
                    // The editor's remove control uses the same emphasis:
                    // quiet until hovered, then warns.
                    .buttonStyle(HoverTextButtonStyle(emphasis: .destructive))
                    .font(.caption)
                    .help("Remove — its pomodoros stay in your history")
                    .accessibilityLabel("Remove task \(progress.name)")
            }
```

- [ ] **Step 4: Build and run the suite**

Run: `just build && just test`
Expected: builds, all tests pass.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryRows.swift
git commit -m "Mark a task row and let its counter remove it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 8: The Settings editor marker

**Files:**
- Modify: `Sources/PomodoroCount/CategoryEditor.swift` (`CategorySettingsRow.body`, ~line 207)

- [ ] **Step 1: Add the marker**

In `CategorySettingsRow.body`, as the first child of the `HStack(spacing: 6)`, before `CommittableNameField`:

```swift
            if category.isTask {
                // Tasks are listed here rather than hidden: this is the one
                // place that shows every category, and a hidden row that still
                // takes the target would be a mystery. The mark says why it
                // will be gone tomorrow.
                Image(systemName: "sun.max")
                    .font(.caption)
                    .foregroundStyle(palette.textDim)
                    .help("Today only — disappears tomorrow")
                    .accessibilityLabel("Today only")
            }
```

- [ ] **Step 2: Build**

Run: `just build`
Expected: builds.

- [ ] **Step 3: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryEditor.swift
git commit -m "Mark one-time tasks in the category editor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

---

### Task 9: Headless render, changelog, agent guide

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased] / Added`)
- Modify: `AGENTS.md` (the pure-logic list under Conventions)

- [ ] **Step 1: Render a store with two tasks and two categories**

```bash
S=/private/tmp/claude-501/-Users-markgustetic-Programming-local-apps-pomodoro-count/fe74190b-f950-4789-bfe1-8b4f67f64309/scratchpad
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --seed-store "$S/tasks.json"
python3 - "$S/tasks.json" <<'EOF'
import json, sys, datetime, uuid
p = sys.argv[1]
d = json.load(open(p))
today = datetime.datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
yday = today - datetime.timedelta(days=1)
def task(name, goal, day):
    return {"id": str(uuid.uuid4()).upper(), "name": name, "dailyGoal": goal,
            "expiresOn": day.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
cats = d["settings"]["categories"][:2]
d["settings"]["categories"] = [task("Write the report", 2, today), task("Close MAR-9", 1, today),
                               task("Stale from yesterday", 3, yday)] + cats
d["settings"]["sessionTargetName"] = "Write the report"
json.dump(d, open(p, "w"), indent=2)
EOF
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview "$S/tasks.png" --store "$S/tasks.json"
"build/Pomodoro Count.app/Contents/MacOS/PomodoroCount" --preview "$S/tasks-synth.png" --store "$S/tasks.json" --theme Synthwave
```

Open both PNGs (Read tool) and check: two sun-marked rows above Alpha and Bravo, no "Stale from yesterday" row (the load sweep dropped it), the "+ Task" caption under the rows, the target outline on "Write the report", and the panel not clipped. In the Settings render the same two rows carry the sun.

- [ ] **Step 2: Changelog**

Under `## [Unreleased]` → `### Added`, add as the first bullet:

```markdown
- **One-time tasks.** Give today a goal that isn't a category: "+ Task" on the
  Focus tab adds a named target with a pomodoro count that sits above your
  categories and disappears tomorrow. Its pomodoros stay in History under the
  task's name.
```

- [ ] **Step 3: Agent guide**

In `AGENTS.md`, the Conventions bullet that lists pure, unit-tested functions: add `TaskExpiry.surviving(_:today:)` and `TaskExpiry.moveKeepsTasksOnTop(_:from:to:)` to the list, after `TargetPick.action(isAlreadyTarget:pinned:autoAdvance:)`. In the "Model and persistence" section, add a bullet after the `realignTarget()` one:

```markdown
- A one-time task is a `Category` with `expiresOn` set — the start of the day
  it was added — kept in the same `settings.categories` array, inserted at
  index 0. There is no second list on purpose: everything that walks
  categories treats a task as one. `expireTasks()` runs on every
  `handleDayChange` *before* `realignTarget()`, so a target left on a gone
  task is re-aimed by the existing start-of-day rule, and from `load()` for
  models built without a launch. `moveCategory` refuses any move that would
  put a task below a standing category or a category above a task.
```

- [ ] **Step 4: Full verification**

Run: `just test && just build`
Expected: all green, app builds.

- [ ] **Step 5: Commit, push, install**

```bash
git add CHANGELOG.md AGENTS.md
git commit -m "Note one-time tasks in the changelog and the agent guide

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
just install
```

Then, by hand in the running app (the panel's gestures cannot be driven synthetically): add a task from Focus, confirm it appears on top with the sun and is the target, log one to it with `+`, open its `±` and press "Remove task", and confirm it is gone while History's breakdown still lists it.
