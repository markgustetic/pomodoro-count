# Categories with daily goals

**Date:** 2026-07-27
**Status:** Approved, ready for implementation planning

## Summary

Let a user group pomodoros into named categories, each with a daily goal — for
example Work 4, AI study 1, Music 1 — and see progress toward those goals the
moment the panel opens. The feature is entirely optional: with it switched off
the app behaves exactly as it does today.

## Goals

- Assign a pomodoro to a category in a single tap, without losing the one-click
  logging the app is built around.
- Show progress against each daily goal without opening anything.
- Aim a built-in focus session at a category before starting it.
- Never lose or silently rewrite history.

## Non-goals

Deliberately excluded to keep the panel compact and the scope shippable:

- Weekly or monthly goals. Daily only.
- Per-category colours or emoji. Rows use the active theme's accent.
- A per-category breakdown in the History tab.
- Per-category menu bar display.
- Editing a pomodoro's category after logging it.

## Decisions

| Question | Decision | Reasoning |
|---|---|---|
| How is a category assigned? | Tap its row in the panel | Keeps logging to one tap and puts goals in view without opening anything |
| Where do untapped pomodoros go? | A built-in fallback category, or a category the user marks as default | The destination is fixed and predictable rather than inferred from recent activity |
| Fallback switched off with pomodoros in it | It stays until empty | Nothing is hidden and no records move without being asked |
| Aiming a focus session | A target pill in the timer card | The destination is visible before the session starts |
| What is a category? | Name and daily goal only | No configuration to get wrong, nothing to clash with either theme |
| Deleting a category | Archive — history stays intact | One rule shared with the fallback bucket |

## Data model

```swift
struct Category: Codable, Identifiable, Equatable {
    var id = UUID()          // list identity for SwiftUI; records never reference it
    var name: String         // unique across categories and the fallback name
    var dailyGoal: Int       // 0...20; 0 means "track it, no goal"
}
```

A goal of `0` is legal and means the category is tracked without a target: its
row shows the running count and no dots. This exists so the fallback bucket can
be an ordinary row rather than a special case, and it costs nothing to allow it
for any category.

`Record` gains one optional field:

```swift
var category: String?        // category NAME; nil means the fallback bucket
```

Records reference the **name**, not the id, because re-adding a category with a
previous name must reunite it with that history. The cost is that renaming must
rewrite the affected records, which the app does in a single pass. `id` exists so
SwiftUI list editing and reordering animate correctly.

`Settings` gains:

| Field | Default | Purpose |
|---|---|---|
| `categoriesEnabled` | `false` | The feature is opt-in |
| `categories` | `[]` | The user's list, in display order |
| `usesFallbackBucket` | `true` | Whether the always-present bucket exists |
| `fallbackName` | `"General"` | Editable display name for the bucket |
| `fallbackGoal` | `0` | The bucket's own daily goal; 0 means none |
| `defaultCategoryName` | `nil` | Destination for untapped pomodoros when the bucket is off |
| `sessionTargetName` | `nil` | Remembered timer target; `nil` means the bucket |

## Migration and compatibility

`category` is optional, and Swift's synthesized decoder treats optional
properties as `decodeIfPresent`. Every existing `data.json` therefore decodes
unchanged and **no `schemaVersion` bump is required**. Existing pomodoros have
`category == nil`, which places them in the fallback bucket.

Turning the feature off after use keeps every record's category. The panel
returns to today's hero button and totals are unaffected; turning it back on
restores the previous view.

## Behaviour rules

### Routing a pomodoro

There are three ways a pomodoro is created, and they resolve differently:

1. **Tapping a category row** credits that category. No ambiguity.
2. **A completed timer session** credits `sessionTargetName` when that category
   still exists. If it was archived, or is `nil`, it falls to the default chain
   below.
3. **The global hotkey** always uses the default chain — it never uses
   `sessionTargetName`, because the timer's target is a property of a session the
   user deliberately aimed, not a standing preference for logging from elsewhere.

The default chain, in order:

1. `defaultCategoryName`, when the bucket is off and that category still exists.
2. The fallback bucket (`category == nil`), when it is on.
3. The first category in display order, when the bucket is off and its marked
   default is missing.
4. The fallback bucket regardless of the toggle, when no categories exist at all.

Steps 3 and 4 exist so a user who archives their marked default can never reach a
state where a pomodoro has nowhere to go.

### Archiving

Deleting a category removes it from `categories`. Its records keep their category
name, so History, all-time totals, and CSV export are unchanged. The category
stops appearing in the panel and stops counting toward goals. Re-adding a
category with the same name reunites it with those records.

The fallback bucket follows the same rule: switching it off stops it receiving
new pomodoros, and it remains visible while it still holds any.

### Renaming

Renaming a category rewrites `category` on every record that referenced the old
name, in one pass, before the new name is saved. No record is orphaned.

### Name uniqueness

Names are unique across the user's categories **and** the fallback name,
compared case-insensitively with surrounding whitespace trimmed. The Settings UI
blocks a colliding name rather than accepting and silently merging it.

### Overshooting

Passing a goal keeps counting. A sixth pomodoro against a goal of 4 shows `6/4`
with every dot filled. The app never hides work because a target was exceeded.

### Undo

"Undo last" stays global — it removes the most recent pomodoro regardless of
category, matching the existing newest-not-last-appended behaviour.

## Interface

