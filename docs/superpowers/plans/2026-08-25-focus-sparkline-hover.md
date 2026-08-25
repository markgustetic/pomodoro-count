# Focus Sparkline Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering the seven-day sparkline in the Focus tab's header names the
day under the pointer and prints its count in a card, lighting that bar.

**Architecture:** A new pure `SparklineLayout` does equal-column hit-testing;
`Sparkline` gains the hover state, a tracking overlay, and a card built from
the *existing* `HoverTooltip` / `TooltipPlacement` / `HistoryReadout.tooltip`
trio. The card is placed against the header card rather than the 78pt strip,
reached through a named coordinate space, because the card is wider than the
strip and clamping to the strip freezes it in place.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftPM, swift-testing (not XCTest),
macOS 14+.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-25-focus-sparkline-hover-design.md`.
  Read it before Task 1.
- Tests are **swift-testing** (`import Testing`, `@Suite`, `@Test`,
  `#expect`), in `Tests/PomodoroCountTests`. Never XCTest.
- **Failing test first**, then the minimal implementation. Tested logic is
  extracted from SwiftUI as a pure function; views are thin over it.
- **Comments record WHY and stay.** Decisions that look odd carry their
  reasoning in place. Do not strip existing comments.
- Every colour goes through `Palette`. This change introduces no new colours —
  `HoverTooltip` already handles its own palette.
- Commit subjects are short imperative sentences telling the story; bodies
  explain the why. Commit and push after each task.
- Run the suite with `just test` (it borrows Xcode's toolchain if the Command
  Line Tools are active). A single suite: `swift test --filter <SuiteName>`.
- Do not touch `HistoryTab.swift`, `Heatmap.swift`, `HoverTooltip.swift`, or
  `TooltipPlacement.swift`. This feature reuses them unchanged.
- The panel is a non-activating `NSPanel`. Hover is a tracking area, not a
  gesture, which is why it works here — but coordinate spaces must be
  **named**, never `.local`.

---

### Task 1: `SparklineLayout` — equal-column hit-testing

**Files:**
- Create: `Sources/PomodoroCount/SparklineLayout.swift`
- Test: `Tests/PomodoroCountTests/SparklineLayoutTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `SparklineLayout.index(atX: CGFloat, width: CGFloat, count: Int) -> Int?`
  - `SparklineLayout.centerX(ofColumn: Int, width: CGFloat, count: Int) -> CGFloat?`

Both are `static` on a caseless `enum`, matching `HeatmapLayout` and
`Reorder`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/SparklineLayoutTests.swift`:

```swift
import Testing
import Foundation
import CoreGraphics
@testable import PomodoroCount

/// The Focus header sparkline's column arithmetic. The numbers are the real
/// ones: a 78pt strip carrying seven days, drawn as 8.571pt capsules with
/// six 3pt gaps between them.
@Suite struct SparklineLayoutTests {

    private let width: CGFloat = 78
    private let count = 7

    @Test func eachColumnCentreFindsItsOwnBar() {
        for bar in 0..<count {
            let x = (CGFloat(bar) + 0.5) * (width / CGFloat(count))
            #expect(SparklineLayout.index(atX: x, width: width, count: count) == bar)
        }
    }

    /// 18 of the strip's 78pt are gap, and a zero-count day is a 3pt stub.
    /// A pointer in a gap must still name a bar, or the card blinks off
    /// between every pair of days and a day off is unreadable.
    ///
    /// The gap between bars 0 and 1 spans 8.571…11.571, so its midpoint is
    /// 10.071 — inside equal-column 0, which runs 0…11.143.
    @Test func aPointerInADrawnGapStillNamesABar() {
        #expect(SparklineLayout.index(atX: 10.071, width: width, count: count) == 0)
    }

    @Test func theLeadingEdgeIsTheFirstBar() {
        #expect(SparklineLayout.index(atX: 0, width: width, count: count) == 0)
    }

    @Test func theLastPointInsideTheStripIsTheLastBar() {
        #expect(SparklineLayout.index(atX: width - 0.001,
                                      width: width, count: count) == count - 1)
    }

    @Test func aPointerOutsideTheStripHoversNothing() {
        #expect(SparklineLayout.index(atX: -1, width: width, count: count) == nil)
        #expect(SparklineLayout.index(atX: width, width: width, count: count) == nil)
    }

    @Test func anEmptySeriesHoversNothing() {
        #expect(SparklineLayout.index(atX: 40, width: width, count: 0) == nil)
    }

    @Test func aStripWithNoWidthHoversNothing() {
        #expect(SparklineLayout.index(atX: 0, width: 0, count: count) == nil)
    }

    @Test func aSingleBarOwnsTheWholeStrip() {
        #expect(SparklineLayout.index(atX: 0, width: width, count: 1) == 0)
        #expect(SparklineLayout.index(atX: width - 0.001, width: width, count: 1) == 0)
    }

    /// The preview flag's forced hover has to land on the bar it names, or a
    /// headless render shows the card pointing at the wrong day — which is
    /// the one failure a render exists to catch and cannot report.
    @Test func aColumnCentreRoundTripsBackToItsOwnIndex() {
        for bar in 0..<count {
            let x = SparklineLayout.centerX(ofColumn: bar, width: width, count: count)
            #expect(x != nil)
            #expect(SparklineLayout.index(atX: x!, width: width, count: count) == bar)
        }
    }

    @Test func thereIsNoCentreForABarThatIsNotThere() {
        #expect(SparklineLayout.centerX(ofColumn: count, width: width, count: count) == nil)
        #expect(SparklineLayout.centerX(ofColumn: -1, width: width, count: count) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
just test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'SparklineLayout' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PomodoroCount/SparklineLayout.swift`:

