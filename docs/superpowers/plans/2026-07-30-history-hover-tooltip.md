# History Hover Tooltip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the History graphs' readout line with a small card floating at the cursor, showing the hovered day and its count.

**Architecture:** The hover plumbing already exists and does not change — `.onContinuousHover`, `HeatmapLayout.hitTest`, `HistoryReadout.index`, the bar dimming and the heatmap ring all stay. What changes is the display: the reserved line under the graph goes away, and both graphs gain an `.overlay` carrying a `HoverTooltip` card positioned by a new pure `TooltipPlacement`. Two more pure functions carry the parts that are easy to get subtly wrong — clamping/flipping the card, and finding a cell's centre so a cursor-less headless render still has somewhere to put it.

**Tech Stack:** Swift Package Manager, SwiftUI + Swift Charts, `Canvas`, swift-testing.

**Spec:** `docs/superpowers/specs/2026-07-30-history-hover-readout-design.md` — read the **Amendment** section at the end; the body describes the readout line this plan removes.

## Global Constraints

- macOS 14+ (`Package.swift` declares `.macOS(.v14)`).
- Tests are **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — never XCTest.
- Every colour comes from `palette` (`Theme.swift`). No `Color.red`, `.primary`, system colours, or system materials (`.ultraThinMaterial` and friends are as forbidden as `Color.red` — they can't be themed).
- Comments record **why**, in place, and stay. Do not strip existing ones.
- Commit subjects are short imperative sentences that tell the story; bodies explain the why.
- The tooltip card must be an `.overlay`, never a popover (a popover is its own window and would dismiss the panel it floats over) and never drawn inside the `Canvas` (which clips — that is what clipped the highlight ring on every edge cell).
- The card is `.allowsHitTesting(false)`. A card that intercepts the pointer would fight the hover that summons it.
- Panel is 300pt wide; the graph container is ~276pt. Chart is 108pt tall, heatmap 40pt.
- Baseline entering this plan: **346 tests in 32 suites**, all passing. Several pre-existing tests deliberately exercise an unreadable-store path and print `data.json failed to decode; original bytes kept in ...` to stderr — expected output, not noise.
- Full suite: `just test`. Single suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <SuiteName>`.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/PomodoroCount/HoverTooltip.swift` (create) | `TooltipPlacement` (pure placement) and the `HoverTooltip` card view |
| `Sources/PomodoroCount/Heatmap.swift` (modify) | `HeatmapLayout.center(of:)`; `HeatmapView` reports the cursor point |
| `Sources/PomodoroCount/HistoryReadout.swift` (modify) | `tooltip(...)` replaces `text(...)` |
| `Sources/PomodoroCount/HistoryTab.swift` (modify) | Cursor state, tooltip overlay; the readout line is removed |
| `Tests/PomodoroCountTests/TooltipPlacementTests.swift` (create) | Clamp and flip cases |
| `Tests/PomodoroCountTests/HeatmapTests.swift` (modify) | `center(of:)` incl. round-trip with `hitTest` |
| `Tests/PomodoroCountTests/HistoryReadoutTests.swift` (modify) | Tooltip wording; resting-total tests deleted |
| `AGENTS.md`, `CHANGELOG.md` (modify) | Tested-logic list; the user-visible entry |

---

### Task 1: Where the card goes

**Files:**
- Create: `Sources/PomodoroCount/HoverTooltip.swift`
- Test: `Tests/PomodoroCountTests/TooltipPlacementTests.swift`

**Interfaces:**
- Produces: `TooltipPlacement.origin(cursor: CGPoint, tooltip: CGSize, in container: CGSize, offset: CGFloat = 10) -> CGPoint`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/TooltipPlacementTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// Where the hover card lands. The numbers below are the real ones: a ~276pt
/// graph inside a 300pt panel, a 108pt chart and a 40pt heatmap, and a card
/// about 62x18 carrying "Jul 28 · 4".
@Suite struct TooltipPlacementTests {

    private let card = CGSize(width: 62, height: 18)
    private let chart = CGSize(width: 276, height: 108)
    private let heatmap = CGSize(width: 276, height: 40)

    @Test func theCardCentresOnTheCursor() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.x == 100 - 31)
    }

    @Test func theCardSitsAboveTheCursorWhenThereIsRoom() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.y == 60 - 10 - 18)
    }

    /// The 40pt heatmap almost never has room above, so the flip is the common
    /// case there rather than an edge case.
    @Test func theCardFlipsBelowWhenItWouldNotFitAbove() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 20),
                                        tooltip: card, in: heatmap)
        #expect(p.y == 20 + 10)
    }

    @Test func theCardClampsAtTheLeftEdge() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 5, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.x == 0)
    }

    /// The load-bearing one: a card centred on the last heatmap column would
    /// otherwise leave the panel entirely.
    @Test func theCardClampsAtTheRightEdge() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 274, y: 60),
                                        tooltip: card, in: chart)
        #expect(p.x == 276 - 62)
        #expect(p.x + card.width <= chart.width)
    }

    @Test func aCardWiderThanItsContainerPinsToTheLeadingEdge() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 60),
                                        tooltip: CGSize(width: 300, height: 18), in: chart)
        #expect(p.x == 0)
    }

    /// A flipped card is allowed to overhang: the overlay drawing it isn't
    /// clipped, and pulling it back inside would park it under the pointer.
    @Test func aFlippedCardMayOverhangTheContainer() {
        let p = TooltipPlacement.origin(cursor: CGPoint(x: 100, y: 20),
                                        tooltip: card, in: heatmap)
        #expect(p.y + card.height > heatmap.height)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TooltipPlacementTests
```

Expected: compile error — `cannot find 'TooltipPlacement' in scope`.

- [ ] **Step 3: Create the file**

Create `Sources/PomodoroCount/HoverTooltip.swift`:

```swift
import SwiftUI

/// Where a hover tooltip's card goes, given the cursor and the space available.
///
/// Pure and free of SwiftUI for the same reason `HeatmapLayout.cells` is: at a
/// 300pt panel the horizontal clamp is load-bearing rather than a formality —
/// a card centred on the last heatmap column would leave the window — and the
/// edges where it matters are exactly the ones a pointer is least likely to
/// land on while someone checks by hand.
enum TooltipPlacement {

    /// The card's top-left corner, in the container's coordinate space.
    ///
    /// Horizontally the card centres on the cursor and clamps to the
    /// container. Vertically it prefers `offset` above the cursor and flips to
    /// `offset` below when it would not fit above — which on the 108pt chart
    /// is nearly never and on the 40pt heatmap is nearly always.
    ///
    /// The vertical result is deliberately **not** clamped. A flipped card
    /// overhangs the graph and covers the tiles beneath, and that is correct:
    /// the overlay drawing it isn't clipped, and pulling it back inside would
    /// park it under the pointer, hiding the square it describes.
    static func origin(cursor: CGPoint, tooltip: CGSize, in container: CGSize,
                       offset: CGFloat = 10) -> CGPoint {
        // The second `max(0,)` is what keeps a card wider than its container
        // pinned to the leading edge instead of being pushed off to the left.
        let x = min(max(0, cursor.x - tooltip.width / 2),
                    max(0, container.width - tooltip.width))
        let above = cursor.y - offset - tooltip.height
        return CGPoint(x: x, y: above >= 0 ? above : cursor.y + offset)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TooltipPlacementTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PomodoroCount/HoverTooltip.swift Tests/PomodoroCountTests/TooltipPlacementTests.swift
git commit -F <message file>
```

Message:

```
Work out where a hover card can sit

Centred on the cursor, clamped to the graph, above unless there's no
room above. At 300pt the clamp is the whole game — a card centred on the
last heatmap column leaves the panel — and that edge is the one nobody
hits while checking by hand, so it gets a test instead.
```

---

### Task 2: The centre of a heatmap cell

A headless render has no cursor, so `--hover-graph <n>` needs somewhere to put
the card. This is also the inverse of `hitTest`, which makes a round-trip test
possible — the strongest check available on this geometry.

**Files:**
- Modify: `Sources/PomodoroCount/Heatmap.swift` (add to `HeatmapLayout`)
- Test: `Tests/PomodoroCountTests/HeatmapTests.swift`

**Interfaces:**
- Consumes: `HeatmapLayout.metrics(columns:size:) -> (cell: CGFloat, gap: CGFloat, origin: CGPoint)`, `HeatmapLayout.hitTest(_:cells:columns:size:) -> Int?`
- Produces: `HeatmapLayout.center(of index: Int, cells: [HeatmapCell], columns: Int, size: CGSize) -> CGPoint?`

- [ ] **Step 1: Write the failing tests**

Add to `struct HeatmapTests` in `Tests/PomodoroCountTests/HeatmapTests.swift`. The suite already has `canvas`, `week(startingMonday:)`, `mondayFirst` and `centre(column:row:columns:)` helpers — use them.

```swift
    /// `center` is `hitTest` run backwards, so the strongest check is that the
    /// round trip closes: the point a cell reports must hit that same cell.
    @Test func aCellsCentreHitsThatCell() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        for index in [0, 7, 9, 13] {
            let point = HeatmapLayout.center(of: index, cells: cells, columns: 2, size: canvas)
            #expect(point != nil)
            #expect(HeatmapLayout.hitTest(point!, cells: cells, columns: 2, size: canvas) == index)
        }
    }

    /// It must agree with the test helper that derives centres independently,
    /// or one of the two is lying about where the grid is.
    @Test func aCellsCentreMatchesTheGridArithmetic() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 14), calendar: mondayFirst)
        let point = HeatmapLayout.center(of: 9, cells: cells, columns: 2, size: canvas)
        let expected = centre(column: 1, row: 2, columns: 2)
        #expect(abs(point!.x - expected.x) < 0.001)
        #expect(abs(point!.y - expected.y) < 0.001)
    }

    @Test func anIndexOutsideTheCellsHasNoCentre() {
        let cells = HeatmapLayout.cells(for: week(startingMonday: 3), calendar: mondayFirst)
        #expect(HeatmapLayout.center(of: 9, cells: cells, columns: 1, size: canvas) == nil)
        #expect(HeatmapLayout.center(of: -1, cells: cells, columns: 1, size: canvas) == nil)
    }
