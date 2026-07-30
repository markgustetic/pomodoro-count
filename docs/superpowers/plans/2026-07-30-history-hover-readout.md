# History Hover Readout Implementation Plan

> **Superseded.** The readout line under the graph described here was
> replaced by a cursor-following tooltip card; see
> `docs/superpowers/plans/2026-07-30-history-hover-tooltip.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering a bar in the Week/Month chart or a square in the Year heatmap names that day and its count in a readout line under the graph, with the hovered mark highlighted.

**Architecture:** All hit-testing and text formatting is pure and unit-tested — `HeatmapLayout.metrics` / `.hitTest` in `Heatmap.swift`, a new `HistoryReadout` enum — and the two views are thin over them. `HeatmapView`'s draw loop is rewritten to read its geometry from the same `metrics` function the hit test uses, so the highlighted square can never be a different one than the readout names. Hover arrives via `.onContinuousHover`, a tracking area rather than a gesture recognizer, which is why it is expected to work in the non-activating panel where drag sessions do not.

**Tech Stack:** Swift Package Manager, SwiftUI + Swift Charts, `Canvas` for the heatmap, swift-testing for tests.

**Spec:** `docs/superpowers/specs/2026-07-30-history-hover-readout-design.md`

## Global Constraints

- macOS 14+ (`Package.swift` declares `.macOS(.v14)`). `.onContinuousHover` and `ChartProxy.plotFrame` both require it.
- Tests are **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — never XCTest.
- Every colour comes from `palette` (`Theme.swift`). No `Color.red`, `.primary`, or system colours.
- Comments record **why**, in place, and stay. Do not strip existing ones.
- Commit subjects are short imperative sentences that tell the story; bodies explain the why.
- `CHANGELOG.md` (Keep a Changelog) gets an entry for the user-visible change — Task 6.
- Full suite: `just test`. Single suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <SuiteName>` (the `DEVELOPER_DIR` prefix is what `just test` does for you when the active toolchain is the Command Line Tools).
- The panel is 300pt wide. The chart is 108pt tall; the heatmap is 40pt tall and packs ~53 week-columns into it, so a cell is roughly 4pt square. Every sizing decision below is measured against those numbers, not assumed.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/PomodoroCount/Heatmap.swift` (modify) | Grid arithmetic — gains `metrics` and `hitTest`; `HeatmapView` gains a hover binding and the highlight ring |
| `Sources/PomodoroCount/HistoryReadout.swift` (create) | Pure readout: date → series index, and the readout string |
| `Sources/PomodoroCount/HistoryTab.swift` (modify) | Hover state, the readout line, chart overlay and bar dimming |
| `Sources/PomodoroCount/Styles.swift` (modify) | `PreviewOverrides` gains `hoveredGraphIndex` and `historyRange` |
| `Sources/PomodoroCount/PomodoroCountApp.swift` (modify) | Parses `--hover-graph` and `--history-range` |
| `Tests/PomodoroCountTests/HeatmapTests.swift` (modify) | `metrics` and `hitTest` cases |
| `Tests/PomodoroCountTests/HistoryReadoutTests.swift` (create) | Readout wording and date→index cases |
| `AGENTS.md`, `CHANGELOG.md` (modify) | Debug flag list; the user-visible entry |

---

### Task 1: Extract the heatmap's cell geometry

The draw loop computes cell size inline. The hit test in Task 2 needs the same
number, and a second copy of that arithmetic is the bug this task exists to
prevent.

**Files:**
- Modify: `Sources/PomodoroCount/Heatmap.swift:13-25` (add to `HeatmapLayout`), `:41-58` (draw loop)
- Test: `Tests/PomodoroCountTests/HeatmapTests.swift`

**Interfaces:**
- Consumes: `HeatmapLayout.cells(for:calendar:)`, `HeatmapCell`, `DayStat` (all existing)
- Produces: `HeatmapLayout.metrics(columns: Int, size: CGSize) -> (cell: CGFloat, gap: CGFloat)`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PomodoroCountTests/HeatmapTests.swift`, inside `struct HeatmapTests`. Add `import CoreGraphics` to the file's imports if `CGSize` does not resolve (`Foundation` normally suffices on macOS).

