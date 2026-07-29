# Category auto-advance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a category meets its daily goal, the session target moves on by itself to the next category that still has an unmet goal.

**Architecture:** A pure function, `CategoryAdvance.next(after:in:)`, decides the successor from the current `CategoryTarget` and the `[CategoryProgress]` rows `AppModel.todayProgress` already builds. A thin `AppModel.advanceTargetIfMet()` wrapper calls it after every record is appended — `complete()` for the timer, `logExternal()` for the log button, hotkey and URL scheme. All the logic lives in the pure function, where it is testable without a timer, a store or a view.

**Tech Stack:** Swift Package Manager, SwiftUI + AppKit reach-ins, swift-testing (not XCTest), macOS 14+.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-29-category-auto-advance-design.md` is the authority. Read it before Task 1.
- **Tests are swift-testing**, in `Tests/PomodoroCountTests`: `import Testing`, `@Suite struct`, `@Test func`, `#expect(...)`. Never XCTest.
- **TDD**: the failing test comes first, and you must see it fail for the stated reason before writing the implementation.
- **Comments record WHY and stay.** Decisions that look odd carry their reasoning in place. Don't strip existing comments; don't re-litigate a commented decision.
- **Availability rule, used verbatim everywhere:** a candidate is available when `goal > 0 && done < goal`. Goal-0 categories are never available.
- **The advance only fires when the current target is itself met.** A goal met by some other category does nothing.
- **`Settings` decodes field-by-field with defaults** so an older `data.json` always loads. Every new field must follow that pattern.
- **Full suite:** `just test`. **One suite:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <SuiteName>` (the `DEVELOPER_DIR` prefix is harmless when full Xcode is already the active toolchain).
- **Commit at the end of every task.** Commit subjects are short imperative sentences; bodies explain the why.

---

### Task 1: The rule — `CategoryAdvance.next(after:in:)`

**Files:**
- Create: `Sources/PomodoroCount/CategoryAdvance.swift`
- Test: `Tests/PomodoroCountTests/CategoryAdvanceTests.swift`

**Interfaces:**
- Consumes: `CategoryTarget` (`Sources/PomodoroCount/Category.swift:32`) — an enum with cases `.fallback` and `.named(String)`. `CategoryProgress` (`Category.swift:38`) — a struct with `let id: String`, `name: String`, `done: Int`, `goal: Int`, `isFallback: Bool`, `isSessionTarget: Bool`, and a computed `var isMet: Bool { goal > 0 && done >= goal }`. `Category.normalized(_ name: String) -> String` (`Category.swift:18`) lowercases and trims.
- Produces: `CategoryAdvance.next(after current: CategoryTarget, in rows: [CategoryProgress]) -> CategoryTarget?` — Task 3 is its only caller.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/CategoryAdvanceTests.swift`:

```swift
import Testing
@testable import PomodoroCount

/// The rule is pure, so none of this needs a model, a store or the main actor.
@Suite struct CategoryAdvanceTests {

    /// A row shaped the way `todayProgress` builds them. `id` plays no part in
    /// the rule, so it just mirrors the name.
    private func row(_ name: String, done: Int, goal: Int,
                     isFallback: Bool = false) -> CategoryProgress {
        CategoryProgress(id: name, name: name, done: done, goal: goal,
                         isFallback: isFallback, isSessionTarget: false)
    }

    /// Two categories and the bucket, in the order `todayProgress` returns them.
    private func rows(work: (Int, Int) = (0, 4),
                      music: (Int, Int) = (0, 1),
                      bucket: (Int, Int) = (0, 0)) -> [CategoryProgress] {
        [row("Work", done: work.0, goal: work.1),
         row("Music", done: music.0, goal: music.1),
         row("General", done: bucket.0, goal: bucket.1, isFallback: true)]
    }

    @Test func advancesToTheNextUnmetCategory() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (4, 4), music: (0, 1)))
        #expect(next == .named("Music"))
    }

    /// A met category at the end of the list looks back at unfinished ones above
    /// it, rather than giving up because it ran out of rows.
    @Test func wrapsPastTheEndOfTheList() {
        let next = CategoryAdvance.next(
            after: .named("Music"), in: rows(work: (1, 4), music: (1, 1)))
        #expect(next == .named("Work"))
    }

    /// A goal of 0 means "tracked without a target", so `isMet` is false for it
    /// forever — landing there would be a sink the rotation could never leave.
    @Test func skipsCategoriesWithNoGoal() {
        let next = CategoryAdvance.next(
            after: .named("Work"),
            in: rows(work: (4, 4), music: (0, 0), bucket: (0, 2)))
        #expect(next == .fallback)
    }

    @Test func advancesIntoTheBucketWhenItCarriesAGoal() {
        let next = CategoryAdvance.next(
            after: .named("Music"),
            in: rows(work: (4, 4), music: (1, 1), bucket: (0, 3)))
        #expect(next == .fallback)
    }

    @Test func skipsTheBucketWhenItHasNoGoal() {
        let next = CategoryAdvance.next(
            after: .named("Music"),
            in: rows(work: (0, 4), music: (1, 1), bucket: (0, 0)))
        #expect(next == .named("Work"))
    }

    /// The whole day's plan is met, so the target stays where it is and further
    /// pomodoros overshoot there.
    @Test func staysPutWhenNothingIsAvailable() {
        let next = CategoryAdvance.next(
            after: .named("Work"),
            in: rows(work: (4, 4), music: (1, 1), bucket: (0, 0)))
        #expect(next == nil)
    }

    @Test func staysPutWhenTheCurrentTargetIsNotMet() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (3, 4), music: (0, 1)))
        #expect(next == nil)
    }

    /// A goal met by some *other* category is not this rule's business.
    @Test func staysPutWhenOnlyAnotherCategoryIsMet() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (0, 4), music: (1, 1)))
        #expect(next == nil)
    }

    /// `todayProgress` is empty while categories are off, and a target with no
    /// row has nowhere to start the search from.
    @Test func staysPutWhenThereAreNoRows() {
        #expect(CategoryAdvance.next(after: .named("Work"), in: []) == nil)
    }

    /// The bucket is matched by `isFallback`, not by name — its row carries the
    /// user's chosen fallback name, which `.fallback` knows nothing about.
    @Test func advancesFromTheBucketWhenItIsTheMetTarget() {
        let next = CategoryAdvance.next(
            after: .fallback,
            in: rows(work: (0, 4), music: (1, 1), bucket: (2, 2)))
        #expect(next == .named("Work"))
    }

    /// Names are compared normalized everywhere else in this codebase; a target
    /// spelled differently from its row must still be found.
    @Test func matchesTheTargetIgnoringCaseAndWhitespace() {
        let next = CategoryAdvance.next(
            after: .named("  work "), in: rows(work: (4, 4), music: (0, 1)))
        #expect(next == .named("Music"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryAdvanceTests`

Expected: compile failure — `cannot find 'CategoryAdvance' in scope`. That is the correct failure; the type does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PomodoroCount/CategoryAdvance.swift`:

```swift
import Foundation

/// Picks the session target that succeeds a finished one.
///
/// Pure and total over its inputs, so wrapping, the goal-0 skip and every way of
/// staying put are all testable without a timer, a store or a view — the same
/// shape as `Reorder.destination` and `HeatmapLayout.cells`.
/// `AppModel.advanceTargetIfMet()` is the only caller.
enum CategoryAdvance {

    /// The target to move to, or nil to stay put.
    ///
    /// `rows` is `AppModel.todayProgress`: every category in display order, then
    /// the fallback bucket. Returns nil unless `current` is one of those rows
    /// *and* its goal is met — a goal met by some other category is not this
    /// rule's business.
    static func next(after current: CategoryTarget,
                     in rows: [CategoryProgress]) -> CategoryTarget? {
        guard let start = rows.firstIndex(where: { matches(current, $0) }),
              rows[start].isMet
        else { return nil }

        // Wrap, so a met category at the end of the list looks back at
        // unfinished ones above it. The range stops one short of a full lap, so
        // a met target can never be handed back as its own successor.
        for offset in 1..<max(rows.count, 1) {
            let row = rows[(start + offset) % rows.count]
            // Availability has to ask for a goal as well as an unmet one:
            // `isMet` is false forever when the goal is 0, so a goal-0 category
            // would be a sink the rotation could never leave.
            guard row.goal > 0, !row.isMet else { continue }
            return row.isFallback ? .fallback : .named(row.name)
        }
        return nil
    }