```

Note: the existing `centre(column:row:columns:)` helper must already account for `metrics`' `origin`. If it does not, that is a pre-existing bug in the helper — fix it and say so in your report.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeatmapTests
```

Expected: compile error — `type 'HeatmapLayout' has no member 'center'`.

- [ ] **Step 3: Implement `center(of:)`**

Add inside `enum HeatmapLayout`, immediately after `hitTest`:

```swift
    /// The centre of a cell, in canvas coordinates — `hitTest` run backwards.
    ///
    /// A headless render has no pointer, so this is where `--hover-graph` puts
    /// the tooltip. Reads the same `metrics` as the draw loop and the hit
    /// test, so all three agree about where a square is; a round-trip test
    /// pins that.
    static func center(of index: Int, cells: [HeatmapCell],
                       columns: Int, size: CGSize) -> CGPoint? {
        guard cells.indices.contains(index) else { return nil }
        let (cell, gap, origin) = metrics(columns: columns, size: size)
        guard cell > 0 else { return nil }
        let step = cell + gap
        return CGPoint(x: origin.x + CGFloat(cells[index].column) * step + cell / 2,
                       y: origin.y + CGFloat(cells[index].row) * step + cell / 2)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeatmapTests
```

Expected: PASS, including all pre-existing cases.

