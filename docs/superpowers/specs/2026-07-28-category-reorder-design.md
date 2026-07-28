# Reordering categories by dragging

Settings gets a grip handle on each category row. Drag it to change the order
categories appear in, both in Settings and in the Focus panel.

## Why

The order already matters — the panel lists categories in settings order, then
the fallback bucket — but there is no way to set it beyond deleting and
re-adding. `.onMove` is wired onto a `List` in `SettingsTab.swift` today, and
`AppModel.moveCategories(fromOffsets:toOffset:)` backs it, but the affordance is
unreachable: no visible handle, and the row is a `TextField`, a `Stepper` and a
remove button edge to edge, so there is nowhere to grab.

## Scope

In: drag-to-reorder the user's own categories, in Settings only, from a grip
handle.

Out:

- Reordering the fallback bucket. It is the catch-all, it reads correctly last,
  and it lives in its own Settings section below a divider. It stays pinned to
  the end of the panel list, exactly as `todayProgress` appends it today.
- Auto-scrolling when a drag reaches the edge of the list. The Settings tab is
  300pt wide with a handful of categories; the machinery is not worth it.
- Reordering from the Focus panel. Rows there log a pomodoro when clicked;
  adding a second meaning to a press would make the primary action worse.

## Interaction

Each category row in Settings carries a grip on its leading edge: the
`line.3.horizontal` SF Symbol, drawn in `palette.textDim` at rest and brightening
on hover, matching how the row's other low-chrome controls behave. The cursor
becomes `NSCursor.openHand` over the grip; once a drag begins the system owns
the cursor and shows its own.

Pressing the grip and moving picks the row up: it lifts slightly, follows the
pointer, and the other rows part to show where it will land. Release, and the
order is committed and written to the store once.

This is the first of four mechanisms tried here, kept after the other three
fell — see Architecture for the full history, including the measurement bug
that made this one stutter for most of a day and what actually fixed it.

In practice the grip is the only place a drag can start, because it is the only
part of the row that is not already a control. The name field, the goal stepper
and the remove button keep their existing behaviour: dragging inside the name
field selects text, as it should.

The grip costs roughly 18pt of a 300pt panel, taken from the name field. Names
still fit comfortably; very long ones truncate slightly sooner while being
typed.

### Accessibility

A system drag has nothing to offer VoiceOver, so each row carries "Move up" and
"Move down" accessibility actions instead. They sit on the row, which already
carries the category's name, rather than on the grip, which is a bare glyph and
is marked `accessibilityHidden`.

On macOS these reach VoiceOver. They do not reach a keyboard-only user with Full
Keyboard Access and no screen reader — custom accessibility actions are exposed
through the accessibility API only, and reaching that audience would need a real
key handler, which this change does not add.

## Architecture

### Four mechanisms, and why it is the first after all

Worth recording, because each failure was informative and none was predictable
from reading code.

**A hand-built `DragGesture`** — what is here now. A `VStack`, a gesture on the
grip, and arithmetic deciding which slot the row belonged in. It worked, and it
flickered, and three rounds of fixes treated real but secondary causes:
matching the animation so the layout shift and its compensation cancelled,
making the slot sticky so a slow crossing did not commit dozens of moves, and
suspending the per-move store writes that each crossing was making
synchronously on the main actor. Each helped; none cured it. The actual cause
is under "The root cause" below.

**A `List` with `.onMove`.** On paper this hands the whole thing to AppKit, and
it is what the codebase already had: `.onMove` was wired up before any of this
work began. The stated reason it was unreachable was that the row is a
`TextField`, a `Stepper` and a `Button` edge to edge with nowhere to grab, and
the grip was supposed to fix exactly that. It did not: dragging the grip moved
nothing. The assumption that only the grab point was missing had never been
tested by anyone, including whoever wrote it down.

**System drag and drop**: `.draggable` on the grip, `.dropDestination` on each
row. Also moved nothing. The panel is a `MenuBarExtra` in `.window` style — a
non-activating `NSPanel` that never takes key status — and AppKit drag sessions
need an active app and a participating window, so both this and the `List`'s
row dragging were structurally dead in it. A hand-built gesture is not a
workaround here; it is the only mechanism that can work in this panel, because
SwiftUI drives it internally with no drag session and no activation.

