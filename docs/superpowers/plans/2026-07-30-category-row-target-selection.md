# Category rows select the session target — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking a category row on the Focus tab aims the session target at it; the dropdown that used to do that becomes plain text, and count adjustment moves to a `±` at each row's trailing edge.

**Architecture:** A new pure `TargetPick.action` decides what a row click means (aim / release a pin / nothing); `AppModel.selectTarget` dispatches on it. `CategoryProgress.isSessionTarget` becomes `isTarget` and stops depending on whether a session is running, so a selected row shows its mark at rest. `CategoryRow` becomes two sibling buttons in a `ZStack` rather than one. Removing the `Menu` removes `NSPopUpButton`, which is the sole reason `TargetPill` exists, so that file and its tests are deleted.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit reach-ins, swift-testing (`import Testing`, **not** XCTest) for units, XCTest/XCUITest for the UI bundle, Swift Package Manager, `just` for commands.

**Spec:** `docs/superpowers/specs/2026-07-30-category-row-target-selection-design.md`

## Global Constraints

- **Comments record WHY, and stay.** Every non-obvious decision carries its reasoning in place. Do not strip existing comments; when a comment's justification stops being true, rewrite it rather than delete it.
- **Unit tests are swift-testing** — `import Testing`, `@Test`, `@Suite`, `#expect`. Never XCTest in `Tests/PomodoroCountTests`. The `UITests/` directory is XCUITest and is the exception.
- **Tested logic is extracted from SwiftUI.** Pure, total functions in their own type; views are thin over them.
- **Every color routes through `Palette`.** No raw `Color.red` / `.primary`. Access it with `@Environment(\.palette) private var palette`.
- **A button style must branch on `ControlState`**, read `@Environment(\.isEnabled)`, and finish with `.dimmed(state, palette)`. Do not hand-roll a style that branches on pressed/hovering alone.
- **Run the suite with `just test`**, not bare `swift test` — the justfile borrows Xcode's toolchain when the Command Line Tools are active. A single suite: `just test` then read the output, or `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TargetPickTests`.
- **Commit after every task.** Commit subjects are short imperative sentences telling the story ("Measure the drag in the list's own coordinate space"); bodies explain why. End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **`head` and `tail` are aliased to `bat` in this shell.** Use `sed -n '1,40p'` instead.
- Baseline before this plan: **407 tests in 36 suites**, all passing, `main` at `44078ad`.

---

### Task 1: `TargetPick` — what a row click means

**Files:**
- Create: `Sources/PomodoroCount/TargetPick.swift`
- Test: `Tests/PomodoroCountTests/TargetPickTests.swift`

**Interfaces:**
- Consumes: `CategoryTarget` (already exists in `Category.swift`) — not referenced by this type, listed only so you know it is *not* a parameter here.
- Produces: `TargetPick.action(isAlreadyTarget:pinned:autoAdvance:) -> TargetPick.Action`, where `Action` is `.aim | .release | .ignore` and is `Equatable`. Task 3 calls it from `AppModel.selectTarget`; Task 4 calls it to derive a tooltip.

- [ ] **Step 1: Write the failing test**

Create `Tests/PomodoroCountTests/TargetPickTests.swift`:

```swift
import Testing
@testable import PomodoroCount

/// What a click on a category row means, in the three-boolean space the row
/// can actually be in.
///
/// The two `.ignore` cases are why this is a type rather than an `if` inside a
/// `Button`: a rule that lives in a closure cannot be tested at all, and those
/// two are exactly where a plausible-looking implementation goes wrong.
@Suite struct TargetPickTests {

    /// The common case. Nothing about a pin matters when the click lands
    /// somewhere the target isn't.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func clickingAnotherRowAlwaysAims(pinned: Bool, autoAdvance: Bool) {
        #expect(TargetPick.action(isAlreadyTarget: false,
                                  pinned: pinned,
                                  autoAdvance: autoAdvance) == .aim)
    }

    /// The handback the dropdown's "Follow the order" entry used to carry.
    @Test func clickingThePinnedTargetAgainReleasesIt() {
        #expect(TargetPick.action(isAlreadyTarget: true,
                                  pinned: true,
                                  autoAdvance: true) == .release)
    }

    /// With the ranking switched off there is nothing to hand control back
    /// *to*, so the pin has nothing to hold out against and the click has
    /// nothing to do. Mirrors the dropdown, which only offered the handback
    /// while the rule was running.
    @Test func clickingThePinnedTargetDoesNothingWhileTheRuleIsOff() {
        #expect(TargetPick.action(isAlreadyTarget: true,
                                  pinned: true,
                                  autoAdvance: false) == .ignore)
    }

    /// The case that must not be routed to the release. `followTheOrder()`
    /// aims at the top unmet category, so releasing here would move the target
    /// off the row that was just clicked and onto a different one — a click
    /// aiming somewhere the user did not click.
    @Test(arguments: [false, true])
    func clickingAnUnpinnedTargetAgainChangesNothing(autoAdvance: Bool) {
        #expect(TargetPick.action(isAlreadyTarget: true,
                                  pinned: false,
                                  autoAdvance: autoAdvance) == .ignore)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just test`
