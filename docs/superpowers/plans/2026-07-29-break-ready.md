# The armed break — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a focus session completes with "Auto-start break" off, the Focus tab arms the break at its configured length instead of dropping back to idle.

**Architecture:** `Phase` gains a fourth case, `.breakReady`. Swift's exhaustive switches then force every phase-rendering site to decide what it shows. The break length is derived from settings on every read (`armedBreakMinutes`), never stored, so the previewed length and the length that actually runs cannot diverge. Decisions that live in un-assertable places — the menu bar's drawn glyph, two view-body conditionals, a notification body that only posts from a real bundle — are extracted as pure members and tested there.

**Tech Stack:** Swift 5.9+, SwiftUI + AppKit reach-ins, Swift Package Manager, swift-testing (not XCTest), macOS 14+.

**Spec:** `docs/superpowers/specs/2026-07-29-break-ready-design.md`

## Global Constraints

- Tests are **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — never XCTest. New tests go in `Tests/PomodoroCountTests/`.
- Test models are built with `makeModel()` from `TestSupport.swift`, which redirects persistence to a throwaway file and turns sound off. Never construct a bare `AppModel()` in a test — it would read and write the user's real `data.json`.
- Every test suite touching `AppModel` is annotated `@MainActor` (`AppModel` is `@MainActor`-isolated).
- **Comments record WHY and stay.** Every non-obvious line added below carries the comment given in this plan verbatim. Do not strip or paraphrase existing comments.
- Full suite: `just test`. Single suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <SuiteName>`.
- Commit subjects are short imperative sentences; bodies explain why.
- The maintainer's workflow is **commit and push each finished task, then `just install`** so the running app matches the commit. Each task below ends that way.
- `settings.autoStartBreak == true` behaviour must not change. Task 2 adds a test that pins it.

---

### Task 1: Extract the menu bar glyph decision

A pure refactor with no behaviour change, done first so the `.breakReady` case in Task 2 lands on a tested function instead of inside an un-assertable drawing routine.

`drawIcon` currently opens with `if !running && phase != .idle { pause glyph }`. That condition is about *stopped-ness*, not about pausing, which is exactly why a fourth stopped phase would silently inherit a pause glyph. Restructuring it as an exhaustive `switch` per phase makes Task 2's compiler errors land here too.

**Files:**
- Modify: `Sources/PomodoroCount/StatusIcon.swift` (`drawIcon`, lines 64–76)
- Test: `Tests/PomodoroCountTests/PresentationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `StatusIcon.Glyph` — `enum Glyph: Equatable { case tomato, cup, pause }`, and `static func glyph(phase: Phase, running: Bool) -> Glyph`. Both are internal (no `private`), so tests reach them via `@testable import`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/PomodoroCountTests/PresentationTests.swift`, immediately after the `statusIconWidensWithItsText` test (keeping it inside the `// MARK: Menu bar status` section):

```swift
    /// The glyph decision, lifted out of the drawing code so it can be
    /// asserted — an `NSImage` of a tomato and an `NSImage` of a cup are
    /// equally "a non-empty template image". Pinned for all six existing
    /// combinations so a later phase cannot quietly change one.
    @Test func theMenuBarGlyphFollowsThePhase() {
        #expect(StatusIcon.glyph(phase: .idle, running: true) == .tomato)
        #expect(StatusIcon.glyph(phase: .idle, running: false) == .tomato)
        #expect(StatusIcon.glyph(phase: .work, running: true) == .tomato)
        #expect(StatusIcon.glyph(phase: .work, running: false) == .pause)
        #expect(StatusIcon.glyph(phase: .breakTime, running: true) == .cup)
        #expect(StatusIcon.glyph(phase: .breakTime, running: false) == .pause)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PresentationTests
```

