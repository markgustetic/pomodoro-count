# The category list as a priority ranking

The order of the categories is the order you work through them. The session
target falls to the highest-ranked category that still has a goal left, restarts
at the top each day, and holds still when you deliberately point it at a
category you have already finished.

## Why

`CategoryAdvance.next(after:in:)` treats the list as a **rotation**: when the
target's goal is met it searches forward from that target, wrapping, and takes
the first category with an unmet goal. That answers "what's next around the
ring", which is not the question a list of goals actually poses. A list written
in priority order poses "what's the most important thing left", and the two
answers differ whenever the target sits below an unfinished category — ranking
`Work, Music, Admin`, finish Music, and the rotation sends you to Admin while
Work is still short.

The 2026-07-29 design parked this deliberately. Two of its **Out** bullets are
superseded here:

- *"Snapping back at midnight … There is no notion of a primary category to
  return to, and inventing one is a separate design."* This is that design: the
  top of the ranking is the primary category.
- *"Reordering, or any change to what 'next' means beyond display order."*
  Display order still decides, but it now means rank rather than ring position.

Nothing else in that spec changes. Undo still doesn't walk the target back, the
advance still isn't announced in a notification, and Start still doesn't
re-check.

## Scope

In: the successor rule, a start-of-day reset, and a pin that lets a deliberate
overshoot run for as long as the user wants.

Out:

- **Re-aiming when the ranking changes.** Dragging a category to the top, or
  adding one there, does not move the target until the next trigger fires. A
  live-derived target would have to be frozen at Start so a mid-session reorder
  couldn't change where the finishing record lands, and that is a larger change
  than this earns.
- **Re-checking at Start.** Unchanged from the previous design, and now doing
  double duty: it is part of what lets a pin hold.
- **A per-category "priority" field.** Rank is array order in
  `settings.categories`. A second source of truth for the same thing is how the
  two could ever disagree.
- **Walking the pin back on `undoLast()`.**

## The rule

A row is **available** when `goal > 0` and it is not met — unchanged. Goal-0
means "tracked without a target" and can never be met, so it would be a sink
rather than a stop. The bucket ranks last, and joins on the same terms: only
when `fallbackGoal > 0`.

`rows` is `AppModel.todayProgress` — every category in display order, then the
bucket. Display order *is* the ranking; there is no second ordering anywhere.

Three triggers move the target, and nothing else:

| Trigger | Effect |
|---|---|
| A record lands and the current target is now met | Re-aim at the highest-ranked available row |
| The app notices the calendar day turned over | Clear the pin, re-aim at the highest-ranked available row, stamp today |
| The user picks from the pill menu | Aim there, and **pin only if that category is already met** |

### The pin, and why picking reads two ways

A **pin** suppresses the met-goal trigger entirely, which is what lets a
deliberate overshoot run for as long as the user wants rather than for exactly
one pomodoro. It is released by the day turning over, by *Follow the order*, and
by archiving the pinned category; picking a different category re-evaluates it
rather than carrying it over.

Whether a hand pick pins depends on the state of what was picked, because the
two cases are genuinely different intents:

- **Picking a category with a goal left** means "work here next". It does not
  pin. The target holds while the category is unfinished — the met-goal trigger
  only fires on a met target — and the ranking resumes on its own once the goal
  is reached. Nothing to switch back on, because nothing was switched off.
- **Picking a category that is already met** can only mean "let me overshoot
  here". It pins, and holds through as many pomodoros as follow.

The alternative — pinning on every hand pick — was rejected. It gives the same
overshoot, but one pick at 11am then leaves the ranking switched off for the rest
of the day, and only the user can switch it back on. That is the papercut the
2026-07-29 design was written to remove, reintroduced behind a single click. The
cost of this rule instead is that two picks which look identical behave
differently; the pill's two labels are what make the difference visible.

A **goal-0 category needs no special case**. `isMet` is false for it forever, so
picking one never pins — and the met-goal trigger can never fire on it either,
so it holds anyway. The same is true of the bucket while `fallbackGoal == 0`.

Raising a pinned category's goal after the fact leaves it pinned but unmet. The
pin stands: it was set deliberately, and the trigger it suppresses would not fire
on an unmet target regardless.

The **daily snap** stamps the day even when there is nothing to aim at (no
category carries a goal). It is a start-of-day event, not a lazy one: adding a
goal later the same day does not retroactively trigger it.

