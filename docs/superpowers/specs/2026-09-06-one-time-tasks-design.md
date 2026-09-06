# One-time tasks on the Focus tab

A one-time task is a category that lives for one day: it has a name and a
pomodoro goal, takes the session target and today's counts like any category,
sits above the standing categories in the ranking, and is gone the next day.
It is added from the Focus tab, not from Settings, because it is a decision
about today rather than about how the app is set up.

## Why

Categories are standing commitments — "3 of Deep work every day". A day also
has things that are only true once: a report to write, a bug to close. Today
the only way to give one of those a goal is to create a category, remember to
delete it tomorrow, and accept that a Settings-tab errand stands between you
and Start. The app already has every mechanism a one-day goal needs — goals,
targets, auto-advance, archived names in History. What it lacks is a category
that knows when to leave.

## Scope

In: a `Category` that carries an expiry day; adding one from the Focus tab;
its removal at the next day rollover (and on the next launch if the app was
not running); early removal from the row's count popover; the ranking rule
that keeps tasks above categories; a marker so a task row reads as
temporary; the pure logic and its tests; a changelog entry.

Out:

- Tasks without categories on. A task *is* a category row, and the Focus tab
  shows category rows only when categories are enabled. Turning categories on
  is the prerequisite, as it is for goals.
- Multi-day tasks or a chosen expiry. "Today" is the whole meaning.
- Carrying an unfinished task to tomorrow. It disappears; the user can add it
  again.
- Any change to History or CSV. Both already handle names that no longer
  belong to a live category, and a finished task's records are exactly that.
- Adding a task from the URL scheme or the hotkey.

## Model

`Category` gains one field:

```swift
/// The calendar day this category disappears at the start of, or nil for a
/// standing category. Stored as the start of the day it was added, so
/// "expired" is `Calendar.current.startOfDay(for: now) > expiresOn`.
var expiresOn: Date?
```

Decoding stays synthesized: an optional decodes as `decodeIfPresent`, so an
existing `data.json` loads unchanged with every category standing. A task is
`expiresOn != nil`; there is no separate type and no second array. Everything
that walks `settings.categories` — `resolve`, `todayProgress`,
`realignTarget`, `CategoryAdvance`, `todayGoalTotal`, `categoryTotals`, the
editor, CSV — sees a task as a category and needs no change. That is the whole
reason for this shape over a parallel `oneTimeTasks` list.

`expiresOn` is the day the task was *added*, not the day after: the pure test
is "is today later than that day", which means the task is visible for the
rest of the day it was created on and not a moment of the next, including a
task added at 23:59.

### Pure logic

`TaskExpiry` (new file, `TaskExpiry.swift`) holds the rules that are worth
testing without an `AppModel`:

```swift
enum TaskExpiry {
    /// The categories that survive into `today`: every standing category, and
    /// every task whose day is not yet over. Order preserved.
    static func surviving(_ categories: [Category], today: Date) -> [Category]

    /// Whether a drag from `source` to `destination` keeps every task above
    /// every standing category. Both ends may be tasks or both categories;
    /// crossing the boundary is refused.
    static func moveKeepsTasksOnTop(_ categories: [Category], from: Int, to: Int) -> Bool
}
```

### `AppModel` additions (`AppModel+Categories.swift`)

- `addTask(name:goal:) -> Bool`. Same name rule as `addCategory`
  (`isCategoryNameAvailable`), so a task cannot shadow a category, the
  bucket, or another task. Goal is 1…20; a task with no goal is not a task.
  Inserts at index 0 with `expiresOn = startOfDay(now)`, then aims the target
  at it through `pickTarget(.named(name))` — a freshly added task is an
  unmet category, so the pick leaves `targetPinned` false and the met-goal
  advance still works. Adding the task and aiming at it happen under one
  `suspendSaves()`/`resumeSaves()` pair, so it is one write.
- `expireTasks(now:)`. Replaces `settings.categories` with
  `TaskExpiry.surviving(_:today:)` when that changes anything, and if the
  session target was one of the leavers clears `targetPinned`, exactly as
  `removeCategory` does. Records are untouched: the name stays on them, which
  is how History keeps the task. Called from two places:
  1. `handleDayChange` — every call, not only when `day > lastSeenDay`, and
     before its `realignTarget()`, so a target left pointing at a gone task
     is re-aimed by the existing rule (an unknown target name already
     resolves to the bucket, and the earlier-day `targetAimedOn` stamp
     already restarts the plan at the top of the ranking — which, after the
     sweep, is the first standing category). The sweep is idempotent and
     cheap, and the wake that reports the new day is the one that must find
     the task gone. Launch calls `handleDayChange` right after load, so the
     morning-after case is covered here too.
  2. `load()` in `Store.swift`, after `settings` is assigned, for the models
     that are built without a launch — tests, `--preview`, the reorder
     harness — so none of them ever shows a task from another day.
     `isLoading` is still true there, so the sweep does not trigger a save;
     the next real change writes the swept list.