Expected: a **compile error**, not a test failure — `type 'StatusIcon' has no member 'glyph'`. In swift-testing a missing symbol fails the build; that is the red state for this step.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/PomodoroCount/StatusIcon.swift`, replace the whole `drawIcon` function:

```swift
    private static func drawIcon(phase: Phase, running: Bool, in rect: NSRect) {
        switch glyph(phase: phase, running: running) {
        case .tomato: drawTomato(in: rect)
        case .cup:    symbol("cup.and.saucer.fill")?.draw(in: rect)
        case .pause:  symbol("pause.fill")?.draw(in: rect)
        }
    }

    enum Glyph: Equatable { case tomato, cup, pause }

    /// Which glyph the menu bar item draws. Extracted from `drawIcon` because
    /// the drawn image is not assertable — one non-empty template image looks
    /// like any other — while the decision behind it is.
    ///
    /// Switched per phase rather than guarded on "stopped and not idle", which
    /// is what this used to be. That guard read as though it were about
    /// pausing, so any new stopped phase would have inherited a pause glyph
    /// without anyone choosing it.
    static func glyph(phase: Phase, running: Bool) -> Glyph {
        switch phase {
        case .idle:      return .tomato
        case .work:      return running ? .tomato : .pause
        case .breakTime: return running ? .cup : .pause
        }
    }
```

Delete the `// Paused: show a pause glyph regardless of phase.` comment along with the guard it described — the new `glyph` doc comment carries that history forward.

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PresentationTests
```

Expected: PASS, including the pre-existing `statusIconRendersForEveryPhase` and `statusIconWidensWithItsText` — they exercise the same drawing path and prove the refactor changed nothing.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all tests pass. This is a no-behaviour-change refactor; any failure means the switch does not reproduce the old guard.

- [ ] **Step 6: Commit and push, then install**

```bash
git add Sources/PomodoroCount/StatusIcon.swift Tests/PomodoroCountTests/PresentationTests.swift
git commit -m "Name the menu bar glyph instead of guarding on stopped-ness