```swift
import CoreGraphics

/// The Focus header sparkline's column arithmetic: which bar the pointer is
/// over, and where a bar sits when there is no pointer.
///
/// Pure and free of SwiftUI for the same reason `HeatmapLayout.hitTest` is —
/// a rendered strip isn't assertable, the arithmetic behind it is.
///
/// It deliberately **ignores the gaps the HStack draws**. The strip is 78pt
/// carrying seven capsules with six 3pt gaps, so 18pt of it — nearly a
/// quarter — is not capsule at all, and a zero-count day is a 3pt stub.
/// Hit-testing the drawn shape would make a day off unreachable, which is
/// exactly the value a reader cannot guess by eye, and would blink the card
/// off in every gap the pointer crossed. Equal columns put a boundary within
/// just over 1pt of the true capsule edge, worst case at the two ends and
/// exact in the middle; that is what "nearest bar" means, not an error.
enum SparklineLayout {

    /// The bar index under `x`, or nil outside the strip.
    static func index(atX x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0, x >= 0, x < width else { return nil }
        // The `min` guards the floating-point case where x/column rounds up
        // to `count` at the last representable x below `width`.
        return min(count - 1, Int(x / (width / CGFloat(count))))
    }

    /// The horizontal centre of a column, in the strip's coordinates —
    /// `index` run backwards.
    ///
    /// A headless render has no pointer, so this is where `--hover-graph`
    /// puts the tooltip. It derives the column width the same way `index`
    /// does, so the two cannot disagree about where a bar is; a round-trip
    /// test pins that.
    static func centerX(ofColumn index: Int, width: CGFloat, count: Int) -> CGFloat? {
        guard count > 0, width > 0, (0..<count).contains(index) else { return nil }
        return (CGFloat(index) + 0.5) * (width / CGFloat(count))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
just test 2>&1 | tail -20
```

Expected: the whole suite passes, `SparklineLayoutTests` included.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/SparklineLayout.swift Tests/PomodoroCountTests/SparklineLayoutTests.swift
git commit -m "$(cat <<'MSG'
Give the Focus sparkline a column hit test

