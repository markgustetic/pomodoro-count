# Opt-in screen-lock pausing and a break that ends with the day — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the timer pausing on screen lock unless the user opts in, and make a calendar-day change drop an in-flight break back to idle with the long-break cycle restarted.

**Architecture:** Two independent behaviour changes that both hang off the notification observers in `SystemIntegration.swift`. Part 1 adds a `Settings` flag and guards the existing `handleScreenLocked()` on it, leaving observer registration alone. Part 2 extracts the phase decision into a pure `DayRollover` enum, adds an in-memory `lastSeenDay` stamp to `AppModel` so the reset fires on a real day change rather than on every wake, and routes both notifications plus launch through one `handleDayChange(now:)` entry point.

**Tech Stack:** Swift 5.9+, SwiftPM, SwiftUI + AppKit, swift-testing (`import Testing`, `@Test`, `#expect`) — **not** XCTest. macOS 14+.

## Global Constraints

- Spec of record: `docs/superpowers/specs/2026-08-18-inactivity-and-day-rollover-design.md`. Read it before starting.
- Tests are swift-testing, in `Tests/PomodoroCountTests`. Never XCTest.
- Test-driven: the failing test comes first, and you run it and see it fail before writing implementation.
- New `Settings` fields **must** be decoded in `init(from:)` with `decodeIfPresent(...) ?? default`, or an older `data.json` stops loading. `CodingKeys` is synthesized — do not add one.
- Comments record *why*, in place, and existing comments are not stripped or re-litigated without new evidence.
- Commit subjects are short imperative sentences telling the story; bodies explain the why. End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- User-visible changes get a `CHANGELOG.md` entry under `## [Unreleased]`, Keep a Changelog format, written in the voice of the existing entries (bold lead sentence, then plain prose about what the user sees).
- Commit and push after each task. Do not batch tasks into one commit.
- Full suite: `just test`. Single suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <SuiteName>`.
- `Phase` has four cases — `.idle`, `.work`, `.breakTime`, `.breakReady`. Anything switching on it handles all four.

---

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `Sources/PomodoroCount/Types.swift` | `Settings.pausesOnScreenLock` field + its decode line | 1 |
| `Sources/PomodoroCount/SystemIntegration.swift` | gate in `handleScreenLocked()`; new `handleDayChange(now:)`; `startDayMonitoring()` delegates to it | 1, 4 |
| `Tests/PomodoroCountTests/ScreenLockTests.swift` | restructured around the new setting | 1 |
| `Sources/PomodoroCount/SettingsTab.swift` | the toggle and its caption | 2 |
| `Sources/PomodoroCount/DayRollover.swift` | **new.** Pure: which phases a day change resets | 3 |
| `Tests/PomodoroCountTests/DayRolloverTests.swift` | **new.** Covers the pure decision and the model wiring | 3, 4 |
| `Sources/PomodoroCount/Model.swift` | `lastSeenDay` stamp, `resetForNewDay()` | 4 |
| `Sources/PomodoroCount/PomodoroCountApp.swift` | launch routes through `handleDayChange()` | 4 |
| `CHANGELOG.md` | one Changed entry per part | 1, 4 |

---

### Task 1: Screen-lock pausing moves behind a setting

**Files:**
- Modify: `Sources/PomodoroCount/Types.swift` (add field near `autoStartBreak` ~line 67; add decode line near ~line 118)
- Modify: `Sources/PomodoroCount/SystemIntegration.swift:180-187` (`handleScreenLocked`)
- Modify: `Tests/PomodoroCountTests/ScreenLockTests.swift` (whole file)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Settings.pausesOnScreenLock: Bool` (default `false`), read by Task 2's toggle binding.

- [ ] **Step 1: Rewrite `ScreenLockTests.swift` with the new expectations**

Replace the entire file. The existing four cases keep their bodies but gain the opt-in line; two new cases pin the default.

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// Pausing on screen lock is opt-in, and off by default.
///
/// The app's premise is counting pomodoros finished somewhere else, so a
/// locked Mac is not evidence that focus stopped — pausing there would fight
/// the thing the app is for. The setting stays for people who want the timer
/// to mean time at *this* keyboard: for them a session burning through a lock
/// claims 50 minutes of focus at an empty chair. Either way there is no
/// auto-resume on unlock; only the user knows whether the time away counted,
/// and `pause()` already preserves what is on the clock.
@MainActor
@Suite struct ScreenLockTests {