- [ ] **Step 5: Commit**

Message:

```
Give a heatmap cell a centre to point at

hitTest run backwards, sharing the same metrics so all three agree
about where a square is. A headless render has no pointer, and this is
where --hover-graph puts the card; the round-trip test is the strongest
check this geometry admits.
```

---

### Task 3: The card's wording

**Files:**
- Modify: `Sources/PomodoroCount/HistoryReadout.swift`
- Test: `Tests/PomodoroCountTests/HistoryReadoutTests.swift`

**Interfaces:**
- Produces: `HistoryReadout.tooltip(hoveredIndex: Int?, series: [DayStat], dayLabel: (Date) -> String) -> String?`
- `text(...)` and `index(...)` are both untouched here. `text` still has a live call site in `HistoryTab`, and Task 4 removes it once the view stops calling it — so this task adds, and nothing in the package breaks.

- [ ] **Step 1: Write the failing tests**

Add to `struct HistoryReadoutTests` in `Tests/PomodoroCountTests/HistoryReadoutTests.swift`, alongside the existing tests (leave all ten of them in place — Task 4 retires the obsolete ones):

```swift
    /// No noun: at 300pt "Jun 2 · 5 pomodoros" is twice the width of
    /// "Jun 2 · 5", and that difference is what makes a floating card viable
    /// here instead of a line with a whole row to itself.
    @Test func theTooltipNamesTheDayAndItsCount() {
        #expect(HistoryReadout.tooltip(hoveredIndex: 1, series: series([3, 5, 2]),
                                       dayLabel: stub) == "Jun 2 · 5")
    }

    /// A day off is a real answer — the heatmap draws those cells, so hovering
    /// one has to say something.
    @Test func theTooltipStillReadsOnADayOff() {
        #expect(HistoryReadout.tooltip(hoveredIndex: 0, series: series([0]),
                                       dayLabel: stub) == "Jun 1 · 0")
    }

    @Test func nothingHoveredIsNoTooltip() {
        #expect(HistoryReadout.tooltip(hoveredIndex: nil, series: series([3, 5]),
                                       dayLabel: stub) == nil)
    }

    /// The range picker swaps the series out from under a live pointer. A
    /// stale index has to read as no hover, not trap.
    @Test func anOutOfRangeIndexIsNoTooltip() {
        #expect(HistoryReadout.tooltip(hoveredIndex: 9, series: series([3, 5]),
                                       dayLabel: stub) == nil)
    }
```

