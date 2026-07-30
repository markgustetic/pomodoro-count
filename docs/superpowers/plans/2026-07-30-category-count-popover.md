# Category Count Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping a category row in the Focus tab opens a compact `−`/count/`+` popover instead of silently logging one pomodoro, so a count can come down as well as up.

**Architecture:** A pure `CountAdjust.newestTodayIndex` picks which record a subtract removes; a four-line `AppModel.unlogToday(from:)` sits over it; `CategoryCountPopover` is a closure-driven view the row presents. The `+` path is the existing `logExternal(to:)`, unchanged.

**Tech Stack:** Swift Package Manager, SwiftUI with AppKit reach-ins, swift-testing (not XCTest), macOS 14+.

Spec: [`docs/superpowers/specs/2026-07-30-category-count-popover-design.md`](../specs/2026-07-30-category-count-popover-design.md)

## Global Constraints

- **Tests are swift-testing**, not XCTest: `import Testing`, `@Suite struct`, `@Test func`, `#expect`, `try #require`. Suites touching `AppModel` are `@MainActor`.
- **Run tests with `just test`.** It borrows Xcode's toolchain when the Command Line Tools are active; bare `swift test` fails in that state. Single suite: `just test` then read the filtered output, or `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CountAdjustTests`.
- **Never write to the real store in a test.** Use `makeModel()` from `Tests/PomodoroCountTests/TestSupport.swift`, which returns a model backed by a throwaway file and with sound off.
- **`resolve(_:)` returns `nil` when `settings.categoriesEnabled` is false**, meaning the fallback bucket. Any test exercising `.named(…)` must set `categoriesEnabled = true` first or it silently tests the bucket instead and passes for the wrong reason.
- **Comments record WHY and stay.** Decisions that look odd carry their reasoning in place. Do not strip existing comments.
- **Every color routes through `Palette`.** No raw `Color.red`/`.primary`. No borderless button styles — use the existing styles, which branch on `ControlState` so `.disabled(…)` is visible.
- **A popover is its own window:** it inherits the environment but not the appearance, so it must apply `.themed(palette)` itself. `@EnvironmentObject` does not reliably reach popover content and fails by *crashing* — popover content takes values and closures as parameters.
- **Commit each task separately** with a short imperative subject and a body explaining why. Push after each.

---

### Task 1: `CountAdjust.newestTodayIndex`

The pure choice of which record a subtract removes, extracted from the model so it is testable without a store — the same shape as `CategoryAdvance.topUnmet` and `Reorder.destination`.

**Files:**
- Create: `Sources/PomodoroCount/CountAdjust.swift`
- Create: `Tests/PomodoroCountTests/CountAdjustTests.swift`
- Modify: `Tests/PomodoroCountTests/TestSupport.swift` (append a `Date.todayAt(hour:)` helper)

**Interfaces:**
- Consumes: `Record` (`Sources/PomodoroCount/Types.swift:8` — `id`, `at: Date`, `source: String`, `category: String?`), `Category.normalized(_:) -> String` (`Sources/PomodoroCount/Category.swift`).
- Produces: `CountAdjust.newestTodayIndex(in records: [Record], category: String?) -> Int?`. Task 2 is the only caller. `Date.todayAt(hour: Int) -> Date`, used by Task 2's tests as well.

- [ ] **Step 1: Add the shared date helper**

Append to `Tests/PomodoroCountTests/TestSupport.swift`, inside the existing `extension Date` that already holds `daysAgo(_:)`:

