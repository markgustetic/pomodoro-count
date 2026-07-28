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

Pressing the grip and moving starts a system drag: macOS carries a small card
showing the category's name under the pointer, and the row you are over lights
up to say that is where it will land. Release, and that category takes the
highlighted row's place.

Nothing in the list moves while the drag is in flight. The order changes once,
on drop. This is deliberate and is the third mechanism tried here — see
Architecture for what the other two did instead, and why this one is the one
that cannot stutter.

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

### Three mechanisms, and why this is the third

Worth recording, because each failure was informative and none was predictable
from reading code.

**A hand-built `DragGesture`.** A `VStack`, a gesture on the grip, and
arithmetic deciding which slot the row belonged in. It worked, and it flickered.
Every crossing reordered the array, wrote the whole store to disk on the main
actor, and started an animation, while the dragged row's offset was recomputed
by hand to cancel the layout shift. Two rounds of fixes — matching the animation
so the two halves cancelled, then making the slot sticky so a slow crossing did
not commit dozens of moves — improved it without curing it. The arithmetic was
correct throughout and thoroughly tested. That was never the problem.

**A `List` with `.onMove`.** On paper this hands the whole thing to AppKit, and
it is what the codebase already had: `.onMove` was wired up before any of this
work began. The stated reason it was unreachable was that the row is a
`TextField`, a `Stepper` and a `Button` edge to edge with nowhere to grab, and
the grip was supposed to fix exactly that. It did not: dragging the grip moved
nothing, because the `List`'s reorder does not function in this
context — a `List` sized to its contents, nested inside the Settings
`ScrollView`. The assumption that only the grab point was missing had never been
tested by anyone, including whoever wrote it down.

**System drag and drop**, which is what is here now: `.draggable` on the grip,
`.dropDestination` on each row. It depends on neither of the above. There is no
`List`, so the nesting cannot break it; there is no per-frame arithmetic, so
there is nothing to get wrong; and nothing in the list moves during the drag, so
there is nothing that can stutter.

### The payload is an id

`.draggable(category.id.uuidString)`, and the drop resolves both ends by id.
Names would be the obvious thing to carry and are the wrong thing: they are
editable while a drag is in flight, and are not unique until
`isCategoryNameAvailable` has had its say. Resolving by id means a list that
changed underneath the drag cannot land the move on the wrong row.

Dropping onto a row moves the dragged category into that row's slot. There is no
above-or-below-the-midpoint question to answer, which is one fewer thing to get
wrong than an insertion-point model would be.

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

`AppModel.settings` saves on `didSet`, so a reorder writes the store. A drop
happens once per drag, so that is one write per reorder — nothing during the
gesture.

Worth stating because the first mechanism got this wrong in a way that was
visible: it committed a move on every crossing, and each move was a synchronous
encode of the entire store on the main actor, mid-drag. That was a real
contributor to the flicker, not a theoretical cost.

No schema change: order is already carried by the position of entries in
`settings.categories`.

## Testing

The drag is the system's and the drop handler is a lookup; what is worth testing
is the model mutation and the invariants around it. All in
`CategoryManagementTests`:

- moving down, moving up, and moving down by one — the last pins the insertion
  offset off-by-one, and fails if the `+ 1` is removed
- a move to the slot the row already occupies, and out-of-range indices, change
  nothing
- resolving both ends by id, which is what the drop handler does
- the new order survives a save and reload
- `todayProgress` reflects the new order, with the fallback bucket still last
- `records` are untouched by a reorder
- the session target still resolves to the same category afterwards — the
  coupling is by name rather than index, exactly the kind of invariant a future
  index-based change could break unnoticed
- nudging one slot, nudging past either end, and nudging an unknown id, for the
  VoiceOver path

Deleted along the way: `Reorder.destination` and its fourteen tests, which
existed only for the hand-built gesture's arithmetic. They were good tests of
correct code that no longer has anything to do.