    // MARK: Default — off

    @Test func lockingDoesNotPauseByDefault() {
        let (m, _) = makeModel()
        #expect(!m.settings.pausesOnScreenLock, "the setting must default to off")
        m.startWork()
        m.handleScreenLocked()
        #expect(m.isRunning, "the session must survive the lock")
        #expect(m.phase == .work)
    }

    @Test func lockingDoesNotPauseARunningBreakByDefault() {
        let (m, _) = makeModel()
        m.startBreak()
        m.handleScreenLocked()
        #expect(m.isRunning)
        #expect(m.phase == .breakTime)
    }

    // MARK: Opted in

    @Test func lockingTheScreenPausesARunningSession() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.startWork()
        let before = m.remaining
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(abs(m.remaining - before) <= 1, "pausing must keep the time on the clock")
    }

    @Test func lockingWhileIdleDoesNothing() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.handleScreenLocked()
        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func lockingAnAlreadyPausedSessionChangesNothing() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.startWork()
        m.pause()
        let before = m.remaining
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .work)
        #expect(abs(m.remaining - before) <= 1)
    }

    @Test func breaksPauseToo() {
        let (m, _) = makeModel()
        m.settings.pausesOnScreenLock = true
        m.startBreak()
        m.handleScreenLocked()
        #expect(!m.isRunning)
        #expect(m.phase == .breakTime)
    }
}
```

- [ ] **Step 2: Run the suite and watch it fail to compile**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ScreenLockTests
```

Expected: a compile error — `value of type 'Settings' has no member 'pausesOnScreenLock'`. That is the failure; do not proceed until you have seen it.

- [ ] **Step 3: Add the setting**

In `Sources/PomodoroCount/Types.swift`, directly after the `autoStartBreak` line in the stored properties:

```swift
    var autoStartBreak = true
    /// Whether a running session pauses when the screen locks or the displays
    /// sleep. Off by default: this app exists to count pomodoros finished
    /// somewhere else, so an unattended Mac is not evidence that focus stopped.
    /// On, the timer means time at this keyboard and a lock stops the clock.
    var pausesOnScreenLock = false
    var soundEnabled = true
```

And in `init(from:)`, directly after the `autoStartBreak` decode line, keeping the column alignment of the block:

```swift
        autoStartBreak        = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? true
        pausesOnScreenLock    = try c.decodeIfPresent(Bool.self, forKey: .pausesOnScreenLock) ?? false
        soundEnabled          = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
```

- [ ] **Step 4: Gate the handler**

In `Sources/PomodoroCount/SystemIntegration.swift`, replace `handleScreenLocked()` and its doc comment:

```swift
    /// Pauses a running session, if the user asked for that.
    ///
    /// Off by default — see `Settings.pausesOnScreenLock`. The guard lives here
    /// rather than in `startScreenLockMonitoring()` so the observers stay
    /// registered whatever the setting says: flipping the toggle then takes
    /// effect on the very next lock, with no teardown, and the "a second call
    /// can never mean a second pause per lock" guard over there is left alone.
    ///
    /// Deliberately no auto-resume on unlock — only the user knows whether the
    /// time away should count, and `pause()` already preserves what's on the
    /// clock.
    func handleScreenLocked() {
        guard settings.pausesOnScreenLock, isRunning else { return }
        pause()
    }
```

- [ ] **Step 5: Run the suite and watch it pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ScreenLockTests
```

Expected: 6 tests, all passing.

- [ ] **Step 6: Run the full suite**

```bash
just test
```

Expected: everything green. A store round-trip test may exist that enumerates settings keys; if one fails, it needs the new key added, not the new key removed.

- [ ] **Step 7: Add the CHANGELOG entry**

Under `## [Unreleased]` in `CHANGELOG.md`, create a `### Changed` section (it does not exist yet under Unreleased) with:

