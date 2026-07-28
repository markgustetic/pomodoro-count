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

Pressing the grip and moving lifts the row — a slight scale and a stronger
shadow — and it follows the pointer vertically while the remaining rows slide to
open a gap. Reordering is live: when the dragged row's position crosses into
another slot, the move happens immediately, so the order visible during the drag
is the order that lands. Releasing settles the row into place with a spring.

The grip is the only drag source. The name field, the goal stepper and the
remove button keep their current behaviour. A drag needs 3pt of movement before
it counts, so a stray click on the grip does nothing.

The grip costs roughly 18pt of a 300pt panel, taken from the name field. Names
still fit comfortably; very long ones truncate slightly sooner while being
typed.

### Accessibility

Today's `List` gives VoiceOver a reorder action and gives keyboard users
nothing — macOS list reordering is mouse-only. Replacing it must not lose the
former, so each row gets "Move up" and "Move down" accessibility actions, which
reach both. The grip itself is decorative to VoiceOver: the actions live on the
row, which already carries the category's name.

## Architecture

Three pieces, so the error-prone part is testable without a UI.

### 1. `Reorder.destination` — pure, no SwiftUI

```swift
static func destination(from startIndex: Int,
                        translation: CGFloat,
                        pitch: CGFloat,
                        count: Int) -> Int
```

Given the index a drag began at and how far it has travelled, returns the slot
the row now belongs in: `startIndex + round(translation / pitch)`, clamped to
`0..<count`. Returns `startIndex` unchanged when `pitch <= 0` or `count <= 0`,
so a row that has not been measured yet cannot produce a nonsense move.

This is where reorder bugs live — rounding at the midpoint, running off the
ends — so it is a free function over numbers, tested directly.

### 2. `AppModel.moveCategory(from:to:)`

Replaces `moveCategories(fromOffsets:toOffset:)`, which existed only to feed
`List.onMove` and has one caller. Swift's `Array.move(fromOffsets:toOffset:)`
takes an *insertion offset measured before the removal*, so moving a row down by
one requires `to + 1`; passing `to` moves nothing and the row appears stuck. That
adjustment is absorbed and commented once here rather than repeated in gesture
code.

Guards: indices outside `settings.categories.indices` and `from == to` change
nothing, so a drag that resolves to its own slot writes nothing to the store.

### 3. The gesture, in the view

`CategoryList` owns the drag state — the dragged category's id, the index the
drag started at, the index it currently occupies, and the raw translation — and
renders rows in a `VStack`.

The dragged row's visual offset is

```
translation - CGFloat(currentIndex - startIndex) * pitch
```

so it stays under the pointer after a swap, rather than jumping by a row each
time one happens. On change: ask `Reorder.destination`; if it differs from
`currentIndex`, call `moveCategory` and update `currentIndex`. On end: clear the
drag state inside a spring animation.

### Row pitch is measured, not hardcoded

The drag needs the row-to-row distance. `SettingsTab.swift` currently hardcodes
`CategorySettingsRow.rowHeight = 32`, carrying a comment warning that it must be
re-measured by hand if the row's font or padding changes. Rather than keep that,
a row reports its real height through a `GeometryReader` in its background and a
`PreferenceKey`; pitch is that height plus the `VStack` spacing.
`onGeometryChange` would be tidier but is macOS 15, and the package targets
macOS 14.

This is possible because the `List` goes away, replaced by a plain `VStack`.
That also removes the nested-scroller problem — a `List` inside the Settings
`ScrollView` — which the height hack existed to work around.

### File split

`SettingsTab.swift` is 383 lines doing two jobs: app preferences and a category
editor. This change adds to the second. The category editor —
`CategorySettingsRow`, `AddCategoryForm`, `RemoveCategoryConfirmation`,
`FallbackNameField`, plus the new `CategoryList`, grip handle and `Reorder` —
moves to `CategoryEditor.swift`, leaving `SettingsTab.swift` at roughly 150
lines of app preferences. This mirrors the existing split of `Category.swift`
from the model.

## Persistence

`AppModel.settings` saves on `didSet`, so each swap writes the store. Swaps are
discrete — they fire when the drag crosses into a new slot, not per frame — so
dragging across four positions costs four writes, comparable to four clicks of a
stepper. This is not the per-keystroke behaviour the rename path was fixed for,
and needs no debouncing.

No schema change: order is already carried by the position of entries in
`settings.categories`.

## Testing

Test-driven, matching the project's existing swift-testing suites.

`Reorder.destination`:

- moving down by one row and by several
- moving up by one row and by several
- zero translation returns the starting index
- exactly half a pitch, the rounding boundary: `rounded()` rounds half away from
  zero, so `+pitch / 2` moves down one slot and `-pitch / 2` moves up one. Pinned
  by a test so it is a decision rather than an accident.
- clamped at index 0 dragging up past the top, and at `count - 1` past the
  bottom
- `pitch <= 0` and `count <= 0` return `startIndex`

`AppModel.moveCategory(from:to:)`, in `CategoryManagementTests`:

- moving down lands in the expected slot (the `to + 1` case)
- moving up lands in the expected slot
- `from == to` leaves the list unchanged
- out-of-range indices leave the list unchanged
- the new order survives a save and reload
- `todayProgress` reflects the new order, with the fallback bucket still last
- `records` are untouched by a reorder

The existing `reorderingChangesDisplayOrder` test moves to the new API.

The gesture itself is not unit-tested — it is a few lines wiring the two tested
pieces together — and is verified by running the app.
