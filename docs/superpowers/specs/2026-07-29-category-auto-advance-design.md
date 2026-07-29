# Advancing the session target when a goal is met

When a category reaches its daily goal, the session target moves on by itself to
the next category that still has an unmet goal. The `towards …` pill in the Focus
tab updates the moment it happens.

## Why

Goals describe a plan for the day, but the target that decides where a pomodoro
lands is a manual pick that never moves. So the common shape of a day is: set
four goals, meet the first one, then keep filing pomodoros into the finished
category until you notice and re-pick. The plan is already written down; the app
should follow it.

## Scope

In: the session target advances when the current target's goal becomes met, from
any logging path.

Out:

- **Re-checking at Start.** Advancing on met is what makes a deliberate re-pick
  of a finished category stick — see Interaction.
- **Walking the target back on `undoLast()`.** Undo can drop a category below its
  goal after the target has already moved on. Reversing the advance means
  guessing whether the undo was a mis-tap on this category or on the previous
  one, and it can only ever be a guess.
- **Announcing the advance in a notification.** The pill is the feedback, and
  `complete()`'s banner already carries the day's count. "Work done — next up
  Music" is a fair follow-up, not part of this.
- **Snapping back at midnight.** Counts reset, so nothing is met and the target
  simply stays where it drifted to. There is no notion of a primary category to
  return to, and inventing one is a separate design.
- **Reordering, or any change to what "next" means beyond display order.**

## Interaction

The `towards …` pill changes under you. That is the whole visible surface of the
feature, and the reason the trigger is "the moment the goal is met" rather than
"when Start is pressed":

- Meet Work's goal of 4 and the pill reads `towards Music` immediately, before
  you go anywhere near the Start button. What it says is what the next session
  will credit — the pill can never name a finished category while Start would
  file somewhere else.
- Nothing re-checks at Start, so picking Work again by hand **sticks**. A
  deliberate overshoot works, which matches the row's own tooltip: "goal met —
  one more still counts".

The trigger fires from every path that appends a record — `complete()` for the
built-in timer, and `logExternal()` for the log button, the global hotkey and
`pomodorocount://log`. External logging is this app's headline feature and is the
usual way a goal actually gets met; hooking only the timer would miss the common
case.

## The rule

**The current target must itself be met**, or nothing happens. A goal met by some
*other* category is not this feature's business — only the target being finished
is.

Given that, `goal > 0 && done < goal` is what makes a candidate **available**.
Search order is display order in `settings.categories` and then the bucket,
**wrapping** — a met category at the end of the list looks back at unfinished ones
above it. The search starts at the position after the current target and takes the
first available category it meets. The current target always has a position to
start from: the `sessionTarget` getter resolves an archived name to `.fallback`,
so the target is always one of the rows `todayProgress` returns.

Goal-0 categories are **not** available, which is the one part of the rule worth
stating on its own. Goal-0 means "tracked without a target" and `isMet` is false
for it forever, so a goal-0 category could never be *left* once the rotation
landed on it — it would be a sink, not a stop. The bucket joins the rotation on
the same terms: only when `fallbackGoal > 0`.

Two cases produce no movement at all:

- **Categories off.** `todayGoalTotal` already establishes that goals are
  invisible then and must not drive anything; this follows that rule.
- **Nothing available.** Every remaining category is met or carries no goal, so
  the target stays put and further pomodoros overshoot where they are.

## Architecture

**`CategoryAdvance.next(after:in:)`** — a pure function, new file
`Sources/PomodoroCount/CategoryAdvance.swift`. Takes the current
`CategoryTarget` and a `[CategoryProgress]`, returns the next `CategoryTarget`,
or `nil` for "stay put". `CategoryProgress` already carries `done`, `goal`,
`isMet` and `isFallback` per row, and `todayProgress` already builds the list in
display order with the bucket appended — so the rule needs no new data and no
second pass over the records. Mapping back out is `.fallback` for the row with
`isFallback`, `.named(name)` otherwise.

This is where the tests go, per the convention that tested logic is extracted
from SwiftUI: the function is total over its inputs, so wrapping, the no-movement
cases and goal-0 skipping are all unit-testable without a timer or a view.

**`AppModel.advanceTargetIfMet()`** — a thin wrapper in
`AppModel+Categories.swift`: bail when `!settings.categoriesEnabled`, read
`todayProgress`, and assign `sessionTarget` when the function returns a target.

**Call sites** — `complete()` (in the `finished == .work` branch, after the
record is appended) and `logExternal()`. `complete()` appends a record and then
writes `settings.sessionTargetName`, which is two saves through the two `didSet`
hooks; both call sites bracket the pair in `suspendSaves()`/`resumeSaves()` so a
completed session costs one store write, with the resume on the cancelled path
too.

**`Settings.autoAdvanceTarget`** — new `Bool`, default `true`, decoded with
`decodeIfPresent(...) ?? true` alongside the other category fields so a
`data.json` from 1.1.0 still loads.

## Settings

A toggle, "Move to the next unfinished category", inside the existing
`categoriesEnabled` block in `SettingsTab.swift` — below "Add category" and above
the "Everything else" divider, since it concerns the user's categories rather
than the bucket. It carries a `.help` explaining that a finished category hands
off to the next one with a goal left.

Default on. It changes where records land, which argues for opt-in, but it can
only ever fire once you have set goals, and the pill shows it happening. The
alternative — default off — makes the feature invisible on install.

## Testing

New suite `Tests/PomodoroCountTests/CategoryAdvanceTests.swift` over the pure
function: advance to the next unmet category; wrap from the last category to an
unfinished earlier one; skip goal-0 categories; advance into the bucket when
`fallbackGoal > 0`; skip the bucket when it is 0; stay put when nothing is
available; stay put when the current target is not met.

Model-level tests join `CategorySessionTests`: a completed session that meets the
goal moves the target and files its own record to the *old* target (the record is
appended before the advance); an external log that meets the goal moves it too; a
manual re-pick of a met category survives the next completion; nothing moves
while `categoriesEnabled` is false; nothing moves while `autoAdvanceTarget` is
false.

`CHANGELOG.md` gets an Added entry — the pill changing on its own is user-visible,
and `just release` refuses to tag without one.
