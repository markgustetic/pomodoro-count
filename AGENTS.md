# Pomodoro Count — agent guide

A macOS menu bar app that counts the pomodoros you finish *somewhere else* —
external hardware first, built-in timer second. Swift Package Manager, SwiftUI
with deliberate AppKit reach-ins, macOS 14+.

## Commands

```bash
just test        # full suite (swift-testing; borrows Xcode's toolchain if the CLT is active)
just build       # release .app into ./build (build-app.sh: compile, bundle, icon, ad-hoc sign)
just install     # build, replace /Applications copy, relaunch
just dev         # run from source, no bundle
just preview     # render the whole panel (all three tabs) to a PNG, headless
just uitest      # both UI bundles: reorder dynamics, then XCUITest against the real menu bar item
just uitest-dynamics  # only the harness-driven reorder tests — unattended, no Automation Mode prompt
just release     # tag VERSION and push the tag; CI publishes
```

`just uitest` needs xcodegen and a full Xcode, and its XCUITest half asks a
person at the keyboard to grant Automation Mode. The `DynamicsTests` bundle is
split out precisely so it doesn't: it drives `--reorder-window` with posted
CGEvents and the Accessibility API, which is not XCUITest, so it runs
unattended — but it does move the real pointer, so leave the machine alone
while it runs. **CI runs only the XCUITest half** (`-only-testing:UITests`):
GitHub's runner has no Accessibility permission, so the dynamics cases all fail
there with an empty AX tree. Those four are a local gate, not a CI one.

Single suite: `swift test --filter ReorderTests` (prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if the active toolchain is the Command Line Tools — `just test` does this dance for you).

Debug flags on the binary: `--store <path>` (redirect persistence — always use a
scratch store for experiments), `--seed-store <path>` (write a known-categories
store and exit), `--preview <png> [--hover] [--armed-break] [--theme Synthwave]
[--history-range Week|Month|Year] [--hover-graph <index>]`, and
`--reorder-window` (hosts the panel UI in a plain window — see the harness rule
below).

The maintainer's workflow: commit and push each finished step, then
`just install` so the running app matches the commit.

## The panel is the architecture

The UI lives in a `MenuBarExtra` `.window` panel — a **non-activating
`NSPanel`** — and most non-obvious decisions in this codebase trace back to
that one fact:

- **AppKit drag sessions never start in it.** `List.onMove` and
  `.draggable`/`.dropDestination` are structurally dead here (both were tried;
  rows simply don't move). Reordering is a hand-built `DragGesture` measured in
  a **named coordinate space on the list container** — never `.local`, whose
  frame the gesture's own effects move (that feedback loop was the historical
  reorder stutter; `docs/superpowers/specs/2026-07-28-category-reorder-design.md`
  has the full post-mortem).
- **The panel dismisses when it loses key status.** Alerts and
  `confirmationDialog` would close the very panel they're confirming in, so
  dialogs are popovers (`AddCategoryForm`, `RemoveCategoryConfirmation`). A
  popover is its own window: it inherits the environment but not the
  appearance, so it must apply `.themed(palette)` itself.
- **`@EnvironmentObject` does not reliably reach popover content** and fails
  by crashing. Popover content takes the model (or closures) as parameters.
- **The panel sizes to its content's *ideal* height**, and a bare
  `ScrollView`'s ideal is next to nothing — tabs wrapped in one collapsed the
  panel to 255pt. Long tabs sit in `PanelTabScroller` (PanelMetrics.swift),
  which measures content and pins height to `min(content, screen cap)`.