```markdown
### Changed

- **The timer no longer stops when your screen locks.** Locking the Mac or
  letting the displays sleep used to pause a running session. It doesn't
  any more — a pomodoro you're running while away from this keyboard is
  exactly the kind this app is built to count. If you'd rather the timer
  meant time at this Mac, **Pause when the screen locks** in Settings brings
  the old behaviour back.
```

- [ ] **Step 8: Commit and push**

```bash
git add Sources/PomodoroCount/Types.swift Sources/PomodoroCount/SystemIntegration.swift Tests/PomodoroCountTests/ScreenLockTests.swift CHANGELOG.md
git commit -m "Stop pausing on screen lock unless asked to

The app counts pomodoros finished somewhere else, so a locked Mac is not
evidence that focus stopped — pausing there fought the premise. The
behaviour survives as Settings.pausesOnScreenLock, off by default.

The guard sits in handleScreenLocked rather than in the observer
registration, so toggling it takes effect on the next lock and the
double-registration guard in startScreenLockMonitoring is untouched.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push
```

---

### Task 2: The Settings toggle

**Files:**
- Modify: `Sources/PomodoroCount/SettingsTab.swift:56-57`

**Interfaces:**
- Consumes: `Settings.pausesOnScreenLock` from Task 1.
- Produces: nothing later tasks depend on.

There is no unit test here — this is a SwiftUI row, and this codebase tests logic extracted *out* of SwiftUI. Verification is the headless panel render.

- [ ] **Step 1: Add the row**

In `Sources/PomodoroCount/SettingsTab.swift`, replace the two bare toggles at lines 56–57 with:

```swift
                Toggle("Auto-start break after focus", isOn: $model.settings.autoStartBreak)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Pause when the screen locks", isOn: $model.settings.pausesOnScreenLock)
                    if !model.settings.pausesOnScreenLock {
                        // Caption only in the non-default state, as with
                        // `showsCountInMenuBar`: it explains what "off" means
                        // rather than restating the label.
                        Text("The timer keeps running while the Mac is locked or the displays sleep.")
                            .font(.caption2)
                            .foregroundStyle(palette.textDim)
                    }
                }
                Toggle("Sound effects", isOn: $model.settings.soundEnabled)
```

- [ ] **Step 2: Render the panel and look at it**

```bash
just preview
```

Open the PNG the command prints. Confirm: the new toggle sits between **Auto-start break after focus** and **Sound effects**, reads off, and shows the caption underneath. Confirm the Settings tab has not grown past its height cap — `PanelTabScroller` should absorb the extra row; if the tab now clips, say so rather than working around it.

- [ ] **Step 3: Check it in the Synthwave theme too**

```bash
just preview
```

then re-render with the theme override:

```bash
swift run PomodoroCount --preview /tmp/synthwave.png --theme Synthwave
```

Confirm the caption uses the dim text colour and is legible against the Synthwave background — it goes through `palette.textDim`, so it should be, but this is the theme that has caught contrast problems before.

- [ ] **Step 4: Run the full suite**

```bash
just test
```

Expected: green. Nothing here should move a test, but the bundle+preview smoke job in CI covers this file.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/SettingsTab.swift
git commit -m "Offer screen-lock pausing in Settings

Sits with auto-start break — the other toggle that changes what the timer
does rather than how it looks. The caption shows only when the setting is
off, matching the menu bar count row: it explains the non-default state
instead of restating the label.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push
```

---

### Task 3: `DayRollover`, the pure decision

**Files:**
- Create: `Sources/PomodoroCount/DayRollover.swift`
- Create: `Tests/PomodoroCountTests/DayRolloverTests.swift`

**Interfaces:**
- Consumes: `Phase` from `Types.swift` — cases `.idle`, `.work`, `.breakTime`, `.breakReady`.
- Produces: `DayRollover.action(phase: Phase) -> DayRollover.Action`, where `Action` is `enum Action: Equatable { case none, resetToIdle }`. Task 4 calls this.

- [ ] **Step 1: Write the failing test**

Create `Tests/PomodoroCountTests/DayRolloverTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// A break should not outlive the day it was earned in. The decision is
/// extracted from the notification handler so a fifth `Phase` case fails a
/// test here rather than quietly inheriting "do nothing" — the same reason
/// `StatusIcon.glyph` lives outside the drawing routine.
@MainActor
@Suite struct DayRolloverDecisionTests {

