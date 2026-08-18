# Screen-lock pausing becomes opt-in; a new day clears an in-flight break

Two independent behaviour changes to the timer, specified together because
they both touch the notification observers in `SystemIntegration.swift`.

## Part 1 — Pause on screen lock becomes an opt-in setting

### Today

`handleScreenLocked()` pauses any running session when the screen locks or the
displays sleep. It is unconditional, and there is no way to turn it off. The
rationale in the source is that a timer burning while the Mac is locked claims
focus that did not happen.

### Change

That rationale still holds for some people, so the behaviour stays available —
but it stops being the default. Pomodoros here are frequently counted against
work happening away from this Mac, which is the whole premise of the app, so a
locked screen is not evidence that focus stopped.

### Design

**Setting.** `Settings.pausesOnScreenLock`, defaulting to `false`.

Decoded field-by-field with a default, as every other field is, so an older
`data.json` missing the key still loads:

```swift
pausesOnScreenLock = try c.decodeIfPresent(Bool.self, forKey: .pausesOnScreenLock) ?? false
```

**Gate.** The guard goes in the handler, not the registration:

```swift
func handleScreenLocked() {
    guard settings.pausesOnScreenLock, isRunning else { return }
    pause()
}
```

`startScreenLockMonitoring()` is untouched: the observers stay registered
whatever the setting says. Gating the handler means flipping the toggle takes
effect on the very next lock with no observer teardown, and the existing
"guarded so a second call cannot mean a second pause per lock" property of
`startScreenLockMonitoring()` is not disturbed.

**UI.** One row in `SettingsTab`, next to `Auto-start break after focus` —
the other toggle that changes what the timer does rather than how it looks:

```swift
VStack(alignment: .leading, spacing: 2) {
    Toggle("Pause when the screen locks", isOn: $model.settings.pausesOnScreenLock)
    if !model.settings.pausesOnScreenLock {
        Text("The timer keeps running while the Mac is locked or the displays sleep.")
            .font(.caption2)
            .foregroundStyle(palette.textDim)
    }
}
```

The caption follows the `showsCountInMenuBar` pattern: shown only in the
non-default state, where it explains what that state means.

### Tests

`ScreenLockTests` currently asserts pausing as unconditional truth, including
in its suite doc comment. It is restructured:

- The four existing cases move under `m.settings.pausesOnScreenLock = true`.
- New: with the setting at its default, a running focus session survives a
  lock — `isRunning` stays true and `remaining` keeps falling.
- New: with the setting at its default, a running break survives a lock.
- The suite doc comment is rewritten to state the new policy: off by default
  because the app counts focus that happens away from this Mac; on for people
  who want the timer to reflect time at this keyboard only.

### Compatibility

This is a visible behaviour change for existing installs, which inherit the
new `false` default rather than keeping what they had. That is deliberate and
gets a CHANGELOG entry under Changed, naming the setting that restores it.

## Part 2 — A new day clears an in-flight break

### Today

`startDayMonitoring()` observes `NSCalendarDayChanged` and
`NSWorkspace.didWakeNotification`, and on either one calls `realignTarget()`
and `objectWillChange.send()`. The timer's phase is not consulted, so an app
left overnight on a break — armed, running or paused — is still on that break
in the morning.

### Change

When the calendar day advances, a break phase drops back to idle and the
long-break cycle counter starts over. A new day starts on focus.

### Design

**Pure decision.** New file `Sources/PomodoroCount/DayRollover.swift`:

```swift
/// What a calendar-day change should do to the timer.
///
/// Extracted and exhaustive on purpose, following `StatusIcon.glyph`: a fifth
/// `Phase` case fails to compile here rather than silently inheriting `.none`
/// and being noticed months later as a break that outlived its day.
enum DayRollover {
    enum Action: Equatable { case none, resetToIdle }

    static func action(phase: Phase) -> Action {
        switch phase {
        case .breakReady, .breakTime: return .resetToIdle
        case .idle, .work:            return .none
        }
    }
}
```

Both break cases count. `.breakReady` is an armed break waiting to be taken;
`.breakTime` is one running or paused. Neither should survive the night.

`.work` is deliberately left alone even when running. A focus session in
progress at midnight is real work, and ending it would destroy the record it
was about to produce.

**Action.** `AppModel.resetForNewDay()`, which must live in `Model.swift`
because `focusSessionsThisCycle` is `private(set)` and Swift scopes that to
the file:

```swift
/// Starts the day's rhythm over: the timer back to idle, and the long-break
/// cycle back to zero so a new day does not open owing yesterday's long break.
func resetForNewDay() {
    reset()
    focusSessionsThisCycle = 0
}
```