The old condition read as though it were about pausing, so any phase that
is stopped but not idle would have inherited a pause glyph without anyone
choosing it. Switching per phase puts that decision somewhere a test can
reach, and makes the compiler ask about it when a phase is added."
git push
just install
```

---

### Task 2: The `.breakReady` phase

The core of the feature. Adding an enum case breaks compilation at every exhaustive switch over `Phase`, so this task necessarily touches all of them at once — that is the point of choosing an enum case over a boolean.

**Files:**
- Modify: `Sources/PomodoroCount/Types.swift` (`enum Phase`, line 119)
- Modify: `Sources/PomodoroCount/Model.swift` (`displayRemaining` 127, `primaryTitle` 131, `statusText` 191, `statusDescription` 205, `toggle()` 239, `startBreak()` 270, `complete()` 325)
- Modify: `Sources/PomodoroCount/StatusIcon.swift` (`glyph`)
- Modify: `Sources/PomodoroCount/RootView.swift` (`phaseColor` 154, `timerTint` 162, `primaryHelp` 172, `phaseSubtitle` 180, `statusBadge` 105)
- Create: `Tests/PomodoroCountTests/BreakReadyTests.swift`
- Modify: `Tests/PomodoroCountTests/PresentationTests.swift` (`statusIconRendersForEveryPhase` arguments, `theMenuBarGlyphFollowsThePhase`)

**Interfaces:**
- Consumes: `StatusIcon.glyph(phase:running:) -> StatusIcon.Glyph` and `StatusIcon.Glyph` from Task 1.
- Produces:
  - `Phase.breakReady` — fourth case on the existing `enum Phase: Equatable`.
  - `AppModel.armedBreakMinutes: Int` — the length of the break offered right now, long where earned.
  - Existing members gain `.breakReady` behaviour: `displayRemaining: TimeInterval`, `primaryTitle: String`, `statusText: String`, `statusDescription: String`, `toggle()`, `startBreak()`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/BreakReadyTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// A completed focus session with `autoStartBreak` off arms its break instead
/// of returning to idle: the panel previews the break at the length it will
/// actually run for, and waits to be told to start it or skip it.
@MainActor
@Suite struct BreakReadyTests {

    /// The state the whole feature hangs on.
    @Test func completingAFocusSessionArmsTheBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakReady)
        #expect(!m.isRunning)
    }

    /// The untouched path: auto-start still means auto-start. This is the
    /// regression guard on the behaviour every existing user has today.
    @Test func autoStartStillStartsTheBreakItself() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = true
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
    }

    /// Arming a break is not a substitute for logging the session.
    @Test func theSessionIsLoggedEitherWay() {
        for auto in [true, false] {
            let (m, _) = makeModel()
            m.settings.autoStartBreak = auto
            m.startWork()
            m.forceCompleteForTesting()
            #expect(m.records.count == 1, "autoStartBreak = \(auto)")
            #expect(m.records[0].source == "timer")
        }
    }

    @Test func theArmedBreakPreviewsTheShortBreakLength() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 7
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.displayRemaining == 7 * 60)
    }

    /// The fourth completion earns the long break, so that is the length the
    /// armed state has to offer — not the short one.
    @Test func theFourthArmedBreakPreviewsTheLongBreakLength() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 7
        m.settings.longBreakMinutes = 21

        for session in 1...3 {
            m.startWork()
            m.forceCompleteForTesting()
            #expect(m.displayRemaining == 7 * 60, "break after session \(session) should be short")
            m.reset()
        }

        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.nextBreakIsLong)
        #expect(m.displayRemaining == 21 * 60)
    }

    /// The preview is computed from settings, not stored, so a length edited
    /// while the break sits armed is both the length shown and the length that
    /// runs.
    @Test func editingTheBreakLengthWhileArmedUpdatesThePreview() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 7
        m.startWork()
        m.forceCompleteForTesting()

        m.settings.breakMinutes = 12
        #expect(m.displayRemaining == 12 * 60)
        m.toggle()
        #expect(abs(m.remaining - 12 * 60) <= 1)
    }

    @Test func theArmedBreakSaysStartBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.primaryTitle == "Start break")
    }

    /// The primary button must start the break, not resume a countdown that
    /// does not exist. `resume()` only guards against `.idle`, so getting this
    /// wrong ticks down from a stale `remaining` of zero.
    @Test func thePrimaryButtonStartsTheArmedBreak() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 9
        m.startWork()
        m.forceCompleteForTesting()

        m.toggle()
        #expect(m.phase == .breakTime)
        #expect(m.isRunning)
        #expect(!m.currentBreakIsLong)
        #expect(abs(m.remaining - 9 * 60) <= 1)
    }

    @Test func theArmedLongBreakStartsLong() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 9
        m.settings.longBreakMinutes = 30

        for _ in 1...3 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()
        }
        m.startWork()
        m.forceCompleteForTesting()

        m.toggle()
        #expect(m.phase == .breakTime)
        #expect(m.currentBreakIsLong)
        #expect(abs(m.remaining - 30 * 60) <= 1)
    }

    /// The stop button's job in this phase: back to idle, previewing focus
    /// again.
    @Test func skippingTheArmedBreakReturnsToIdle() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.workMinutes = 40
        m.startWork()
        m.forceCompleteForTesting()

        m.reset()
        #expect(m.phase == .idle)
        #expect(m.primaryTitle == "Start focus")
        #expect(m.displayRemaining == 40 * 60)
    }

    /// Only *taking* the long break restarts the cycle, so a skipped long
    /// break is still owed and the next one offered is long again.
    @Test func skippingAnArmedLongBreakKeepsItOwed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 9
        m.settings.longBreakMinutes = 30

        for _ in 1...4 {
            m.startWork()
            m.forceCompleteForTesting()
            m.reset()                       // skipped every time
        }
        #expect(m.nextBreakIsLong)

        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.displayRemaining == 30 * 60)
    }

    // MARK: Menu bar

    /// Nothing is counting while a break is armed, so the item keeps showing
    /// the count. A frozen clock up there would read as a paused timer.
    @Test func theMenuBarKeepsTheCountWhileABreakIsArmed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.statusText == "1")
        #expect(!m.statusText.contains(":"))
    }

    @Test func theArmedBreakRespectsTheIconOnlyMenuBar() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.showsCountInMenuBar = false
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.statusText == "")
    }

    @Test func theArmedBreakIsAnnouncedWithItsLength() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.settings.breakMinutes = 10
        m.startWork()
        m.forceCompleteForTesting()
        #expect(m.statusDescription.contains("Break ready"))
        #expect(m.statusDescription.contains("10 minutes"))
    }
}
```

