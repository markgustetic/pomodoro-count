# Adjusting a category's count

Tapping a category row in the Focus tab currently logs one pomodoro and nothing
else. It becomes a popover instead: a compact `−  3/8  +` strip anchored beside
the row, where `+` logs one and `−` takes one back. Each tap commits
immediately; the popover stays open until dismissed.

## Why

The row is a one-way ratchet. Every count in the app can go up and only the
whole day can come back down, through "Undo last" — which removes the newest
record *anywhere*, so correcting a mis-tap on Writing means first checking
whether something landed on Admin since.

That is the wrong shape for how the counts are actually entered. The app's
premise is that the pomodoro happened somewhere else and gets typed in
afterwards, often several at once and often from memory. Entry from memory is
entry that gets revised. A row that can only be incremented forces the revision
through a global undo whose behaviour depends on rows the user isn't looking at.

Per-category subtract is the gap. The popover is what makes it reachable
without giving `−` a hidden gesture of its own.

## Scope

In: the popover on category rows in the Focus tab, a `−` that removes today's
newest record in that category, and a VoiceOver adjustable action on the row.

Out: editing counts for past days (History stays read-only), typing a count
directly, batch entry beyond repeated `+` taps, and any change to the
no-categories path — `LogButton` and "Undo last" are untouched.

## Interaction

Tapping a row opens a popover on its **trailing** edge, so it sits beside the
row rather than over the rows below it. Contents, one line:

```
   −     3/8     +
```

The count reads `done/goal` when the category has a goal and bare `done` when
it doesn't — the same rule the row's trailing column already follows. The
category name is **not** repeated: the row that was tapped is still visible
immediately beside the popover.

- `+` calls `logExternal(to:)`. This is precisely what the row does today,
  including the `realignTarget()` that follows every append.
- `−` calls the new `unlogToday(from:)`. Disabled when `done == 0`.

The popover stays open until the user clicks outside it or presses Escape.
There is no Done or Cancel: nothing is pending, so there is nothing to confirm
or discard. Repeated `+` taps land in one place, which is the batch-entry case.

The panel is not dismissed by either button. Row logging never dismissed it —
only `LogButton` does, because that path has nothing left to show.

### Three deliberate non-changes

**`−` does not realign the session target.** `undoLast()` already establishes
this: a removal is not an append, and the target advance is forward-only.
Un-aiming a running session because a count dropped would move the target out
from under a Start the user already pressed. This needs a WHY comment at the
call site, because AGENTS.md's "every record-appending path also realigns"
reads as an invitation to add it to the removing path for symmetry.

**`−` never reaches an earlier day.** A category with nothing logged today is a
no-op even when yesterday has records in it. The row shows today; the popover
adjusts today.

**"Undo last" stays.** It is the only correction path when categories are off.
With categories on it is now a second mechanism, but removing it would take the
correction away from the users who have no rows to tap.

## Architecture

### Pure logic, tested

```swift
enum CountAdjust {
    /// Index of today's newest record in one category — what a subtract
    /// removes. `nil` category means the fallback bucket. `nil` result means
    /// there is nothing to remove.
    static func newestTodayIndex(in records: [Record], category: String?) -> Int?
}
```

Normalizes the name the way `todayCount(inCategory:)` does, and filters on
`Calendar.current.isDateInToday` for the same reason. Pure over an array of
records, so the choice of *which* record is tested without a store.

### Model

```swift
/// The subtract half of the row popover: drops today's newest record in one
/// category. Nothing logged today is a no-op, so a count cannot go negative —
/// the popover disables the button there too, but the model must not depend on
/// the view for that.
func unlogToday(from target: CategoryTarget)
```

Four lines over `CountAdjust.newestTodayIndex`: resolve the target, find the
index, remove it, `play(.countDown)`. No `realignTarget()`, with the comment
above explaining the omission.