- `moveCategory(from:to:)` gains a guard on
  `TaskExpiry.moveKeepsTasksOnTop`. A refused move changes nothing, which the
  drag already handles as "ended where it began". `nudgeCategory` inherits
  the guard.
- `removeCategory(id:)` is what "Remove task" calls. Nothing new.

`CategoryProgress` gains `let isTask: Bool`, set from `expiresOn != nil` in
`todayProgress`, and `accessibilityValue` appends ", today only" for a task
so VoiceOver hears what the marker shows.

## Interaction

### Adding

Below the category rows on the Focus tab, a caption-sized `HoverTextButtonStyle`
button reads **"+ Task"** with the tooltip "Add a goal for today only — it
disappears tomorrow". It shows whenever categories are on, including while the
rows are empty (then it is the only thing the empty-list caption offers besides
"Add a category in Settings"). It opens a popover — an alert or
`confirmationDialog` would dismiss the panel — anchored to the button.

The popover is `AddCategoryForm` in a task mode, chosen by a `kind` parameter
(`.category`, the default, or `.task`), rather than a second form: the name
field, the availability check, the "already taken" message, Cancel/Add and the
Synthwave background fix are identical and should not exist twice. Task mode
differs in three places:

- the caption reads "Today's task";
- a `Stepper` for the goal, 1…20, defaulting to 1, labelled "Pomodoros", sits
  between the name field and the buttons;
- Add calls `addTask(name:goal:)`.

The form is presented from `RootView`'s log section with the model passed in
as a parameter, as the popover rule requires.

### The row

A task row is a `CategoryRow` with one addition: a small `sun.max` glyph at
caption size in `palette.textDim` before the name, and the tooltip on the
row says "Today only" after the existing target text. Nothing else about the
row changes — it aims the target on click, its `±` opens the count popover,
dots and bar draw from the goal as today.

### Removing early

`CategoryCountPopover` gains a trailing "Remove task" text button for a task
row only (`progress.isTask`), styled `HoverTextButtonStyle(emphasis:
.destructive)` like the editor's remove control, with the tooltip "Remove —
its pomodoros stay in your history". No confirmation: the editor's confirm
exists because a category is standing configuration; a task is today's
scratch note, and a mis-click costs a two-field form. The popover closes on
removal. `CategoryCountPopover` takes an `onRemove: (() -> Void)?` closure —
nil for categories — because popover content takes closures, not the
environment.

### At the day change

The task rows vanish, the target re-aims by the existing rollover rule, and
nothing announces it: the rows themselves are the announcement, and the
Focus tab is what the user opens next.

### Settings editor

A task appears in the category editor with the same `sun.max` marker and its
tooltip; its name and goal edit as usual, and remove works as usual. A drag
or keyboard nudge that would put a task below a category, or a category above
a task, is refused by `moveCategory` and the row snaps back. Tasks are shown
here rather than hidden because the editor is the one place that lists every
category, and a hidden row that still takes the target would be a mystery.

## Testing

All in `Tests/PomodoroCountTests`, swift-testing, failing first.

`TaskExpiry`:

- a standing category survives any `today`;
- a task added today survives today;
- a task added yesterday is gone today, including one added at 23:59 checked
  at 00:00;
- order is preserved; the surviving list is the input when nothing expires;
- `moveKeepsTasksOnTop` allows task↔task and category↔category, refuses
  either crossing, and allows any move when the list holds only one kind.

`AppModel` (with a scratch store):

- `addTask` inserts at index 0 with today's `expiresOn`, aims the target at
  it unpinned, refuses a taken name and a goal of 0, and saves once;
- `expireTasks` removes yesterday's task, keeps today's, leaves records
  alone, and clears `targetPinned` when the pinned target leaves;
- `handleDayChange` on a new day drops the task and re-aims the target at
  the first standing category with a goal left;
- a fresh `AppModel` loading a store with an expired task starts without it;
- `moveCategory` refuses a boundary crossing and leaves the array unchanged;
- `categoryTotals` still lists a removed task's name with its count;
- `todayProgress` marks a task `isTask` and its `accessibilityValue` says
  "today only";
- `Settings` decoding of a file without `expiresOn` yields standing
  categories.

Rendering: `--preview` against a seeded store holding two tasks and two
categories, to check the marker, the "+ Task" button and the panel height.
Drag verification stays manual, per the harness rule.

## Changelog

Under `[Unreleased] / Added`: "**One-time tasks.** Give today a goal that
isn't a category: "+ Task" on the Focus tab adds a named target with a
pomodoro count that sits above your categories and disappears tomorrow. Its
pomodoros stay in History under the task's name."