### Focus tab, categories on

The category rows replace the hero log button. Tapping a row logs one pomodoro to
that category, with the same sound and undo behaviour as the button today.

**The fallback bucket is an ordinary row**, listed last, and tappable like any
other. With `fallbackGoal` at its default of 0 it shows only a count. This is why
a goal of 0 is legal: the bucket needs no special rendering path.

```
Work        ●●○○     2/4
AI study    ●        1/1
Music       ○        0/1
General              3        ← goal 0: count only, no dots
            Undo last
```

Row anatomy, at 300pt panel width with 14pt padding (~272pt usable):

- **Name** — left, semibold, 13pt, truncating with a tail ellipsis.
- **Progress** — one dot per goal unit up to **8 units**; above 8 the row draws a
  slim progress bar in the same space, so the row never reflows.
- **Count** — `done/goal`, right-aligned, tabular figures so digits don't jitter.
  When the goal is met the count takes the theme's accent colour.

Heights: three categories plus Undo is roughly 110pt, against roughly 90pt for
today's hero button and Undo. Each additional category adds about 33pt. Beyond
six rows the list scrolls within a ~200pt cap, matching the existing History
day-list pattern, so the panel stops growing.

**Empty state.** Only reachable with the feature on, no categories created, *and*
the fallback bucket switched off — otherwise the bucket row is always there to
tap. In that case a single muted row reads "Add a category in Settings", rather
than leaving a gap where the log button was.

### Timer card

A target pill sits below the subtitle:

```
        50:00
Focus session · 50 min
   ● towards Work ▾
[ Start focus ] [ ■ ] [ ☕ ]
```

The pill is a menu listing every category plus the fallback bucket. The selection
persists as `sessionTargetName`. While a session runs the subtitle reads "Focus
in progress · Work" and that category's row is outlined. On completion the
pomodoro credits the target.

Breaks credit nothing, unchanged from today.

### Settings

A **Categories** section. Because the Settings tab is already the longest — two
steppers, four toggles, the shortcut recorder, launch at login, and the updater
controls — its content scrolls inside a height cap, the same treatment History
already has.

```
Use categories                          [ on ]
──────────────────────────────────────────────
Work                            [ 4 ] ⌃⌄   ⊖
AI study                        [ 1 ] ⌃⌄   ⊖
Music                           [ 1 ] ⌃⌄   ⊖
＋ Add category
──────────────────────────────────────────────
Fallback category               [ on ]
  Name  [ General            ]     [ 0 ] ⌃⌄
```

Rows drag to reorder; that order is the panel order, with the fallback bucket
always last. With the fallback off, its block becomes a picker for
`defaultCategoryName`.

### Menu bar

Unchanged — the icon plus today's total across all categories. Showing progress
against summed goals was considered and rejected: the icon-only setting exists to
give menu bar width back, and this would quietly spend it again.

## Accessibility

Following the VoiceOver work already in the app:

- Each category row is a real `Button`, labelled with the category name and
  valued "2 of 4 pomodoros". Progress dots are decorative and hidden.
- A met goal is conveyed in the value, not by colour alone.
- The target pill is a labelled menu ("Session target", value "Work").
- Settings rows label their name field and goal stepper per category.

## Export

CSV gains one column, appended so existing columns keep their positions:

```
timestamp,source,category
2026-07-27T09:12:04Z,manual,Work
2026-07-27T10:03:41Z,timer,AI study
2026-07-27T11:20:00Z,manual,General
```

The value is `record.category ?? fallbackName`, so bucket pomodoros — including
everything logged before this feature existed — read as "General" rather than
blank. Existing quoting rules apply unchanged, which matters because category
names are user-entered and may contain commas.

## Code structure

The feature needs room, so two large files get split as part of the work. No
unrelated refactoring.

| File | Now | Change |
|---|---|---|
| `Model.swift` | 581 lines | Extract `Category.swift`: the type, goal/progress maths, routing and archive rules |
| `RootView.swift` | 469 lines | Move `HistoryTab` and `SettingsTab` to their own files — a pure move of existing structs |
| `CategoryRows.swift` | new | The tappable row list and its empty state |

## Testing

Roughly 30 tests on top of the existing 104:

- **Migration** — an old `data.json` decodes with `category == nil` and lands in
  the bucket; no `schemaVersion` change.
- **Routing** — all five resolution rules, including the archived-default and
  no-categories cases.
- **Session target** — starting "towards Work" credits Work on completion; an
  archived target falls back correctly.
- **Progress** — under, exactly met, overshoot, the dots-to-bar threshold at 8,
  and a goal of 0 rendering a bare count.
- **Archive** — records, totals, and CSV are unchanged; re-adding the same name
  reunites them.
- **Rename** — rewrites its records and orphans nothing.
- **Uniqueness** — collisions between categories, and with the fallback name,
  case-insensitively and with whitespace trimmed.
- **Feature off** — `statusText` and panel content identical to today.
- **Export** — the category column, including a name containing a comma.
- **Accessibility** — row label and value strings, including a met goal.

## Risks

- **Name-keyed records** make renaming a write across history. The rewrite is a
  single pass over an array the app already holds in memory and saves atomically,
  so the failure mode is the existing one: a failed write leaves the previous
  file intact.
- **Panel height** grows with categories. The 200pt scroll cap bounds it, but a
  user with many categories plus a long Settings tab will scroll more than today.