No `suspendSaves()` either, and for a reason worth stating: the bracket exists
for a *burst* of related changes, and this is one mutation of `records`, so its
`didSet` should write once. `logExternal` brackets because it pairs an append
with a target advance; a removal has no second half to pair with.

### Views

`CategoryCountPopover(progress:onAdd:onSubtract:)`, in `CategoryRows.swift`
beside the row it belongs to.

It takes **closures, not the model**: `@EnvironmentObject` does not reliably
reach popover content and fails by crashing, which is why `AddCategoryForm` and
`RemoveCategoryConfirmation` are shaped this way. It applies `.themed(palette)`
itself — a popover is its own window and inherits the environment but not the
appearance.

The live count needs no extra machinery. `CategoryRows.body` re-runs when
`records` changes, so the popover's content closure is re-evaluated with a
fresh `CategoryProgress`. The `@State` flag driving presentation survives that
rebuild because the `ForEach` identifies rows by `id`.

`CategoryRow` changes in three places: its `action` closure sets the
presentation flag instead of logging, its `.help` becomes "Adjust
\(name)'s count for today", and its accessibility grows an adjustable action:

```swift
.accessibilityAdjustableAction { direction in
    switch direction {
    case .increment: onAdd()
    case .decrement: onSubtract()
    @unknown default: break
    }
}
```

This is not decoration. The row currently logs in one VoiceOver activation, and
routing it through a popover would cost that. The adjustable action restores it
— VoiceOver swipe-up and swipe-down increment and decrement without opening the
popover at all — and it is the idiomatic control for exactly this. The
`accessibilityHint` becomes "Opens a counter you can adjust".

Both buttons use `SoftIconButtonStyle`, which already branches on
`ControlState` rather than pressed/hovering — so `.disabled(done == 0)` on the
`−` is visibly dim and stays dark under `PreviewOverrides.forceHover`. A
hand-rolled borderless style here would reintroduce the dead-button-looks-live
bug the palette exists to prevent.

### Preview

`--preview` cannot show this. A popover is its own window, which is the whole
reason this app uses popovers for dialogs, and the offscreen renderer draws the
panel. Nothing is added to `PreviewRenderer` on the strength of a flag that
would render an empty panel.

The popover's *appearance* is therefore a by-hand check after `just install`,
in both themes and with the `−` both live and disabled. Its *behaviour* is
covered by the tests below. This split is stated so nobody later reads a green
suite as evidence the popover looks right.

## Testing

Failing first, in `Tests/PomodoroCountTests` (swift-testing).

`CountAdjust.newestTodayIndex`:

1. Returns the newest matching index, not the last appended one — the trap
   `undoLastRemovesTheNewestNotTheLastAppended` guards for the global case.
2. Returns `nil` on an empty array and on no match.
3. Matches the bucket on `nil`, and does not match a named category to it.
4. Normalizes: `"writing"` finds a record stored as `"Writing"`.

`unlogToday`:

5. Removes one record from the named category and leaves other categories'
   records alone — including a record in another category with a *newer*
   timestamp.
6. Is a no-op on a category with nothing logged today.
7. Leaves yesterday's records alone even when the category has nothing today.
8. Removes a category-less record when passed `.fallback`.
9. Does not move `sessionTarget`, including in the case where the removal takes
   a met category back below its goal.

## Alternatives considered

**Keep tap as `+1`, put the popover on right-click.** Preserves the one-tap
errand exactly. Rejected because a right-click-only adjuster is undiscoverable:
the feature exists to fix a correction path that is already too obscure.

**Stage the delta and commit on Done.** The popover would show a pending number
and write the difference on Done. Rejected as more machinery for less: it needs
a Done/Cancel row, and it needs a rule for what timestamps a batch of new
records gets, which immediate commit answers by just using `Date()`.

**Close the popover after the first tap.** Closest to the old feel, but a
stepper that dismisses itself on every press is strange to use, and it makes
the batch case — the reason the popover is worth opening — cost a reopen per
pomodoro.