The three `index(for:in:)` tests and the `series(_:)` / `stub(_:)` helpers stay exactly as they are.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HistoryReadoutTests
```

Expected: compile error — `type 'HistoryReadout' has no member 'tooltip'`.

- [ ] **Step 3: Add `tooltip`**

In `Sources/PomodoroCount/HistoryReadout.swift`, add below `text(...)` — leaving `text` and `pomodoros(_:)` in place for now, since `HistoryTab` still calls `text` until Task 4:

```swift
    /// The tooltip's line, or nil when nothing is hovered.
    ///
    /// No noun. The card floats over a graph of pomodoros in an app about
    /// pomodoros, and at 300pt of panel "Jul 28 · 4 pomodoros" is twice the
    /// width of "Jul 28 · 4" — 40% of the plot against 22% of it. That is the
    /// difference between a card that obscures the comparison it explains and
    /// one that doesn't, which is why the noun is gone and should stay gone.
    ///
    /// An out-of-range index reads as no hover rather than trapping — the
    /// range picker swaps the series under a live pointer, and a stale index
    /// must not take the panel down with it.
    static func tooltip(hoveredIndex: Int?, series: [DayStat],
                        dayLabel: (Date) -> String) -> String? {
        guard let i = hoveredIndex, series.indices.contains(i) else { return nil }
        return "\(dayLabel(series[i].date)) · \(series[i].count)"
    }
```

The `·` is U+00B7 MIDDLE DOT. Copy it, don't retype it.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HistoryReadoutTests
```

Expected: PASS, 14 tests (the 10 that were there, plus your 4).

- [ ] **Step 5: Commit**

Message:

```
Drop the noun from the hover text

"Jul 28 · 4 pomodoros" was written for a line with a whole row to
itself. A card at the cursor is priced differently: the noun is half the
width, and half the width is the difference between covering 40% of the
plot and 22%. The window total goes too — it only existed to give a
reserved line something to say at rest.
```

---

### Task 4: The card itself

**Files:**
- Modify: `Sources/PomodoroCount/HoverTooltip.swift` (add the view)
- Modify: `Sources/PomodoroCount/HistoryTab.swift`
- Modify: `Sources/PomodoroCount/Heatmap.swift` (`HeatmapView`)
- Modify: `AGENTS.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `TooltipPlacement.origin` (Task 1), `HeatmapLayout.center(of:)` (Task 2), `HistoryReadout.tooltip` (Task 3)
- Produces: `HoverTooltip(text:)`, `TooltipSizeKey`; `HeatmapView(stats:hovered:hoverPoint:)`

- [ ] **Step 1: Add the card view**

Append to `Sources/PomodoroCount/HoverTooltip.swift`:

```swift
/// The hover card: one line, sized by its content.
///
/// Backed by `bgBottom` *under* `cardFill` so it is opaque whatever alpha the
/// theme gives the fill — a card you can read the graph through defeats the
/// point of putting it in front of the graph.
struct HoverTooltip: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.bgBottom)
                    .overlay { RoundedRectangle(cornerRadius: 6).fill(palette.cardFill) }
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(palette.cardStroke) }
            }
            .fixedSize()
    }
}