The glyph assertion for `.breakReady` deliberately does **not** live here. It
belongs to the glyph table in `PresentationTests` (Step 8), so the whole
phase/running decision reads as one thing in one place rather than being
asserted twice.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BreakReadyTests
```

Expected: a **compile error** — `type 'Phase' has no member 'breakReady'`.

- [ ] **Step 3: Add the phase**

In `Sources/PomodoroCount/Types.swift`, replace `enum Phase`:

```swift
enum Phase: Equatable {
    /// `.breakReady` is a fourth state, not a flavour of idle: a focus session
    /// has finished and its break is armed at the configured length, waiting to
    /// be started or skipped. Reusing `.idle` would have left the panel
    /// previewing the *focus* length with no sign a break was owed; reusing a
    /// paused `.breakTime` would have let `startBreak()` spend the earned long
    /// break at arm time, so skipping it would silently cancel it.
    case idle, work, breakTime, breakReady
}
```

**Sites to leave alone.** Four places look like they want changing and do not.
Touching them is a review rejection, not an improvement:

- `reset()` already sets `phase = .idle`, which is exactly the skip behaviour.
  It needs no `.breakReady` case, and the stop button's `.disabled(phase == .idle)`
  already enables itself in the new phase.
- **Nothing persists the phase.** `phase` has never been written to `data.json`
  and must not start now: an armed break restored hours later would be counting
  a rest the user has long since taken or skipped. A relaunch landing in `.idle`
  is the intended behaviour, matching `focusSessionsThisCycle`.
- `AppModel+Categories.swift`'s `sessionRunning` (`phase == .work && isRunning`)
  is already correct — an armed break should outline no category row.
- `handleScreenLocked()` guards on `isRunning`, so it is already a no-op while
  armed. There is no countdown to pause.

- [ ] **Step 4: Build to collect the exhaustiveness errors**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Expected: FAIL, with `switch must be exhaustive` at every site listed in this task's **Files**. That list is the checklist for Steps 5–7; the compiler is the authority on it, so if it names a site not listed here, handle it and note it in the commit body.

- [ ] **Step 5: Teach the model the new phase**

In `Sources/PomodoroCount/Model.swift`, add `armedBreakMinutes` directly beneath `nextBreakIsLong` (line 268):

```swift
    /// How long the break offered right now will run for. One source of truth:
    /// the armed state previews this number and `startBreak()` counts down from
    /// it, so what the panel promises and what runs cannot diverge.
    var armedBreakMinutes: Int {
        nextBreakIsLong ? settings.longBreakMinutes : settings.breakMinutes
    }
```

Replace `displayRemaining`:

```swift
    /// Time shown on the big timer. Neither stopped phase has a countdown, so
    /// each previews the length of whatever its primary button will start —
    /// computed from settings rather than stored, so editing a length in
    /// Settings moves the readout while it is on screen.
    var displayRemaining: TimeInterval {
        switch phase {
        case .idle:             return TimeInterval(settings.workMinutes * 60)
        case .breakReady:       return TimeInterval(armedBreakMinutes * 60)
        case .work, .breakTime: return remaining
        }
    }
```

Replace `primaryTitle`:

```swift
    var primaryTitle: String {
        if isRunning { return "Pause" }
        switch phase {
        case .idle:             return "Start focus"
        case .breakReady:       return "Start break"
        case .work, .breakTime: return "Resume"
        }
    }
```

Replace `statusText`:

```swift
    var statusText: String {
        switch phase {
        // An armed break has no countdown, so the item keeps showing the count
        // and the cup glyph carries the news that a break is waiting.
        case .idle, .breakReady: return settings.showsCountInMenuBar ? "\(todayCount)" : ""
        case .work, .breakTime:  return Self.mmss(remaining)
        }
    }
```

In `statusDescription`, add a case between `.idle` and `.work`:

```swift
        case .breakReady:
            return "Break ready: \(Self.spokenDuration(TimeInterval(armedBreakMinutes * 60)))"
```

Replace `toggle()`:

```swift
    func toggle() {
        if isRunning {
            pause()
        } else if phase == .idle {
            startWork()
        } else if phase == .breakReady {
            // Not `resume()`. There is no countdown behind an armed break, and
            // `resume()`'s guard only excludes `.idle` — it would happily start
            // ticking from a stale `remaining`, which is zero straight after
            // the focus session that armed this.
            startBreak()
        } else {
            resume()
        }
    }