Equal columns rather than the drawn capsules: 18 of the strip's 78pt are
gap and a zero-count day is a 3pt stub, so hit-testing the shape would make
a day off unhoverable and blink the card off between every pair of days.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
git push origin main
```

---

### Task 2: `Sparkline` carries days, not bare counts

**Files:**
- Modify: `Sources/PomodoroCount/Styles.swift:293-331` (the `Sparkline` struct)
- Modify: `Sources/PomodoroCount/RootView.swift:87-90` (the single call site)

**Interfaces:**
- Consumes: `DayStat` (existing, `Types.swift` — `let date: Date`, `let count: Int`).
- Produces: `Sparkline(days:accent:accent2:neon:)`. Task 3 adds two more
  parameters to this same initializer.

This task is mechanical and changes nothing a user can see. It exists on its
own so Task 3's diff is about hover and nothing else.

- [ ] **Step 1: Change the property and everything reading it**

In `Sources/PomodoroCount/Styles.swift`, replace `let values: [Int]` with
`let days: [DayStat]`, and update the two members that read it. Keep the
existing doc comments on the struct and on `spokenValue` verbatim.

```swift
struct Sparkline: View {
    let days: [DayStat]
    var accent: Color
    var accent2: Color
    var neon: Bool
    var height: CGFloat = 22

    /// The bars carry no information a screen reader can get at, so state the
    /// trend as one value instead of exposing seven unlabelled shapes.
    private var spokenValue: String {
        guard !days.isEmpty else { return "no data" }
        let total = days.reduce(0) { $0 + $1.count }
        return "\(total) in the last \(days.count) days, today \(days.last?.count ?? 0)"
    }

    var body: some View {
        let peak = max(1, days.map(\.count).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == days.count - 1
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent2],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(isToday ? 1.0 : 0.40)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(day.count) / CGFloat(peak) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .neonGlow(accent, enabled: neon, radius: 4, opacity: 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent activity")
        .accessibilityValue(spokenValue)
    }
}
```

- [ ] **Step 2: Update the call site**

In `Sources/PomodoroCount/RootView.swift`, the `Sparkline(...)` call inside
`header` becomes:

```swift
                Sparkline(days: model.dailySeries(days: 7),
                          accent: palette.accent,
                          accent2: palette.accent2,
                          neon: palette.neon)
                    .frame(width: 78)
```

- [ ] **Step 3: Verify it builds and the suite still passes**

```bash
just test 2>&1 | tail -20
```

Expected: PASS — but note that nothing in the suite constructs a `Sparkline`,
so a green run here only proves it still compiles. `spokenValue`'s wording is
guarded by review alone: it must come out of this task character-for-character
unchanged, because a screen reader is the only way the strip is readable at
all and this task is not the place to renegotiate that.

- [ ] **Step 4: Commit and push**

```bash
git add Sources/PomodoroCount/Styles.swift Sources/PomodoroCount/RootView.swift
git commit -m "$(cat <<'MSG'
Hand the sparkline whole days instead of counts

The call site already has [DayStat] and throws the dates away with
.map(\.count). A hover card has to name the day it is describing, so the
dates have to survive the trip.

No visible change: the bars, the ordering and the spoken summary are
identical.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
git push origin main
```

---

### Task 3: The hover card

**Files:**
- Modify: `Sources/PomodoroCount/Styles.swift` (the `Sparkline` struct)
- Modify: `Sources/PomodoroCount/RootView.swift` (the `header` property)
- Test: `Tests/PomodoroCountTests/HistoryReadoutTests.swift` (add one case)

**Interfaces:**
- Consumes: `SparklineLayout.index(atX:width:count:)` and
  `SparklineLayout.centerX(ofColumn:width:count:)` from Task 1;
  `Sparkline(days:...)` from Task 2. Plus, all pre-existing and unchanged:
  `HistoryReadout.tooltip(hoveredIndex:series:dayLabel:) -> String?`,
  `TooltipPlacement.origin(cursor:tooltip:in:offset:) -> CGPoint`,
  `HoverTooltip(text:)`, `TooltipSizeKey`,
  `PreviewOverrides.hoveredGraphIndex`, and `AppModel.dayLabel(_:)`.
- Produces: `Sparkline(days:accent:accent2:neon:dayLabel:tooltipContainer:)`
  and `Sparkline.headerSpace: String`.

- [ ] **Step 1: Write the failing test**

The card's wording is `HistoryReadout.tooltip`, already tested for the
History graphs. Add one case to
`Tests/PomodoroCountTests/HistoryReadoutTests.swift` pinning that a
seven-day Focus series phrases a day identically, so the two cannot drift
apart unnoticed. Add it inside the existing `@Suite`:

```swift
    /// The Focus sparkline formats through this same function, so all three
    /// graphs phrase a day identically. A seven-day series must read exactly
    /// as the History chart's does — no shorter form for the smaller strip.
    @Test func theFocusSparklineSeriesReadsLikeTheHistoryOne() {
        let day = Date(timeIntervalSince1970: 1_785_000_000)
        let week = (0..<7).map {
            DayStat(date: Calendar.current.date(byAdding: .day, value: -$0, to: day)!,
                    count: $0)
        }
        #expect(HistoryReadout.tooltip(hoveredIndex: 3, series: week,
                                       dayLabel: { _ in "Wed, Jul 29" })
                == "Wed, Jul 29 · 3")
    }