A **running focus session is never re-aimed** — the same
`phase == .work && isRunning` guard, for the same reason. Start already chose
the destination and the record that finishes the session has to honour it.
Skipping is not a lost snap: the day stamp stays stale, and `complete()` clears
`isRunning` before it appends and re-evaluates.

`autoAdvanceTarget` gates the two **automatic** triggers. Someone who turns it
off wants a target that never moves on its own, and a midnight re-aim violates
that exactly as much as a met-goal one does. It does not gate a hand pick —
nothing should stop the user aiming the target — but with the rule off there is
no automatic behaviour for a pin to hold out against, so the pinned state stops
being a distinction worth showing: the pill reads `towards …` and the menu drops
its *Follow the order* entry. `targetPinned` is still recorded, so turning the
rule back on restores whatever the pill was already promising.

## Interaction

The `towards …` pill is the whole visible surface.

- Meet Music's goal and the pill reads `towards Work` immediately — up the
  ranking, not down. What it says is what the next session credits, on every
  logging path.
- Pick an unfinished category by hand and the pill still reads `towards Admin`,
  which is the truth: the rule is driving and will move on when Admin is done.
- Pick a category that is already met and it reads `pinned to Admin`. The two
  labels are the whole visible difference between the two kinds of pick, which
  is why they are worded as different promises rather than as a decoration.
- The menu gains a first entry, **Follow the order**, above a divider. It clears
  the pin and aims at `topUnmet` straight away, so the pinned state always has a
  visible way out. Note that it does *not* go through the met-goal trigger,
  whose guard requires the current target to be met — handing control back has
  to work from an unfinished target too.
- Text-only, both states. `RootView` documents that `.menuStyle(.borderlessButton)`
  draws the label through `NSPopUpButton`, which drops arbitrary `Shape` content
  and paints an `Image` in the control's own colour ignoring `foregroundStyle` —
  so a dot or a lock icon can only ever be a black bullet matching neither
  palette. The words carry the meaning.
- `.help` and `.accessibilityValue` read the same description, so the pinned
  state is not sighted-only.

Lowering a goal in Settings can still leave the pill naming an already-met
category, since that changes no records; the next log corrects it. Unchanged.

## Architecture

**`CategoryAdvance`** keeps its shape — pure, total, unit-tested, the only
caller being the model — and loses the wrap arithmetic. Searching from the top
cannot hand a met target back to itself, so the modulo and the deliberately
short range both go.

```swift
/// The highest-ranked row with a goal left. nil when the day's plan is done.
static func topUnmet(in rows: [CategoryProgress]) -> CategoryTarget?

/// The target to move to, or nil to stay put.
static func next(after current: CategoryTarget,
                 in rows: [CategoryProgress],
                 pinned: Bool) -> CategoryTarget?
```

`next` returns nil when `pinned`, keeps the guard that `current` must itself be
met, and otherwise returns `topUnmet`.

**Two new `Settings` fields**, decoded `decodeIfPresent ?? default` so older
files still load:

- `targetPinned = false`
- `targetAimedOn: Date?` — the day the target was last aimed

`targetAimedOn` is what makes the daily snap survive a quit or a long sleep:
`NSCalendarDayChanged` only fires while the app runs, so an event-driven snap
would be missed by anyone who closes their laptop. A stamp is checked whenever
the app looks, however it finds out the day turned over.

`autoAdvanceTarget` **keeps its name and JSON key** despite its widened meaning.
Decoding is field-by-field with defaults, so a rename would read the missing key
as `true` and silently un-opt-out everyone who had turned it off.

**`advanceTargetIfMet()` becomes `realignTarget()`** — one entry point holding
both automatic triggers, since they share the enabled checks and the
running-session guard. The daily branch is checked first and returns: at the
start of a day nothing is met, so falling through to the met-goal rule could
only ever be a no-op, and returning says so rather than leaving a reader to
work it out.

Call sites: `complete()` and `logExternal()` as before, plus app startup beside
`startDayMonitoring()`, plus the day-change/wake `refresh` closure in
`SystemIntegration`, which today only sends `objectWillChange`.