```swift
    /// A stamp guaranteed to land on today, `hour` hours in.
    ///
    /// Tests needing two same-day timestamps can't just offset `Date()` by an
    /// hour: a run starting at 00:00:30 would push the earlier one into
    /// yesterday, and the assertion would fail for reasons having nothing to do
    /// with the code under test.
    static func todayAt(hour: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(hour) * 3600)
    }
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/PomodoroCountTests/CountAdjustTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// Which record a subtract removes. Pure, so no store and no model.
@Suite struct CountAdjustTests {

    @Test func findsNothingInAnEmptyStore() {
        #expect(CountAdjust.newestTodayIndex(in: [], category: "Writing") == nil)
    }

    @Test func findsNothingWhenNoRecordMatches() {
        let records = [Record(at: .todayAt(hour: 12), source: "manual", category: "Admin")]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "Writing") == nil)
    }

    /// Newest by timestamp, not last in the array: a backdated manual log can be
    /// appended after a session completion, and the newest one is what the user
    /// means to drop. `undoLast` has the same rule for the same reason.
    @Test func findsTheNewestNotTheLastAppended() {
        let records = [
            Record(at: .todayAt(hour: 12), source: "timer", category: "Writing"),
            Record(at: .todayAt(hour: 9), source: "manual", category: "Writing"),
        ]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "Writing") == 0)
    }

    @Test func normalizesTheNameItLooksFor() {
        let records = [Record(at: .todayAt(hour: 12), source: "manual", category: "Writing")]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "  writing ") == 0)
    }

    /// nil means the bucket, and the bucket is not a wildcard: a named
    /// category's record must not answer a bucket query, or a subtract on the
    /// bucket would silently eat a pomodoro belonging to someone else's row.
    @Test func matchesTheBucketOnlyOnRecordsWithNoCategory() {
        let records = [
            Record(at: .todayAt(hour: 12), source: "manual", category: "Writing"),
            Record(at: .todayAt(hour: 9), source: "manual", category: nil),
        ]
        #expect(CountAdjust.newestTodayIndex(in: records, category: nil) == 1)
    }

    /// The row shows today, so the subtract adjusts today — even when today is
    /// empty and yesterday is not.
    @Test func ignoresEarlierDays() {
        let records = [Record(at: .daysAgo(1), source: "manual", category: "Writing")]
        #expect(CountAdjust.newestTodayIndex(in: records, category: "Writing") == nil)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
just test
```

Expected: compile failure — `cannot find 'CountAdjust' in scope`. That is the correct first failure; there is no type yet.

- [ ] **Step 4: Write the implementation**

Create `Sources/PomodoroCount/CountAdjust.swift`:

```swift
import Foundation

/// Picks which record a subtract removes.
///
/// Pure and total over its inputs, so "today's newest in this category" is
/// testable without a store, a view or a clock the test has to fake — the same
/// shape as `CategoryAdvance.topUnmet` and `Reorder.destination`.
/// `AppModel.unlogToday` is the only caller.
enum CountAdjust {

    /// Index of today's most recent record filed under `category`, or nil when
    /// there is nothing to remove.
    ///
    /// `category` is a display name and is normalized here, exactly as
    /// `todayCount(inCategory:)` does it — a record stored as "Writing" has to
    /// be found from a row labelled "writing". `nil` means the fallback bucket,
    /// whose records carry no category at all, and it matches *only* those: a
    /// bucket subtract must never reach into a named category.
    ///
    /// Newest by timestamp rather than last in the array, because those are not
    /// the same thing — a session completion can be appended after a manual log
    /// that was backdated, and the user means the newest one.
    static func newestTodayIndex(in records: [Record], category: String?) -> Int? {
        let wanted = category.map(Category.normalized)
        let calendar = Calendar.current
        return records.indices
            .filter {
                calendar.isDateInToday(records[$0].at)
                    && records[$0].category.map(Category.normalized) == wanted
            }
            .max { records[$0].at < records[$1].at }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
just test
```

Expected: PASS — all six new cases, and the pre-existing suite still green (347 tests before this task).

- [ ] **Step 6: Commit and push**

```bash
git add Sources/PomodoroCount/CountAdjust.swift Tests/PomodoroCountTests/CountAdjustTests.swift Tests/PomodoroCountTests/TestSupport.swift
git commit -m "Pick the record a subtract removes, in one pure function"
git push
```

Body for the commit message:

```
A subtract needs today's newest record in one category, which is not the
last element of the array and not the newest record overall. Both of those
distinctions are easy to get wrong and neither is visible from a view, so
the choice lives in a pure function with its own tests.
```

---

### Task 2: `AppModel.unlogToday(from:)`

The model method the popover's `−` calls, plus the documentation of why it breaks the realign symmetry.

**Files:**
- Modify: `Sources/PomodoroCount/Model.swift` (add after `undoLast()`, which is the last method in the final `extension AppModel`)
- Modify: `Tests/PomodoroCountTests/LoggingTests.swift` (append a new `// MARK:` section — this is where record *removal* is already tested)
- Modify: `AGENTS.md` (the "Model and persistence" bullet about record-appending paths)

**Interfaces:**
- Consumes: `CountAdjust.newestTodayIndex(in:category:) -> Int?` from Task 1. `resolve(_ target: CategoryTarget) -> String?` (`Sources/PomodoroCount/AppModel+Categories.swift:8`). `play(_:)` with the `.countDown` case, as used by `undoLast()`.
- Produces: `AppModel.unlogToday(from target: CategoryTarget)`, returning `Void`. Task 3 calls it.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PomodoroCountTests/LoggingTests.swift`, inside the existing `@MainActor @Suite struct LoggingTests`:

```swift
    // MARK: Per-category subtract

    @Test func unlogTodayRemovesFromTheNamedCategory() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3),
                                 Category(name: "Admin", dailyGoal: 3)]
        m.logExternal(to: .named("Writing"))
        m.logExternal(to: .named("Admin"))

        m.unlogToday(from: .named("Writing"))

        #expect(m.todayCount(inCategory: "Writing") == 0)
        #expect(m.todayCount(inCategory: "Admin") == 1)
    }

    /// The whole point of a per-category subtract: a newer pomodoro somewhere
    /// else is exactly the case the global "Undo last" gets wrong.
    @Test func unlogTodayIgnoresANewerRecordInAnotherCategory() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3),
                                 Category(name: "Admin", dailyGoal: 3)]
        m.records = [
            Record(at: .todayAt(hour: 9), source: "manual", category: "Writing"),
            Record(at: .todayAt(hour: 12), source: "manual", category: "Admin"),
        ]

        m.unlogToday(from: .named("Writing"))

        #expect(m.records.count == 1)
        #expect(m.records.first?.category == "Admin")
    }

    @Test func unlogTodayOnAnEmptyCategoryIsANoOp() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3)]

        m.unlogToday(from: .named("Writing"))
        m.unlogToday(from: .named("Writing"))

        #expect(m.records.isEmpty)
        #expect(m.todayCount == 0)
    }

    /// The row shows today, so the subtract adjusts today. Yesterday's history
    /// is not a reserve the counter can draw down.
    @Test func unlogTodayLeavesEarlierDaysAlone() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3)]
        m.records = [Record(at: .daysAgo(1), source: "manual", category: "Writing")]

        m.unlogToday(from: .named("Writing"))

        #expect(m.records.count == 1)
    }

    @Test func unlogTodayRemovesABucketRecord() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3)]
        m.records = [
            Record(at: .todayAt(hour: 9), source: "manual", category: nil),
            Record(at: .todayAt(hour: 12), source: "manual", category: "Writing"),
        ]

        m.unlogToday(from: .fallback)

        #expect(m.records.count == 1)
        #expect(m.records.first?.category == "Writing")
    }

    /// A removal must not re-aim the session. The advance is forward-only on
    /// purpose: re-aiming because a count dropped would move the target out
    /// from under a Start the user has already pressed.
    ///
    /// Non-vacuous by construction: after the removal Writing is both unmet and
    /// top-ranked, so a `realignTarget()` here *would* pull the target off
    /// Admin. The assertion fails if anyone adds one for symmetry.
    @Test func unlogTodayLeavesTheSessionTargetAlone() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.autoAdvanceTarget = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 1),
                                 Category(name: "Admin", dailyGoal: 3)]
        m.records = [Record(at: .todayAt(hour: 9), source: "manual", category: "Writing")]
        m.settings.targetAimedOn = Date()
        m.sessionTarget = .named("Admin")

        m.unlogToday(from: .named("Writing"))

        #expect(m.sessionTarget == .named("Admin"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