```

- [ ] **Step 2: Run it to confirm the suite is green before the view work**

```bash
swift test --filter HistoryReadoutTests 2>&1 | tail -10
```

Expected: PASS — this case is a regression fence around wording that already
exists, not a red-to-green step. If it fails, `HistoryReadout.tooltip` was
changed and must be put back.

- [ ] **Step 3: Add hover state and the tracker to `Sparkline`**

In `Sources/PomodoroCount/Styles.swift`, extend the struct. Two new
parameters, four new pieces of state, a tracker overlay, and the highlight
rule:

```swift
struct Sparkline: View {
    /// The header card is the container the hover card is placed against —
    /// see `tooltip`. Named, never `.local`: `.local` here is the 78pt strip,
    /// and the reorder post-mortem is about measuring in a frame your own
    /// effects move.
    static let headerSpace = "focusHeader"

    let days: [DayStat]
    var accent: Color
    var accent2: Color
    var neon: Bool
    var height: CGFloat = 22
    /// Names the hovered day. `AppModel.dayLabel`, so "Today" and "Yesterday"
    /// read as words here exactly as they do in History.
    var dayLabel: (Date) -> String
    /// The header card's size, in which the hover card is placed. The card is
    /// wider than the strip, so the strip cannot be its own container.
    var tooltipContainer: CGSize

    @State private var hoveredIndex: Int?
    @State private var hoverPoint: CGPoint?
    // Starts .zero and keeps the previous card's size across hovers, so a
    // newly-shown card lays out once at the wrong width before the preference
    // below lands. Invisible at 60Hz — not a bug.
    @State private var tooltipSize: CGSize = .zero

    /// The bars carry no information a screen reader can get at, so state the
    /// trend as one value instead of exposing seven unlabelled shapes.
    private var spokenValue: String {
        guard !days.isEmpty else { return "no data" }
        let total = days.reduce(0) { $0 + $1.count }
        return "\(total) in the last \(days.count) days, today \(days.last?.count ?? 0)"
    }

    /// The effective hover: a real pointer, or a preview's forced one.
    ///
    /// The forced index is range-checked here rather than left to the card.
    /// `--hover-graph` is shared with the History graphs, where 200 is a
    /// legitimate index into a year; unchecked, it would dim every bar on
    /// this seven-day strip with no card on screen to explain why.
    private var effectiveHover: Int? {
        if let hoveredIndex { return hoveredIndex }
        guard let forced = PreviewOverrides.hoveredGraphIndex,
              days.indices.contains(forced) else { return nil }
        return forced
    }