```

Replace the body of `startBreak()` so it reads the length from the one place that computes it:

```swift
    func startBreak() {
        let long = nextBreakIsLong
        // Read before the cycle resets: `armedBreakMinutes` is derived from
        // `focusSessionsThisCycle`, so asking after the reset below would
        // always answer "short".
        let minutes = armedBreakMinutes
        if long { focusSessionsThisCycle = 0 }   // taking it restarts the cycle
        currentBreakIsLong = long
        phase = .breakTime
        clock.remaining = TimeInterval(minutes * 60)
        beginCountdown()
    }
```

In `complete()`, change the focus path's `else` branch (line 347) from `phase = .idle` to:

```swift
            } else {
                // Not `.idle`: the break is owed, so offer it at the length it
                // will run for instead of dropping back to previewing focus.
                phase = .breakReady
            }
```

- [ ] **Step 6: Teach the menu bar glyph the new phase**

In `Sources/PomodoroCount/StatusIcon.swift`, add the case to `glyph`:

```swift
    static func glyph(phase: Phase, running: Bool) -> Glyph {
        switch phase {
        case .idle:      return .tomato
        // Stopped, but not paused — there is no countdown behind it to resume,
        // so the cup says "a break is waiting" and the pause glyph would lie.
        case .breakReady: return .cup
        case .work:      return running ? .tomato : .pause
        case .breakTime: return running ? .cup : .pause
        }
    }
```

- [ ] **Step 7: Teach the Focus tab the new phase**

In `Sources/PomodoroCount/RootView.swift`:

`statusBadge` — add before `case .work`:

```swift
        case .breakReady:
            badge("Break ready", palette.breakColor)
```

`phaseColor` and `timerTint` — fold `.breakReady` in with the break cases:

```swift
    private var phaseColor: Color {
        switch model.phase {
        case .idle: return palette.idleColor
        case .work: return palette.focusColor
        case .breakTime, .breakReady: return palette.breakColor
        }
    }

    private var timerTint: ButtonTint {
        switch model.phase {
        case .idle: return palette.idleButton
        case .work: return palette.focusButton
        case .breakTime, .breakReady: return palette.breakButton
        }
    }
```

`primaryHelp` — add a case, naming the length the way the idle case already does:

```swift
        case .breakReady: return "Start your \(model.armedBreakMinutes)-minute break"
```

`phaseSubtitle` — add a case:

```swift
        case .breakReady:
            return model.nextBreakIsLong
                ? "Long break — earned · \(model.armedBreakMinutes) min"
                : "Break · \(model.armedBreakMinutes) min"
