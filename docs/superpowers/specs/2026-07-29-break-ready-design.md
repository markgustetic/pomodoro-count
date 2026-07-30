# The armed break

When a focus session completes and auto-start break is off, the Focus tab
offers the break instead of falling back to idle: the countdown previews the
configured break length and the primary button becomes **Start break**.

## Why

`complete()` ends the focus path with `phase = .idle` when
`settings.autoStartBreak` is off. That drops the panel back to its cold state —
the big number re-previews the *focus* length, the primary button says "Start
focus", the stop button greys out — and the only route to a break is the small
cup icon in the button row, which reads as an escape hatch rather than the
obvious next step.

So the toggle has two meanings today: on means "take a break automatically",
off means "nothing happens". The break length the user configured in Settings
is never shown anywhere until a break is already running. This gives "off" a
real behaviour: the break is armed and waiting, at the length it will actually
run for.

## Scope

In: a fourth phase representing a completed focus session with its break not yet
started, reached only when `autoStartBreak` is off; its presentation in the
Focus tab and the menu bar; the route back to focus.

Out:

- Changing what `autoStartBreak == true` does. That path is untouched, and a
  test pins it.
- A "starting in 3…" self-starting countdown. It needs a second timer, a cancel
  path, and a new setting to explain itself; the toggle already expresses the
  choice.
- Auto-opening the panel when a break arms. The app is deliberately quiet — a
  sound and a notification are what a completed session gets today.
- Persisting the armed state across relaunch. See Architecture.

## Interaction

A focus session completes. The sound plays and the record is written, both
unchanged, the notification posts with its break-aware wording (below), and the
Focus tab settles into the armed state:

- **Countdown:** the break length, in the break colour. `10:00` for a short
  break, the long-break length when the cycle owes one.
- **Subtitle:** `Break · 10 min`, or `Long break — earned · 15 min`.
- **Badge:** `Break ready`, in the break colour, where `Focus` / `Break` /
  `Paused` appear today.
- **Primary button:** `Start break`, in the break tint. Pressing it starts the
  break exactly as the cup button does today.
- **Stop button:** enabled, and returns to idle. Its tooltip becomes "Skip the
  break".
- **Cup button:** hidden. The primary button already offers the break, and two
  controls doing one thing in one row is worse than one.

The countdown previews from settings, not from a stored value, so editing Break
length in Settings while a break is armed updates the readout live — the same
way the idle state previews focus length.

Nothing about the armed state expires. It ends when the user starts the break,
skips it, or quits.

### Skipping

The stop button is the way out, chosen over a separate "Skip break" text button
because it needs no new control and its existing meaning — "get me out of this
phase" — already fits. What changes is its tooltip: "Abandons the session —
nothing is logged" is false here. The session *was* logged; that is why there is
a break to skip.

Skipping does not spend the long break. `focusSessionsThisCycle` is only reset
by `startBreak()`, when the long break is actually taken, so a skipped long
break stays owed — which is what the comment on `nextBreakIsLong` already
promises for the auto-start-off case.

### Menu bar

Cup glyph, plus today's count — no clock, because nothing is counting. It says
"a break is waiting" from the menu bar without implying a running timer.

The count follows `showsCountInMenuBar` exactly as the idle state does; with it
off, the armed break is a bare cup glyph.

VoiceOver announces `Break ready: 10 minutes` (spoken duration, matching how
`statusDescription` speaks the other phases).

### Notification

With auto-start off the banner is the only thing that reaches a user whose panel
is closed, so it names the break:

> **Pomodoro complete** — That's 4 today — break's ready when you are.

The auto-start-on path keeps today's "Nice — that's 4 today."

## Architecture

`Phase` gains a fourth case, `.breakReady`.

The alternatives were a `breakArmed` boolean alongside `phase == .idle`, and
reusing `.breakTime` in its paused state. Both were rejected, and for reasons
worth recording:

- **A boolean** produces a smaller diff precisely because the compiler stays
  quiet. Every existing `phase == .idle` test — the focus-length preview, the
  count in the menu bar, `primaryTitle`, the disabled stop button — would keep
  answering as though nothing had happened, and each would have to be found by
  hand. A new case makes the exhaustive switches fail until every render site
  has decided what it shows.
- **A paused `.breakTime`** is nearly free and lands the break length in
  `clock.remaining` without any new code, but it misrepresents the state in
  three places: the menu bar draws the pause glyph, the subtitle reads "Paused",
  and — the real defect — `startBreak()` zeroes `focusSessionsThisCycle` when it
  is called, so arming a long break this way and then skipping it would silently
  cancel a long break the user had earned.

`.breakReady` is in-memory, like `focusSessionsThisCycle` and for the same
reason: a relaunch lands in `.idle`. An armed break restored hours later,
counting a rest the user has long since taken or not taken, would be worse than
a clean slate.

### Sites that change

`Model.swift`:

- `complete()` — the focus path's `else` branch sets `.breakReady` instead of
  `.idle`. The record append and the sound stay ahead of it, unchanged; the
  notification body becomes conditional on which branch is about to be taken.