    var body: some View {
        let peak = max(1, days.map(\.count).max() ?? 1)
        let hovered = effectiveHover
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                // While hovering, only the hovered bar is lit — today gives up
                // its marker for the duration, the way the History chart's
                // bars do. Nothing is lost: the card names the day outright,
                // which is more than the marker was saying.
                let lit = hovered == nil ? index == days.count - 1 : hovered == index
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent2],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(lit ? 1.0 : 0.40)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(day.count) / CGFloat(peak) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .neonGlow(accent, enabled: neon, radius: 4, opacity: 0.45)
        // On top, not behind: a bar is hit-testable and would otherwise eat
        // the hover before the tracker saw it. Nothing here is clickable, so
        // covering the strip costs nothing.
        .overlay { hoverTracker }
        .overlay(alignment: .topLeading) { tooltip }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent activity")
        .accessibilityValue(spokenValue)
    }

    private var hoverTracker: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                // A tracking area, not a gesture — which is why this works in
                // the non-activating panel where drag sessions never start.
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoveredIndex = SparklineLayout.index(atX: point.x,
                                                             width: geo.size.width,
                                                             count: days.count)
                        hoverPoint = point
                    case .ended:
                        hoveredIndex = nil
                        hoverPoint = nil
                    }
                }
                // A render has no pointer, so a forced hover gets its column's
                // centre at mid-height. `onAppear` rather than a computed
                // value: writing state during layout is how SwiftUI gets an
                // update loop.
                .onAppear {
                    guard let forced = PreviewOverrides.hoveredGraphIndex,
                          let x = SparklineLayout.centerX(ofColumn: forced,
                                                          width: geo.size.width,
                                                          count: days.count)
                    else { return }
                    hoverPoint = CGPoint(x: x, y: geo.size.height / 2)
                }
        }
    }
```

- [ ] **Step 4: Add the card itself**

Still in `Sparkline`, directly after `hoverTracker`:

```swift
    /// The hover card, placed against the header rather than the strip.
    ///
    /// `TooltipPlacement.origin` clamps x to
    /// `min(cursor.x - w/2, max(0, container.width - w))`. The card is around
    /// 90pt and the strip is 78, so against the strip the second term is 0
    /// and the result is 0 for all seven bars — the card would sit at the
    /// leading edge and never move, which is the one thing it must do. (It
    /// would still be inside the panel, landing flush with the header card's
    /// trailing edge. The defect is the frozen position, not spill.) Against
    /// the header's 272pt the clamp is live again: the card runs 142.6–232.6
    /// under the first bar and 182–272 under the last.
    @ViewBuilder private var tooltip: some View {
        if let text = HistoryReadout.tooltip(hoveredIndex: effectiveHover,
                                             series: days, dayLabel: dayLabel),
           let cursor = hoverPoint {
            GeometryReader { geo in
                let strip = geo.frame(in: .named(Sparkline.headerSpace))
                let at = TooltipPlacement.origin(
                    cursor: CGPoint(x: strip.minX + cursor.x,
                                    y: strip.minY + cursor.y),
                    tooltip: tooltipSize,
                    in: tooltipContainer)
                HoverTooltip(text: text)
                    .background {
                        GeometryReader { card in
                            Color.clear.preference(key: TooltipSizeKey.self,
                                                   value: card.size)
                        }
                    }
                    // Back out of the header's coordinates into this overlay's,
                    // whose origin is the strip's top-left. The result is
                    // negative on both axes for most bars, which is fine — an
                    // overlay is not clipped, the same fact that lets a
                    // History card flip below a 40pt heatmap.
                    .offset(x: at.x - strip.minX, y: at.y - strip.minY)
            }
            .onPreferenceChange(TooltipSizeKey.self) { tooltipSize = $0 }
            // Never intercept the pointer: the card would fight the hover that
            // summons it.
            .allowsHitTesting(false)
        }
    }
}
```

- [ ] **Step 5: Wire up the header in `RootView`**

In `Sources/PomodoroCount/RootView.swift`, add the state property next to the
existing `@State private var tab: Tab`:

```swift
    @State private var headerSize: CGSize = .zero
```

Pass the two new parameters at the call site:

```swift
                Sparkline(days: model.dailySeries(days: 7),
                          accent: palette.accent,
                          accent2: palette.accent2,
                          neon: palette.neon,
                          dayLabel: model.dayLabel,
                          tooltipContainer: headerSize)
                    .frame(width: 78)
```

And give the header its coordinate space and a size probe. Replace the
modifier chain at the end of `header`:

```swift
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .cardBackground(cornerRadius: 14)
        // The sparkline's hover card is wider than the 78pt strip, so it is
        // placed against this card instead — see Sparkline.tooltip. Measured
        // rather than derived from the panel's 300pt, so a padding change
        // can't silently mis-clamp it.
        //
        // This is written on layout, never on a pointer move. The hover state
        // itself lives inside Sparkline precisely so that a 60Hz pointer does
        // not invalidate this view, which rebuilds dailySeries every pass.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { headerSize = geo.size }
                    .onChange(of: geo.size) { headerSize = geo.size }
            }
        }
        .coordinateSpace(name: Sparkline.headerSpace)