```

- [ ] **Step 8: Extend the presentation tests to the new phase**

In `Tests/PomodoroCountTests/PresentationTests.swift`, add `.breakReady` to the phase argument list:

```swift
    @Test(arguments: [Phase.idle, .work, .breakTime, .breakReady])
    func statusIconRendersForEveryPhase(phase: Phase) {
```

And add the two new combinations to `theMenuBarGlyphFollowsThePhase`, after the `.breakTime` lines:

```swift
        #expect(StatusIcon.glyph(phase: .breakReady, running: false) == .cup)
        #expect(StatusIcon.glyph(phase: .breakReady, running: true) == .cup)
```

- [ ] **Step 9: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BreakReadyTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PresentationTests
```

Expected: PASS for both.

- [ ] **Step 10: Run the full suite**

```bash
just test
```

Expected: all pass. Pay attention to `LongBreakTests` and `TimerTests` — they drive `forceCompleteForTesting()` with `autoStartBreak = true` and assert on `remaining`, so they exercise the path this task must leave alone.

- [ ] **Step 11: Commit and push, then install**

```bash
git add Sources/PomodoroCount/Types.swift Sources/PomodoroCount/Model.swift \
        Sources/PomodoroCount/StatusIcon.swift Sources/PomodoroCount/RootView.swift \
        Tests/PomodoroCountTests/BreakReadyTests.swift \
        Tests/PomodoroCountTests/PresentationTests.swift
git commit -m "Arm the break instead of returning to idle

With auto-start off, a completed focus session dropped straight back to
idle: the panel re-previewed the focus length and the only route to the
break the user had just earned was a small cup icon. It now holds the
break at the length it will actually run for.

A fourth Phase case rather than a flag, so the exhaustive switches make
every render site say what it shows. The length is derived on every read
from one property both the preview and startBreak() use, so the number on
screen cannot promise a break the timer will not run."
git push
just install
```

---

### Task 3: The button row

Two view-body conditionals now answer wrongly for the new phase. Both are lifted onto the model, where they can be asserted — the cup's visibility and the stop button's tooltip are decisions, not layout.

**Files:**
- Modify: `Sources/PomodoroCount/Model.swift` (add two members near `primaryTitle`)
- Modify: `Sources/PomodoroCount/RootView.swift` (`focusTab`'s button row, lines 232–255)
- Test: `Tests/PomodoroCountTests/BreakReadyTests.swift`

**Interfaces:**
- Consumes: `Phase.breakReady` from Task 2.
- Produces: `AppModel.offersManualBreak: Bool`, `AppModel.resetHelp: String`.

- [ ] **Step 1: Write the failing tests**

Append to `BreakReadyTests.swift`, before the closing brace:

```swift
    // MARK: The button row

    /// The cup stands down while a break is armed: the primary button already
    /// offers exactly that, and two controls doing one job in one row is worse
    /// than one. The three older phases keep the behaviour they had.
    @Test func theCupButtonStandsDownWhileABreakIsArmed() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        #expect(m.offersManualBreak)          // idle — rest now, before starting
        m.startWork()
        #expect(m.offersManualBreak)          // mid-focus — cut it short and rest
        m.forceCompleteForTesting()
        #expect(!m.offersManualBreak)         // armed — the big button is the offer
        m.toggle()
        #expect(!m.offersManualBreak)         // already resting
    }

    /// "Abandons the session — nothing is logged" is false once a break is
    /// armed. The session *was* logged; that is why there is a break to skip.
    @Test func theStopButtonStopsPromisingNothingWasLogged() {
        let (m, _) = makeModel()
        m.settings.autoStartBreak = false
        m.startWork()
        #expect(m.resetHelp.contains("nothing is logged"))
        m.forceCompleteForTesting()
        #expect(m.resetHelp.contains("Skip the break"))
        #expect(!m.resetHelp.contains("nothing is logged"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BreakReadyTests
```

Expected: compile error — `value of type 'AppModel' has no member 'offersManualBreak'`.

- [ ] **Step 3: Write the implementation**

In `Sources/PomodoroCount/Model.swift`, add both directly beneath `primaryTitle`:

```swift
    /// Whether the panel offers the "rest now" cup button. Not while a break is
    /// already armed — the primary button offers exactly that, and two controls
    /// doing one job in one row is worse than one.
    var offersManualBreak: Bool {
        phase == .idle || phase == .work
    }

    /// The stop button's tooltip. It abandons an unfinished session in the
    /// running phases, but an armed break has a session already logged behind
    /// it, so "nothing is logged" would be a lie exactly where the user is most
    /// likely to hesitate over the button.
    var resetHelp: String {
        phase == .breakReady
            ? "Skip the break — the session is already logged"
            : "Abandons the session — nothing is logged"
    }
```

In `Sources/PomodoroCount/RootView.swift`, change the stop button's `.help` from the literal to the model's string, and replace the cup button's condition:

```swift
                Button { model.reset() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(SoftIconButtonStyle())
                .disabled(model.phase == .idle)
                // Says what the label doesn't: the hint and the tooltip share
                // this string, and repeating the label would double-speak.
                // Phase-dependent since an armed break has a logged session
                // behind it — see `AppModel.resetHelp`.
                .help(model.resetHelp)
                .accessibilityLabel("Stop and reset")

                if model.offersManualBreak {
                    Button { model.startBreak() } label: {
                        Image(systemName: "cup.and.saucer.fill")
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help("Rest now — an unfinished focus session isn't logged")
                    .accessibilityLabel("Start a break now")
                }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BreakReadyTests
```

Expected: PASS.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: all pass. `AccessibilityTests` is the one to watch — it asserts on panel control labels.

- [ ] **Step 6: Commit and push, then install**

```bash
git add Sources/PomodoroCount/Model.swift Sources/PomodoroCount/RootView.swift \
        Tests/PomodoroCountTests/BreakReadyTests.swift
git commit -m "Stop offering the break twice, and stop mis-describing the stop

The cup button and the armed state's primary button offered the same
thing in the same row, and the stop button's tooltip promised nothing was
logged at the one moment when something had been. Both decisions move
onto the model, where a test can hold them to it."
git push
just install
```

---

### Task 4: The banner, and the changelog

With auto-start off, the notification is the only thing that reaches a user whose panel is closed, so it should mention the break. `notify` returns early unless the app is bundled — nothing posts under test — so the wording is extracted to be assertable.

**Files:**
- Modify: `Sources/PomodoroCount/Model.swift` (`complete()`, and a new static near it)
- Modify: `CHANGELOG.md` (under `## [Unreleased]`)
- Test: `Tests/PomodoroCountTests/BreakReadyTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks beyond `Phase.breakReady` already being in place.
- Produces: `AppModel.completionBody(count: Int, breakArmed: Bool) -> String` (static).

- [ ] **Step 1: Write the failing tests**

Append to `BreakReadyTests.swift`, before the closing brace:

```swift
    // MARK: The banner

    /// With auto-start off and the panel closed, this banner is the only thing
    /// that tells you a break is waiting.
    @Test func theBannerNamesTheWaitingBreak() {
        #expect(AppModel.completionBody(count: 4, breakArmed: true)
                == "That's 4 today — break's ready when you are.")
    }

    /// The auto-start path keeps the wording it has always had.
    @Test func theBannerIsUnchangedWhenTheBreakStartsItself() {
        #expect(AppModel.completionBody(count: 4, breakArmed: false)
                == "Nice — that's 4 today.")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BreakReadyTests
```

Expected: compile error — `type 'AppModel' has no member 'completionBody'`.

- [ ] **Step 3: Write the implementation**

In `Sources/PomodoroCount/Model.swift`, add immediately above `private func complete()`:

```swift
    /// The body of the banner a finished focus session posts. Extracted and
    /// pure because `notify` returns early unless the app is bundled, so this
    /// wording posts nothing under test — and with auto-start off it is the
    /// only news a user with the panel closed gets.
    static func completionBody(count: Int, breakArmed: Bool) -> String {
        breakArmed
            ? "That's \(count) today — break's ready when you are."
            : "Nice — that's \(count) today."
    }
```

In `complete()`, replace the `notify` call on the focus path:

```swift
            notify("Pomodoro complete",
                   Self.completionBody(count: todayCount,
                                       breakArmed: !settings.autoStartBreak))
```

`breakArmed` reads the same setting the `if` below branches on, two lines later — they cannot disagree.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BreakReadyTests
```

Expected: PASS.

- [ ] **Step 5: Add the changelog entry**

In `CHANGELOG.md`, under the empty `## [Unreleased]` heading, add:

```markdown
### Changed

- **A finished focus session now offers the break** — with "Auto-start break"
  off, a completed session no longer drops back to idle. The Focus tab holds the
  break at its configured length (the long one when you have earned it), the big
  button becomes "Start break", and the menu bar shows a cup beside your count.
  The stop button skips it, and skipping a long break keeps it owed.
```

- [ ] **Step 6: Run the full suite**

```bash
just test
```

Expected: all pass. `VersionTests` checks VERSION/CHANGELOG consistency, so it is the one this step can break.

- [ ] **Step 7: Commit and push, then install**

```bash
git add Sources/PomodoroCount/Model.swift CHANGELOG.md \
        Tests/PomodoroCountTests/BreakReadyTests.swift
git commit -m "Say in the banner that a break is waiting

With auto-start off and the panel shut, the notification is the only
thing that reaches you, and it said nothing about the break it had just
armed. The wording is a static function because notify() posts nothing
unless the app is bundled, so in place it cannot be asserted at all."
git push
just install
```

---

### Task 5: Make the armed state visible to `just preview`

Beyond the spec's original scope, and separable — reject this task and the feature still works. Without it the armed state cannot be looked at without sitting through a real focus session, which makes reviewing its colour, badge, subtitle and button row impractical.

**Files:**
- Modify: `Sources/PomodoroCount/Styles.swift` (`enum PreviewOverrides`, lines 6–13)
- Modify: `Sources/PomodoroCount/PomodoroCountApp.swift` (`--preview` flag parsing, lines 45–51)
- Modify: `Sources/PomodoroCount/PreviewRenderer.swift` (`render(to:)`, after the seeding block)
- Modify: `AGENTS.md` (the debug-flags paragraph)

**Interfaces:**
- Consumes: `Phase.breakReady`, `AppModel.forceCompleteForTesting()`.
- Produces: `PreviewOverrides.armedBreak: Bool` and the `--armed-break` CLI flag.

- [ ] **Step 1: Add the override flag**

In `Sources/PomodoroCount/Styles.swift`, add to `PreviewOverrides`:

```swift
    /// Arms a break on the preview's throwaway model before rasterising, so the
    /// `.breakReady` panel can be looked at without sitting out a real focus
    /// session.
    nonisolated(unsafe) static var armedBreak = false
```

- [ ] **Step 2: Parse the CLI flag**

In `Sources/PomodoroCount/PomodoroCountApp.swift`, inside the `--preview` block, beside the existing `forceHover` line:

```swift
            PreviewOverrides.armedBreak = args.contains("--armed-break")
```

And extend the comment above the block:

```swift
        // --preview <path> renders the popover UI to a PNG and exits (no window).
        // Add --hover to render buttons in their hover state, or --armed-break
        // to render the Focus tab with a completed session's break waiting.
```

- [ ] **Step 3: Arm the break in the renderer**

In `Sources/PomodoroCount/PreviewRenderer.swift`, after `model.settings.categories = [...]` and before the `PreviewOverrides.theme` line:

```swift
        if PreviewOverrides.armedBreak {
            // The only route into `.breakReady` is a completed focus session,
            // so drive one. That logs a pomodoro, which nudges the fallback
            // bucket's count past what the seeding comment above describes —
            // true of this mode only, and the whole point of it.
            model.settings.soundEnabled = false
            model.settings.autoStartBreak = false
            model.startWork()
            model.forceCompleteForTesting()
        }
```

- [ ] **Step 4: Render it and look**

```bash
swift run PomodoroCount --preview /tmp/armed.png --armed-break
```

Then open `/tmp/armed.png` and check the Focus tab against the spec: the countdown reads the break length in the break colour, the badge says "Break ready", the subtitle says `Break · 10 min`, the primary button says "Start break", the stop button is enabled, and **no cup button** sits in the row.

Also render the default, and confirm it is unchanged:

```bash
just preview
```

- [ ] **Step 5: Document the flag**

In `AGENTS.md`, extend the debug-flags sentence in the Commands section to name it:

```markdown
`--preview <png> [--hover] [--armed-break] [--theme Synthwave]`
```

- [ ] **Step 6: Run the full suite**

```bash
just test
```

Expected: all pass. Nothing here is on a tested path, but `MenuBarPanelTests` and the bundle/preview smoke job both exercise the renderer.

- [ ] **Step 7: Commit and push, then install**

```bash
git add Sources/PomodoroCount/Styles.swift Sources/PomodoroCount/PomodoroCountApp.swift \
        Sources/PomodoroCount/PreviewRenderer.swift AGENTS.md
git commit -m "Let --preview show a waiting break

The armed state was otherwise unreachable without sitting out a real
focus session, which is no way to review a colour and a subtitle. Follows
--hover and --theme; the pomodoro it has to log to get there shifts the
bucket count in this mode only."
git push
just install
```

---

## Final verification

- [ ] `just test` — full suite green.
- [ ] `just build` — release bundle compiles, is signed, and carries its icon.
- [ ] `swift run PomodoroCount --preview /tmp/armed.png --armed-break` — the armed panel matches the spec by eye.
- [ ] `just install` — the running app is the committed code.
- [ ] By hand, in the installed app, since drag-free panel state is still worth one human pass: turn **Auto-start break** off, set focus to 1 minute, run a session to completion, and confirm the panel arms the break, the menu bar shows a cup beside the count, "Start break" starts a break of the configured length, and the stop button returns to "Start focus".
- [ ] `git log --oneline origin/main..HEAD` — five commits, each with a body explaining why.