/// Reports the card's measured size back up so `TooltipPlacement` can clamp it.
/// Measured rather than hand-set because the label runs from "Today" to
/// "Wednesday" and a fixed width would clamp the wrong edge for one of them.
struct TooltipSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
```

- [ ] **Step 2: Have the heatmap report the cursor**

In `Sources/PomodoroCount/Heatmap.swift`, add below `@Binding var hovered: Int?`:

```swift
    @Binding var hoverPoint: CGPoint?
```

In the `.onContinuousHover` handler, set both bindings — `.active` stores the point, `.ended` clears it alongside `hovered`.

Then, inside the `GeometryReader` (so `geo.size` is in scope), attach to the `Canvas`:

```swift
            // A render has no pointer, so a forced hover gets the cell's own
            // centre. `onAppear` rather than a computed value: writing state
            // during layout is how SwiftUI gets an update loop.
            .onAppear {
                if let forced = PreviewOverrides.hoveredGraphIndex {
                    hoverPoint = HeatmapLayout.center(of: forced, cells: cells,
                                                      columns: columns, size: geo.size)
                }
            }
```

- [ ] **Step 3: Wire the tab**

In `Sources/PomodoroCount/HistoryTab.swift`:

Add beside `hoveredIndex`:

```swift
    @State private var hoverPoint: CGPoint?
    @State private var tooltipSize: CGSize = .zero
```

Replace the graph block and the readout call:

```swift
            if range == .year {
                HeatmapView(stats: series, hovered: $hoveredIndex)
            } else {
                chart(series)
            }
            readout(series)
```

with:

```swift
            // A year of daily bars is texture pretending to be data; the
            // heatmap grid is the honest form at that scale.
            Group {
                if range == .year {
                    HeatmapView(stats: series, hovered: $hoveredIndex,
                                hoverPoint: $hoverPoint)
                } else {
                    chart(series)
                }
            }
            // On the graph's own container, so the card's coordinates and the
            // cursor's are the same space. Not inside the Canvas — that clips,
            // and a card flipped below a 40pt heatmap is entirely outside it.
            .overlay(alignment: .topLeading) { tooltip(series) }
```

> The existing "A year of daily bars…" comment moves onto the `Group` — do not drop it.

Delete `readout(_:)` entirely and add in its place:

```swift
    @ViewBuilder private func tooltip(_ series: [DayStat]) -> some View {
        if let text = HistoryReadout.tooltip(hoveredIndex: effectiveHover,
                                             series: series, dayLabel: model.dayLabel),
           let cursor = hoverPoint {
            GeometryReader { geo in
                let at = TooltipPlacement.origin(cursor: cursor, tooltip: tooltipSize,
                                                 in: geo.size)
                HoverTooltip(text: text)
                    .background {
                        GeometryReader { card in
                            Color.clear.preference(key: TooltipSizeKey.self, value: card.size)
                        }
                    }
                    .offset(x: at.x, y: at.y)
            }
            .onPreferenceChange(TooltipSizeKey.self) { tooltipSize = $0 }
            // Never intercept the pointer: the card would fight the hover that
            // summons it.
            .allowsHitTesting(false)
        }
    }
```

Update the range-change reset to clear the point too:

```swift
            .onChange(of: range) { hoveredIndex = nil; hoverPoint = nil }
```

- [ ] **Step 4: Have the chart report the cursor**

In `chart(_:)`'s `.onContinuousHover` handler, store `point` into `hoverPoint` on `.active` (on every guard-failure path set it to nil alongside `hoveredIndex`), and clear it on `.ended`.

Then attach to the `Rectangle` inside `chartOverlay`'s `GeometryReader`:

```swift
                    .onAppear {
                        // Same reason as the heatmap: a render has no pointer.
                        // The bar's own x, at mid-height of the plot.
                        guard let forced = PreviewOverrides.hoveredGraphIndex,
                              series.indices.contains(forced),
                              let plot = proxy.plotFrame,
                              let x = proxy.position(forX: series[forced].date)
                        else { return }
                        hoverPoint = CGPoint(x: geo[plot].origin.x + x,
                                             y: geo[plot].midY)
                    }