**Writes go through one `settings` assignment.** Pinning touches two fields and
the daily snap three; each mutation of `settings` is its own `didSet` → save.
These use the local-copy pattern the rename path already uses rather than adding
`suspendSaves()`/`resumeSaves()` call sites — `Store.swift`'s comment enumerates
the existing three by name and explains why each needs its own resume, and that
comment should stay true.

**`AppModel.pickTarget(_:)`** is the hand-pick path, and the one place the
"which kind of pick was that" question is answered:

```swift
/// Aims the target where the user asked. Pins only when that category is
/// already met — the one reading of such a pick is "let me overshoot here",
/// where picking an unfinished category just says "work here next" and should
/// hand back to the ranking once it is finished.
func pickTarget(_ target: CategoryTarget)
```

Assigning `sessionTarget` directly stays unpinned, which keeps "the rule put it
here" as the default and means the existing tests that assign it need no
rewriting to keep meaning what they meant.

**View changes are thin.** The pill menu routes its category buttons through
`pickTarget(_:)` instead of assigning `sessionTarget`, and reads its label from a
new `sessionTargetDescription`. The Settings toggle keeps its binding and gets
new copy:

> **Follow the category order**
> The top category with a goal left is the target, and each new day starts at
> the top again. Pick one by hand to work there next; pick a finished one to
> keep going past its goal.

**Archiving the pinned category clears the pin.** The `sessionTarget` getter
resolves an archived name to `.fallback`, so a surviving pin would silently pin
the bucket.

## What changes for someone already using this

1. Meeting a goal re-aims at the top unfinished category, not the next one down.
2. Re-picking a finished category holds there for as many pomodoros as follow.
   Today it yields exactly one overshoot and then moves on.
3. A new day re-aims at the top.
4. The pill reads `pinned to X` while overshooting, and its menu has a new first
   entry.

Picking an *unfinished* category behaves exactly as it does today — it holds
until the goal is met, then hands back — so the only hand pick whose behaviour
changes is the one aimed at a category that is already done.

The first launch after this ships re-aims once: existing stores carry no
`targetAimedOn`, so the first evaluation reads as "the day turned over". That is
a consequence of the defaults rather than a migration, and it is the feature's
premise anyway.

## Testing

Pure, on `CategoryAdvance`:

- `topUnmet` takes the first row with a goal left; skips goal-0 rows; skips met
  rows; returns the bucket only when `fallbackGoal > 0`; nil when all met.
- `next` jumps **up** the list: ranking `A, B, C`, `A` and `C` unfinished,
  current `B` met → `A`. This one case pins the whole change; the rotation
  answers `C`.
- `next` returns nil when pinned, nil when `current` is unmet, nil when nothing
  is available.

Model-level, in `Tests/PomodoroCountTests` with swift-testing:

- `pickTarget` on a **met** category pins; on an **unfinished** one it does not.
  This pair is the rule, so it is the pair to write first.
- A pinned target survives **repeated** overshoot logs — not just one. This
  rewrites `aDeliberateRePickIsHonouredForTheNextSession`, which asserts today's
  one-pomodoro limit; rewritten rather than deleted, since it is the record of a
  behaviour being changed on purpose.
- An unfinished hand pick still hands back to the ranking once its own goal is
  met, and hands back to the **top**, not to the row below it.
- `pickTarget` on a goal-0 category does not pin and is never advanced away
  from — the two halves of "no special case needed".
- A stale `targetAimedOn` clears the pin and re-aims; a same-day stamp does
  neither.
- Both triggers defer while a focus session runs, and the deferred snap lands
  when `complete()` runs.
- `autoAdvanceTarget == false` freezes both automatic triggers, and a hand pick
  still works while it is off.
- *Follow the order* clears the pin and re-aims immediately, including from an
  unfinished target.
- Archiving the pinned category clears the pin.
- Persistence: both fields round-trip, and a `data.json` without them loads with
  `targetPinned == false` and `targetAimedOn == nil`.

No UI automation. The pill's two label states are visible in `--preview` if
worth an eye, but nothing here needs the `--reorder-window` harness.

## Docs

- `CHANGELOG.md` under Changed: the four items in "What changes for someone
  already using this".
- `AGENTS.md`: the model section names `advanceTargetIfMet()`, and the
  conventions section lists `CategoryAdvance.next(after:in:)` among the pure
  extracted functions. Both signatures change.
- This spec notes above which bullets of the 2026-07-29 design it supersedes, so
  the two do not read as contradicting each other.