### The root cause of the stutter

The gesture measured its translation in `.local` — the grip's own coordinate
space. But the gesture's own effects move the grip: `visualOffset` slides the
row with the pointer every event, and each committed move shifts its layout
slot by a whole pitch. The measuring stick was nailed to the thing being
moved.

Measured, in a window where synthetic events could drive the gesture: the
translation accumulated at exactly half the pointer's real travel (the pointer
had moved 46pt when the translation first read 23), oscillating a point or two
between successive events — each event's value chasing a position its previous
value had just moved. Worse, on the frame after each committed move the
translation jumped by a full pitch off one frame of stale layout, read as a
second spurious move, then snapped back and reverted it. Rows stuttered in and
out; hysteresis could not help, because a full-pitch jump sails over any
reasonable stickiness band.

The fix is the platform's own idiom for exactly this: measure the drag in a
coordinate space that does not move during the drag.
`.coordinateSpace(name:)` on the list's `VStack`, and the `DragGesture`
created against `.named` that space. One measurement-frame change; the offset
compensation, the hysteresis and the animation pinning were all correct once
the number they operated on was.

### Why there is a harness window

Synthetic mouse events — XCUITest's synthesis and raw `CGEvent` streams alike,
with or without click-state and delta fields — do not drive this panel's
gesture, while a hand does. They do drive the identical view in an ordinary
window. `--reorder-window` (`ReorderHarness`) hosts the panel's UI in a plain
window for exactly that purpose, and it is how the numbers above were
captured. Its doc comment records the one rule of its use: reproducing a
failure there is evidence, reproducing a success is not — an ordinary key
window is permissive in exactly the way that made two AppKit-drag mechanisms
look plausible while being dead in the panel.

### `AppModel.moveCategory(from:to:)`

`Array.move(fromOffsets:toOffset:)` takes an insertion offset measured *before*
the removal, not a destination index: moving a row down by one needs `to + 1`,
and passing `to` unadjusted moves nothing at all. That adjustment is absorbed
and commented once here rather than at the call site.

Out-of-range indices and a move to the slot the category already occupies change
nothing, so a row dropped back where it came from writes nothing to the store.

### File split

`SettingsTab.swift` was 383 lines doing two jobs: app preferences and a category
editor. The category editor — `CategoryList`, `CategorySettingsRow`,
`AddCategoryForm`, `RemoveCategoryConfirmation` and `FallbackNameField` — moved
to `CategoryEditor.swift`, leaving `SettingsTab.swift` at app preferences only.
This mirrors the existing split of `Category.swift` from the model.

## Persistence

`AppModel.settings` saves on `didSet`, so every committed move would write the
store — synchronously, on the main actor, mid-gesture. Saves are therefore
suspended for the length of a drag (`suspendSaves` / `resumeSaves`) and the one
pending write is performed when it ends, on the cancelled path as well as the
normal one — a suspend left unbalanced would silently stop the app persisting
anything at all.

No schema change: order is already carried by the position of entries in
`settings.categories`.

## Testing

The slot arithmetic lives in `Reorder.destination`, deliberately free of
SwiftUI, with its own suite pinning the midpoint rounding, the hysteresis band
and both ends of the list. The model mutation and the invariants around it are
in `CategoryManagementTests`:

- moving down, moving up, and moving down by one — the last pins the insertion
  offset off-by-one, and fails if the `+ 1` is removed
- a move to the slot the row already occupies, and out-of-range indices, change
  nothing
- the new order survives a save and reload
- `todayProgress` reflects the new order, with the fallback bucket still last
- `records` are untouched by a reorder
- the session target still resolves to the same category afterwards — the
  coupling is by name rather than index, exactly the kind of invariant a future
  index-based change could break unnoticed
- nudging one slot, nudging past either end, and nudging an unknown id, for the
  VoiceOver path

What the unit suite cannot see is the gesture's interaction with layout — the
stutter lived there, and 228 passing tests said nothing about it. That is what
the harness window plus a posted-event drag is for; the skipped drag tests in
`CategoryReorderUITests` record how far automation gets against the real
panel, and why.