- `toggle()` — a `.breakReady → startBreak()` branch **before** the `resume()`
  fallback. There is no countdown to resume, and `resume()`'s guard
  (`phase != .idle`) would otherwise let it through into `beginCountdown()` with
  a stale `remaining`.
- `displayRemaining` — `.breakReady` returns `armedBreakMinutes * 60`, computed
  from settings so the preview tracks Settings edits.
- `armedBreakMinutes` — new derived property: `nextBreakIsLong ?
  settings.longBreakMinutes : settings.breakMinutes`. `startBreak()` makes the
  same decision inline today; both read it from here so the previewed length and
  the length that runs cannot diverge.
- `primaryTitle` — `.breakReady → "Start break"`.
- `statusText` — `.breakReady` behaves like `.idle`: the count, subject to
  `showsCountInMenuBar`.
- `statusDescription` — `.breakReady → "Break ready: <spoken duration>"`.
- `reset()` — no change needed; it already sets `.idle`.

`RootView.swift`: `phaseColor` and `timerTint` take the break colour and break
tint; `statusBadge` gains the `Break ready` case; `phaseSubtitle` gains the two
break-length strings; `primaryHelp` gains "Start your 10-minute break" (long
where earned), matching how the idle case already names the focus length. The cup
button's condition becomes "idle or work" rather than "not breakTime", and the
stop button's `.help` string becomes phase-dependent — "Skip the break" while
armed, its current wording otherwise.

`StatusIcon.swift`: `drawIcon` opens with

```swift
if !running && phase != .idle { pause glyph }
```

which would catch `.breakReady` — not running, not idle — and draw a pause. That
guard must exclude `.breakReady` explicitly, and the exclusion carries a comment
saying why, because the condition reads as though it were about pausing.

`AppModel+Categories.swift`'s `sessionRunning` (`phase == .work && isRunning`) is
already correct for the new phase: an armed break outlines no category row.

`handleScreenLocked()` guards on `isRunning` and so is a no-op while armed,
which is right — there is nothing to pause.

### Extracted for test

Three decisions move out of places that cannot be asserted, following the same
shape as `Reorder.destination` and `HeatmapLayout.cells`:

- `StatusIcon.glyph(phase:running:) -> Glyph` (`.tomato`, `.cup`, `.pause`),
  lifted out of `drawIcon`, which then switches on it to draw. The drawn image
  is not assertable; the decision behind it is.
- `AppModel.offersManualBreak: Bool` and `AppModel.resetHelp: String` — the cup
  button's visibility and the stop button's tooltip, which are otherwise buried
  in view-body conditionals.
- `AppModel.completionBody(count:breakArmed:)` — the banner's wording. `notify`
  returns early unless the app is bundled, so nothing posts under test.

`phaseSubtitle` and `primaryHelp` stay in `RootView` as `private` computed
properties, where the existing per-phase strings already live. They are checked
by eye in the preview render rather than by assertion; moving the whole family
onto the model to test two new strings would be a larger change than this
feature earns.

## Testing

New `Tests/PomodoroCountTests/BreakReadyTests.swift` (swift-testing):

- Completing a focus session with `autoStartBreak == false` lands in
  `.breakReady`.
- Completing one with `autoStartBreak == true` still lands in `.breakTime` and
  running — the regression guard on the untouched path.
- The record is appended in both cases; arming is not a substitute for logging.
- `displayRemaining` in `.breakReady` is `breakMinutes * 60`, and
  `longBreakMinutes * 60` once the cycle owes the long break.
- Editing `settings.breakMinutes` while armed changes `displayRemaining`.
- `toggle()` from `.breakReady` starts the break: `.breakTime`, running, and
  `currentBreakIsLong` matching what was previewed.
- `reset()` from `.breakReady` returns to `.idle` and leaves `nextBreakIsLong`
  untouched — the skipped long break stays owed.
- `statusText` in `.breakReady` is the count, not `mm:ss`, and is empty when
  `showsCountInMenuBar` is off.
- `statusDescription` in `.breakReady` names the break and its length.
- `StatusIcon.glyph(phase: .breakReady, running: false) == .cup`, alongside the
  existing cases, so the pause-glyph trap stays closed.

`primaryTitle` is asserted in the same suite. `PresentationTests`'
`statusIconRendersForEveryPhase` gains `.breakReady` to its argument list, so
every phase keeps proving it renders.

## Verification

The armed state is otherwise unreachable without sitting through a real focus
session, so `--preview` gains `--armed-break`: it arms a break on the throwaway
preview model before rasterising, alongside the existing `--hover` and
`--theme` overrides. `just preview` then shows the state a reviewer needs to
look at — the break colour, the badge, the subtitle, the button row with the cup
gone.

The armed record it logs shifts the preview's fallback-bucket count by one, in
that mode only. The default `just preview` output is unchanged.

## Documentation

CHANGELOG gets a Changed entry under Unreleased: a completed focus session now
offers the break at its configured length instead of returning to idle, when
auto-start break is off.