`reset()` already stops the timer, clears `isRunning`, sets `phase = .idle`
and zeroes the countdown, so this adds only the cycle counter.

The cycle counter resets only on the break path — i.e. only when
`DayRollover.action` says `.resetToIdle`. Resetting it on every rollover would
be defensible ("the rhythm is per-day"), but it would quietly shorten the
break owed to a focus session that happened to be running at midnight, which
is a worse surprise than the inconsistency it removes.

**Trigger, and why the stamp is required.** The refresh closure in
`startDayMonitoring()` fires on two notifications, and only one of them means
the day changed. `didWakeNotification` fires on every wake, including a
five-minute lid-close in the middle of a break. Running the reset off that
closure unguarded would eat that break.

So `AppModel` gains an in-memory `lastSeenDay`, seeded in `init` from
`Calendar.current.startOfDay(for: Date())`, and the day handler becomes:

```swift
func handleDayChange(now: Date = Date()) {
    let day = Calendar.current.startOfDay(for: now)
    if day > lastSeenDay {
        lastSeenDay = day
        if DayRollover.action(phase: phase) == .resetToIdle { resetForNewDay() }
    }
    // Unchanged, and deliberately outside the stamp: `realignTarget()` carries
    // its own `targetAimedOn` day stamp, and the repaint is what makes a wake
    // show today's count rather than the one from before the lid shut.
    realignTarget()
    objectWillChange.send()
}
```

`startDayMonitoring()`'s closure becomes a call to `handleDayChange()`, and
the bare `AppModel.shared.realignTarget()` line in
`applicationDidFinishLaunching` becomes `handleDayChange()` too, so launch
takes the same path as every other way the app notices the date. At launch
`lastSeenDay` was just seeded to today, so the rollover branch cannot fire and
the call does exactly what the `realignTarget()` line did before — this is a
consolidation, not a behaviour change.

`now:` is a parameter with a default so tests can advance the day without
touching the system clock.

`lastSeenDay` is in memory, not persisted, matching `focusSessionsThisCycle`.
`phase` is not persisted either, so a relaunch already lands on `.idle` with a
fresh cycle; the stamp only has to be right for a process that stays up.

`>` rather than `!=`, so a system clock or timezone change that moves the date
backwards does not read as a rollover.

### Tests

New `DayRolloverTests`:

- `DayRollover.action` returns `.resetToIdle` for `.breakReady` and
  `.breakTime`, and `.none` for `.idle` and `.work`.
- A model on an armed break, handed a `now` one day ahead, lands on `.idle`
  with `isRunning` false and `remaining` zero.
- A model on a running break, same, lands on `.idle`.
- A model running a focus session, handed a `now` one day ahead, is still
  running that session — phase `.work`, `isRunning` true.
- With `autoStartBreak` off, four sessions driven to completion via
  `forceCompleteForTesting()` leave `nextBreakIsLong` true and the phase
  `.breakReady`; a day advance then leaves `nextBreakIsLong` false. (The
  setting has to be off, or taking the fourth break would zero the cycle
  counter itself and the test would pass without the new code.)
- A model on a running break, handed a `now` *later the same day*, is still on
  that break. This is the wake-from-a-nap case, and the reason the stamp
  exists.
- Regression on the count: a store holding records dated yesterday, a day
  advance, and `todayCount` reads 0.

### Not in scope

A stale today-count was raised as a possible symptom. The path was checked:
the count is derived from dated records, and both notifications already call
`objectWillChange.send()`, which invalidates `StatusItemLabel` (it observes
the model directly) and the panel. No mechanism was found that leaves it
stale, so no machinery is added for it — the regression test above pins the
behaviour instead. If a reproduction turns up, it is its own investigation.

## Files touched

| File | Change |
| --- | --- |
| `Sources/PomodoroCount/Types.swift` | `pausesOnScreenLock` field + decode line |
| `Sources/PomodoroCount/SettingsTab.swift` | toggle + caption |
| `Sources/PomodoroCount/SystemIntegration.swift` | gate in `handleScreenLocked`; `handleDayChange` replaces the refresh closure body |
| `Sources/PomodoroCount/Model.swift` | `lastSeenDay`, `resetForNewDay()` |
| `Sources/PomodoroCount/DayRollover.swift` | new, pure |
| `Sources/PomodoroCount/PomodoroCountApp.swift` | launch calls `handleDayChange()` |
| `Tests/PomodoroCountTests/ScreenLockTests.swift` | restructured around the setting |
| `Tests/PomodoroCountTests/DayRolloverTests.swift` | new |
| `CHANGELOG.md` | Changed + Added entries |