    /// The bucket is identified by `isFallback` rather than by name: its row
    /// carries whatever the user called it, and `.fallback` names nothing.
    private static func matches(_ target: CategoryTarget,
                                _ row: CategoryProgress) -> Bool {
        switch target {
        case .fallback:
            return row.isFallback
        case .named(let name):
            return !row.isFallback
                && Category.normalized(row.name) == Category.normalized(name)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategoryAdvanceTests`

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/CategoryAdvance.swift Tests/PomodoroCountTests/CategoryAdvanceTests.swift
git commit -m "Work out which category follows a finished one

Pure over the rows todayProgress already builds, so wrapping, the goal-0
skip and every way of staying put are testable without a timer or a view.
A goal of 0 can never be met, so it can never be left either — those
categories are skipped rather than becoming a sink."
```

---

### Task 2: Persist the opt-out — `Settings.autoAdvanceTarget`

**Files:**
- Modify: `Sources/PomodoroCount/Types.swift:89` (add the property after `sessionTargetName`) and `Types.swift:112` (add the decode line)
- Test: `Tests/PomodoroCountTests/PersistenceTests.swift:99` (extend `missingSettingsKeysFallBackToDefaults`)

**Interfaces:**
- Produces: `Settings.autoAdvanceTarget: Bool`, default `true`. Task 3 gates on it, Task 4 binds a Toggle to it.

`CodingKeys` is synthesized for `Settings` — there is no explicit enum — so adding a stored property gives it a coding key and puts it in the synthesized `encode(to:)` automatically. Only the hand-written `init(from:)` needs a new line.

- [ ] **Step 1: Write the failing test**

In `Tests/PomodoroCountTests/PersistenceTests.swift`, add one line to the existing `missingSettingsKeysFallBackToDefaults` test so it reads:

```swift
    @Test func missingSettingsKeysFallBackToDefaults() throws {
        let url = try storeURL(containing: """
        {"records":[],"settings":{"workMinutes":25,"breakMinutes":5,\
        "autoStartBreak":true,"soundEnabled":true}}
        """)
        let m = AppModel(storeURL: url)
        #expect(m.settings.shortcut.display == "⌃⌥⌘P")
        #expect(m.settings.globalShortcutEnabled)
        #expect(m.settings.theme == .classic)
        #expect(m.settings.autoAdvanceTarget)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PersistenceTests`

Expected: compile failure — `value of type 'Settings' has no member 'autoAdvanceTarget'`.

- [ ] **Step 3: Add the property and its decode line**

In `Sources/PomodoroCount/Types.swift`, immediately after the `sessionTargetName` property (line 89):

```swift
    /// When on, a target whose goal is met hands off to the next category that
    /// still has one. Defaults on: it can only ever fire once the user has set
    /// goals, and the panel's "towards …" pill shows it happen.
    var autoAdvanceTarget = true
```

And in `init(from decoder:)`, immediately after the `sessionTargetName` line (line 112):

```swift
        autoAdvanceTarget     = try c.decodeIfPresent(Bool.self, forKey: .autoAdvanceTarget) ?? true
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PersistenceTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/Types.swift Tests/PomodoroCountTests/PersistenceTests.swift
git commit -m "Remember whether the target may advance itself

Decoded with a default like every other setting, so a data.json from
1.1.0 still loads and arrives with the behaviour switched on."
```

---

### Task 3: Wire it up — `advanceTargetIfMet()` at every logging path

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift` (append a new section at the end of the file)
- Modify: `Sources/PomodoroCount/Model.swift:328-338` (`complete()`, the `finished == .work` branch) and `Model.swift:351-357` (`logExternal`)
- Test: `Tests/PomodoroCountTests/CategorySessionTests.swift` (append to the existing suite)

**Interfaces:**
- Consumes: `CategoryAdvance.next(after:in:) -> CategoryTarget?` from Task 1; `Settings.autoAdvanceTarget` from Task 2; `AppModel.todayProgress: [CategoryProgress]` (`AppModel+Categories.swift:49`); `AppModel.sessionTarget: CategoryTarget` (a get/set computed property over `settings.sessionTargetName`, `Model.swift:41`); `suspendSaves()` / `resumeSaves()` (`Store.swift:96` and `:101`).
- Produces: `AppModel.advanceTargetIfMet()`.

Two ordering facts this task must not get wrong:

1. **The record is appended before the advance**, so a finished session credits the target it actually ran against. `resolve(sessionTarget)` is evaluated in the append expression, before the target can move.
2. **`logExternal`'s `target` argument is usually not the session target** — the panel's log button and the global hotkey both pass `.fallback`, and a category row passes its own name. The advance asks whether the *session target* is now met regardless of where this particular record went, which is the point: what matters is whether the thing the timer will credit is finished.

- [ ] **Step 1: Write the failing tests**

Append to the `CategorySessionTests` suite in `Tests/PomodoroCountTests/CategorySessionTests.swift`, inside the closing brace. Note `configured()` gives you `Work` (goal 4) and `Music` (goal 1), in that order, with the bucket last at goal 0.

```swift
    // MARK: Advancing to the next unfinished category

    /// The session that meets the goal still credits the target it ran against;
    /// only the *next* one goes somewhere new.
    @Test func meetingAGoalMovesTheTargetOnButNotThisRecord() {
        let m = configured()
        m.sessionTarget = .named("Music")        // goal 1, so this session meets it
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.sessionTarget == .named("Work"))
    }

    /// External hardware is the headline way pomodoros arrive here, so a log
    /// that fills the last slot has to move the target just as a session does.
    @Test func anExternalLogThatMeetsTheGoalMovesTheTarget() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Work"))
    }