```

- [ ] **Step 6: Run the suite**

```bash
just test 2>&1 | tail -20
```

Expected: PASS, all suites.

- [ ] **Step 7: Verify headlessly that the card lands on the bar it names**

```bash
swift run PomodoroCount --preview /tmp/sparkline-hover.png --hover-graph 3 && open /tmp/sparkline-hover.png
```

Expected in the Focus tab's header card: bar 4 of 7 at full strength with the
other six dimmed, and a card near it reading a day name and a count. Check
three things and do not accept the render otherwise — a render that looks
plausible has been the expensive failure mode in this project before:

1. The card's horizontal centre is near the lit bar, not pinned to the
   strip's left edge. Pinned means `tooltipContainer` arrived as `.zero`.
2. The card is inside the header card's rounded rectangle.
3. The count on the card matches the lit bar's height against its neighbours.
4. **Where the card sits relative to the status badge.** The vertical rule
   prefers 10pt above the cursor, which puts the card over the badge. The spec
   accepts that as transient and expects it — but this render is the moment to
   look at it and say so. If it reads badly, flipping the card below is the
   `offset` argument to `TooltipPlacement.origin`, and that is a decision to
   raise rather than take silently.

Then confirm the shared flag still behaves at a History-scale index:

```bash
swift run PomodoroCount --preview /tmp/sparkline-year.png --hover-graph 200 --history-range Year && open /tmp/sparkline-year.png
```

Expected: the History heatmap shows its hovered cell as before, and the Focus
sparkline shows **no** card and **no** dimming — today still lit. A dimmed
strip with no card means the range guard in `effectiveHover` is missing.

- [ ] **Step 8: Commit and push**

```bash
git add Sources/PomodoroCount/Styles.swift Sources/PomodoroCount/RootView.swift Tests/PomodoroCountTests/HistoryReadoutTests.swift
git commit -m "$(cat <<'MSG'
Name the day under the pointer on the Focus sparkline

The sparkline was the only graph in the app whose numbers appear nowhere
else on its own tab — no axis, no list beneath it, 8.6pt bars against an
invisible peak. It now answers the same way the History graphs do, through
the same HoverTooltip, TooltipPlacement and HistoryReadout.tooltip, so all
three phrase a day identically.

The card is placed against the header card rather than the 78pt strip. The
strip is narrower than the card, which collapses TooltipPlacement's
horizontal clamp to a constant 0 and would freeze the card at the leading
edge for all seven bars.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
git push origin main
```

---

### Task 4: Changelog and verification in the real panel

**Files:**
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the finished feature from Task 3.
- Produces: nothing code depends on.

- [ ] **Step 1: Add the changelog entry**

`## [Unreleased]` currently holds only a `### Fixed` section. Keep a
Changelog orders Added before Fixed, so insert a new section above it:

```markdown
## [Unreleased]

### Added

- **Hover the seven-day graph on the Focus tab** to read a day off it. The bar
  under the pointer lights up and a card names the day and its count — the
  same readout the History tab's graphs already give you.

### Fixed
```

- [ ] **Step 2: Install the build and check it by hand**

```bash
just install
```

Then open the panel and, on the Focus tab, sweep the pointer across the
sparkline. Confirm:

1. The card appears and **tracks the pointer** across all seven bars.
2. It names each day correctly — the rightmost bar reads "Today", the one
   before it "Yesterday".
3. It stays inside the header card at both ends of the sweep.
4. Only the bar under the pointer is lit; leaving the strip relights today.
5. A day with zero pomodoros — a 3pt stub — is hoverable and reads "· 0".
6. The panel does not resize or flicker as the card appears.

This is the gate the automated checks cannot stand in for. Hover in the
non-activating panel is well-precedented by the History graphs, so it is
expected to work — but the `ReorderHarness` rule holds for anything
synthetic, and this is the only place a success counts as evidence.

- [ ] **Step 3: Commit and push**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'MSG'
Note the Focus sparkline hover in the changelog

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
git push origin main
```