    @Test func anArmedBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakReady) == .resetToIdle)
    }

    @Test func aRunningBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakTime) == .resetToIdle)
    }

    @Test func idleIsLeftAlone() {
        #expect(DayRollover.action(phase: .idle) == .none)
    }

    /// A focus session in progress at midnight is real work about to become a
    /// record. Ending it would destroy that.
    @Test func aFocusSessionIsLeftAlone() {
        #expect(DayRollover.action(phase: .work) == .none)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DayRolloverDecisionTests
```

Expected: a compile error — `cannot find 'DayRollover' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PomodoroCount/DayRollover.swift`:

```swift
import Foundation

/// What a calendar-day change should do to the timer.
///
/// A break belongs to the day that earned it: an app left overnight on an
/// armed or running break used to still be on that break in the morning, with
/// the long-break cycle counting yesterday's sessions. A new day starts on
/// focus.
///
/// The `switch` is exhaustive on purpose, following `StatusIcon.glyph`: a
/// fifth `Phase` case has to be given a rule here, rather than inheriting
/// `.none` by default and being noticed months later as a break that outlived
/// its day.
enum DayRollover {
    enum Action: Equatable {
        /// Leave the timer as it is.
        case none
        /// Stop the timer, drop to `.idle`, and restart the long-break cycle.
        case resetToIdle
    }

    static func action(phase: Phase) -> Action {
        switch phase {
        // Armed and running breaks alike: `.breakReady` is a break waiting to
        // be taken, `.breakTime` one under way or paused. Neither should
        // survive the night.
        case .breakReady, .breakTime: return .resetToIdle
        // `.work` even while running — see the focus-session test.
        case .idle, .work:            return .none
        }
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DayRolloverDecisionTests
```

Expected: 4 tests, all passing.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/DayRollover.swift Tests/PomodoroCountTests/DayRolloverTests.swift
git commit -m "Decide what a new day does to the timer, in one pure place

Extracted rather than written inline in the notification handler so the
switch over Phase is exhaustive: a fifth case has to be given a rule here
instead of inheriting 'do nothing' and being found later as a break that
outlived its day.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push
```

---

### Task 4: Wire the rollover into the model

**Files:**
- Modify: `Sources/PomodoroCount/Model.swift` (add `lastSeenDay` beside the observer vars ~line 93-97; add `resetForNewDay()` after `reset()` ~line 375)
- Modify: `Sources/PomodoroCount/SystemIntegration.swift:217-232` (`startDayMonitoring`, plus new `handleDayChange`)
- Modify: `Sources/PomodoroCount/PomodoroCountApp.swift:32` (the launch `realignTarget()` call)
- Modify: `Tests/PomodoroCountTests/DayRolloverTests.swift` (add a second suite)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `DayRollover.action(phase:)` from Task 3; `AppModel.reset()`, `AppModel.realignTarget()`, `AppModel.forceCompleteForTesting()`, `AppModel.focusSessionsThisCycle` (all existing).
- Produces: `AppModel.handleDayChange(now: Date = Date())`, `AppModel.resetForNewDay()`, `AppModel.lastSeenDay: Date`.

- [ ] **Step 1: Write the failing tests**

Append a second suite to `Tests/PomodoroCountTests/DayRolloverTests.swift`:

```swift
/// The wiring: which notification-shaped events actually run the reset.
///
/// `handleDayChange` is called from two notifications, and only one of them
/// means the day changed. `didWakeNotification` fires on every wake — a
/// five-minute lid-close in the middle of a break included — so the reset is
/// gated on a stamp rather than on the call.
@MainActor
@Suite struct DayRolloverWiringTests {

    private func tomorrow() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    }

    @Test func aNewDayClearsAnArmedBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakReady, "precondition: a break is armed")

        m.handleDayChange(now: tomorrow())

        #expect(m.phase == .idle)
        #expect(!m.isRunning)
        #expect(m.remaining == 0)
    }

    @Test func aNewDayClearsARunningBreak() {
        let (m, _) = makeModel()
        m.startBreak()
        #expect(m.phase == .breakTime)

        m.handleDayChange(now: tomorrow())

        #expect(m.phase == .idle)
        #expect(!m.isRunning)
    }

    @Test func aNewDayLeavesARunningFocusSessionAlone() {
        let (m, _) = makeModel()
        m.startWork()

        m.handleDayChange(now: tomorrow())

        #expect(m.phase == .work)
        #expect(m.isRunning, "midnight must not throw away work in progress")
    }

    /// `autoStartBreak` has to be off, or taking the fourth break would zero
    /// the cycle counter itself and this would pass without the new code.
    @Test func aNewDayRestartsTheLongBreakCycle() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        for _ in 0..<4 {
            m.startWork()
            m.forceCompleteForTesting()
        }
        #expect(m.nextBreakIsLong, "precondition: a long break is owed")

        m.handleDayChange(now: tomorrow())

        #expect(!m.nextBreakIsLong)
    }

    /// The wake-from-a-nap case, and the reason the stamp exists at all.
    @Test func wakingLaterTheSameDayLeavesTheBreakRunning() {
        let (m, _) = makeModel()
        m.startBreak()

        m.handleDayChange(now: Date().addingTimeInterval(300))

        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
    }

    /// Pins the behaviour the count already has: it is derived from dated
    /// records, so yesterday's do not show up in today's tally.
    @Test func yesterdaysRecordsDoNotCountToday() {
        let (m, _) = makeModel()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        m.records.append(Record(at: yesterday, source: "manual", category: nil))

        m.handleDayChange()

        #expect(m.todayCount == 0)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DayRolloverWiringTests
```

Expected: a compile error — `value of type 'AppModel' has no member 'handleDayChange'`.

- [ ] **Step 3: Add the stamp and the reset to `Model.swift`**

Beside the other observer-adjacent stored properties (after `var clockChangeObserver: NSObjectProtocol?`), add:

```swift
    /// The calendar day the model last saw, so a day change can be told apart
    /// from a wake. `didWakeNotification` fires on every wake — a five-minute
    /// lid-close in the middle of a break included — and running the rollover
    /// off that unguarded would eat the break.
    ///
    /// In memory, not persisted, matching `focusSessionsThisCycle`: `phase`
    /// isn't persisted either, so a relaunch already lands on `.idle` with a
    /// fresh cycle. This only has to be right for a process that stays up.
    var lastSeenDay = Calendar.current.startOfDay(for: Date())
```

Internal, not `private`, deliberately — `SystemIntegration.swift` is a different file, and `private` is file-scoped in Swift. That matches `dayChangeObserver` and its neighbours, which are internal for the same reason.

Then, directly after `reset()`:

```swift
    /// Starts the day's rhythm over: the timer back to idle and the long-break
    /// cycle back to zero, so a new day doesn't open owing yesterday's long
    /// break.
    ///
    /// Lives here rather than next to `handleDayChange` because
    /// `focusSessionsThisCycle` is `private(set)`, and Swift scopes that to
    /// the file.
    func resetForNewDay() {
        reset()
        focusSessionsThisCycle = 0
    }
```

- [ ] **Step 4: Add `handleDayChange` and route the notifications through it**

In `Sources/PomodoroCount/SystemIntegration.swift`, in the `// MARK: - Daily rollover` extension, add above `startDayMonitoring()`:

```swift
    /// Everything the app does when it notices what day it is: from the two
    /// notifications below, and once at launch.
    ///
    /// Only the phase reset is gated on the day actually advancing.
    /// `realignTarget()` carries its own `targetAimedOn` stamp, and the
    /// repaint is the whole point of the wake notification — it is what makes
    /// a Mac opened after midnight show today's count rather than the one from
    /// before the lid shut.
    ///
    /// `>` rather than `!=` so a system-clock or timezone change that moves
    /// the date backwards doesn't read as a rollover.
    ///
    /// `now` is injectable so tests can advance the day without touching the
    /// system clock.
    func handleDayChange(now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        if day > lastSeenDay {
            lastSeenDay = day
            if DayRollover.action(phase: phase) == .resetToIdle { resetForNewDay() }
        }
        realignTarget()
        objectWillChange.send()
    }
```

and replace the body of the closure in `startDayMonitoring()`, keeping the surrounding registration untouched:

```swift
    /// Today's count is derived from dated records, so it is always 0 at the
    /// start of a new day and older days stay in history. A long-running app,
    /// though, won't recompute on its own — so refresh the UI when the calendar
    /// day changes or the Mac wakes, rolling the visible count back to 0. A new
    /// day also ends a break that outlived it: see `handleDayChange`.
    func startDayMonitoring() {
        guard dayChangeObserver == nil else { return }
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDayChange() }
        }
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)
    }
```

Note the comment about the target following the day moved into `handleDayChange`; do not leave a duplicate behind.

- [ ] **Step 5: Route launch through the same entry point**

In `Sources/PomodoroCount/PomodoroCountApp.swift`, replace the `realignTarget()` line and its comment in `applicationDidFinishLaunching`:

```swift
        // Catch a day that turned over while the app was quit or the lid was
        // shut, which the notification above can only report while running.
        // At launch `lastSeenDay` was just seeded to today, so this can only
        // realign the target and repaint — the same thing the bare
        // `realignTarget()` call did here before.
        AppModel.shared.handleDayChange()
```

- [ ] **Step 6: Run the new suite and watch it pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DayRollover
```

Expected: 10 tests across both suites, all passing.

- [ ] **Step 7: Run the full suite**

```bash
just test
```

Expected: green. Pay attention to any existing target-realignment or day-change test — the behaviour on those paths is unchanged, so a failure there means the refactor moved something it shouldn't have.

- [ ] **Step 8: Add the CHANGELOG entry**

Append to the `### Changed` section under `## [Unreleased]` created in Task 1:

```markdown
- **A new day starts on focus.** Leave the app overnight with a break waiting
  or running and it used to still be on that break in the morning, counting
  yesterday's sessions towards the next long one. When the date changes the
  timer now drops back to a fresh focus session, and the every-fourth-session
  rhythm starts over. A focus session actually running at midnight is left
  alone — it's about to become a record.
```

- [ ] **Step 9: Commit and push**

```bash
git add Sources/PomodoroCount/Model.swift Sources/PomodoroCount/SystemIntegration.swift Sources/PomodoroCount/PomodoroCountApp.swift Tests/PomodoroCountTests/DayRolloverTests.swift CHANGELOG.md
git commit -m "End a break when the day it was earned in ends

An app left overnight on an armed or running break was still on it in the
morning, with the long-break cycle counting yesterday's sessions. A day
change now drops those phases to idle and restarts the cycle. A running
focus session is left alone: it is about to become a record.

The reset is gated on a lastSeenDay stamp, not on the call. Both
notifications land in one handler and didWakeNotification fires on every
wake, so an ungated reset would have eaten the break of anyone who shut
the lid for five minutes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 10: Install the build so the running app matches the commit**

```bash
just install
```

Then open the panel and check by hand: the new Settings toggle is there and off, and a running focus session survives locking the screen (⌃⌘Q, then unlock). The overnight rollover is not hand-checkable in a sitting — the tests are the evidence for that half.

---

## Self-Review

**Spec coverage.** Part 1's setting, decode line, handler gate, Settings row and test restructure map to Tasks 1–2. Part 2's `DayRollover`, `resetForNewDay()`, `lastSeenDay`, `handleDayChange`, the launch consolidation and all seven listed tests map to Tasks 3–4. Both CHANGELOG entries are placed. The spec's "Not in scope" section correctly produces no task — the stale-count regression test it asks for instead is Task 4, Step 1, `yesterdaysRecordsDoNotCountToday`.

**Naming consistency.** `pausesOnScreenLock`, `DayRollover.action(phase:)`, `DayRollover.Action.resetToIdle`, `resetForNewDay()`, `lastSeenDay`, `handleDayChange(now:)` are spelled identically in every task and in the spec.

**One thing to watch during execution.** Task 4 Step 1 uses `Record(at:source:category:)` and `makeModel()`; both exist today (`Types.swift`, `Tests/PomodoroCountTests/TestSupport.swift`). If `Record`'s initialiser has drifted, match the call site in `AppModel.logExternal` rather than inventing a shape.