Expected: FAIL to **compile**, with `cannot find 'TargetPick' in scope`. A compile failure is the correct red here — the type does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PomodoroCount/TargetPick.swift`:

```swift
/// What a click on a category row should do.
///
/// Pure and total over its inputs — the same shape as `Reorder.destination`
/// and `CategoryAdvance.next` — because the interesting half of this rule is
/// the two cases where the answer is *nothing*, and a rule living inside a
/// `Button`'s closure cannot be tested at all.
enum TargetPick {

    enum Action: Equatable {
        /// Aim the session target at the clicked category.
        case aim
        /// Hand control back to the ranking: clear the pin, restart at the top.
        case release
        /// Change nothing.
        case ignore
    }

    /// - Parameters:
    ///   - isAlreadyTarget: the clicked row is the one finished pomodoros
    ///     already land on.
    ///   - pinned: `settings.targetPinned` — the user aimed at a category that
    ///     was already met, which reads as "let me overshoot here".
    ///   - autoAdvance: `settings.autoAdvanceTarget` — the ranking is driving.
    static func action(isAlreadyTarget: Bool,
                       pinned: Bool,
                       autoAdvance: Bool) -> Action {
        guard isAlreadyTarget else { return .aim }
        // A second click releases a pin and does nothing else. Routing an
        // *unpinned* re-click to the release would call
        // `restartFromTopOfRanking()`, which aims at the top unmet category —
        // so clicking the row you are already working in would move the target
        // off it and onto another one. A click must never aim somewhere the
        // user did not click.
        //
        // And with `autoAdvanceTarget` off there is no ranking to hand back to,
        // which is why the dropdown this replaces only offered "Follow the
        // order" while that rule was running.
        guard pinned, autoAdvance else { return .ignore }
        return .release
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `just test`
Expected: PASS. Test count rises from 407 to **411**.

Note on counting: swift-testing's "Test run with N tests" counts `@Test`
*declarations*, not expanded parameterised cases — this suite's four
declarations report as 4 even though two of them take argument lists. Verified
against `CategoryProgressTests`, which reports 23 for 23 declarations while
containing a 4-argument parameterised test.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/TargetPick.swift Tests/PomodoroCountTests/TargetPickTests.swift
git commit -m "Decide what a second click on the target row means

A click on a row that is already the target releases a pin, and does
nothing else. Routing an unpinned re-click to the handback would aim at
the top unmet category, moving the target off the row just clicked.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The target mark stops depending on "running"

Rename `CategoryProgress.isSessionTarget` to `isTarget` and drop the `sessionRunning` guard, so a selected row shows its mark while idle and paused. This task changes behaviour visible in the app (the outline now appears at rest) but does not yet change what a click does.

**Files:**
- Modify: `Sources/PomodoroCount/Category.swift:45-47` (the property), `:64-73` (`accessibilityValue`)
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift:52-56` and `:68-87` (`todayProgress`), `:326-329` (a comment in `realignTarget` that justifies itself by pointing at the guard being removed)
- Modify: `Sources/PomodoroCount/CategoryRows.swift:88` (the one view use)
- Test: `Tests/PomodoroCountTests/CategoryProgressTests.swift:99,105,114` (argument labels), `:141-153` and `:169-215` (the behaviour tests)
- Test: `Tests/PomodoroCountTests/CategoryAdvanceTests.swift:12` (argument label)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `CategoryProgress.isTarget: Bool` — true whenever finished pomodoros land in that row, regardless of phase. Tasks 4 and 6 read it. The memberwise initialiser's third-from-last argument label becomes `isTarget:`.

- [ ] **Step 1: Write the failing tests**

In `Tests/PomodoroCountTests/CategoryProgressTests.swift`, replace the entire `// MARK: Session-target outline` section (lines 169–214, from the MARK comment through the closing brace of `isSessionTargetIsFalseWhilePaused`) with:

```swift
    // MARK: Target mark

    @Test func isTargetMarksOnlyTheTargetCategory() {
        let m = configured()
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        let ai = m.todayProgress.first { $0.name == "AI study" }!
        #expect(work.isTarget)
        #expect(!ai.isTarget)
    }

    @Test func isTargetMarksTheBucketWhenThatIsTheTarget() {
        let m = configured()   // sessionTarget unset -> automatic -> bucket
        let bucket = m.todayProgress.first { $0.isFallback }!
        #expect(bucket.isTarget)
    }

    /// The three tests below asserted the opposite until the rows became how
    /// the target is *chosen*. A row you click to select has to show its
    /// selection before Start is pressed, so the mark has to survive every
    /// state a not-yet-running session can be in.
    @Test func isTargetSurvivesWithNoSessionRunning() {
        let m = configured()
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.isTarget)
    }

    @Test func isTargetSurvivesABreak() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.breakMinutes = 1
        m.startBreak()
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.isTarget)
        m.reset()
    }

    @Test func isTargetSurvivesAPause() {
        let m = configured()
        m.sessionTarget = .named("Work")
        m.settings.workMinutes = 1
        m.startWork()
        m.pause()
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.isTarget)
        m.reset()
    }
```

Then update the accessibility test at lines 141–153 — replace that whole `@Test func accessibilityValueNamesTheSessionTarget()` block (including its doc comment) with:

```swift
    /// A met goal and the target mark are both conveyed in the value, not by
    /// colour alone. The outline is colour; this is what VoiceOver gets.
    @Test func accessibilityValueNamesTheTarget() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Work", dailyGoal: 4)]
        m.sessionTarget = .named("Work")
        let work = m.todayProgress.first { $0.name == "Work" }!
        #expect(work.accessibilityValue.hasSuffix(", session target"))
    }
```

Finally, change the argument label at three construction sites in the same file — lines 99, 105, and 114 — from `isSessionTarget: false` to `isTarget: false`, and the same at `Tests/PomodoroCountTests/CategoryAdvanceTests.swift:12`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL to compile — `value of type 'CategoryProgress' has no member 'isTarget'` and `incorrect argument label in call (have 'isTarget:', expected 'isSessionTarget:')`.

- [ ] **Step 3: Rename the property and drop the guard**

In `Sources/PomodoroCount/Category.swift`, replace lines 45–47:

```swift
    /// True when finished pomodoros land here — idle, paused, running, or
    /// between sessions.
    ///
    /// Not "a session is running and aimed here", which is what this meant
    /// while the target was picked from a dropdown. The rows are now how the
    /// target is chosen, so a row has to show its selection before Start is
    /// pressed; a mark that appears only once a session runs would be absent
    /// at exactly the moment the user is deciding. Whether a session is
    /// *running* is answered by the countdown directly above the list.
    let isTarget: Bool
```

And in `accessibilityValue` (line 68), change:

```swift
        let target = isTarget ? ", session target" : ""
```

In `Sources/PomodoroCount/AppModel+Categories.swift`, replace lines 52–56:

```swift
        // Not gated on a running session: these rows are how the target gets
        // chosen, so the mark has to be readable before Start is pressed.
        let targetName = resolve(sessionTarget)
        let normalizedTarget = targetName.map(Category.normalized)
```

Then line 75 becomes:

```swift
                isTarget: normalizedTarget == Category.normalized(category.name))
```

and line 86 becomes:

```swift
            isTarget: targetName == nil))
```

In the same file, `realignTarget`'s comment at lines 326–329 justifies its guard by pointing at `todayProgress` using the same test — which stops being true here. Replace the sentence beginning `` `phase == .work && isRunning` is deliberately the same "actually running… `` and running through `…so neither trigger should be.` with:

```swift
        // `phase == .work && isRunning` is "actually running, not idle or
        // paused". `todayProgress` used to gate its target mark on this same
        // test and no longer does — the mark answers "where do pomodoros
        // land", which is true in every phase, while this guard answers "is a
        // Start already pointed somewhere", which is only true in one.
```

In `Sources/PomodoroCount/CategoryRows.swift`, line 88 becomes `if progress.isTarget {`. The comment above it says "The running session's target row stays outlined" — replace those three comment lines with:

```swift
                        // The target row stays outlined so it is clear where
                        // the next finished pomodoro lands, and — since the
                        // rows are what aim it — which row a click already
                        // selected.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS, **411 tests** (unchanged from Task 1 — six tests were rewritten in place, not added).

- [ ] **Step 5: Verify the mark now shows at rest**

Run: `just preview`
Then open the PNG path it prints and look at the Focus tab's category list. Exactly one row must carry the accent outline even though no session is running — previously none did.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount Tests/PomodoroCountTests
git commit -m "Mark the target row in every phase, not only while running

The rows are about to become how the target is chosen, and a row you
click to select has to show its selection before Start is pressed. So
the mark now answers 'where do pomodoros land', which is true in every
phase, and isSessionTarget is renamed isTarget because the old name
would be a lie.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `AppModel.selectTarget`

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift` — add a method immediately after `pickTarget(_:)` (which ends at line 403) and before `followTheOrder()`
- Test: `Tests/PomodoroCountTests/CategorySessionTests.swift` — append to the suite, before its closing brace

**Interfaces:**
- Consumes: `TargetPick.action(isAlreadyTarget:pinned:autoAdvance:)` from Task 1; `CategoryProgress.isTarget` from Task 2 (not directly — this method uses `resolve`, see below).
- Produces: `AppModel.selectTarget(_ target: CategoryTarget)`. Task 4's row click calls exactly this.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PomodoroCountTests/CategorySessionTests.swift`, inside the suite (before its final `}`):

```swift
    // MARK: selectTarget — what a click on a category row does

    @Test func clickingAnotherRowAimsAtIt() {
        let m = configured()
        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
    }

    /// `pickTarget`'s pin rule is unchanged and still reached: picking a
    /// category that is already met reads as "let me overshoot here".
    @Test func clickingAMetRowPinsIt() {
        let m = configured()
        m.logExternal(to: .named("Music"))      // Music's goal is 1, so this meets it
        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
        #expect(m.settings.targetPinned)
    }

    /// The handback the dropdown's "Follow the order" entry used to carry.
    /// Work is first in the ranking and unmet, so the release lands there.
    @Test func clickingThePinnedRowAgainHandsControlBack() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.selectTarget(.named("Music"))
        #expect(m.settings.targetPinned)

        m.selectTarget(.named("Music"))
        #expect(!m.settings.targetPinned)
        #expect(m.sessionTargetLabel == "Work")
    }

    /// The case a naive implementation gets wrong: re-clicking an *unpinned*
    /// target must not run the handback, which would aim at the top unmet
    /// category and move the target off the row that was just clicked.
    @Test func clickingAnUnpinnedTargetRowAgainChangesNothing() {
        let m = configured()
        m.selectTarget(.named("Music"))
        #expect(!m.settings.targetPinned)

        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
    }

    /// With the ranking off there is nothing to hand back to, so the pin
    /// stands and the target stays put.
    @Test func clickingThePinnedRowAgainDoesNothingWhileTheRuleIsOff() {
        let m = configured()
        m.logExternal(to: .named("Music"))
        m.selectTarget(.named("Music"))
        m.settings.autoAdvanceTarget = false

        m.selectTarget(.named("Music"))
        #expect(m.sessionTargetLabel == "Music")
        #expect(m.settings.targetPinned)
    }

    /// The bucket is a row like any other, and it is identified by `.fallback`
    /// rather than by name — its label is whatever the user called it.
    @Test func clickingTheBucketRowAimsAtIt() {
        let m = configured()
        m.selectTarget(.named("Work"))
        m.selectTarget(.fallback)
        #expect(m.sessionTargetLabel == m.settings.fallbackName)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL to compile — `value of type 'AppModel' has no member 'selectTarget'`.

- [ ] **Step 3: Write the implementation**

In `Sources/PomodoroCount/AppModel+Categories.swift`, insert immediately after the closing brace of `pickTarget(_:)`:

```swift
    /// What a click on a category row does.
    ///
    /// The row list is the target picker now, so one gesture has to carry both
    /// halves of what the dropdown offered: its category entries, and the
    /// *Follow the order* entry that handed control back to the ranking. A
    /// click on a different row aims; a second click on the row already aimed
    /// at releases a pin, if there is one to release.
    ///
    /// The decision itself is in `TargetPick` rather than here because two of
    /// its cases do nothing, and "does nothing" is the part of a rule that
    /// rots silently.
    ///
    /// `resolve` on both sides, not `==` on the targets: it returns the
    /// canonical stored spelling, so a row's `.named("work")` and a stored
    /// `.named("Work")` compare equal, and `.fallback` resolves to nil on both
    /// sides.
    func selectTarget(_ target: CategoryTarget) {
        let isAlreadyTarget = resolve(target) == resolve(sessionTarget)
        switch TargetPick.action(isAlreadyTarget: isAlreadyTarget,
                                 pinned: settings.targetPinned,
                                 autoAdvance: settings.autoAdvanceTarget) {
        case .aim: pickTarget(target)
        case .release: followTheOrder()
        case .ignore: break
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS, **417 tests** (6 added).

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/AppModel+Categories.swift Tests/PomodoroCountTests/CategorySessionTests.swift
git commit -m "Let one gesture both aim the target and hand it back

The row list has to carry what the dropdown carried: its category
entries and its Follow-the-order entry. A click on another row aims; a
second click on the row already aimed at releases a pin.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The row becomes two controls

The row button selects; a `±` at its trailing edge opens the count popover. After this task the dropdown still exists and still works — both ways of aiming are live, which is a coherent intermediate state.

**Files:**
- Modify: `Sources/PomodoroCount/CategoryRows.swift` — `CategoryRows.body`'s `ForEach` (lines 25–31) and the whole of `struct CategoryRow` (lines 41–152). `CategoryCountPopover` below it is **unchanged**.

**Interfaces:**
- Consumes: `AppModel.selectTarget(_:)` from Task 3; `TargetPick.action(isAlreadyTarget:pinned:autoAdvance:)` from Task 1; `CategoryProgress.isTarget` from Task 2.
- Produces: `CategoryRow(progress:clickReleasesPin:onSelect:onAdd:onSubtract:)`. Nothing else constructs it.

- [ ] **Step 1: Rewrite the `ForEach` that builds the rows**

In `Sources/PomodoroCount/CategoryRows.swift`, replace lines 25–31 (the `ForEach(rows) { row in … }` block) with:

```swift
                        ForEach(rows) { row in
                            let target: CategoryTarget =
                                row.isFallback ? .fallback : .named(row.name)
                            // The same rule the click runs, so the tooltip
                            // cannot promise a handback the click won't
                            // perform.
                            let releases = TargetPick.action(
                                isAlreadyTarget: row.isTarget,
                                pinned: model.settings.targetPinned,
                                autoAdvance: model.settings.autoAdvanceTarget) == .release
                            CategoryRow(progress: row,
                                        clickReleasesPin: releases,
                                        onSelect: { model.selectTarget(target) },
                                        onAdd: { model.logExternal(to: target) },
                                        onSubtract: { model.unlogToday(from: target) })
                        }
```

- [ ] **Step 2: Replace `struct CategoryRow` entirely**

Replace lines 41–152 — the whole of `struct CategoryRow`, from its doc comment down to and including the closing brace after the `bar` property — with:

```swift
/// One category, carrying two controls rather than one: the row itself aims the
/// session target, and the `±` at its trailing edge opens the count adjuster.
///
/// They are **siblings in a `ZStack`**, not a `±` nested inside the row's
/// label. A `Button` inside another `Button`'s label does not receive clicks on
/// macOS — the outer button's hit testing swallows them, so the inner control
/// looks live and does nothing. Drawn second, the `±` sits above the row in
/// z-order and takes its own hits; the row takes everything else.
struct CategoryRow: View {
    let progress: CategoryProgress
    /// Whether a click would hand control back to the ranking rather than aim.
    /// Computed by the parent from `TargetPick`, so it is the same rule the
    /// click itself runs.
    let clickReleasesPin: Bool
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onSubtract: () -> Void

    @Environment(\.palette) private var palette
    @State private var hover = false
    @State private var showingCounter = false

    /// The `±`'s hit target, and the gap between it and the card's edge. The
    /// row's content reserves exactly `glyphWidth + 2 * glyphInset` on its
    /// trailing side, so the count text can never slide underneath the glyph
    /// that is drawn on top of it.
    private static let glyphWidth: CGFloat = 22
    private static let glyphInset: CGFloat = 8

    var body: some View {
        ZStack(alignment: .trailing) {
            selectButton
            adjustButton
        }
    }

    private var selectButton: some View {
        Button(action: onSelect) {
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

                Text(progress.countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(progress.isMet ? palette.accent : palette.textDim)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10 + Self.glyphWidth + Self.glyphInset)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                CardBackground(cornerRadius: 11, fillOpacity: hover ? 1.6 : 1.0)
                    .overlay {
                        // A met goal soaks the whole card in a wash of the
                        // accent — the count text already turns accent at the
                        // same moment, this just makes it readable from across
                        // the room. Under the target stroke, so both can show.
                        if progress.isMet {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(palette.accent.opacity(0.12))
                        }
                        // The target row stays outlined so it is clear where
                        // the next finished pomodoro lands, and — since the
                        // rows are what aim it — which row a click already
                        // selected.
                        if progress.isTarget {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(palette.accent.opacity(0.8), lineWidth: 1.5)
                        }
                    }
            }
            // Collapsed here, inside the label — NOT on the Button, which is
            // where these three sat until the AX tree was actually read back.
            // `.accessibilityElement(children: .ignore)` builds a fresh, plain
            // element and throws away the one it is applied to, so on the
            // Button it discarded the button itself: the row came out
            // `AXUnknown` with no `AXPress` and no focus, and because a plain
            // element has no `AXValue` attribute, the macOS bridge demoted
            // `accessibilityValue` to `AXValueDescription`. One cause, three
            // symptoms. Applied to the label, it collapses only the HStack, and
            // the Button wraps that in its own element — role, press, focus and
            // value all intact. Measured through the Accessibility API, not
            // assumed.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.name)
            .accessibilityValue(progress.accessibilityValue)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(selectHelp)
        .accessibilityHint("Sends finished pomodoros here")
    }

    /// What the row promises before it is clicked. Three readings, because a
    /// click on the row already aimed at is not the same act as a click on any
    /// other row, and a control that does nothing needs to say so rather than
    /// look broken.
    private var selectHelp: String {
        if clickReleasesPin {
            return "Pinned to \(progress.name) — click to follow the category order again"
        }
        if progress.isTarget {
            return "Finished pomodoros already land in \(progress.name)"
        }
        return "Send finished pomodoros to \(progress.name)"
    }

    private var adjustButton: some View {
        Button { showingCounter = true } label: {
            Image(systemName: "plusminus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: Self.glyphWidth, height: Self.glyphWidth)
                // The glyph draws at about 10pt. Without this the clickable
                // area *is* the glyph, which is a smaller target than a pointer
                // can reliably land on inside a 33pt row.
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Adjust today's count for \(progress.name)")
                .accessibilityValue(progress.countText)
        }
        // Not `SoftIconButtonStyle`: that draws a filled, stroked well, and a
        // well inside a card at 22pt reads as a second card sitting on the
        // first rather than as a mark on it. `HoverTextButtonStyle` is this
        // app's low-chrome control — `textDim` at rest, lit on hover, a neon
        // glow under Synthwave — and, like every style here, it branches on
        // `ControlState` and finishes with `.dimmed`.
        .buttonStyle(HoverTextButtonStyle(emphasis: .action))
        .padding(.trailing, Self.glyphInset)
        .help("Adjust today's count for \(progress.name)")
        // Moved here from the row, which now means "select". Its reason is
        // unchanged: routing a count change through a popover would cost
        // VoiceOver three activations, and swipe up/down still does it in one.
        // Its home is the element that owns counting.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdd()
            case .decrement: onSubtract()
            @unknown default: break
            }
        }
        // Trailing, not bottom: the rows are a list, and a popover hanging off
        // the bottom edge covers the neighbours whose counts give this one its
        // context. Anchored on the `±` rather than the row so it hangs off the
        // control that opened it.
        .popover(isPresented: $showingCounter, arrowEdge: .trailing) {
            // A popover is its own window: it inherits the environment but not
            // the appearance, so the theme has to be applied again here.
            CategoryCountPopover(progress: progress, onAdd: onAdd, onSubtract: onSubtract)
                .themed(palette)
        }
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

Also update `CategoryRows`'s own doc comment at lines 3–4, which still describes the old click:

```swift
/// The panel's category list. Replaces the hero log button when categories are
/// on: tapping a row aims the session target at it, and the `±` on its trailing
/// edge opens a counter that adds to or subtracts from today's count.
```

- [ ] **Step 3: Run the suite**

Run: `just test`
Expected: PASS, **417 tests** — unchanged. Nothing here is unit-testable (it is all SwiftUI); the behaviour it drives was covered in Tasks 1–3.

- [ ] **Step 4: Verify the claim about nested buttons by running it**

This is the step the spec singles out as *must be verified, not trusted*. Build and drive the real panel:

```bash
just install
```

Then open the panel from the menu bar and, by hand:
1. Click a category row's **name area** → the target outline moves to that row, and no popover appears.
2. Click that row's **`±`** → the `− count +` popover appears, and the target does **not** move.
3. Click the row that is already outlined → nothing moves (unless it is pinned, in which case the outline jumps to the first unmet row).

If step 2 opens nothing, or step 1 opens the popover, the `ZStack` sibling arrangement is not winning hits and the structure needs revisiting — do not paper over it by moving the `±` back inside the label.

For a headless check of the geometry rather than the hit testing, use the `drive-panel` skill, which reads element frames and `accessibilityValue`s through the Accessibility API. Note the harness rule from `AGENTS.md`: *reproducing a failure there is evidence; reproducing a success is not* — so the three clicks above still get one pass by hand.

- [ ] **Step 5: Verify the look**

Run: `just preview`
Open the PNG and check, on the Focus tab:
- a `±` sits at the right of every row, dim, clear of the count text (no overlap);
- exactly one row carries the accent outline;
- the row heights have not changed.

Then render Synthwave and confirm the `±` is visible against the neon card rather than lost in it:

```bash
swift run PomodoroCount --preview /tmp/synth.png --theme Synthwave
```

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/CategoryRows.swift
git commit -m "Split the category row into aiming and counting

The row selects the session target; a ± on its trailing edge opens the
count adjuster. They are siblings in a ZStack rather than nested, because
a Button inside another Button's label never receives clicks on macOS —
the outer button's hit testing swallows them.

The adjustable action moves to the ± with them: the row owns targeting
now, and counting belongs to the element that opens the counter.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Retire the dropdown and `TargetPill`

**Files:**
- Modify: `Sources/PomodoroCount/RootView.swift:215-270` (the `Menu` block)
- Modify: `Sources/PomodoroCount/Model.swift:83-93` (delete `sessionTargetPillText`)
- Delete: `Sources/PomodoroCount/TargetPill.swift`
- Delete: `Tests/PomodoroCountTests/TargetPillTests.swift`
- Modify: `AGENTS.md` (the extracted-logic bullet under `## Conventions`)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing. `AppModel.sessionTargetDescription` and the private `sessionTargetPromise` both **stay** — `sessionTargetDescription` now drives the visible text as well as the spoken value.

- [ ] **Step 1: Replace the `Menu` with text**

In `Sources/PomodoroCount/RootView.swift`, replace lines 215–270 — the whole `if model.settings.categoriesEnabled { Menu { … } … }` block — with:

```swift
            if model.settings.categoriesEnabled {
                // Plain text, not a control. The category rows below are what
                // aims the target now, and a second picker listing those same
                // categories without any of the counts that make one worth
                // picking is what this stopped being.
                //
                // `.lineLimit`/`.truncationMode` do the job here that
                // `TargetPill` had to do by hand: `NSPopUpButton` ignored
                // SwiftUI frames on its content, so the string had to be cut to
                // a measured width before it ever reached the label. A `Text`
                // truncates at the width it is actually given, and `.tail` cuts
                // the name while leaving the promise — "towards" versus "pinned
                // to" — which is the one property that shortening existed to
                // guarantee.
                //
                // `palette.text`, not `textDim`: this replaced a control drawn
                // at control-text weight, and dropping it to `textDim` would
                // merge it with the identically-sized subtitle directly above.
                Text(model.sessionTargetDescription)
                    .font(.caption)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("Which category a finished session credits — click a category below to change it")
                    .accessibilityLabel("Session target")
                    .accessibilityValue(model.sessionTargetDescription)
            }
```

- [ ] **Step 2: Delete `sessionTargetPillText` and `TargetPill`**

In `Sources/PomodoroCount/Model.swift`, delete lines 83–93 — the `sessionTargetPillText` property together with its doc comment. Leave `sessionTargetPromise` and `sessionTargetDescription` alone.

Then:

```bash
git rm Sources/PomodoroCount/TargetPill.swift Tests/PomodoroCountTests/TargetPillTests.swift
```

- [ ] **Step 3: Update AGENTS.md**

Under `## Conventions`, in the **Tested logic is extracted from SwiftUI** bullet, remove `TargetPill.label(prefix:name:)` from the list of pure types and delete the trailing sentences about it — everything from `` `TargetPill` is the case for *how far* out: `` through `a hand-built stand-in for that control measured five points narrower.` Add `TargetPick.action(isAlreadyTarget:pinned:autoAdvance:)` to the list in its place, so the bullet ends at `…the wrong icon in the menu bar.`

- [ ] **Step 4: Run the suite**

Run: `just test`
Expected: PASS, **407 tests** (417 minus the 10 in `TargetPillTests`). Confirm the drop is exactly the deleted suite and nothing else — if the number is lower, something else broke.

- [ ] **Step 5: Verify nothing still references the deleted symbols**

Run:

```bash
grep -rn "TargetPill\|sessionTargetPillText" Sources/ Tests/ UITests/ AGENTS.md
```

Expected: no output.

- [ ] **Step 6: Verify the look**

Run: `just preview`
Open the PNG and confirm the Focus tab shows `towards General` as plain text with no chevron, sitting where the dropdown was, distinguishable from the `Focus session · 50 min` line above it. Then check a long name does not push the card wide:

```bash
swift run PomodoroCount --seed-store /tmp/long.json
# hand-edit /tmp/long.json to rename a category to something ~40 characters
swift run PomodoroCount --preview /tmp/long.png --store /tmp/long.json
```

The panel must stay 300pt wide with the text truncated by an ellipsis, and the promise (`towards ` / `pinned to `) must still be readable.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Retire the target dropdown and the pill it needed

The dropdown listed the same categories the rows below it show, without
the counts that make one worth picking. Its text stays, as text.

TargetPill goes with it. It existed only because NSPopUpButton ignores
SwiftUI frames on its content, so the string had to be cut to a measured
width before reaching the label; a Text truncates at the width it is
given, and .tail keeps the promise while cutting the name. The workaround
goes because its cause goes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Accessibility coverage and the changelog

The unit suite cannot see the AX tree, and the existing UI test asserts the *old* row behaviour (that clicking a row opens the popover), so it must change or it will fail against the shipped design.

**Files:**
- Modify: `UITests/CategoryRowAccessibilityUITests.swift` — the doc comment, `expectedValue` (line 27), and the tests from line 66 down
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: nothing.

- [ ] **Step 1: Loosen the two progress assertions**

The target mark now appears on a row at rest, so a row that happens to be the target reads `"0 of 1 pomodoros, session target"` and an equality check on `expectedValue` would fail for reasons that have nothing to do with the progress string. In `UITests/CategoryRowAccessibilityUITests.swift`, change line 27's comment and the two assertions.

Replace the `expectedValue` declaration (lines 25–27) with:

```swift
    /// `StoreSeed` gives every category a daily goal of 1 and no records, so
    /// every row starts at "0 of 1 pomodoros". Asserted as a *prefix*: the
    /// target mark is appended to this string, and which row the app launches
    /// aimed at is not this test's business.
    private let expectedProgress = "0 of 1 pomodoros"
```

In `testACategoryRowSpeaksItsProgress`, replace the final assertion with:

```swift
        XCTAssertTrue((row.value as? String)?.hasPrefix(expectedProgress) == true,
                      "wrong value on Alpha: \(String(describing: row.value))")
```

In `testEveryCategoryRowSpeaksItsProgress`, replace the final assertion with:

```swift
            XCTAssertTrue((row.value as? String)?.hasPrefix(expectedProgress) == true,
                          "wrong value on \(name): \(String(describing: row.value))")
```

- [ ] **Step 2: Replace the activation test with the new behaviour**

Replace `testACategoryRowCanBeActivated` (the last test in the file, including its doc comment) with these three:

```swift
    /// Activating a row aims the session target at it — the row's own job now
    /// that the dropdown is gone. Asserted through `AXValue`, because the
    /// outline that says the same thing to the eye is invisible to this API.
    ///
    /// Bravo rather than Alpha: whichever row the app launches aimed at, it can
    /// only be the first unmet one or the bucket, never the second category. So
    /// clicking Bravo is always a real move.
    func testActivatingARowAimsTheTargetAtIt() {
        let bravo = app.buttons["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 10), "no button labelled Bravo")
        XCTAssertTrue(bravo.isHittable, "the row reports no activation point")
        bravo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue((bravo.value as? String)?.hasSuffix(", session target") == true,
                      "activating the row did not aim the target at it: \(String(describing: bravo.value))")
        XCTAssertFalse((app.buttons["Alpha"].value as? String)?.hasSuffix(", session target") == true,
                       "the mark stayed on Alpha as well")
    }

    /// Activating a row must *not* open the counter. That was the old
    /// behaviour, and the whole point of moving counting onto its own control
    /// was to give the row back to the commoner action.
    func testActivatingARowDoesNotOpenTheCounter() {
        let bravo = app.buttons["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 10), "no button labelled Bravo")
        bravo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertFalse(app.buttons["Add one pomodoro to Bravo"].exists,
                       "clicking the row raised the count popover")
    }

    /// The ± is its own element with its own role, not decoration inside the
    /// row — which is what it would be if it were nested in the row button's
    /// label rather than sitting beside it.
    func testTheAdjustGlyphIsItsOwnButtonAndOpensTheCounter() {
        let adjust = app.buttons["Adjust today's count for Alpha"]
        XCTAssertTrue(adjust.waitForExistence(timeout: 10),
                      "the row has no separate adjust button")
        XCTAssertTrue(adjust.isHittable, "the adjust button reports no activation point")
        adjust.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue(app.buttons["Add one pomodoro to Alpha"].waitForExistence(timeout: 10),
                      "the adjust button did not raise the count popover")
    }
```

Finally, update the suite's doc comment: its closing sentence describes the row's `AXPress` as "how a VoiceOver user opens the count popover". Change that to "how a VoiceOver user aims the session target".

- [ ] **Step 3: Run the UI bundle**

Run: `just uitest`

This needs xcodegen and a full Xcode, and its XCUITest half **asks a person at the keyboard to grant Automation Mode** — do not run it unattended and expect a clean pass. It also moves the real pointer; leave the machine alone while it runs.

Expected: the four `CategoryRowAccessibilityUITests` cases pass. The `ReorderDynamicsTests` cases are a local gate only and are unaffected by this work.

- [ ] **Step 4: Add the changelog entry**

`CHANGELOG.md` follows Keep a Changelog, and `just release` refuses to tag without an entry. Add under the `## [Unreleased]` heading (create `### Changed` if it is not already there):

```markdown
### Changed
- Click a category on the Focus tab to send finished pomodoros there. The
  target dropdown is gone — it listed the same categories as the rows below it,
  without the counts that make one worth picking. The line it occupied still
  says where pomodoros are going.
- Adjusting a category's count for today moved to a `±` at the right of each
  row, so the row itself is free for the commoner action.
- The target row now stays outlined while the timer is idle or paused, not only
  while a session runs, so you can see what you picked before pressing Start.
- Clicking the category you are pinned to hands control back to the category
  order — what the dropdown's "Follow the order" entry used to do.
```

- [ ] **Step 5: Run the full suite one last time**

Run: `just test`
Expected: PASS, **407 tests in 36 suites**. (Task 1 added 4 and Task 3 added 6; Task 5 removed the 10 in `TargetPillTests`. The totals landing back on the baseline is a coincidence, not a check — read the suite names if the number looks right but something feels missing.)

- [ ] **Step 6: Commit and install**

```bash
git add -A
git commit -m "Cover the row's two elements from the Accessibility API

The old activation test asserted the row opens the counter, which is now
the ± button's job. Replaced with three: the row aims the target, the row
does not open the counter, and the ± is its own button that does.

The progress assertions became prefix checks — the target mark is
appended to the value, and which row the app launches aimed at is not
this test's business.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push origin main
just install
```

---

## Self-review notes

**Spec coverage.** Selecting → Task 3. Releasing a pin (all four table rows) → Tasks 1 and 3. The target mark and its rename → Task 2. `TargetPick` → Task 1. Two sibling buttons and `HoverTextButtonStyle` → Task 4. The accessibility split and the adjustable action's move → Task 4, asserted in Task 6. Dropdown → text, and the `TargetPill` deletions → Task 5. Tests → distributed, each written before its implementation. Verification beyond the suite → Task 4 steps 4–5, Task 5 step 6, Task 6 step 3.

**Ordering.** Every task leaves a working, installable app. After Task 4 both the rows and the dropdown aim the target; that redundancy is deliberate and lasts exactly one commit.

**The risky step** is Task 4 step 4. The `ZStack`-sibling arrangement is the standard fix for nested buttons on macOS, but this codebase's history with SwiftUI-in-an-`NSPanel` is a list of arrangements that should have worked. If hits do not land, the fallback is a single row button plus a `.simultaneousGesture` on the glyph region — but try the sibling structure first and confirm by clicking, not by reasoning.
