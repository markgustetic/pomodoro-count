# Category rows select the target

**Date:** 2026-07-30
**Status:** approved, not yet implemented

## The problem

Aiming the session target and reading the category list are the same act, done
in two places. The Focus tab carries a dropdown — `towards Work ⌄` — that lists
every category by name, and directly below it sits a list of those same
categories showing their counts and goals. To aim at "Music" you read the row
that says Music, then open a menu and find Music again in a second list that
shows none of the information that made you choose it.

The rows themselves are already clickable, but a click opens the count
adjuster — the rarer action, since correcting a miscount happens far less often
than choosing what to work on next.

So: the common action is buried in a menu that duplicates the list, and the
list's own click is spent on the rare one.

## The change

**A click on a category row aims the session target at it.** The dropdown goes
away; the text it carried — `towards Work` / `pinned to Music` — stays exactly
where it was, now as plain text. Count adjustment moves to a small `±` on the
right of each row, which opens the same popover it opens today.

```
      50:00
Focus session · 50 min
    towards Work          ← was a dropdown, now plain text

┌──────────────────────────────┐
│  Work        ●●○○   2/4   ±  │   ← click row: aim here
├──────────────────────────────┤
│▓ Music        ●     1/1   ±  │   ← accent stroke: target
└──────────────────────────────┘      click ±: − 1 +
```

## Behaviour

### Selecting