- **Synthetic mouse events cannot drive the panel's gestures** (clicks work,
  gestures never fire — XCUITest and raw CGEvent streams alike). The
  `--reorder-window` harness exists for automated gesture work, with one rule,
  documented on `ReorderHarness`: *reproducing a failure there is evidence;
  reproducing a success is not.* Drag-start in the real panel can only be
  verified by hand. Headless verification recipe: drive the harness (or read
  the real panel's state) through the Accessibility API — element frames and
  `accessibilityValue`s — plus posted CGEvents.

## Model and persistence

- `AppModel` is the one `ObservableObject` almost everything observes.
  `records` and `settings` save to disk on `didSet`; a burst of related
  changes brackets itself in `suspendSaves()`/`resumeSaves()` (resume on the
  cancelled path too — an unbalanced suspend silently stops all persistence).
- The 0.5s countdown lives in `SessionClock`, split from `AppModel` so ticks
  invalidate only the two views that display seconds (the big countdown, the
  menu bar label). Do not add `@Published` fast-tickers to `AppModel`.
- One JSON file (`data.json`), schema-versioned. `Settings` decodes
  **field-by-field with defaults** so old files always load — new fields must
  follow that pattern. A newer-schema file and an unreadable file are both
  backed up before the next save can overwrite them; history must never be
  silently lost.
- Categories are keyed by **normalized name**, archived rather than deleted
  (records keep their labels; re-adding a name reunites it with its history).
  The fallback bucket always exists. Order is array order in
  `settings.categories`.
- `pomodorocount://log[?category=Name]` logs externally; a URL may not invent
  categories — unknown names land in the bucket.
- Every record-appending path also calls `realignTarget()` — append first, so
  the record credits the target it ran against, then realign. It holds two
  automatic triggers: a met target hands off to the **highest-ranked** category
  with a goal left (the list is a priority ranking, not a rotation), and a
  `settings.targetAimedOn` stamp from an earlier day restarts the plan at the
  top. Both are suppressed while a focus session is actually running, so an
  external log can't re-aim a session Start already pointed elsewhere, and both
  are gated by `settings.autoAdvanceTarget`. `settings.targetPinned` suppresses
  the first on its own: it is set by `pickTarget(_:)` only when the user aims at
  a category that is *already met*, which is the one reading of that pick, and
  it is what makes a deliberate overshoot last longer than one pomodoro.
  Record-*removing* paths (`undoLast`, `unlogToday`) deliberately do not
  realign: the advance is forward-only, and a correction must not move the
  target out from under a Start already pressed.
- `Phase` has **four** cases, and `.breakReady` is a state of its own, not a
  flavour of idle: a finished session's break is armed at its configured length
  waiting to be started or skipped. Anything that switches on phase must handle
  it — the compiler catches the `switch`es, not the `if phase == .idle` checks.
  Its length reads `nextBreakIsLong` (nothing has started, so that is the only
  truthful source); once the break is *running*, `currentBreakIsLong` is, because
  `startBreak()` has already zeroed `focusSessionsThisCycle`.
- `suspendSaves()` has three call sites (a drag reorder, and the two
  record-append-plus-realign pairs above) and **counts depth**, because the
  hotkey and the URL scheme fire the latter two mid-drag; only the outermost
  resume writes. So each suspend needs its own resume. A spare resume is fine
  (the count clamps at zero), a missing one is not — and unlike the old `Bool`
  a count can't heal itself, which is why the drag resumes on view teardown as
  well as on end and cancel.

## Theming

Every color routes through `Palette` (Theme.swift) — including error red.
AppKit-backed controls (switches, steppers, text fields) can't be restyled,
only told which appearance to draw via the palette's `chrome`; that's why
Synthwave forces `.dark`. Raw `Color.red`/`.primary`/borderless button styles
have each burned this codebase before; the WHY comments at the call sites say
how.

Two rules the palette exists to enforce, both learned the hard way:

- **A button style must branch on `ControlState`, not on pressed/hovering.**
  The three styles each read `@Environment(\.isEnabled)` and finish with
  `.dimmed(state, palette)`, so `.disabled(…)` is visible; before that, a dead
  button looked live and swallowed the press. Disabled outranks hover — a
  disabled control must not brighten under the pointer, and must stay dark under
  `PreviewOverrides.forceHover`.
- **Don't put two neon light sources in one card.** Synthwave's tints are
  bright enough that a filled button matching the text above it makes the pair
  bloom into one shape. `ButtonTint.electricCyan` sits deliberately deeper than
  `idleColor` for that reason, and a white label needs the gradient's *midpoint*
  to clear ~4.5:1 — the top stop is what fails first.

## Signing

`build-app.sh` is the only place that calls `codesign --sign`. It takes
`CODESIGN_IDENTITY` (default `-`, ad-hoc); a real identity also gets
`--options runtime --timestamp`, both of which notarization requires. The
release workflow imports the certificate, reads the identity back out of the
keychain, and hands it to the script — it does no signing of its own, and
`--deep` appears only in `codesign --verify`, never in signing.

The nested walk is an **explicit list** of Sparkle's four inner binaries, and a
missing one fails the build. It replaced a `find -maxdepth 3` that never reached
`Versions/*/XPCServices`, so both XPC services silently kept the ad-hoc signature
Sparkle ships — invisible while everything was ad-hoc, fatal under a Developer
ID. A Sparkle upgrade that moves them should break here, not at Apple.

Sparkle accepts an update whose **EdDSA key** matches *or* whose **code signing
identity** matches — one may change per release, never both. Changing both
strands every existing install permanently. One-time Apple-side setup is in
`packaging/signing/README.md`.

## Conventions

- **Comments record WHY, and stay.** Decisions that look odd carry their
  reasoning in place (often "measured, not assumed"). Don't re-litigate a
  commented decision without new evidence; don't strip the comments.
- **Tested logic is extracted from SwiftUI.** `Reorder.destination`,
  `HeatmapLayout.cells`, `HeatmapLayout.metrics`, `HeatmapLayout.hitTest`,
  `HeatmapLayout.center(of:)`, `PanelMetrics.tabHeightCap(visibleHeight:)`,
  `CategoryAdvance.next(after:in:pinned:)`, `CountAdjust.newestTodayIndex`,
  `StatusIcon.glyph(phase:running:)`, `HistoryReadout.tooltip` and
  `TooltipPlacement.origin` are pure and unit-tested; views are thin over
  them. Follow that shape: new behavior gets a failing test first, in
  `Tests/PomodoroCountTests` (swift-testing, not XCTest). The glyph is the
  clearest case for why: it was lifted out of the drawing routine so that a
  phase arriving without its own glyph rule fails a test, instead of waiting
  for someone to notice the wrong icon in the menu bar.
- Commit subjects are short imperative sentences that tell the story
  ("Measure the drag in the list's own coordinate space"), bodies explain the
  why; CHANGELOG.md (Keep a Changelog) gets an entry for user-visible changes,
  and `just release` refuses to tag without one.
- The four CI jobs (tests, bundle+preview smoke, UI reachability, version/
  changelog consistency) must stay green; the UI job's name is deliberate —
  it proves the panel opens, not that dragging works.
