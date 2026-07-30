# Category Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the category list a priority ranking — the session target falls to the highest-ranked category that still has a goal left, restarts at the top each day, and holds still when the user deliberately points it at a category they have already finished.

**Architecture:** The pure rule in `CategoryAdvance` swaps its forward-wrapping search for a search from the top of the list, and gains a `pinned` escape and an `isMet` query. Two new `Settings` fields carry the state the rule can't derive: `targetPinned` (the user asked to overshoot) and `targetAimedOn` (the day the target was last aimed, so the start-of-day reset survives a quit). `AppModel.advanceTargetIfMet()` becomes `realignTarget()`, holding both automatic triggers behind the checks they share, and a new `pickTarget(_:)` is the hand-pick path that decides which kind of pick just happened.

**Tech Stack:** Swift 5.9+, Swift Package Manager, SwiftUI + AppKit, swift-testing (`import Testing`, **not** XCTest), macOS 14+.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-30-category-ranking-design.md`. Read it before Task 1.
- **Tests are swift-testing**, not XCTest: `import Testing`, `@Suite struct`, `@Test func`, `#expect(...)`. Never `XCTAssert`.
- **Run tests with `just test`**, which borrows Xcode's toolchain when the Command Line Tools are active. A single suite is `swift test --filter SuiteName`, prefixed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `swift test` alone fails to find swift-testing.
- **TDD, strictly.** Failing test first, watch it fail, minimal implementation, watch it pass, commit. Every task below is written in that order.
- **Comments record WHY and stay.** This codebase carries its reasoning in place ("measured, not assumed"). The comments in this plan's code blocks are part of the deliverable — type them in. Do not strip existing comments; where a comment describes behaviour this plan changes, rewrite it to describe the new behaviour and its reason.
- **New `Settings` fields decode field-by-field with defaults** (`try c.decodeIfPresent(...) ?? default`) so a `data.json` written by an older version still loads. This is non-negotiable — see `Sources/PomodoroCount/Types.swift:100`.
- **`autoAdvanceTarget` keeps its Swift name and its JSON key** even though its meaning widens. Renaming it would make the missing key decode to the `true` default and silently un-opt-out everyone who turned it off.
- **Commit subjects are short imperative sentences that tell the story**; bodies explain why. Commit after every task.
- **`CHANGELOG.md` gets an entry for user-visible changes** (Keep a Changelog format, under `## [Unreleased]`). Task 6 does this.
- **Do not add `@Published` fast-tickers to `AppModel`** and do not touch `SessionClock`. Nothing in this plan needs to.

---

## File Structure

| File | Change | Responsibility after this plan |
|---|---|---|
| `Sources/PomodoroCount/CategoryAdvance.swift` | Modify | The pure rule: `topUnmet(in:)`, `next(after:in:pinned:)`, `isMet(_:in:)` |
| `Sources/PomodoroCount/Types.swift` | Modify | `Settings.targetPinned`, `Settings.targetAimedOn`, their decode lines, and `Settings.aim(at:)` |
| `Sources/PomodoroCount/Model.swift` | Modify | `sessionTarget`'s setter routes through `Settings.aim(at:)`; two call sites renamed |
| `Sources/PomodoroCount/AppModel+Categories.swift` | Modify | `realignTarget()`, `restartFromTopOfRanking()`, `pickTarget(_:)`, `followTheOrder()`, `sessionTargetDescription`, pin-clearing in `removeCategory(id:)` |
| `Sources/PomodoroCount/PomodoroCountApp.swift` | Modify | One `realignTarget()` call at launch |
| `Sources/PomodoroCount/SystemIntegration.swift` | Modify | The day-change/wake closure also calls `realignTarget()` |
| `Sources/PomodoroCount/RootView.swift` | Modify | The pill: *Follow the order* entry, `pickTarget(_:)` routing, `sessionTargetDescription` label |
| `Sources/PomodoroCount/SettingsTab.swift` | Modify | The toggle's label and caption copy |
| `Tests/PomodoroCountTests/CategoryAdvanceTests.swift` | Modify | The pure rule's tests |
| `Tests/PomodoroCountTests/CategorySessionTests.swift` | Modify | The model-level target behaviour |
| `Tests/PomodoroCountTests/PersistenceTests.swift` | Modify | The two new fields round-trip and default |
| `CHANGELOG.md`, `AGENTS.md` | Modify | Docs |

---

### Task 1: The pure rule — search from the top

**Files:**
- Modify: `Sources/PomodoroCount/CategoryAdvance.swift` (whole file)
- Test: `Tests/PomodoroCountTests/CategoryAdvanceTests.swift`

**Interfaces:**
- Consumes: `CategoryProgress` (`Sources/PomodoroCount/Category.swift:37`) with `name`, `goal`, `isFallback`, and `var isMet: Bool { goal > 0 && done >= goal }`; `CategoryTarget` (`Category.swift:32`) with cases `.fallback` and `.named(String)`; `Category.normalized(_:)`.
- Produces:
  - `CategoryAdvance.topUnmet(in rows: [CategoryProgress]) -> CategoryTarget?`
  - `CategoryAdvance.next(after current: CategoryTarget, in rows: [CategoryProgress], pinned: Bool) -> CategoryTarget?`
  - `CategoryAdvance.isMet(_ target: CategoryTarget, in rows: [CategoryProgress]) -> Bool`

**Context you need:** the existing rule searches *forward from the current target and wraps*, taking the first available row. The new rule searches *from index 0*. Every one of the 11 existing tests in `CategoryAdvanceTests` happens to pass under both rules — none of them exercises the case where the two diverge, which is exactly why Step 1 adds that case first.

- [ ] **Step 1: Write the failing test for the divergent case**

Add to `Tests/PomodoroCountTests/CategoryAdvanceTests.swift`, after the existing `advancesToTheNextUnmetCategory` test. Note this uses a three-category helper the file doesn't have yet, so add both:

```swift
    /// Three categories, so the rule has somewhere both above *and* below the
    /// current target to go. `rows(…)` above can't express that: its middle
    /// category is the only one that can sit between two others.
    private func ranked(_ a: (Int, Int), _ b: (Int, Int), _ c: (Int, Int))
        -> [CategoryProgress] {
        [row("A", done: a.0, goal: a.1),
         row("B", done: b.0, goal: b.1),
         row("C", done: c.0, goal: c.1),
         row("General", done: 0, goal: 0, isFallback: true)]
    }

    /// The whole point of the change. The list is a priority ranking, so a met
    /// target hands off to the highest-ranked category with a goal left — *up*
    /// the list, past unfinished work, rather than onwards to whatever happens
    /// to sit below it. The old rotation answered `C` here.
    @Test func handsOffToTheHighestRankedUnmetCategory() {
        let next = CategoryAdvance.next(
            after: .named("B"), in: ranked((0, 1), (1, 1), (0, 1)), pinned: false)
        #expect(next == .named("A"))
    }

    /// A pin means the user pointed the target at a category they had already
    /// finished, which can only mean "let me overshoot here". Nothing moves.
    @Test func staysPutWhilePinned() {
        let next = CategoryAdvance.next(
            after: .named("B"), in: ranked((0, 1), (1, 1), (0, 1)), pinned: true)
        #expect(next == nil)
    }

    @Test func theTopUnmetRowIsTheHighestRankedOneWithAGoalLeft() {
        #expect(CategoryAdvance.topUnmet(in: ranked((1, 1), (0, 1), (0, 1)))
                == .named("B"))
    }

    @Test func thereIsNoTopUnmetRowWhenEveryGoalIsMet() {
        #expect(CategoryAdvance.topUnmet(in: ranked((1, 1), (1, 1), (1, 1))) == nil)
    }

    /// `isMet` is how `pickTarget` tells the two kinds of hand pick apart, so it
    /// has to answer for the bucket and for an absent row too.
    @Test func isMetAnswersForEveryKindOfTarget() {
        let rows = self.rows(work: (4, 4), music: (0, 1), bucket: (2, 2))
        #expect(CategoryAdvance.isMet(.named("Work"), in: rows))
        #expect(!CategoryAdvance.isMet(.named("Music"), in: rows))
        #expect(CategoryAdvance.isMet(.fallback, in: rows))
        #expect(!CategoryAdvance.isMet(.named("Nowhere"), in: rows))
    }

    /// A goal of 0 can never be met, so picking one never pins — the other half
    /// of "goal-0 needs no special case" is that the advance can't fire on it
    /// either, which `staysPutWhenTheCurrentTargetIsNotMet` already covers.
    @Test func aGoalOfZeroIsNeverMet() {
        #expect(!CategoryAdvance.isMet(.named("Music"),
                                       in: rows(work: (0, 4), music: (3, 0))))
    }
```

- [ ] **Step 2: Add the `pinned:` argument to the 11 existing tests**

Every existing call in the file is `CategoryAdvance.next(after: X, in: Y)`. Add `, pinned: false` to each. There are 11, in these tests: `advancesToTheNextUnmetCategory`, `wrapsPastTheEndOfTheList`, `skipsCategoriesWithNoGoal`, `advancesIntoTheBucketWhenItCarriesAGoal`, `skipsTheBucketWhenItHasNoGoal`, `staysPutWhenNothingIsAvailable`, `staysPutWhenTheCurrentTargetIsNotMet`, `staysPutWhenOnlyAnotherCategoryIsMet`, `staysPutWhenThereAreNoRows`, `advancesFromTheBucketWhenItIsTheMetTarget`, `matchesTheTargetIgnoringCaseAndWhitespace`.

Also rename `wrapsPastTheEndOfTheList` and rewrite its comment — there is no wrapping any more, and the name would lie:

```swift
    /// A met category at the end of the list still finds unfinished ones above
    /// it. Under the old rotation this was the wrap-around case; under a
    /// ranking it is just "search from the top", which is the same answer for a
    /// less interesting reason.
    @Test func handsBackUpToAnUnfinishedCategoryAboveIt() {
        let next = CategoryAdvance.next(
            after: .named("Music"), in: rows(work: (1, 4), music: (1, 1)),
            pinned: false)
        #expect(next == .named("Work"))
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `just test 2>&1 | tail -30`

Expected: compile failure — `extra argument 'pinned' in call`, and `type 'CategoryAdvance' has no member 'topUnmet'` / `'isMet'`.

- [ ] **Step 4: Rewrite `CategoryAdvance.swift`**

Replace the whole file with:

```swift
import Foundation

/// Picks the session target that succeeds a finished one.
///
/// Pure and total over its inputs, so the ranking, the goal-0 skip, the pin and
/// every way of staying put are all testable without a timer, a store or a
/// view — the same shape as `Reorder.destination` and `HeatmapLayout.cells`.
/// `AppModel` is the only caller.
enum CategoryAdvance {

    /// The highest-ranked row with a goal left, or nil when the day's plan is
    /// done.
    ///
    /// `rows` is `AppModel.todayProgress`: every category in display order, then
    /// the fallback bucket. Display order *is* the ranking — this list is a
    /// priority order, not a rotation, so the search starts at the top rather
    /// than at whatever position the target happens to occupy. That is the whole
    /// change from the rule this replaced, and it is why the modulo arithmetic
    /// that used to live here is gone: searching from the top cannot hand a met
    /// target back to itself, so nothing has to stop the search one short of a
    /// full lap any more.
    ///
    /// Availability asks for a goal as well as an unmet one: `isMet` is false
    /// forever when the goal is 0, so a goal-0 category would be a sink nothing
    /// could ever leave. The bucket joins on the same terms, and ranks last.
    static func topUnmet(in rows: [CategoryProgress]) -> CategoryTarget? {
        guard let row = rows.first(where: { $0.goal > 0 && !$0.isMet })
        else { return nil }
        return row.isFallback ? .fallback : .named(row.name)
    }

    /// The target to move to, or nil to stay put.
    ///
    /// Returns nil unless `current` is one of `rows` *and* its goal is met — a
    /// goal met by some other category is not this rule's business.
    ///
    /// `pinned` suppresses it outright. A pin means the user aimed the target at
    /// a category that was already met, which can only mean "let me overshoot
    /// here"; without it a deliberate overshoot would last exactly one pomodoro,
    /// because the next record would find the target met all over again.
    static func next(after current: CategoryTarget,
                     in rows: [CategoryProgress],
                     pinned: Bool) -> CategoryTarget? {
        guard !pinned, isMet(current, in: rows) else { return nil }
        return topUnmet(in: rows)
    }