just test
```

Expected: compile failure — `value of type 'AppModel' has no member 'unlogToday'`.

- [ ] **Step 3: Write the implementation**

In `Sources/PomodoroCount/Model.swift`, add directly after `undoLast()`:

```swift
    /// Removes today's most recent record in one category — the subtract half of
    /// the category row's counter. A category with nothing logged today is a
    /// no-op, so a count can never go negative; the popover disables its `−`
    /// there too, but the model must not depend on a view for that.
    ///
    /// Deliberately does **not** call `realignTarget()`, unlike every appending
    /// path. The advance is forward-only on purpose: re-aiming because a count
    /// dropped would move the target out from under a Start the user has already
    /// pressed, and it would undo a hand-picked pin the moment a mis-tap was
    /// corrected. `undoLast()` has left the target alone for the same reason
    /// since it was written. `unlogTodayLeavesTheSessionTargetAlone` fails if
    /// this gets "fixed" for symmetry.
    ///
    /// No `suspendSaves()` bracket either: that exists for a *burst* of related
    /// changes, and this is one mutation of `records`, whose `didSet` should
    /// write exactly once. `logExternal` brackets because it pairs an append
    /// with a target advance; a removal has no second half to pair with.
    func unlogToday(from target: CategoryTarget) {
        guard let index = CountAdjust.newestTodayIndex(in: records,
                                                      category: resolve(target))
        else { return }
        records.remove(at: index)
        play(.countDown)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
just test
```

Expected: PASS — six new cases plus everything from Task 1.

- [ ] **Step 5: Correct the AGENTS.md bullet and note the asymmetry**

The existing bullet under "Model and persistence" reads:

```markdown
- Every record-appending path also calls `advanceTargetIfMet()` — append
  first, so the record credits the target it ran against, then advance. The
  advance is suppressed while a focus session is actually running, so an
  external log can't re-aim a session Start already pointed elsewhere.
```

That method is now called `realignTarget()`; the doc is one rename behind, and this is the exact line that invites someone to add a realign to the removing path. Replace it with:

```markdown
- Every record-appending path also calls `realignTarget()` — append
  first, so the record credits the target it ran against, then advance. The
  advance is suppressed while a focus session is actually running, so an
  external log can't re-aim a session Start already pointed elsewhere.
  Record-*removing* paths (`undoLast`, `unlogToday`) deliberately do not
  realign: the advance is forward-only, and a correction must not move the
  target out from under a Start already pressed.
```

- [ ] **Step 6: Commit and push**

```bash
git add Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/LoggingTests.swift AGENTS.md
git commit -m "Let one category give a pomodoro back"
git push
```

Body for the commit message:

```
"Undo last" removes the newest record anywhere, so correcting a mis-tap on
one category means first checking what has landed on the others since.
`unlogToday` scopes the removal to the row the user is looking at.

It does not realign the session target, and the comment says why at length
because the surrounding code realigns on every append — the test that would
catch a symmetry "fix" is named in the comment.

The AGENTS.md bullet next to it still said `advanceTargetIfMet`, which was
renamed; fixed while amending the same sentence.
```

---

### Task 3: The popover and the row that opens it

**Files:**
- Modify: `Sources/PomodoroCount/CategoryRows.swift` (both `CategoryRows` and `CategoryRow`; add `CategoryCountPopover`)
- Modify: `CHANGELOG.md` (the existing `## [Unreleased]` → `### Changed` section)

**Interfaces:**
- Consumes: `AppModel.unlogToday(from:)` from Task 2; the existing `logExternal(to:)`; `CategoryProgress` (`name`, `done`, `goal`, `isFallback`, `isMet`, `accessibilityValue`); `SoftIconButtonStyle(width:height:)` from `Styles.swift:147`; `.themed(_:)` from `Theme.swift`.
- Produces: nothing later tasks depend on — this is the last task.

**Four things this task must NOT do.** Each is behavior the spec settled, and each is a plausible "improvement" that would break it:

- **Do not add a Done or Cancel button.** Each tap has already committed; there is nothing pending to confirm or discard. `.popover`'s default dismissal — click outside, or Escape — is exactly the required behavior, so it needs no code at all.
- **Do not dismiss the panel** from either button. Row logging never did; only `LogButton` calls `MenuBarPanel.dismiss()`, because that path has nothing left to show.
- **Do not remove the "Undo last" button** in `RootView.swift:146` as now-redundant. It is the only correction path when categories are off.
- **Do not add an `@ObservedObject` or `@EnvironmentObject` to `CategoryCountPopover`** to make the count live. It already is: `CategoryRows.body` re-runs when `records` changes, so the popover's content closure is re-evaluated with a fresh `CategoryProgress`, and the `@State` driving presentation survives because the `ForEach` identifies rows by `id`. An `@EnvironmentObject` here would crash.

- [ ] **Step 1: Add the popover view**

In `Sources/PomodoroCount/CategoryRows.swift`, add below `CategoryRow`:

```swift
/// The `−`/count/`+` strip a category row opens.
///
/// Takes closures rather than the model, like `AddCategoryForm` and
/// `RemoveCategoryConfirmation`: `@EnvironmentObject` does not reliably reach
/// popover content, and it fails by *crashing* rather than by looking wrong.
///
/// The name is deliberately not repeated here — the row that was tapped is
/// still on screen immediately beside this, and a second copy of the label in a
/// strip this small reads as clutter.
struct CategoryCountPopover: View {
    let progress: CategoryProgress
    let onAdd: () -> Void
    let onSubtract: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            // SoftIconButtonStyle, not a borderless style: it branches on
            // `ControlState`, so `.disabled` at zero actually looks dead. A
            // hand-rolled style here is how the dimming bug got in last time.
            Button(action: onSubtract) {
                Image(systemName: "minus")
            }
            .buttonStyle(SoftIconButtonStyle(width: 34, height: 30))
            .disabled(progress.done == 0)
            .help("Take one back from \(progress.name)")
            .accessibilityLabel("Remove one pomodoro")

            Text(progress.goal > 0 ? "\(progress.done)/\(progress.goal)" : "\(progress.done)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(progress.isMet ? palette.accent : palette.text)
                // Fixed width so the strip doesn't jump between 9 and 10.
                .frame(minWidth: 48)
                .accessibilityLabel(progress.accessibilityValue)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(SoftIconButtonStyle(width: 34, height: 30))
            .help("Log one pomodoro to \(progress.name)")
            .accessibilityLabel("Add one pomodoro")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
```

- [ ] **Step 2: Rewrite `CategoryRow` to present it**

Change the stored properties at the top of `CategoryRow` from:

```swift
    let progress: CategoryProgress
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false
```

to:

```swift
    let progress: CategoryProgress
    let onAdd: () -> Void
    let onSubtract: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false
    @State private var showingCounter = false
```

Change `Button(action: action) {` to:

```swift
        Button { showingCounter = true } label: {
```

Then replace the modifier block after `.buttonStyle(.plain)` — currently:

```swift
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(progress.isMet ? "\(progress.name): goal met — one more still counts"
                             : "Log one pomodoro to \(progress.name)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.name)
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityHint("Logs one pomodoro")
```

with:

```swift
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        // Trailing, not bottom: the rows are a list, and a popover hanging off
        // the bottom edge covers the neighbours whose counts give this one its
        // context.
        .popover(isPresented: $showingCounter, arrowEdge: .trailing) {
            // A popover is its own window: it inherits the environment but not
            // the appearance, so the theme has to be applied again here.
            CategoryCountPopover(progress: progress, onAdd: onAdd, onSubtract: onSubtract)
                .themed(palette)
        }
        .help(progress.isMet ? "\(progress.name): goal met — adjust today's count"
                             : "Adjust today's count for \(progress.name)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.name)
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityHint("Opens a counter you can adjust")
        // Restores what the popover would otherwise cost VoiceOver. The row used
        // to log in one activation; routing it through a popover would make that
        // three. Swipe up and down adjust the count without opening anything.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdd()
            case .decrement: onSubtract()
            @unknown default: break
            }
        }
```

- [ ] **Step 3: Pass both closures from `CategoryRows`**

Replace the `ForEach` body in `CategoryRows` — currently:

```swift
                        ForEach(rows) { row in
                            CategoryRow(progress: row) {
                                model.logExternal(to: row.isFallback ? .fallback : .named(row.name))
                            }
                        }
```

with:

```swift
                        ForEach(rows) { row in
                            let target: CategoryTarget =
                                row.isFallback ? .fallback : .named(row.name)
                            CategoryRow(progress: row,
                                        onAdd: { model.logExternal(to: target) },
                                        onSubtract: { model.unlogToday(from: target) })
                        }
```

Also update the type's doc comment, which currently promises the old behavior:

```swift
/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row logs one pomodoro to that category.
```

becomes:

```swift
/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row opens a counter that adds to or subtracts from its count.
```

- [ ] **Step 4: Build and run the full suite**

```bash
just test
```

Expected: PASS, no new failures. No new unit tests in this task — views are thin over the logic tested in Tasks 1 and 2, and neither a popover's presentation nor an accessibility action is reachable from swift-testing.

- [ ] **Step 5: Verify by hand, because nothing else can**

`just preview` cannot show this: a popover is its own window, which is the whole reason this app uses popovers for dialogs. Do not treat a green suite as evidence the popover looks right.

```bash
just install
```

Then, with categories enabled, check all of:

1. Tapping a row opens the strip beside it, not over the rows below.
2. `+` raises the row's count behind the popover; the menu bar count follows.
3. `−` lowers it; at zero the `−` is visibly dim and does nothing.
4. Clicking outside and pressing Escape both close it; the panel itself stays open.
5. The strip is themed in Synthwave as well as the default — a popover that skipped `.themed(palette)` shows up as a light-mode strip.
6. With a goal set, the count reads `3/8`; with the goal at 0 it reads `3`.

If any of these fail, fix and re-run this step before committing.

- [ ] **Step 6: Add the CHANGELOG entry**

Under the existing `## [Unreleased]` → `### Changed`, append:

```markdown
- **Tapping a category now opens a counter instead of logging straight away.**
  The row opens a small `−`/count/`+` strip, so a count can come down as well as
  up — correcting a mis-tap on one category no longer means reaching for "Undo
  last" and hoping nothing has landed on another category since. VoiceOver keeps
  its one-swipe adjustment on the row itself.
```

- [ ] **Step 7: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryRows.swift CHANGELOG.md
git commit -m "Open a counter on a category row instead of logging at once"
git push
```

Body for the commit message:

```
The row was a one-way ratchet, and the only way down was a global "Undo
last" whose behaviour depended on rows the user wasn't looking at.

Tapping opens a −/count/+ strip on the row's trailing edge; each tap
commits. The popover takes closures rather than the model, and applies the
theme itself, for the two reasons every other popover in this app does.

The row keeps its one-activation VoiceOver path through an adjustable
action, so the popover costs nothing to a screen reader.
```

---

## Notes for the executor

- **Work in a worktree, not the shared checkout.** This repo has had another session land commits on a branch created in place. Create the worktree via the `superpowers:using-git-worktrees` skill before Task 1, and if you dispatch subagents, force `git -C <worktree>` — a dispatched agent's cwd does not inherit the worktree and will otherwise commit to `main`.
- **Task order is a dependency chain:** Task 2 will not compile without Task 1, and Task 3 will not compile without Task 2. Do not reorder.
- **Baseline is 347 tests green.** Task 1 adds 6, Task 2 adds 6.