A click on a row that is **not** the target calls the existing
`pickTarget(_:)`, whose rule is unchanged and already correct: picking a
category that is *already met* pins (the only reading of that pick is "let me
overshoot here"), picking one with a goal left does not.

### Releasing a pin

The dropdown's first entry, *Follow the order*, was the only way to hand
control back to the ranking after a pin. It becomes a **second click on the row
that is already the target**:

| Clicked row is target | `targetPinned` | `autoAdvanceTarget` | Result |
|---|---|---|---|
| no | — | — | aim (`pickTarget`) |
| yes | yes | yes | release (`followTheOrder`) |
| yes | yes | no | nothing |
| yes | no | — | nothing |

The two no-op rows are the reason this gets a pure function rather than an
`if` in a view. Routing an unpinned re-click to `followTheOrder()` would call
`restartFromTopOfRanking()`, which aims at the top unmet category — so clicking
"Music" while Music is already the unpinned target would move the target *off*
Music and onto Work. A second click must never move the target somewhere the
user did not click.

With `autoAdvanceTarget` off there is no ranking driving anything, so there is
nothing to hand back to. This mirrors what the dropdown did: it only showed
*Follow the order* while the rule was running.

### The target mark

`CategoryProgress.isSessionTarget` becomes **`isTarget`**, and drops the
`sessionRunning` guard in `todayProgress`. Its meaning changes from "a session
is running and aimed here" to "pomodoros land here".

The rename is the point. A row you can click to select needs to show its
selection before you press Start, so the mark must survive idle and paused —
at which point the old name would be a lie. What a mark means has to be one
thing, and "pomodoros land here" is the thing worth marking; whether a session
is currently running is already answered, in 48pt digits, directly above.

VoiceOver's suffix in `accessibilityValue` goes from `", current session
target"` to `", session target"` for the same reason.

## Structure

### `TargetPick` — new, pure

```swift
enum TargetPick {
    enum Action { case aim, release, ignore }
    static func action(isAlreadyTarget: Bool, pinned: Bool, autoAdvance: Bool) -> Action
}
```

Eight cases, all enumerable, none of them reachable from a unit test if the
rule lives inside a `Button`'s closure. Follows the house shape —
`Reorder.destination`, `CategoryAdvance.next`, `HeatmapLayout.hitTest`.

`AppModel.selectTarget(_:)` computes `isAlreadyTarget` (it already has
`resolve`) and dispatches to `pickTarget`, `followTheOrder`, or nothing.

### `CategoryRows.swift` — one button becomes two

The row is a `ZStack(alignment: .trailing)` holding the row button and the `±`
button as **siblings**, not the `±` nested inside the row button's label. A
Button inside another Button's label does not receive clicks on macOS; the
outer button's hit testing swallows it. As a sibling drawn later, the `±` is
above in z-order and takes its own hits, and the row takes everything else.

*This must be verified by running it, not by trusting the paragraph above.*
The row content reserves trailing room so the count text does not slide under
the `±`.

The `±` uses the existing **`HoverTextButtonStyle(emphasis: .action)`** — no new
style. It already rests at `textDim`, brightens on hover, glows under
Synthwave, branches on `ControlState`, and ends in `.dimmed(state, palette)`,
which is what the button-style rule in AGENTS.md requires. Its glyph is
`plusminus`, in a 22×22 `contentShape(Rectangle())` so the hit target is bigger
than the glyph.

The popover moves from the row to the `±`, keeping `arrowEdge: .trailing`, so
it hangs off the control that opened it.

### Accessibility

The split follows the same seam as the click targets:

- **Row element** — label `name`, value `accessibilityValue` (which now carries
  the target mark), hint "Sends finished pomodoros here", `AXPress` selects.
- **`±` element** — label "Adjust today's count for *name*", value `countText`,
  `AXPress` opens the popover.

`.accessibilityAdjustableAction` **moves from the row to the `±`**. It exists so
VoiceOver can adjust a count in one swipe instead of three activations through
a popover; that reason is untouched, but its home is now the element that owns
counting. The row owns targeting.

`.accessibilityElement(children: .ignore)` stays **inside** each button's
label, never on the button — on the button it discards the button's own
element, taking `AXPress`, focus and `AXValue` with it. That was measured
through the Accessibility API in `a4626f3` and is guarded by
`CategoryRowAccessibilityUITests`.

### `RootView.swift` — dropdown to text

The `Menu` block becomes a plain `Text(model.sessionTargetDescription)` in the
same slot at the same `.caption`, with `.lineLimit(1)` and
`.truncationMode(.tail)`. Tooltip becomes "Which category a finished session
credits — click a category below to change it", since the text no longer
explains how to change it.

### Deletions

Removing the `Menu` removes `NSPopUpButton`, which was the entire reason
`TargetPill` exists — that control ignores SwiftUI frames on its content, so
the string had to be cut to a measured width *before* it reached the label. A
plain `Text` truncates natively at its rendered width, and `.tail` cuts the
name rather than the promise, which is the one property `TargetPill.label`
was written to guarantee. So it goes, and its measured `chrome` constant with
it:

- `Sources/PomodoroCount/TargetPill.swift`
- `Tests/PomodoroCountTests/TargetPillTests.swift`
- `AppModel.sessionTargetPillText`
- the `TargetPill` entry and paragraph in AGENTS.md

`sessionTargetPromise` stays — it feeds `sessionTargetDescription`, which is
unchanged and now drives the visible text as well as the spoken one.

This is a deletion the change *earns*, not one it takes on faith: the
workaround goes because its cause goes.

## Tests

Failing first, in `Tests/PomodoroCountTests`, swift-testing.

- **`TargetPickTests`** — all eight cases of `TargetPick.action`, named for the
  rule each pins down. The two no-op cases get their own tests: they are the
  ones a plausible-looking implementation gets wrong.
- **`CategoryProgressTests`** — the five `isSessionTarget` tests become
  `isTarget` tests. Three of them
  (`…IsFalseWithNoSessionRunning`, `…IsFalseDuringABreak`, `…IsFalseWhilePaused`)
  currently assert the opposite of the new rule and invert to assert the mark
  *survives* each of those states.
- **`CategorySessionTests`** — a second pick on a pinned target releases the pin
  and re-aims at the top unmet category; a second pick on an unpinned target
  changes nothing; a second pick with `autoAdvanceTarget` off changes nothing.
- **`CategoryRowAccessibilityUITests`** — extended to assert the row and the
  `±` are two elements, each with its own role and press.

## Verification beyond the suite

- `--preview` for the look: one row always outlined, `±` on every row, in both
  palettes. `--preview --store` (merged in `26f11ef`) can seed a pinned target,
  which the hardcoded demo model cannot express.
- The `drive-panel` skill for the click behaviour: the real panel cannot be
  driven synthetically, so selection is checked by reading `accessibilityValue`
  back off the rows through the Accessibility API after posted clicks, per the
  harness rule — *reproducing a failure there is evidence; reproducing a
  success is not*, so drag-free click behaviour in the real panel still gets one
  pass by hand.

## Out of scope

While a session runs, `phaseSubtitle` already appends the target
("Focus in progress · Work") one line above the text that now reads
"towards Work". That duplication predates this change and is left alone.