    /// True when `target`'s row has met its goal. A target with no row at all —
    /// categories switched off, so `todayProgress` is empty — is not met, which
    /// is what keeps both callers from doing anything in that state.
    ///
    /// Public because it answers a question `AppModel.pickTarget(_:)` has to
    /// ask: picking a met category pins, picking an unfinished one does not.
    /// Asking it here rather than there keeps row-matching in one place.
    static func isMet(_ target: CategoryTarget,
                      in rows: [CategoryProgress]) -> Bool {
        rows.first { matches(target, $0) }?.isMet ?? false
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

- [ ] **Step 5: Run the tests to verify they pass**

Run: `just test 2>&1 | tail -20`

Expected: PASS. `CategoryAdvanceTests` now has 17 tests. Every pre-existing one still passes — none of them exercised the divergent case, which is why they survive a rule change unedited apart from the new argument.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/CategoryAdvance.swift Tests/PomodoroCountTests/CategoryAdvanceTests.swift
git commit -m "$(cat <<'MSG'
Search the ranking from the top, not around the ring

The rule walked forward from the current target and wrapped, which answers
"what is next around the ring". A list of daily goals written in priority
order poses a different question, and the two answers diverge whenever the
target sits below unfinished work.

Every existing test passed under both rules, which is its own finding: none
of them covered the divergent case. That case is now the first test in the
file.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: The two persisted fields

**Files:**
- Modify: `Sources/PomodoroCount/Types.swift` (the `Settings` struct, around `:88-95` and the decode block at `:100-120`)
- Modify: `Sources/PomodoroCount/Model.swift:48-53` (the `sessionTarget` setter)
- Test: `Tests/PomodoroCountTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `Settings.targetPinned: Bool`, default `false`
  - `Settings.targetAimedOn: Date?`, default `nil`
  - `Settings.aim(at target: CategoryTarget)` — a `mutating` func, used by every later task that batches target changes into one `settings` assignment

**Why `aim(at:)` exists:** `AppModel.sessionTarget`'s setter maps a `CategoryTarget` onto `settings.sessionTargetName`. Tasks 3 and 4 need that same mapping *inside* a local `var updated = settings` copy, because they change two or three fields at once and each separate mutation of `settings` fires its own `didSet` → `save()`. Rather than duplicate the switch, the mapping moves onto `Settings` and the model's setter calls it.

- [ ] **Step 1: Write the failing persistence tests**

Add to `Tests/PomodoroCountTests/PersistenceTests.swift`, near the existing `autoAdvanceTarget` default assertion at `:163`:

```swift
    /// The pin and the day stamp both survive a relaunch: a pin the user set
    /// this morning must still hold after lunch, and a stamp that didn't
    /// persist would make every launch look like a new day.
    @Test func theTargetPinAndDayStampRoundTrip() {
        let (m, url) = makeModel()
        let stamp = Date(timeIntervalSince1970: 1_780_000_000)
        m.settings.targetPinned = true
        m.settings.targetAimedOn = stamp
        let reloaded = AppModel(storeURL: url).settings
        #expect(reloaded.targetPinned)
        #expect(reloaded.targetAimedOn == stamp)
    }
```

And extend whatever test at `:163` asserts the older defaults — find the `#expect(m.settings.autoAdvanceTarget)` line and add these two beneath it, inside the same test:

```swift
        // An older data.json carries neither key. Decoding them to these
        // defaults is what makes the first launch after this ships re-aim once
        // — a nil stamp reads as "the day turned over" — rather than needing a
        // migration step of its own.
        #expect(!m.settings.targetPinned)
        #expect(m.settings.targetAimedOn == nil)
```

- [ ] **Step 2: Run to verify it fails**

Run: `just test 2>&1 | tail -20`

Expected: compile failure — `value of type 'Settings' has no member 'targetPinned'`.

- [ ] **Step 3: Add the fields and the decode lines**

In `Sources/PomodoroCount/Types.swift`, directly after the `autoAdvanceTarget` declaration:

```swift
    /// True when the user aimed the target at a category that was *already*
    /// met. The only reading of such a pick is "let me overshoot here", so it
    /// suppresses the met-goal advance until the day turns over or the user
    /// hands control back. A pick of an unfinished category leaves this false:
    /// it needs no pin, because the advance only ever fires on a met target.
    var targetPinned = false
    /// The day the target was last aimed, so the start-of-day reset survives a
    /// quit or a long sleep. `NSCalendarDayChanged` only fires while the app is
    /// running, so a reset driven by that notification alone would be missed by
    /// anyone who closes their laptop overnight. A stamp is checked whenever the
    /// app next looks, however it finds out the day turned over.
    var targetAimedOn: Date?
```

In the decode block, after the `autoAdvanceTarget` line:

```swift
        targetPinned          = try c.decodeIfPresent(Bool.self, forKey: .targetPinned) ?? false
        targetAimedOn         = try c.decodeIfPresent(Date.self, forKey: .targetAimedOn)
```

- [ ] **Step 4: Add `Settings.aim(at:)` and route the model's setter through it**

Add to `Types.swift`, as an extension below the `Settings` struct:

```swift
extension Settings {
    /// Writes a session target into the settings value.
    ///
    /// `AppModel.sessionTarget`'s setter is the usual way in, but the paths that
    /// change the target *and* the pin *and* the day stamp have to batch all
    /// three into one assignment — each separate mutation of `settings` is its
    /// own `didSet` and its own write to disk. They need this mapping on a local
    /// copy, so it lives here and the setter calls it rather than the two
    /// keeping their own copies of the same switch.
    mutating func aim(at target: CategoryTarget) {
        switch target {
        case .named(let name): sessionTargetName = name
        case .fallback: sessionTargetName = nil
        }
    }
}
```

Then in `Sources/PomodoroCount/Model.swift`, replace the `sessionTarget` setter body:

```swift
        set { settings.aim(at: newValue) }
```

- [ ] **Step 5: Run to verify it passes**

Run: `just test 2>&1 | tail -20`

Expected: PASS, whole suite. If `Date` decoding errors, check that `Settings`'s encoder/decoder pair uses the same date strategy the rest of the store does — `Record.at` is already a `Date`, so no new strategy is needed.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/Types.swift Sources/PomodoroCount/Model.swift Tests/PomodoroCountTests/PersistenceTests.swift
git commit -m "$(cat <<'MSG'
Persist the target's pin and the day it was aimed

Neither can be derived. A pinned met category and a target sitting on a met
category because nothing else was available look identical from the records,
and NSCalendarDayChanged only fires while the app runs — so a reset driven by
the notification alone would be missed by anyone who shuts the lid.

Settings.aim(at:) comes along now because the paths that write these fields
change two or three at once, and each separate mutation of `settings` is its
own write to disk.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: `realignTarget()` — both automatic triggers

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift:283-316` (the "Following the day's plan" section)
- Modify: `Sources/PomodoroCount/Model.swift:412` and `:445` (the two call sites)
- Modify: `Sources/PomodoroCount/PomodoroCountApp.swift:17` area (launch)
- Modify: `Sources/PomodoroCount/SystemIntegration.swift:218-227` (`startDayMonitoring`)
- Test: `Tests/PomodoroCountTests/CategorySessionTests.swift`

**Interfaces:**
- Consumes: `CategoryAdvance.topUnmet(in:)` and `CategoryAdvance.next(after:in:pinned:)` from Task 1; `Settings.targetPinned`, `Settings.targetAimedOn`, `Settings.aim(at:)` from Task 2; `AppModel.todayProgress: [CategoryProgress]` (`AppModel+Categories.swift:49`); `AppModel.sessionTarget` (`Model.swift:41`).
- Produces:
  - `AppModel.realignTarget()` — replaces `advanceTargetIfMet()`, same call sites plus two
  - `AppModel.restartFromTopOfRanking()` — clears the pin, aims at `topUnmet`, stamps today. Task 4's `followTheOrder()` calls it too, so it is `internal`, not `private`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PomodoroCountTests/CategorySessionTests.swift`. The `configured()` helper at the top of that file gives `Work` (goal 4) and `Music` (goal 1) with categories enabled.

```swift
    /// The ranking's payoff at model level: Music is met, Work is not, and Work
    /// ranks above it. The old rotation would have looked *past* Work.
    @Test func aMetGoalHandsOffUpTheRanking() {
        let m = configured()
        m.settings.categories.append(Category(name: "Admin", dailyGoal: 2))
        m.sessionTarget = .named("Music")            // goal 1, ranks second
        m.settings.targetAimedOn = Date()            // not a new day
        m.logExternal(to: .named("Music"))           // meets Music
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A stale stamp means the app has not aimed the target today: counts have
    /// reset, so the plan restarts at the top and yesterday's pin is stale.
    @Test func aNewDayRestartsAtTheTopOfTheRanking() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.realignTarget()
        #expect(m.sessionTarget == .named("Work"))
        #expect(!m.settings.targetPinned)
        #expect(Calendar.current.isDateInToday(m.settings.targetAimedOn ?? .distantPast))
    }

    /// Same day, so the reset must not fire — it would wipe a pick the user
    /// made half an hour ago.
    @Test func aSameDayStampLeavesTheTargetAlone() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))
        #expect(m.settings.targetPinned)
    }

    /// The reset is a start-of-day event, not a lazy one: it stamps even when
    /// there is nothing to aim at, so adding a goal at noon does not make it
    /// fire retroactively.
    @Test func theDailyResetStampsEvenWithNothingToAimAt() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 0)]
        m.settings.targetAimedOn = nil
        m.realignTarget()
        #expect(Calendar.current.isDateInToday(m.settings.targetAimedOn ?? .distantPast))
    }

    /// A pin suppresses the advance, so an overshoot lasts as long as the user
    /// wants rather than exactly one pomodoro.
    @Test func aPinnedTargetSurvivesRepeatedOvershoots() {
        let m = configured()
        m.sessionTarget = .named("Music")            // goal 1
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        for _ in 0..<3 { m.logExternal(to: .named("Music")) }
        #expect(m.sessionTarget == .named("Music"))
        #expect(m.todayCount(inCategory: "Music") == 3)
    }

    /// A session in flight is never re-aimed, the daily reset included: the
    /// record that finishes it has to land where Start pointed.
    @Test func aRunningSessionDefersTheDailyReset() {
        let m = configured()
        m.sessionTarget = .named("Music")
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.settings.workMinutes = 1
        m.startWork()
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))  // deferred, not lost
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music") // Start's promise kept
        #expect(m.sessionTarget == .named("Work"))   // and only then, the reset
    }

    /// Turning the rule off freezes both automatic triggers. Someone who opted
    /// out wants a target that never moves on its own, and an overnight re-aim
    /// violates that exactly as much as a met-goal one does.
    @Test func theOptOutFreezesTheDailyResetToo() {
        let m = configured()
        m.settings.autoAdvanceTarget = false
        m.sessionTarget = .named("Music")
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.realignTarget()
        #expect(m.sessionTarget == .named("Music"))
    }
```

- [ ] **Step 2: Rewrite the existing overshoot test, which asserts the old limit**

`aDeliberateRePickIsHonouredForTheNextSession` at `CategorySessionTests.swift:89` asserts that a re-pick buys exactly one pomodoro and then moves on (`#expect(m.sessionTarget == .named("Work"))` at `:98`). That is the behaviour being changed. Replace the whole test — comment included — with:

```swift
    /// A re-pick used to buy exactly one pomodoro: the next record found the
    /// target met all over again and moved it on. Now the pin holds, and Task 4
    /// is what sets it — here it stands in for that, so this test stays about
    /// the advance rather than about how the pin arrives.
    @Test func aRePickedFinishedCategoryKeepsTheNextSession() {
        let m = configured()
        m.logExternal(to: .named("Music"))       // Music met
        m.sessionTarget = .named("Music")        // the user insists
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        m.settings.workMinutes = 1
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.records.last?.category == "Music")
        #expect(m.sessionTarget == .named("Music"))
    }
```

- [ ] **Step 3: Run to verify the new tests fail**

Run: `just test 2>&1 | tail -30`

Expected: compile failure — `value of type 'AppModel' has no member 'realignTarget'`.

- [ ] **Step 4: Replace `advanceTargetIfMet()` with `realignTarget()`**

In `Sources/PomodoroCount/AppModel+Categories.swift`, replace the entire `// MARK: - Following the day's plan` extension (`:283` to the end of the file) with:

```swift
// MARK: - Following the day's plan

@MainActor
extension AppModel {

    /// Keeps the session target pointed at the day's plan.
    ///
    /// Two automatic triggers live here because they share every check around
    /// them. The start-of-day reset comes first and returns: at the start of a
    /// day nothing is met, so falling through to the advance could only ever be
    /// a no-op, and returning says so instead of leaving a reader to work it out.
    ///
    /// Called after every record is appended — a completed session and every
    /// external log — because a goal is met by whichever of those fills the last
    /// slot, and external hardware is this app's headline source. Also at launch
    /// and from the day-change/wake notification, which is where a new day gets
    /// noticed while the app is idle.
    ///
    /// Nothing re-checks this when a session starts, and that is deliberate: it
    /// is what lets a hand-picked target stick until its own goal is met.
    func realignTarget() {
        guard settings.categoriesEnabled, settings.autoAdvanceTarget else { return }
        // Don't re-aim a session that is actually in flight: an external log
        // that backfills the running target's last slot must not hand the
        // credit to wherever the target moves next — the record that finishes
        // this session still has to land on what Start was pressed against.
        // This does *not* block the advance at completion: `complete()` sets
        // `isRunning = false` before it appends the record and calls here, so a
        // session that meets its own goal still credits the right category and
        // only then hands the target on. Nor does it lose a start-of-day reset:
        // the stamp stays stale, and `complete()` is itself one of the points
        // that re-checks it. `phase == .work && isRunning` is deliberately the
        // same "actually running, not idle or paused" test `todayProgress` uses
        // for `isSessionTarget` — a paused session's target row isn't held
        // still either, so neither trigger should be.
        guard !(phase == .work && isRunning) else { return }

        // A stamp from an earlier day (or none at all, on a store written
        // before this feature existed) means the app has not aimed the target
        // today. Counts have reset, so the plan restarts at the top and
        // yesterday's pin is stale.
        guard Calendar.current.isDateInToday(settings.targetAimedOn ?? .distantPast)
        else { return restartFromTopOfRanking() }

        guard let next = CategoryAdvance.next(after: sessionTarget,
                                              in: todayProgress,
                                              pinned: settings.targetPinned)
        else { return }
        sessionTarget = next
    }

    /// Clears the pin, aims at the highest-ranked category with a goal left, and
    /// stamps today.
    ///
    /// Shared by the start-of-day reset above and by *Follow the order* in the
    /// target menu, which want exactly the same thing for different reasons.
    ///
    /// The stamp is written even when there is nothing to aim at — no category
    /// carries a goal, so `topUnmet` is nil. That makes this a start-of-day
    /// event rather than a lazy one: adding a goal at noon must not make the
    /// reset fire retroactively and move a target the user has been using all
    /// morning.
    ///
    /// One assignment to `settings`, not three. Each mutation of `settings` is
    /// its own `didSet` and its own synchronous write to disk, and the
    /// alternative — bracketing in `suspendSaves()`/`resumeSaves()` — would add
    /// call sites to a mechanism whose comment in Store.swift enumerates the
    /// existing ones by name and explains why each needs its own resume.
    func restartFromTopOfRanking() {
        var updated = settings
        updated.targetPinned = false
        updated.targetAimedOn = Date()
        if let top = CategoryAdvance.topUnmet(in: todayProgress) {
            updated.aim(at: top)
        }
        settings = updated
    }
}
```

- [ ] **Step 5: Rename the two existing call sites**

In `Sources/PomodoroCount/Model.swift`, change `advanceTargetIfMet()` to `realignTarget()` at `:412` (inside `complete()`) and `:445` (inside `logExternal`). Update the comment at `:405-408` — it says "The record and the target it may have just finished off" — to:

```swift
            // The record and the target it may have just moved are one change
            // as far as the store is concerned, so they cost one write rather
            // than two. The append comes first: this session credits the target
            // it actually ran against, and only the next one moves.
```

- [ ] **Step 6: Add the two new call sites**

In `Sources/PomodoroCount/PomodoroCountApp.swift`, in `applicationDidFinishLaunching`, directly after the `AppModel.shared.startDayMonitoring()` line:

```swift
        // Catch a day that turned over while the app was quit or the lid was
        // shut, which the notification below can only report while running.
        AppModel.shared.realignTarget()
```

In `Sources/PomodoroCount/SystemIntegration.swift`, in `startDayMonitoring()`, extend the `refresh` closure so it realigns as well as invalidating:

```swift
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                // The target follows the day as well as the count does: a new
                // day restarts the plan at the top of the ranking.
                self?.realignTarget()
                self?.objectWillChange.send()
            }
        }
```

- [ ] **Step 7: Run to verify everything passes**

Run: `just test 2>&1 | tail -20`

Expected: PASS, whole suite.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'MSG'
Restart the plan at the top of the ranking each day

advanceTargetIfMet becomes realignTarget: the met-goal advance and the new
start-of-day reset share the enabled checks and the never-re-aim-a-running-
session guard, and the reset has to run first — nothing is met at the start of
a day, so the advance below it could only ever be a no-op.

The reset is driven by a stored day stamp rather than by NSCalendarDayChanged
alone, so it survives a quit or a shut lid, and it stamps even when there is
nothing to aim at — adding a goal at noon must not move a target that has been
in use all morning.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: `pickTarget(_:)` — telling the two kinds of hand pick apart

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift` (add to the "Following the day's plan" section; edit `removeCategory(id:)` at `:184`)
- Modify: `Sources/PomodoroCount/Model.swift` (add `sessionTargetDescription` beside `sessionTargetLabel` at `:61`)
- Test: `Tests/PomodoroCountTests/CategorySessionTests.swift`

**Interfaces:**
- Consumes: `CategoryAdvance.isMet(_:in:)` and `CategoryAdvance.topUnmet(in:)` from Task 1; `Settings.targetPinned`, `Settings.targetAimedOn`, `Settings.aim(at:)` from Task 2; `AppModel.restartFromTopOfRanking()` from Task 3.
- Produces:
  - `AppModel.pickTarget(_ target: CategoryTarget)` — the hand-pick path
  - `AppModel.followTheOrder()` — clears the pin and re-aims
  - `AppModel.sessionTargetDescription: String` — `"towards X"` or `"pinned to X"`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PomodoroCountTests/CategorySessionTests.swift`:

```swift
    /// The rule, both halves. Picking a finished category can only mean "let me
    /// overshoot here" and pins; picking one with a goal left just says "work
    /// here next" and needs no pin, because the advance only fires on a met
    /// target and will hand back to the ranking once the goal is reached.
    @Test func pickingAFinishedCategoryPinsAndPickingAnUnfinishedOneDoesNot() {
        let m = configured()
        m.logExternal(to: .named("Music"))       // Music (goal 1) is now met
        m.pickTarget(.named("Music"))
        #expect(m.settings.targetPinned)
        m.pickTarget(.named("Work"))             // goal 4, nothing logged
        #expect(!m.settings.targetPinned)
    }

    /// The unpinned half, end to end: a hand pick holds while it is unfinished,
    /// then rejoins the ranking on its own — at the *top*, not at the row below.
    @Test func anUnfinishedHandPickHandsBackToTheTopWhenItIsMet() {
        let m = configured()
        m.settings.categories.append(Category(name: "Admin", dailyGoal: 1))
        m.pickTarget(.named("Admin"))            // ranks last, goal 1
        #expect(m.sessionTarget == .named("Admin"))
        m.logExternal(to: .named("Admin"))       // meets it
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A hand pick stamps today, or the next realign would read the target as
    /// yesterday's and wipe a pick made moments ago.
    @Test func aHandPickStampsToday() {
        let m = configured()
        m.settings.targetAimedOn = Date(timeIntervalSinceNow: -60 * 60 * 48)
        m.pickTarget(.named("Work"))
        m.realignTarget()
        #expect(m.sessionTarget == .named("Work"))
    }

    /// A goal of 0 can never be met, so picking one never pins — and the advance
    /// can never fire on it either, so it holds anyway. Both halves of "no
    /// special case needed".
    @Test func pickingAGoalLessCategoryNeitherPinsNorMoves() {
        let m = configured()
        m.settings.categories.append(Category(name: "Reading", dailyGoal: 0))
        m.pickTarget(.named("Reading"))
        #expect(!m.settings.targetPinned)
        m.logExternal(to: .named("Reading"))
        #expect(m.sessionTarget == .named("Reading"))
    }

    /// Handing control back has to work from an unfinished target too, which is
    /// why it does not route through the advance and its met-target guard.
    @Test func followingTheOrderClearsThePinAndAimsAtTheTop() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))            // pinned, and Music is met
        m.followTheOrder()
        #expect(!m.settings.targetPinned)
        #expect(m.sessionTarget == .named("Work"))
    }

    /// The getter resolves an archived name to `.fallback`, so a pin that
    /// outlived its category would silently pin the bucket instead.
    @Test func archivingThePinnedCategoryClearsThePin() {
        let m = configured()
        let music = m.settings.categories[1]
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        #expect(m.settings.targetPinned)
        m.removeCategory(id: music.id)
        #expect(!m.settings.targetPinned)
    }

    /// Archiving some *other* category is not the pinned one's business.
    @Test func archivingAnotherCategoryLeavesThePinAlone() {
        let m = configured()
        let work = m.settings.categories[0]
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        m.removeCategory(id: work.id)
        #expect(m.settings.targetPinned)
    }

    /// Two different promises, not a mode indicator: one says the ranking will
    /// move on when this is done, the other says it won't.
    @Test func theDescriptionSaysWhichPromiseIsInForce() {
        let m = configured()
        #expect(m.sessionTargetDescription == "towards \(m.settings.fallbackName)")
        m.pickTarget(.named("Work"))
        #expect(m.sessionTargetDescription == "towards Work")
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        #expect(m.sessionTargetDescription == "pinned to Music")
    }

    /// With the rule off there is no automatic behaviour for a pin to hold out
    /// against, so the distinction stops being worth showing. The flag is still
    /// recorded, so turning the rule back on restores what the pill promised.
    @Test func theDescriptionDropsThePinWhileTheRuleIsOff() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.pickTarget(.named("Music"))
        m.settings.autoAdvanceTarget = false
        #expect(m.sessionTargetDescription == "towards Music")
        #expect(m.settings.targetPinned)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `just test 2>&1 | tail -30`

Expected: compile failure — `value of type 'AppModel' has no member 'pickTarget'`.

- [ ] **Step 3: Add `pickTarget` and `followTheOrder`**

Append to the `// MARK: - Following the day's plan` extension in `AppModel+Categories.swift`, after `restartFromTopOfRanking()`:

```swift
    /// Aims the target where the user asked, and records which of the two kinds
    /// of pick it was.
    ///
    /// Picking a category that is **already met** can only mean "let me
    /// overshoot here", so it pins and the advance stops firing until the day
    /// turns over or the user hands control back. Picking one with a goal
    /// **left** just says "work here next" and needs no pin: the advance only
    /// fires on a met target, so the pick holds until the goal is reached and
    /// then rejoins the ranking on its own.
    ///
    /// Pinning *every* hand pick was the obvious design and is the wrong one. It
    /// gives the same overshoot, but one pick in the morning then leaves the
    /// ranking switched off for the rest of the day with only the user able to
    /// switch it back on — which is the papercut the advance exists to remove,
    /// reintroduced behind a single click.
    ///
    /// A goal-0 category needs no special case: `isMet` is false for it forever,
    /// so it never pins — and the advance can never fire on it either, so it
    /// holds regardless.
    ///
    /// The stamp matters as much as the pin. Without it a pick made this
    /// afternoon would still carry this morning's date only by luck, and a pick
    /// made on a store last touched yesterday would be wiped by the very next
    /// realign.
    func pickTarget(_ target: CategoryTarget) {
        var updated = settings
        updated.aim(at: target)
        updated.targetPinned = CategoryAdvance.isMet(target, in: todayProgress)
        updated.targetAimedOn = Date()
        settings = updated
    }

    /// Hands control back to the ranking, from the target menu's first entry.
    ///
    /// Deliberately not routed through `realignTarget()`, whose advance guards
    /// on the *current* target being met: handing control back has to work from
    /// an unfinished target too, and from a pinned one, which is precisely the
    /// case that guard would refuse.
    func followTheOrder() {
        restartFromTopOfRanking()
    }
```

- [ ] **Step 4: Clear the pin when the pinned category is archived**

Replace `removeCategory(id:)` at `AppModel+Categories.swift:182-186`:

```swift
    /// Archives rather than deletes: the category leaves the list but its
    /// records keep their name, so History, totals and CSV are unchanged.
    ///
    /// A pin does not survive its own category leaving. The `sessionTarget`
    /// getter resolves a name no longer in the list to `.fallback`, so a pin
    /// left standing would silently pin the bucket — a category the user never
    /// asked to overshoot in.
    func removeCategory(id: UUID) {
        let leaving = settings.categories.first { $0.id == id }
            .map { Category.normalized($0.name) }
        var updated = settings
        updated.categories.removeAll { $0.id == id }
        if let leaving, updated.sessionTargetName.map(Category.normalized) == leaving {
            updated.targetPinned = false
        }
        settings = updated
    }
```

- [ ] **Step 5: Add `sessionTargetDescription`**

In `Sources/PomodoroCount/Model.swift`, directly below `sessionTargetLabel` (`:61-63`):

```swift
    /// What the target pill says, and what VoiceOver reads.
    ///
    /// Two different promises rather than a mode indicator: `towards …` means
    /// the ranking is driving and will move on when that category is done,
    /// `pinned to …` means the user asked to keep going past a goal already met.
    /// Wording them differently is the whole visible difference between the two
    /// kinds of hand pick, so it carries real information rather than decorating
    /// a state.
    ///
    /// With `autoAdvanceTarget` off there is no automatic behaviour for a pin to
    /// hold out against, so the distinction stops being worth showing and
    /// everything reads `towards …`. The flag stays recorded, so turning the
    /// rule back on restores whatever the pill was already promising.
    var sessionTargetDescription: String {
        settings.targetPinned && settings.autoAdvanceTarget
            ? "pinned to \(sessionTargetLabel)"
            : "towards \(sessionTargetLabel)"
    }
```

- [ ] **Step 6: Run to verify it passes**

Run: `just test 2>&1 | tail -20`

Expected: PASS, whole suite.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'MSG'
Pin a hand pick only when the category is already met

The two picks are different intents. Picking a category with a goal left says
"work here next" and needs no pin — the advance only fires on a met target, so
it holds until finished and then hands back on its own. Picking one already
met can only mean "let me overshoot here", and that is the pick worth pinning.

Pinning both would buy the same overshoot at the price of switching the
ranking off for the rest of the day after a single click, which is the
papercut the advance was written to remove.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: The panel and the Settings copy

**Files:**
- Modify: `Sources/PomodoroCount/RootView.swift:215-245` (the target menu)
- Modify: `Sources/PomodoroCount/SettingsTab.swift:138-144` (the toggle)

**Interfaces:**
- Consumes: `AppModel.pickTarget(_:)`, `AppModel.followTheOrder()`, `AppModel.sessionTargetDescription` from Task 4.
- Produces: nothing later tasks depend on.

**Context you need:** this panel is a non-activating `NSPanel`. The pill is a `Menu` with `.menuStyle(.borderlessButton)`, which draws its label through `NSPopUpButton` — that control drops arbitrary `Shape` content entirely and paints an `Image` in its own text colour, ignoring `foregroundStyle`. The existing comment at `RootView.swift:222` records this. **Do not** add a dot, lock or pin icon to signal the pinned state; the words carry it. Keep that comment.

- [ ] **Step 1: Rewrite the target menu**

Replace `RootView.swift:215-245` (the `if model.settings.categoriesEnabled { Menu { … } … }` block) with:

```swift
            if model.settings.categoriesEnabled {
                Menu {
                    // Only while the rule is running: with it off there is
                    // nothing to hand control back *to*, and an entry that did
                    // nothing visible would be worse than no entry.
                    if model.settings.autoAdvanceTarget {
                        Button("Follow the order") { model.followTheOrder() }
                        Divider()
                    }
                    Button(model.settings.fallbackName) { model.pickTarget(.fallback) }
                    ForEach(model.settings.categories) { category in
                        Button(category.name) { model.pickTarget(.named(category.name)) }
                    }
                } label: {
                    // No decorative dot here, and it isn't an oversight.
                    // `.menuStyle(.borderlessButton)` draws this label through
                    // NSPopUpButton, which drops arbitrary Shape content entirely
                    // (a Circle rendered as nothing) and paints an Image in the
                    // control's own text colour, ignoring foregroundStyle. So a
                    // dot can only ever be a black bullet that matches neither
                    // palette. The text and the chevron carry the meaning —
                    // including the difference between "towards" and "pinned
                    // to", which is why those read as two different promises
                    // rather than as an icon the control would refuse to draw.
                    HStack(spacing: 4) {
                        Text(model.sessionTargetDescription)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // The Menu below is `.fixedSize()`, so without a cap
                            // here a long category name would push the pill past
                            // the panel's edge instead of truncating. "pinned
                            // to " is a few points wider than "towards ", so the
                            // cap grew to match.
                            .frame(maxWidth: 180, alignment: .leading)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Which category a finished session credits")
                .accessibilityLabel("Session target")
                .accessibilityValue(model.sessionTargetDescription)
            }
```

- [ ] **Step 2: Rewrite the Settings toggle copy**

Replace `SettingsTab.swift:138-144`:

```swift
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Follow the category order",
                                   isOn: $model.settings.autoAdvanceTarget)
                            Text("The top category with a goal left is the target, and each new day starts at the top again. Pick one by hand to work there next; pick a finished one to keep going past its goal.")
                                .font(.caption2)
                                .foregroundStyle(palette.textDim)
                        }
```

- [ ] **Step 3: Check the caption doesn't blow out the panel height**

The caption is markedly longer than the one it replaces, and the Settings tab sits in a `PanelTabScroller` that pins height to `min(content, screen cap)` — a taller tab is fine, a tab that reports a bad ideal height is not.

Run: `just preview /tmp/ranking-check.png` then open it, or:

```bash
swift run pomodoro-count --preview /tmp/ranking-check.png --store /tmp/ranking-scratch.json
```

Expected: all three tabs render; the Settings tab shows the new caption wrapped across three or four lines with nothing clipped and no collapsed panel. If the caption is too long to look right, shorten the second sentence rather than the first — the first sentence is the rule.

- [ ] **Step 4: Run the whole suite**

Run: `just test 2>&1 | tail -20`

Expected: PASS. Nothing in the suite asserts on the pill's label or accessibility value, so this task should not move any test — if one fails, it has found something real.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'MSG'
Say which promise the target pill is making

"towards X" and "pinned to X" are two different statements — one says the
ranking will move on when X is done, the other says it won't — so the pill
words them differently rather than marking a mode. It has no choice, in fact:
NSPopUpButton drops Shape content and repaints Images, so an icon was never
available to carry this.

The menu's new first entry hands control back, and appears only while the
rule is running, since with it off there is nothing to hand control back to.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Documentation

**Files:**
- Modify: `CHANGELOG.md` (under `## [Unreleased]`)
- Modify: `AGENTS.md` (the "Model and persistence" bullet naming `advanceTargetIfMet()`, and the "Conventions" bullet listing `CategoryAdvance.next(after:in:)`)

**Interfaces:** none.

- [ ] **Step 1: Add the CHANGELOG entry**

Under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
### Changed

- **The category list is now a priority ranking.** When a category meets its
  daily goal the session target falls to the highest-ranked category that still
  has a goal left, rather than to whichever one happens to sit below it. Each new
  day starts at the top of the list again.
- **Re-picking a finished category now holds there.** Pointing the target at a
  category you have already completed keeps it there for as many pomodoros as
  follow, instead of moving on after one — the pill reads `pinned to …` while it
  does. Picking a category that still has a goal left is unchanged: it holds
  until you finish it, then rejoins the ranking.
- **The target menu has a new first entry, "Follow the order",** which hands
  control back to the ranking.
- The Settings toggle "Move on when a goal is met" is now "Follow the category
  order". Your existing setting is kept.
```

- [ ] **Step 2: Update AGENTS.md — the model bullet**

Find the bullet beginning "Every record-appending path also calls `advanceTargetIfMet()`" and replace it with:

```markdown
- Every record-appending path also calls `realignTarget()` — append first, so
  the record credits the target it ran against, then realign. It holds two
  automatic triggers: a met target hands off to the **highest-ranked** category
  with a goal left (the list is a priority ranking, not a rotation), and a
  `settings.targetAimedOn` stamp from an earlier day restarts the plan at the
  top. Both are suppressed while a focus session is actually running, so an
  external log can't re-aim a session Start already pointed elsewhere, and both
  are gated by `settings.autoAdvanceTarget`. `settings.targetPinned` suppresses
  the first on its own: it is set by `pickTarget(_:)` only when the user aims at
  a category that is *already met*, which is the one reading of that pick, and
  it is what makes a deliberate overshoot last longer than one pomodoro.
```

- [ ] **Step 3: Update AGENTS.md — the conventions bullet**

In the "Tested logic is extracted from SwiftUI" bullet, `CategoryAdvance.next(after:in:)` is listed among the pure unit-tested functions. Change it to `CategoryAdvance.next(after:in:pinned:)`.

- [ ] **Step 4: Verify the docs' claims still hold**

Run: `git diff --stat` and re-read the two AGENTS.md bullets against the code you actually wrote in Tasks 3 and 4. AGENTS.md is loaded into every agent's context in this repo; a stale claim there is worse than no claim.

- [ ] **Step 5: Run the whole suite one last time**

Run: `just test 2>&1 | tail -20`

Expected: PASS. Report the actual test count in the commit or the handoff — do not claim green without having seen it.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md AGENTS.md
git commit -m "$(cat <<'MSG'
Describe the ranking where the next agent will look

AGENTS.md still described advanceTargetIfMet and a rotation. It is loaded
into every agent's context here, so a stale claim in it is worse than none.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

## Self-Review

**1. Spec coverage.** Every section of `2026-07-30-category-ranking-design.md` maps to a task:

| Spec section | Task |
|---|---|
| The rule — availability, ranking, `topUnmet` | 1 |
| The rule — pin suppresses the advance | 1 (rule), 4 (who sets it) |
| The rule — goal-0 needs no special case | 1 (`aGoalOfZeroIsNeverMet`), 4 (`pickingAGoalLessCategoryNeitherPinsNorMoves`) |
| The rule — daily snap stamps even with nothing to aim at | 3 (`theDailyResetStampsEvenWithNothingToAimAt`) |
| The rule — running session never re-aimed | 3 (`aRunningSessionDefersTheDailyReset`) |
| The rule — `autoAdvanceTarget` gates the two automatic triggers | 3 (`theOptOutFreezesTheDailyResetToo`) |
| The rule — raising a pinned category's goal leaves the pin standing | Falls out of Task 4's code with no branch: `pickTarget` reads `isMet` once at pick time and nothing recomputes it. No test — there is no code path to protect. |
| Interaction — two pill labels | 4 (`theDescriptionSaysWhichPromiseIsInForce`), 5 (wiring) |
| Interaction — *Follow the order*, not routed through the advance | 4 (`followingTheOrderClearsThePinAndAimsAtTheTop`), 5 (menu entry) |
| Interaction — text-only, no icon | 5 (comment preserved and extended) |
| Interaction — `.help` / `.accessibilityValue` | 5 |
| Architecture — `CategoryAdvance` three functions | 1 |
| Architecture — two `Settings` fields, decoded with defaults | 2 |
| Architecture — `autoAdvanceTarget` keeps name and key | Global Constraints; Task 5 changes only the UI string |
| Architecture — `realignTarget()`, call sites | 3 |
| Architecture — one `settings` assignment, not suspend/resume | 3, 4 |
| Architecture — `pickTarget(_:)` | 4 |
| Architecture — Settings copy | 5 |
| Architecture — archiving clears the pin | 4 (`archivingThePinnedCategoryClearsThePin`) |
| What changes / first launch re-aims once | 2 (`theTargetPinAndDayStampRoundTrip` + the defaults assertion) |
| Docs | 6 |

**2. Placeholder scan.** No TBD/TODO. Every code step carries the actual code. The one step that is a judgement call rather than a fixed edit — Task 5 Step 3, shortening the caption if it doesn't fit — names which sentence to cut and why.

**3. Type consistency.** `topUnmet(in:)`, `next(after:in:pinned:)` and `isMet(_:in:)` have one signature each across Task 1's definition, Tasks 3 and 4's call sites, and both Interfaces blocks. `realignTarget()`, `restartFromTopOfRanking()`, `pickTarget(_:)`, `followTheOrder()` and `sessionTargetDescription` are spelled identically in their definitions, their call sites, their tests and the AGENTS.md text. `targetPinned` and `targetAimedOn` match across Types.swift, the decode lines, all four consuming methods and every test. `Settings.aim(at:)` is defined in Task 2 and used in Tasks 3 and 4 only.

**One known interaction between tasks.** Task 3's rewritten `aRePickedFinishedCategoryKeepsTheNextSession` sets `settings.targetPinned` by hand, because `pickTarget(_:)` doesn't exist until Task 4. That is deliberate — it keeps the test about the advance rather than about how the pin arrives — and Task 4's `pickingAFinishedCategoryPinsAndPickingAnUnfinishedOneDoesNot` covers the arrival. Leave it as it is when you get to Task 4.