    /// Nothing re-checks the target at Start, which is what lets a deliberate
    /// re-pick of a finished category stick: the next session credits it. (It
    /// advances again straight after, having met the goal a second time.)
    @Test func aDeliberateRePickIsHonouredForTheNextSession() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))       // Music met; target moved to Work
        m.sessionTarget = .named("Music")        // the user insists
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
    }

    /// The day's whole plan is met, so there is nowhere to advance to and
    /// further pomodoros overshoot where they are.
    @Test func theTargetStaysPutWhenEveryGoalIsMet() {
        let m = configured()
        m.settings.categories = [
            Category(name: "Work", dailyGoal: 1),
            Category(name: "Music", dailyGoal: 1),
        ]
        m.sessionTarget = .named("Work")
        m.logExternal(to: .named("Music"))       // Music met
        m.logExternal(to: .named("Work"))        // Work met, nothing left
        #expect(m.sessionTarget == .named("Work"))
    }

    /// Goals are invisible while categories are off and must not drive
    /// anything — the same rule `todayGoalTotal` follows.
    @Test func nothingAdvancesWhileCategoriesAreOff() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.categoriesEnabled = false
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Music"))
    }

    @Test func nothingAdvancesWhenTheSettingIsOff() {
        let m = configured()
        m.settings.autoAdvanceTarget = false
        m.sessionTarget = .named("Music")
        m.logExternal(to: .named("Music"))
        #expect(m.sessionTarget == .named("Music"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategorySessionTests`

Expected: the four tests that expect movement fail on the target still being its old value (e.g. `Expectation failed: (m.sessionTarget → .named("Music")) == (.named("Work"))`). The two "nothing advances" tests pass already — they assert the current behaviour, and they are here to hold it once the feature lands.

- [ ] **Step 3: Add `advanceTargetIfMet()`**

Append a new section to the end of `Sources/PomodoroCount/AppModel+Categories.swift`:

```swift
// MARK: - Following the day's plan

@MainActor
extension AppModel {

    /// Moves the session target on when it has met its goal, so the next
    /// pomodoro lands on something unfinished.
    ///
    /// Called after every record is appended — a completed session and every
    /// external log — because a goal is met by whichever of those happens to
    /// fill the last slot, and external hardware is this app's headline source.
    ///
    /// Nothing re-checks this when a session starts, and that is deliberate: it
    /// is what lets a deliberate re-pick of a finished category stick, so
    /// overshooting a goal on purpose still works.
    func advanceTargetIfMet() {
        guard settings.categoriesEnabled, settings.autoAdvanceTarget else { return }
        guard let next = CategoryAdvance.next(after: sessionTarget, in: todayProgress)
        else { return }
        sessionTarget = next
    }
}
```

- [ ] **Step 4: Call it from `complete()`**

In `Sources/PomodoroCount/Model.swift`, replace the record-append in the `finished == .work` branch of `complete()`:

```swift
        if finished == .work {
            focusSessionsThisCycle += 1
            records.append(Record(at: Date(), source: "timer",
                                  category: resolve(sessionTarget)))
```

with:

```swift
        if finished == .work {
            focusSessionsThisCycle += 1
            // The record and the target it may have just finished off are one
            // change as far as the store is concerned, so they cost one write
            // rather than two. The append comes first: this session credits the
            // target it actually ran against, and only the next one moves.
            suspendSaves()
            records.append(Record(at: Date(), source: "timer",
                                  category: resolve(sessionTarget)))
            advanceTargetIfMet()
            resumeSaves()
```

- [ ] **Step 5: Call it from `logExternal()`**

In the same file, replace the first line of `logExternal`:

```swift
    func logExternal(to target: CategoryTarget = .fallback, announce: Bool = false) {
        records.append(Record(at: Date(), source: "manual", category: resolve(target)))
```

with:

```swift
    func logExternal(to target: CategoryTarget = .fallback, announce: Bool = false) {
        // One write for the pair, as in `complete()`. `target` is usually not the
        // session target — the log button and the hotkey both pass `.fallback`,
        // a category row passes its own name — but the advance asks about the
        // session target either way: what matters is whether the category the
        // timer will credit is finished.
        suspendSaves()
        records.append(Record(at: Date(), source: "manual", category: resolve(target)))
        advanceTargetIfMet()
        resumeSaves()
```

- [ ] **Step 6: Run the suite to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CategorySessionTests`

Expected: PASS, all tests.

- [ ] **Step 7: Run the full suite**

Run: `just test`

Expected: PASS. `complete()` and `logExternal` are load-bearing for many suites (`TimerTests`, `LoggingTests`, `LongBreakTests`, `URLCommandTests`, `CategoryRoutingTests`, `NudgeTests`), and the new `suspendSaves()`/`resumeSaves()` bracket touches persistence. If anything fails here, fix it before committing — do not proceed to Task 4 with a red suite.

- [ ] **Step 8: Commit**

```bash
git add Sources/PomodoroCount/AppModel+Categories.swift Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/CategorySessionTests.swift
git commit -m "Hand the target on when its goal is met

Hooked into every path that appends a record, not into Start: external
hardware is how goals usually get met here, so a check at Start would
miss the common case. The append comes first, so the session that meets
the goal still credits the category it ran against.

Nothing re-checks at Start, which is what lets a deliberate re-pick of a
finished category stick — overshooting on purpose still works."
```

---

### Task 4: The Settings toggle, and the changelog entry

**Files:**
- Modify: `Sources/PomodoroCount/SettingsTab.swift:118-133` (after the "Add category" button, before the `Divider()` at line 134)
- Modify: `CHANGELOG.md` (the `## [Unreleased]` section)

**Interfaces:**
- Consumes: `Settings.autoAdvanceTarget` from Task 2.

There is no test step here. The toggle is a direct binding with no logic of its own — the behaviour it gates is already covered by Task 3's `nothingAdvancesWhenTheSettingIsOff` — and this codebase tests logic extracted from SwiftUI rather than the views over it. Verification is the preview render plus the full suite.

- [ ] **Step 1: Add the toggle**

In `Sources/PomodoroCount/SettingsTab.swift`, inside the `if model.settings.categoriesEnabled` block, between the "Add category" `Button` (with its `.popover`) and the `Divider()` that precedes "Everything else":

```swift
                        // A sub-option of the category list, so it sits above
                        // the divider that starts the bucket's own section.
                        // Caption2 explanation underneath, matching how the
                        // long-break and shortcut settings carry theirs.
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Move on when a goal is met",
                                   isOn: $model.settings.autoAdvanceTarget)
                            Text("A finished category hands the target to the next one with a goal left.")
                                .font(.caption2)
                                .foregroundStyle(palette.textDim)
                        }
```

- [ ] **Step 2: Check it builds and renders**

Run: `just preview`

Expected: the panel renders and opens. The preview covers all three tabs, so the Settings tab must still lay out — a `PanelTabScroller` height regression would show here as a clipped or collapsed tab.

- [ ] **Step 3: Run the full suite**

Run: `just test`

Expected: PASS. `PresentationTests` and `PanelMetricsTests` are the ones a Settings-tab change can disturb.

- [ ] **Step 4: Add the changelog entry**

Under `## [Unreleased]` in `CHANGELOG.md`, add an `### Added` section:

```markdown
### Added

- **The target follows the day's plan** — when a category meets its daily goal,
  the session target moves on by itself to the next category with a goal left,
  and the Focus tab's "towards …" pill says so straight away. Picking a finished
  category by hand still sticks, so overshooting one on purpose works. Switch it
  off with "Move on when a goal is met" in Settings.
```

The pill changing on its own is user-visible, and `just release` refuses to tag without an entry.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/SettingsTab.swift CHANGELOG.md
git commit -m "Offer a way to switch the advancing off

Default on: it can only fire once goals are set, and the pill shows it
happen. But it changes where records land, and someone using categories
as plain buckets — every new one arrives with a goal of 1 — should be
able to say no."
```

---

## Task 5: Verify it in the running app

**Files:** none — this task changes nothing.

The panel is a non-activating `NSPanel` and synthetic mouse events cannot drive its gestures, but nothing here needs a gesture: this is a label that must change and a toggle that must click. `just install` and check by hand.

- [ ] **Step 1: Install the build**

Run: `just install`

Expected: builds, replaces the `/Applications` copy, relaunches. The running app now matches the commits.

- [ ] **Step 2: Set up a category that is one pomodoro from its goal**

In the panel: Settings → make sure "Use categories" is on, and that you have at least two categories with goals. Set the first one's goal so today's count is one short of it — the Focus tab's rows show `done/goal` for each.

- [ ] **Step 3: Watch the pill move**

Aim the Focus tab's "towards …" pill at that nearly-finished category, then click its row in the Focus tab to log the pomodoro that meets its goal.

Expected: the row takes on its met-goal wash, and the pill changes to the next category with an unmet goal **immediately**, without the panel being reopened. That instant update is the whole point of the trigger — if it only changes after a reopen, the advance is firing but the view is not observing, and that is a bug.

- [ ] **Step 4: Check that a deliberate re-pick sticks**

Pick the now-finished category from the pill's menu again.

Expected: it stays picked. Nothing snaps it back.

- [ ] **Step 5: Check the toggle**

Settings → switch "Move on when a goal is met" off. Meet another category's goal.

Expected: the pill does not move.

- [ ] **Step 6: Report**

Nothing to commit. Report what you saw at each step — particularly step 3, which the unit suite cannot check.

---

## Self-Review

Ran against the spec:

**Spec coverage** — every section maps to a task. Trigger points → Task 3 steps 4 and 5 (`complete()`, `logExternal`). The rule, wrapping, goal-0 skipping, the three no-movement cases → Task 1. `CategoryAdvance.next(after:in:)` and `advanceTargetIfMet()` → Tasks 1 and 3. The two saves bracketed in `suspendSaves()`/`resumeSaves()` → Task 3 steps 4 and 5. `Settings.autoAdvanceTarget` decoded with a default → Task 2. The Settings toggle and its copy → Task 4. Every test the spec's Testing section names → Task 1 step 1 and Task 3 step 1. `CHANGELOG.md` → Task 4 step 4.

The spec's four "Out" items stay out, and the "deliberate re-pick sticks" property is pinned by a test rather than left as prose (Task 3, `aDeliberateRePickIsHonouredForTheNextSession`).

**Placeholders** — none. Every code step carries the actual code; no "add error handling", no "similar to Task N".

**Type consistency** — `CategoryAdvance.next(after:in:)` has one signature across Task 1 (definition), Task 3 (call site) and the Interfaces blocks. `advanceTargetIfMet()` is named identically in its definition, both call sites and the commit message. `autoAdvanceTarget` is spelled the same in Types.swift, the decode line, `advanceTargetIfMet()`, the SwiftUI binding and all three tests that touch it. `CategoryProgress`'s initializer in the test helper matches its declaration at `Category.swift:38` — `id`, `name`, `done`, `goal`, `isFallback`, `isSessionTarget`, all six, in order.

One thing fixed inline while reviewing: `for offset in 1..<rows.count` traps on an empty `rows`, which `staysPutWhenThereAreNoRows` exercises. The `firstIndex` guard already returns first on empty input, so it could never actually be reached — but a range expression that is only safe because of a guard above it is a trap waiting for a refactor. It is `1..<max(rows.count, 1)` in the plan.
