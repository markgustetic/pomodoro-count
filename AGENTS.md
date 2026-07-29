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
just uitest      # XCUITest against the real menu bar item (needs xcodegen + full Xcode)
just release     # tag VERSION and push the tag; CI publishes
```

Single suite: `swift test --filter ReorderTests` (prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if the active toolchain is the Command Line Tools — `just test` does this dance for you).

Debug flags on the binary: `--store <path>` (redirect persistence — always use a
scratch store for experiments), `--seed-store <path>` (write a known-categories
store and exit), `--preview <png> [--hover] [--theme Synthwave]`, and
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

## Theming

Every color routes through `Palette` (Theme.swift) — including error red.
AppKit-backed controls (switches, steppers, text fields) can't be restyled,
only told which appearance to draw via the palette's `chrome`; that's why
Synthwave forces `.dark`. Raw `Color.red`/`.primary`/borderless button styles
have each burned this codebase before; the WHY comments at the call sites say
how.

## Conventions

- **Comments record WHY, and stay.** Decisions that look odd carry their
  reasoning in place (often "measured, not assumed"). Don't re-litigate a
  commented decision without new evidence; don't strip the comments.
- **Tested logic is extracted from SwiftUI.** `Reorder.destination`,
  `HeatmapLayout.cells`, `PanelMetrics.tabHeightCap(visibleHeight:)` are pure
  and unit-tested; views are thin over them. Follow that shape: new behavior
  gets a failing test first, in `Tests/PomodoroCountTests` (swift-testing, not
  XCTest).
- Commit subjects are short imperative sentences that tell the story
  ("Measure the drag in the list's own coordinate space"), bodies explain the
  why; CHANGELOG.md (Keep a Changelog) gets an entry for user-visible changes,
  and `just release` refuses to tag without one.
- The four CI jobs (tests, bundle+preview smoke, UI reachability, version/
  changelog consistency) must stay green; the UI job's name is deliberate —
  it proves the panel opens, not that dragging works.