```swift
    /// The real canvas: the panel is 300pt wide and `HeatmapView` is 40pt tall.
    private var canvas: CGSize { CGSize(width: 276, height: 40) }

    /// A year is ~53 week-columns, and at that count the width is what binds:
    /// 53 squares plus 52 gaps have to fit across the canvas.
    @Test func metricsFitAYearAcrossTheCanvas() {
        let (cell, gap) = HeatmapLayout.metrics(columns: 53, size: canvas)
        #expect(gap == 1)
        #expect(abs(cell - (276 - 52) / 53) < 0.001)
        #expect(53 * cell + 52 * gap <= 276.001)
    }

    /// With few columns there is width to spare, so the seven weekday rows are
    /// what binds instead.
    @Test func aShortSeriesIsBoundByHeight() {
        let (cell, _) = HeatmapLayout.metrics(columns: 1, size: canvas)
        #expect(abs(cell - (40 - 6) / 7) < 0.001)
    }

    /// No days, no grid — and no division by zero.
    @Test func anEmptyGridHasNoCell() {
        #expect(HeatmapLayout.metrics(columns: 0, size: canvas).cell == 0)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeatmapTests
```

Expected: compile error — `type 'HeatmapLayout' has no member 'metrics'`.

- [ ] **Step 3: Add `metrics` to `HeatmapLayout`**

In `Sources/PomodoroCount/Heatmap.swift`, add inside `enum HeatmapLayout` after `cells(for:calendar:)`:

```swift
    /// The pixel geometry of the grid: the square each day gets, and the gap
    /// between squares.
    ///
    /// Extracted from the draw loop so the hit test can read the same numbers.
    /// A hit test that recomputed this independently could drift by a fraction
    /// of a point and name a different day than the one it highlights — which
    /// is exactly the failure a hover readout would make invisible.
    static func metrics(columns: Int, size: CGSize) -> (cell: CGFloat, gap: CGFloat) {
        let gap: CGFloat = 1
        guard columns > 0 else { return (0, gap) }
        let cell = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                       (size.height - gap * 6) / 7)
        return (max(0, cell), gap)
    }
```

- [ ] **Step 4: Rewrite the draw loop to use it**

In `Sources/PomodoroCount/Heatmap.swift`, replace the first two lines inside the `Canvas` closure:

```swift
        Canvas { context, size in
            let gap: CGFloat = 1
            let cell = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                           (size.height - gap * 6) / 7)
```

with:

```swift
        Canvas { context, size in
            let (cell, gap) = HeatmapLayout.metrics(columns: columns, size: size)
```

Leave the rest of the closure untouched.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeatmapTests
```

Expected: PASS, including the six pre-existing cases.

- [ ] **Step 6: Commit**

```bash
git add Sources/PomodoroCount/Heatmap.swift Tests/PomodoroCountTests/HeatmapTests.swift
git commit -m "Give the heatmap's cell geometry one owner