```

- [ ] **Step 5: Retire the readout's text**

Nothing calls `HistoryReadout.text` once Step 3 lands. Remove it, its private `pomodoros(_:)` helper, and the seven tests that pin behavior no longer on screen:

- `restingTextTotalsTheWindow`
- `oneIsSingularInTheTotalToo`
- `aYearIsSpelledAsAYear`
- `hoverNamesTheDayAndItsCount`
- `oneIsSingular`
- `aDayOffStillReads`
- `anOutOfRangeIndexFallsBackToTheTotal`

Keep the three `index(for:in:)` tests and the `series(_:)` / `stub(_:)` helpers. Also update `HistoryReadout`'s type doc comment — it says "the line of text that names it", describing the line this plan removes.

Do this as a step of its own so the deletion is legible in the diff rather than buried in the view work.

- [ ] **Step 6: Run the full suite**

```bash
just test
```

Expected: PASS. Arithmetic: 346 baseline + 7 (Task 1) + 3 (Task 2) + 4 (Task 3) − 7 (deleted just now) = **353**. Report the actual number; if it differs, say why before continuing.

- [ ] **Step 7: Verify headlessly, and look at every render**

```bash
swift run PomodoroCount --preview /tmp/tip-chart.png --hover-graph 5
swift run PomodoroCount --preview /tmp/tip-year.png --history-range Year --hover-graph 360
swift run PomodoroCount --preview /tmp/tip-left.png --history-range Year --hover-graph 3
swift run PomodoroCount --preview /tmp/tip-right.png --history-range Year --hover-graph 364
```

The render is 1944x1666, three panels side by side; the History panel is the middle one and the heatmap sits roughly at left 690, top 200, width 620, height 220. **Crop and upscale** (`sips -c <h> <w> --cropOffset <top> <left>`, then `sips -Z 1800`) — the card is small.

Confirm, for each:

- `tip-chart` — card reads `Yesterday · 1`, sits **above** the bar (the chart has room), one bar lit and six dimmed.
- `tip-year` — card reads `Sun, Jul 26 · 2`, sits **below** the cell (the 40pt heatmap has no room above), ring still visible on the cell.
- `tip-left` — card does not run off the **left** edge of the panel.
- `tip-right` — card does not run off the **right** edge of the panel. This is the case the clamp exists for; index 364 is the last column.
- In all four: the card is **opaque** — no grid squares or bars showing through it. If anything reads through, report it rather than working around it.

- [ ] **Step 8: Update the docs**

In `AGENTS.md`, the "Tested logic is extracted from SwiftUI" list currently names `HeatmapLayout.hitTest` and `HistoryReadout.text`. Rename the latter to `HistoryReadout.tooltip` and add `TooltipPlacement.origin`. Change nothing else.

In `CHANGELOG.md`, the `## [Unreleased]` entry describes a readout line that no longer exists. Rewrite that bullet to describe the tooltip — keep the existing bold-lead-in style, keep the bar dimming and the heatmap ring (both still true), drop the range-total sentence, and say the count now appears in a small card at the pointer.

- [ ] **Step 9: Commit**

Message:

```
Put the count in a card at the pointer

The line under the graph made you look away from the square you were
asking about. The card goes where you're already looking, clamped so it
can't leave a 300pt panel and flipped below the cursor when a 40pt
heatmap leaves no room above.
```

---

## Verification

```bash
just test
```

By hand, after `just dev` — still outstanding from the previous plan and now covering this one too:

1. Hover the Week chart: the card tracks the pointer and sits above it; other bars dim.
2. Hover the Year heatmap: the card tracks and sits below; the ring follows.
3. Sweep to both ends of the heatmap: the card never leaves the panel.
4. Roll the scroll wheel over the chart: the tab still scrolls.
5. Leave the graph: the card disappears.
