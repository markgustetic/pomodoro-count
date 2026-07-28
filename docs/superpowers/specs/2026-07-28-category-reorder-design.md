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
becomes `NSCursor.openHand` over the grip and `NSCursor.closedHand` during a
drag.

Pressing the grip and moving lifts the row and carries it under the pointer
while the others open a gap for it; releasing drops it in. That behaviour is
AppKit's — the list is a `List`, and its reordering is the system's, so it
matches every other reorderable list on the Mac and moves at the frame rate the
platform manages rather than one we compute.

In practice the grip is the only place a drag can start, because it is the only
part of the row that is not already a control. The name field, the goal stepper
and the remove button keep their existing behaviour: dragging inside the name
field selects text, as it should.

The grip costs roughly 18pt of a 300pt panel, taken from the name field. Names
still fit comfortably; very long ones truncate slightly sooner while being
typed.

### Accessibility

The `List` gives VoiceOver its standard reorder action, and keeping the `List`
keeps it — this is the behaviour that already shipped, and the surest way not to
regress it was not to replace it. Keyboard-only reordering, for a user with Full
Keyboard Access and no screen reader, is not something macOS list reordering
offers and this change does not add it.

The grip is decorative to VoiceOver, and marked `accessibilityHidden`: the row
already carries the category's name and the reorder action, so announcing the
glyph as well would only add noise.

## Architecture

### The reorder is the platform's, not ours

`CategoryList` is a `List` with `.onMove`. On macOS a `List` is backed by
NSTableView, so AppKit drives the drag: the row lifts, tracks the pointer and
drops natively, and the move arrives once, on drop.

This was not the first attempt. A hand-built version — a `VStack`, a
`DragGesture` on the grip, and arithmetic that decided which slot the row
belonged in — was built, reviewed and shipped, and it flickered. Each crossing
reordered the array, wrote the store and started an animation, while the dragged
row's offset was recomputed by hand to compensate; two rounds of fixes (matching
the animation, then making the slot sticky so a slow crossing did not commit
dozens of moves) improved it without curing it. The lesson worth keeping: the
part that felt wrong was never the part that was hard to get right. The
arithmetic was correct and thoroughly tested. What could not be reproduced by
hand was the frame-by-frame smoothness AppKit gives away for nothing.

The grip is what makes the `List` usable, and is the whole reason the first
attempt existed. A `List` row drags from any non-interactive part of itself, and
this row is a `TextField`, a `Stepper` and a `Button` edge to edge — there was
nowhere to grab, which is why the `.onMove` already wired up before this change
was unreachable. The glyph is the one part of the row that takes no clicks, so
it is the part you grab. It carries no gesture of its own; it is a grab point
and a signpost.

### `AppModel.moveCategories(fromOffsets:toOffset:)`

Takes exactly what `.onMove` hands over — source offsets and an insertion offset
measured before the removal. That convention is awkward in isolation, but the
only caller is `.onMove`, and translating it into something tidier here would
mean translating it back at the call site.

### Row height is measured, not hardcoded

The `List` is given an explicit height so it does not open a scroller of its own
nested inside the Settings `ScrollView`. That height used to be a hardcoded
`CategorySettingsRow.rowHeight = 32`, carrying a comment warning it had to be
re-measured by hand whenever the row's font or padding changed. Instead a row
reports its real height through a `GeometryReader` in its background, published
to state by `.task(id:)` — which runs after the layout that produced the height,
so the write cannot land mid-update.

A single fallback constant remains, applying only to the first frame before any
measurement lands. Without it the `List` would be asked for a height of zero and
the rows would vanish, which is precisely what an earlier attempt at self-sizing
this list (`.scrollDisabled` plus `.fixedSize`) did.

### File split

`SettingsTab.swift` was 383 lines doing two jobs: app preferences and a category
editor. The category editor — `CategoryList`, `CategorySettingsRow`,
`AddCategoryForm`, `RemoveCategoryConfirmation` and `FallbackNameField` — moved
to `CategoryEditor.swift`, leaving `SettingsTab.swift` at app preferences only.
This mirrors the existing split of `Category.swift` from the model.

## Persistence

`AppModel.settings` saves on `didSet`, so a reorder writes the store. `.onMove`
fires once per completed drag, so that is one write per reorder, on drop —
nothing during the gesture.

This is worth stating because the hand-built version got it wrong in a way that
was visible: it committed a move on every crossing, and each move was a
synchronous encode of the whole store on the main actor, mid-drag. That was a
real contributor to the flicker, not just a theoretical cost.

No schema change: order is already carried by the position of entries in
`settings.categories`.

## Testing

The reorder itself is AppKit's and is not ours to test. What is ours is the
model mutation and the invariants around it, all in `CategoryManagementTests`:

- moving down, moving up, and moving down by one — the last pins `.onMove`'s
  insertion-offset convention, which a caller passing a destination index
  instead would silently get wrong
- dropping a row back where it started changes nothing
- the new order survives a save and reload
- `todayProgress` reflects the new order, with the fallback bucket still last
- `records` are untouched by a reorder
- the session target still resolves to the same category after one — the
  coupling is by name rather than index, which is exactly the kind of invariant
  a future index-based change could break unnoticed

Deleted along with the hand-built gesture: `Reorder.destination` and its suite.
The arithmetic was correct and well tested; it simply has nothing left to do.