The draw loop sized its squares inline. A hit test needs the same
arithmetic, and a second copy of it could drift by a fraction of a point
and name a different day than the one it highlights."
```

---

### Task 2: Hit-test a point to a heatmap cell

**Files:**
- Modify: `Sources/PomodoroCount/Heatmap.swift` (add to `HeatmapLayout`)
- Test: `Tests/PomodoroCountTests/HeatmapTests.swift`

**Interfaces:**
- Consumes: `HeatmapLayout.metrics(columns:size:)` from Task 1
- Produces: `HeatmapLayout.hitTest(_ point: CGPoint, cells: [HeatmapCell], columns: Int, size: CGSize) -> Int?` — an index into `cells`, which is equally an index into the `[DayStat]` those cells were built from

- [ ] **Step 1: Write the failing tests**

Add to `struct HeatmapTests`:

```swift
    /// The centre of the square at (column, row), in canvas coordinates.
    private func centre(column: Int, row: Int, columns: Int) -> CGPoint {
        let (cell, gap) = HeatmapLayout.metrics(columns: columns, size: canvas)
        let step = cell + gap
        return CGPoint(x: CGFloat(column) * step + cell / 2,
                       y: CGFloat(row) * step + cell / 2)
    }

    @Test func hitTestFindsTheFirstCell() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 0, row: 0, columns: 2),
                                      cells: cells, columns: 2, size: canvas) == 0)
    }

    @Test func hitTestFindsTheLastCell() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 1, row: 6, columns: 2),
                                      cells: cells, columns: 2, size: canvas) == 13)
    }

    /// The index a hit test returns addresses the same day in the series the
    /// cells were built from. The readout formats from that series, so if this
    /// slips it names one day while ringing another.
    @Test func aHitIndexAddressesTheSameDayInTheSeries() {
        let stats = week(startingMonday: 14)
        let cells = HeatmapLayout.cells(for: stats, calendar: mondayFirst)
        let hit = HeatmapLayout.hitTest(centre(column: 1, row: 2, columns: 2),
                                        cells: cells, columns: 2, size: canvas)
        #expect(hit == 9)
        #expect(cells[9].count == stats[9].count)
        #expect(cells[9].column == 1)
        #expect(cells[9].row == 2)
    }

    /// The 1pt gap between squares belongs to no day.
    @Test func aPointInTheGapHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        let (cell, _) = HeatmapLayout.metrics(columns: 2, size: canvas)
        let inTheGap = CGPoint(x: cell + 0.5, y: cell / 2)
        #expect(HeatmapLayout.hitTest(inTheGap, cells: cells, columns: 2, size: canvas) == nil)
    }

    @Test func aPointOutsideTheGridHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 275, y: 5),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: -1, y: 5),
                                      cells: cells, columns: 2, size: canvas) == nil)
        #expect(HeatmapLayout.hitTest(CGPoint(x: 2, y: 41),
                                      cells: cells, columns: 2, size: canvas) == nil)
    }

    /// A short series leaves the tail of its last column empty. Those slots are
    /// grid positions with no day behind them.
    @Test func anEmptySlotInTheGridHitsNothing() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 3), calendar: mondayFirst)
        #expect(HeatmapLayout.hitTest(centre(column: 0, row: 5, columns: 1),
                                      cells: cells, columns: 1, size: canvas) == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeatmapTests
```

Expected: compile error — `type 'HeatmapLayout' has no member 'hitTest'`.

- [ ] **Step 3: Implement `hitTest`**

Add inside `enum HeatmapLayout`, after `metrics`:

```swift
    /// The index of the cell under `point`, or nil for a point in the gap
    /// between squares, outside the grid, or on a grid slot no day occupies.
    ///
    /// Reads its geometry from `metrics`, so it can only ever name the square
    /// the draw loop actually drew. The returned index addresses `cells` —
    /// which `cells(for:)` builds 1:1 and in order from its `[DayStat]` — so
    /// it is equally an index into that series.
    ///
    /// The linear search is 365 comparisons on a pointer move, which is
    /// nothing next to the redraw it triggers; a lookup table would be a
    /// second copy of the layout to keep in sync.
    static func hitTest(_ point: CGPoint, cells: [HeatmapCell],
                        columns: Int, size: CGSize) -> Int? {
        let (cell, gap) = metrics(columns: columns, size: size)
        guard cell > 0, point.x >= 0, point.y >= 0 else { return nil }
        let step = cell + gap
        let column = Int(point.x / step)
        let row = Int(point.y / step)
        guard column < columns, row < 7 else { return nil }
        // Past the square is the gap, and the gap is nobody's day.
        guard point.x - CGFloat(column) * step <= cell,
              point.y - CGFloat(row) * step <= cell else { return nil }
        return cells.firstIndex { $0.column == column && $0.row == row }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeatmapTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/Heatmap.swift Tests/PomodoroCountTests/HeatmapTests.swift
git commit -m "Find the day under a point in the heatmap

Rejects the gap between squares and grid slots no day occupies, so a
hover can't round to a neighbour. Shares metrics with the draw loop, and
a test pins that its index addresses the same day in the series."
```

---

### Task 3: The readout's wording

**Files:**
- Create: `Sources/PomodoroCount/HistoryReadout.swift`
- Test: `Tests/PomodoroCountTests/HistoryReadoutTests.swift`

**Interfaces:**
- Consumes: `DayStat` (`Types.swift` — `let date: Date`, `let count: Int`)
- Produces:
  - `HistoryReadout.index(for date: Date, in series: [DayStat], calendar: Calendar = .current) -> Int?`
  - `HistoryReadout.text(hoveredIndex: Int?, series: [DayStat], days: Int, dayLabel: (Date) -> String) -> String`

`dayLabel` is passed in rather than reached for: the real one is
`AppModel.dayLabel(_:)` (`Formatting.swift:33`), an instance method on a
`@MainActor ObservableObject` that hardcodes `Calendar.current`. Injecting it
keeps this enum pure and keeps day naming in one place — its Today/Yesterday
behaviour is already pinned by `PresentationTests.dayLabelsUseFriendlyNamesForRecentDays`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/HistoryReadoutTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// The hover readout under the History graphs. Naming a day is `dayLabel`'s
/// job and is pinned in `PresentationTests`; these pin the composition around
/// it, so a stub label keeps the assertions free of the machine's locale.
@Suite struct HistoryReadoutTests {

    private let cal = Calendar(identifier: .gregorian)

    /// Consecutive days from 2026-06-01, one per count.
    private func series(_ counts: [Int]) -> [DayStat] {
        let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        return counts.enumerated().map { offset, count in
            DayStat(date: cal.date(byAdding: .day, value: offset, to: start)!, count: count)
        }
    }

    private func stub(_ date: Date) -> String { "Jun \(cal.component(.day, from: date))" }

    @Test func restingTextTotalsTheWindow() {
        #expect(HistoryReadout.text(hoveredIndex: nil, series: series([3, 5, 2]),
                                    days: 7, dayLabel: stub)
                == "10 pomodoros in the last 7 days")
    }

    @Test func oneIsSingularInTheTotalToo() {
        #expect(HistoryReadout.text(hoveredIndex: nil, series: series([1]),
                                    days: 30, dayLabel: stub)
                == "1 pomodoro in the last 30 days")
    }

    /// 365 is spelled as a year. "in the last 365 days" is arithmetic, not
    /// English.
    @Test func aYearIsSpelledAsAYear() {
        #expect(HistoryReadout.text(hoveredIndex: nil, series: series([2, 2]),
                                    days: 365, dayLabel: stub)
                == "4 pomodoros in the last year")
    }

    @Test func hoverNamesTheDayAndItsCount() {
        #expect(HistoryReadout.text(hoveredIndex: 1, series: series([3, 5, 2]),
                                    days: 7, dayLabel: stub)
                == "Jun 2 · 5 pomodoros")
    }

    @Test func oneIsSingular() {
        #expect(HistoryReadout.text(hoveredIndex: 0, series: series([1]),
                                    days: 7, dayLabel: stub)
                == "Jun 1 · 1 pomodoro")
    }

    /// A day off is a real answer, not an empty one — the heatmap draws those
    /// cells, so hovering one has to say something.
    @Test func aDayOffStillReads() {
        #expect(HistoryReadout.text(hoveredIndex: 0, series: series([0]),
                                    days: 7, dayLabel: stub)
                == "Jun 1 · 0 pomodoros")
    }

    /// The range picker swaps the series out from under a live hover. A stale
    /// index has to fall back to the resting line, not trap.
    @Test func anOutOfRangeIndexFallsBackToTheTotal() {
        #expect(HistoryReadout.text(hoveredIndex: 9, series: series([3, 5]),
                                    days: 7, dayLabel: stub)
                == "8 pomodoros in the last 7 days")
    }

    @Test func indexFindsTheMatchingDay() {
        let s = series([3, 5, 2])
        let noon = cal.date(byAdding: .hour, value: 12, to: s[1].date)!
        #expect(HistoryReadout.index(for: noon, in: s, calendar: cal) == 1)
    }

    @Test func indexMissesDatesOutsideTheSeries() {
        let s = series([3, 5, 2])
        let before = cal.date(byAdding: .day, value: -1, to: s[0].date)!
        let after = cal.date(byAdding: .day, value: 1, to: s[2].date)!
        #expect(HistoryReadout.index(for: before, in: s, calendar: cal) == nil)
        #expect(HistoryReadout.index(for: after, in: s, calendar: cal) == nil)
    }

    @Test func indexOfAnEmptySeriesIsNil() {
        #expect(HistoryReadout.index(for: Date(), in: [], calendar: cal) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HistoryReadoutTests
```

Expected: compile error — `cannot find 'HistoryReadout' in scope`.

- [ ] **Step 3: Create `HistoryReadout`**

Create `Sources/PomodoroCount/HistoryReadout.swift`:

```swift
import Foundation

/// The History graphs' hover readout: which day the pointer is over, and the
/// line of text that names it.
///
/// Pure and free of SwiftUI for the same reason `StatusIcon.glyph` and
/// `HeatmapLayout.cells` are — a rendered line isn't assertable, the wording
/// behind it is, and both graphs have to phrase the same day identically.
enum HistoryReadout {

    /// The series index for `date`, matched on the calendar day. The chart
    /// hands back a `Date` interpolated from a pointer position, so it lands
    /// anywhere inside the day rather than on its midnight.
    static func index(for date: Date, in series: [DayStat],
                      calendar: Calendar = .current) -> Int? {
        series.firstIndex { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The readout line: the hovered day and its count, or the window's total
    /// when nothing is hovered.
    ///
    /// An out-of-range index reads as no hover rather than trapping — the
    /// range picker swaps the series under a live pointer, and a stale index
    /// must not take the panel down with it.
    static func text(hoveredIndex: Int?, series: [DayStat], days: Int,
                     dayLabel: (Date) -> String) -> String {
        if let i = hoveredIndex, series.indices.contains(i) {
            return "\(dayLabel(series[i].date)) · \(pomodoros(series[i].count))"
        }
        let total = series.reduce(0) { $0 + $1.count }
        return "\(pomodoros(total)) in the last \(days == 365 ? "year" : "\(days) days")"
    }

    /// Matches the pluralisation the tab's accessibility values already use, so
    /// a day off reads "0 pomodoros" rather than inventing a word for zero.
    private static func pomodoros(_ count: Int) -> String {
        "\(count) \(count == 1 ? "pomodoro" : "pomodoros")"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HistoryReadoutTests
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/HistoryReadout.swift Tests/PomodoroCountTests/HistoryReadoutTests.swift
git commit -m "Write the History readout's wording down where it can be tested

Both graphs have to phrase a day identically, and a rendered line isn't
assertable. Takes dayLabel as a parameter so day naming stays in one
place and this stays pure."
```

---

### Task 4: Preview plumbing

The Year heatmap has no headless coverage today — `--preview` only ever renders
the Week chart. Tasks 5 and 6 need both a forced range and a forced hover to be
verifiable at all.

**Files:**
- Modify: `Sources/PomodoroCount/Styles.swift:7-18` (`PreviewOverrides`)
- Modify: `Sources/PomodoroCount/PomodoroCountApp.swift` (the `--preview` block)
- Modify: `Sources/PomodoroCount/HistoryTab.swift:11` (initial `range`)
- Modify: `AGENTS.md` (the debug-flags paragraph)

**Interfaces:**
- Produces: `PreviewOverrides.hoveredGraphIndex: Int?`, `PreviewOverrides.historyRange: String?`

- [ ] **Step 1: Add the overrides**

In `Sources/PomodoroCount/Styles.swift`, add inside `enum PreviewOverrides` after `armedBreak`:

```swift
    /// Forces a hovered day on the History graphs. No real pointer exists in a
    /// headless render, so without this the readout and the highlight can only
    /// be seen by hand.
    nonisolated(unsafe) static var hoveredGraphIndex: Int?
    /// The `ChartRange` raw value the History tab opens on when rendering.
    /// A string rather than the enum because `ChartRange` is nested in a view
    /// and this file has no business importing that isolation. Without it a
    /// preview only ever shows the Week chart, and the Year heatmap has no
    /// headless coverage at all.
    nonisolated(unsafe) static var historyRange: String?
```

- [ ] **Step 2: Parse the flags**

In `Sources/PomodoroCount/PomodoroCountApp.swift`, inside the `--preview` block, after the `PreviewOverrides.armedBreak` line and before the `--theme` block:

```swift
            if let h = args.firstIndex(of: "--hover-graph"), h + 1 < args.count {
                PreviewOverrides.hoveredGraphIndex = Int(args[h + 1])
            }
            if let r = args.firstIndex(of: "--history-range"), r + 1 < args.count {
                PreviewOverrides.historyRange = args[r + 1].capitalized
            }
```

Extend the *first paragraph* of the comment above `if let i = args.firstIndex(of: "--preview")` to name the new flags — leave the `--store` paragraph below it alone:

```swift
        // --preview <path> renders the popover UI to a PNG and exits (no window).
        // Add --hover to render buttons in their hover state, --armed-break
        // to render the Focus tab with a completed session's break waiting,
        // --history-range to pick which History graph shows, or --hover-graph
        // to hover a day on it.
```

- [ ] **Step 3: Honour the range override**

In `Sources/PomodoroCount/HistoryTab.swift`, replace:

```swift
    @State private var range: ChartRange = .week
```

with:

```swift
    // Week unless a preview asked for another: the Year heatmap is otherwise
    // unreachable headlessly, since nothing can drive the picker in a render.
    @State private var range: ChartRange =
        PreviewOverrides.historyRange.flatMap(ChartRange.init(rawValue:)) ?? .week
```

- [ ] **Step 4: Verify the heatmap renders headlessly**

```bash
swift run PomodoroCount --preview /tmp/pomo-year.png --history-range Year
```

Expected: `Wrote preview → /tmp/pomo-year.png`. Open it and confirm the middle
panel's History tab shows the heatmap grid rather than the week bar chart.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: PASS, no regressions.

- [ ] **Step 6: Document the flags**

In `AGENTS.md`, in the "Debug flags on the binary" list, replace the `--preview` bullet's flag line:

```
- `--preview <png> [--hover] [--armed-break] [--theme Synthwave] [--store <path>]`
```

with:

```
- `--preview <png> [--hover] [--armed-break] [--theme Synthwave] [--store <path>]
  [--history-range Week|Month|Year] [--hover-graph <index>]`
```

Leave the rest of that bullet and the paragraph below it intact — they document
which flags compose and that `--store` is read through a copy. Add the two new
flags to the "applied *after* the model is built" sentence, since they are
`PreviewOverrides` and compose with `--store` the same way the other three do.

- [ ] **Step 7: Commit**

```bash
git add Sources/PomodoroCount/Styles.swift Sources/PomodoroCount/PomodoroCountApp.swift Sources/PomodoroCount/HistoryTab.swift AGENTS.md
git commit -m "Let a preview pick which History graph it renders

The Year heatmap had no headless coverage: --preview only ever opened on
Week, and nothing can drive the picker in a render. --hover-graph lands
alongside it for the readout work, which no real pointer can reach."
```

---

### Task 5: Hover the bar chart

**Files:**
- Modify: `Sources/PomodoroCount/HistoryTab.swift` — `body` (`:27-101`), `chart` (`:123-157`)

**Interfaces:**
- Consumes: `HistoryReadout.index(for:in:)` and `.text(hoveredIndex:series:days:dayLabel:)` (Task 3); `PreviewOverrides.hoveredGraphIndex` (Task 4)
- Produces: `HistoryTab.hoveredIndex` state and the `readout(_:)` view, both reused by Task 6

- [ ] **Step 1: Hoist the series and add the hover state**

In `Sources/PomodoroCount/HistoryTab.swift`, add below `@State private var grouping`:

```swift
    @State private var hoveredIndex: Int?
```

In `body`, add the series alongside the existing `let` bindings (the chart
computed its own copy; one binding now feeds the chart, the heatmap and the
readout, which also drops a redundant pass over the window):

```swift
        let series = model.dailySeries(days: range.days)
```

Replace the graph block:

```swift
            if range == .year {
                HeatmapView(stats: model.dailySeries(days: range.days))
            } else {
                chart
            }
```

with:

```swift
            if range == .year {
                HeatmapView(stats: series)
            } else {
                chart(series)
            }
            readout(series)
```

and hang this off the `VStack(spacing: 14) { … }` — on the line after its
closing brace, still inside `PanelTabScroller`, where the `VStack` currently
carries no modifiers at all:

```swift
            .onChange(of: range) { hoveredIndex = nil }
```

Without it, switching Year → Week mid-hover strands a highlight on whatever
index the pointer last touched, on a series that no longer has that day.

> `HeatmapView(stats:)` keeps its current signature until Task 6.

- [ ] **Step 2: Add the readout view**

Add to `HistoryTab`, after `statTile`:

```swift
    /// The effective hover: a real pointer, or a preview's forced one.
    private var effectiveHover: Int? { hoveredIndex ?? PreviewOverrides.hoveredGraphIndex }

    private func readout(_ series: [DayStat]) -> some View {
        Text(HistoryReadout.text(hoveredIndex: effectiveHover, series: series,
                                 days: range.days, dayLabel: model.dayLabel))
            .font(.caption)
            .foregroundStyle(effectiveHover == nil ? palette.textDim : palette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Height reserved in both states. PanelTabScroller sizes this tab
            // to its content's ideal height, so a line that appeared only on
            // hover would grow the panel out from under the pointer that
            // summoned it.
            .frame(height: 13)
    }
```

- [ ] **Step 3: Turn `chart` into a function and add the overlay**

Replace the `chart` computed property's header:

```swift
    @ViewBuilder private var chart: some View {
        let series = model.dailySeries(days: range.days)
        Chart(series) { day in
```

with:

```swift
    @ViewBuilder private func chart(_ series: [DayStat]) -> some View {
        let hovered = effectiveHover
        Chart(Array(series.enumerated()), id: \.element.id) { item in
```

and inside the `BarMark`, replace the two `day.` references with `item.element.`:

```swift
            BarMark(
                x: .value("Day", item.element.date, unit: .day),
                y: .value("Pomodoros", item.element.count)
            )
```

Add to the `BarMark`, after its `.foregroundStyle(…)`:

```swift
            // Only the hovered bar stays lit, so the line underneath can't be
            // read as describing some other day.
            .opacity(hovered == nil || hovered == item.offset ? 1 : 0.45)
```

Add before the closing `.frame(height: 108)`:

```swift
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            // `plotFrame` is where the bars actually are: the
                            // leading y-axis makes the plot narrower than the
                            // view, and hand-computing that inset would drift
                            // the moment an axis label got wider.
                            guard let plot = proxy.plotFrame,
                                  let date: Date = proxy.value(atX: point.x - geo[plot].origin.x)
                            else { hoveredIndex = nil; return }
                            hoveredIndex = HistoryReadout.index(for: date, in: series)
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
            }
        }
```

- [ ] **Step 4: Verify the hover state renders headlessly**

```bash
swift run PomodoroCount --preview /tmp/pomo-hover.png --hover-graph 5
```

Expected: `Wrote preview → /tmp/pomo-hover.png`. Open it. The History panel's
chart shows one bar at full colour and six dimmed, and the line beneath reads
`Yesterday · 1 pomodoro` (the preview seeds `[3, 5, 2, 6, 4, 1, 4]`, so index 5
is yesterday's single pomodoro).

- [ ] **Step 5: The hover gate — verify by hand in the real panel**

This is the one assumption the design rests on. `.onContinuousHover` is a
tracking area rather than a gesture recognizer, so it is expected to fire in
the non-activating panel where `List.onMove` and drag sessions are structurally
dead — the hover-reactive button styles are the precedent. Confirm it:

```bash
just install
```

Open the panel from the menu bar, go to History, and move the pointer across
the week chart. Expected: the readout tracks the pointer day by day and the
unhovered bars dim.

**If nothing happens**, the tracking area is not getting mouse-moved events in a
non-key panel. Fallback: replace `.onContinuousHover` with an
`NSViewRepresentable` that installs an `NSTrackingArea` with
`[.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]` and
reports `convert(event.locationInWindow, from: nil)` through a closure —
`.activeAlways` is the part `.onContinuousHover` may not be asking for. Apply
the same fallback in Task 6 if so, and note it in the commit body.

Per the `ReorderHarness` rule, do not substitute the harness for this check: a
success reproduced there would not be evidence.

- [ ] **Step 6: Run the full suite**

```bash
just test
```

Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add Sources/PomodoroCount/HistoryTab.swift
git commit -m "Name the day under the pointer on the History chart

A readout line under the graph, with the other bars dimmed so the number
and the bar can't come apart. Its height is reserved in both states —
PanelTabScroller sizes the tab to its ideal height, and a line that
appeared on hover would grow the panel out from under the pointer."
```

---

### Task 6: Hover the year heatmap

**Files:**
- Modify: `Sources/PomodoroCount/Heatmap.swift:31-65` (`HeatmapView`)
- Modify: `Sources/PomodoroCount/HistoryTab.swift` (the `HeatmapView(stats:)` call)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `HeatmapLayout.hitTest(_:cells:columns:size:)` (Task 2), `HistoryTab.hoveredIndex` (Task 5)
- Produces: `HeatmapView(stats:hovered:)`

- [ ] **Step 1: Give `HeatmapView` a hover binding and a ring**

In `Sources/PomodoroCount/Heatmap.swift`, add below `let stats: [DayStat]`:

```swift
    @Binding var hovered: Int?
```

Add below the existing `let total = …` line in `body`:

```swift
        let highlight = hovered ?? PreviewOverrides.hoveredGraphIndex
```

Wrap the `Canvas` in a `GeometryReader` — the hover handler needs the canvas
size, which the `Canvas` closure's `size` is not in scope to give it — and
change the `for` loop to carry its index:

```swift
        GeometryReader { geo in
            Canvas { context, size in
                let (cell, gap) = HeatmapLayout.metrics(columns: columns, size: size)
                for (index, c) in cells.enumerated() {
```

Inside the loop, after the existing `if c.count == 0 { … } else { … }` block:

```swift
                    if index == highlight {
                        // Drawn expanded, so the 1pt stroke lands in the 1pt
                        // gap rather than eating into the ~4pt square it
                        // marks. An inset ring at this size leaves nothing to
                        // see — measured, not assumed.
                        let ring = Path(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5),
                                        cornerRadius: cell * 0.2 + 0.5)
                        context.stroke(ring, with: .color(palette.text), lineWidth: 1)
                    }
```

Close the `Canvas` and attach the hover, then close the `GeometryReader`:

```swift
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovered = HeatmapLayout.hitTest(point, cells: cells,
                                                    columns: columns, size: geo.size)
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: 40)
```

The existing `.frame(height: 40)` and the accessibility modifiers stay where
they are, on the outside — a `GeometryReader` has no ideal height of its own,
so that frame is now load-bearing rather than cosmetic.

- [ ] **Step 2: Pass the binding**

In `Sources/PomodoroCount/HistoryTab.swift`:

```swift
                HeatmapView(stats: series, hovered: $hoveredIndex)
```

- [ ] **Step 3: Verify headlessly**

```bash
swift run PomodoroCount --preview /tmp/pomo-heat.png --history-range Year --hover-graph 360
```

Expected: the History panel shows the heatmap with a ring around one square
near the right edge, and the line beneath names that day. `dailySeries` runs
oldest-first, so with 365 days only indices 358–364 carry the preview's seeded
week; index 360 is four days ago, count 2.

Run it again with `--hover-graph 300` — an empty cell, well before the seeded
week — and confirm the ring is legible against `palette.hairline` too, not just
against a filled square:

```bash
swift run PomodoroCount --preview /tmp/pomo-heat-empty.png --history-range Year --hover-graph 300
```

- [ ] **Step 4: Verify by hand**

```bash
just install
```

Open the panel, History, pick **Year**, and move the pointer across the grid.
Expected: the ring follows the pointer square by square, the readout names each
day, and the panel does not resize. If hover does not fire, apply the
`NSTrackingArea` fallback from Task 5 Step 5.

- [ ] **Step 5: Run the full suite**

```bash
just test
```

Expected: PASS, no regressions.

- [ ] **Step 6: Add the CHANGELOG entry**

Under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
### Added

- **The History graphs will tell you their numbers** — hover a bar in Week or
  Month, or a square in the Year heatmap, and the line under the graph names
  that day and its count. The other bars dim, or the square takes a ring, so
  it's clear which day you're reading. With nothing hovered the line shows the
  range's total. The heatmap needed this most: a day there is a four-point
  square whose only encoding was how dark it was.
```

- [ ] **Step 7: Commit**

```bash
git add Sources/PomodoroCount/Heatmap.swift Sources/PomodoroCount/HistoryTab.swift CHANGELOG.md
git commit -m "Ring the heatmap square under the pointer

The densest data in the app and the only view that couldn't be read: a
day is a ~4pt square encoded in opacity alone. The ring is drawn
expanded so it lands in the gap instead of eating the square it marks."
```

---

## Verification

After Task 6, the whole feature:

```bash
just test
```

```bash
swift run PomodoroCount --preview /tmp/pomo-all.png --history-range Year --hover-graph 360
```

By hand, after `just install`: hover the Week chart, the Month chart and the
Year heatmap; confirm the readout tracks, the highlight follows, leaving each
graph restores the range total, and switching range mid-hover clears the
highlight rather than stranding it.
