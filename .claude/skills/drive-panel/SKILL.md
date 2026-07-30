---
name: drive-panel
description: Use when Pomodoro Count's UI needs verifying or debugging without a human at the mouse — gesture bugs, panel sizing, menu bar state, drag behavior, or any claim the unit suite and --preview cannot check.
---

# Driving the panel headlessly

## Overview

The unit suite can't see the UI and `--preview` renders in a permissive
environment the real panel doesn't match. Real verification = the
Accessibility API for reading (element frames, `accessibilityValue`s, the
status item title) plus posted CGEvents for input. The bundled
[drive.swift](drive.swift) is a working driver: `swift drive.swift <pid>
<command>`.

## Hard-won rules — violating these wastes the hours they cost

1. **The real panel's gestures cannot be driven synthetically.** Clicks work;
   `DragGesture` never fires — XCUITest and raw CGEvent streams alike, any
   tap, click-state and delta fields set. Don't burn time retrying variants.
2. **Gesture work goes through the harness**: launch with `--reorder-window`
   (plain window, identical view code, gestures fully drivable). The rule on
   `ReorderHarness` is law: *a failure reproduced there is evidence; a success
   proves nothing about the panel.* Drag-start in the panel is hand-verified only.
3. **Always `--store <scratch>/data.json`** (seed via `--seed-store`) for
   experiments. If you must touch the real running app, restore what you
   change — a test log is undone via the panel's "Undo last".
4. **One process per interaction sequence.** The panel dismisses between
   separate driver invocations (each recompiles for seconds). Compound
   commands (`openclick`, `measuretabs`) exist for this; add more before
   chaining single steps.
5. **Read values, not pixels.** The countdown's drawn text is replaced in AX
   by its label/value (`accessibilityValue` = spoken duration). `texts` finds
   little; `tree` + grep does.
6. **Check the window before trusting element frames.** AX positions elements
   that are laid out below a collapsed window (`window` command compares AX vs
   CGWindowList). Events aimed there land in whatever app is behind.
7. **An empty `AXValue` is not proof of a missing value — dump the attribute
   list first.** Which attribute a SwiftUI modifier lands in depends on the
   element's *role*, and `tree` prints only `AXValue`:
   - `AXStaticText` — a `Text`'s `.accessibilityLabel` lands in **`AXValue`**
     (a static text's "value" *is* its string), leaving `AXDescription` empty.
   - `AXButton` / `AXMenuButton` — `.accessibilityLabel` → `AXDescription`,
     `.accessibilityValue` → `AXValue`.
   - `AXUnknown` (a generic element) — has **no `AXValue` attribute at all**;
     `.accessibilityValue` is demoted to **`AXValueDescription`**.

   `AXUIElementCopyAttributeNames` settles it in one call. Reading only
   `AXValue` once produced a bug report against working code — and hid the real
   defect underneath it (rule 8).
8. **`.accessibilityElement(children: .ignore)` goes *inside* a `Button`'s
   label, never on the `Button`.** It builds a fresh plain element and discards
   the one it is applied to, so on a Button it throws the button away: the role
   drops to `AXUnknown`, `AXPress` and focusability vanish, and the value is
   demoted per rule 7 — one cause, three symptoms, none of them visible on
   screen or to the unit suite. `CategoryRow` carries the fix and the full
   reasoning; `CategoryRowAccessibilityUITests` is the regression gate, and
   XCUITest is the only suite here that can see any of it.

## Recipe

```bash
swift build
.build/debug/PomodoroCount --seed-store "$SCRATCH/data.json"
nohup .build/debug/PomodoroCount --store "$SCRATCH/data.json" --reorder-window \
  > /dev/null 2> "$SCRATCH/app.log" &   # stderr catches NSLog instrumentation
swift drive.swift <pid> tree            # see what's there
```

Commands: `tree` (roles/titles/values/frames), `open`, `button <name>`,
`openclick <name>`, `rows`, `drag <A> <B>` (slow, samples positions),
`statusitem`, `measuretabs` (per-tab panel heights), `window`, `advance <row>`
(click a category row, read the session-target pill before and after, in one
process — proves the pill updates live rather than on reopen), `counter <row>`
(open its count popover and work its − and + in one process), `counterkeys
<row>` (same popover, the short VoiceOver-and-Escape probe), `countershot
<row> <path>` (screenshot the popover in place, from inside the process),
`settingsshot <button> <path>` (open Settings, click `<button>`, and
screenshot — for comparing a pre-existing popover against a new one). Coordinates
are CG global, top-left origin. Temporary NSLog lines in the app + captured
stderr give the event stream; remove them before committing.

## Common mistakes

| Mistake | Reality |
|---|---|
| "The drag didn't fire, let me tweak event fields" | Panel gestures are undrivable. Harness. |
| Driving the installed app's real store | Scratch store, or undo what you logged. |
| Harness drag works → "panel drag works" | Harness success proves nothing. |
| Reading the panel between two driver calls | It dismissed. Compound command. |
