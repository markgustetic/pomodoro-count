# Hovering the History graphs

The two graphs in the History tab — the Week/Month bar chart and the Year
heatmap — answer "how much" only by eye. Hovering one names the day under the
pointer and prints its count in a readout line beneath the graph, with the
hovered bar or cell highlighted so the number and the mark are unambiguously
linked.

## Why

Every other number in History is written down. The list rows print their count
in a trailing column, the stat tiles print theirs in `.title3`. The two graphs
print nothing: the bar chart's y-axis has three gridlines and the heatmap has
no axis at all, so a cell is a shade of accent and nothing more.

That is tolerable for the week chart, where seven bars against three gridlines
can be read to within one. It fails completely for the year heatmap, where a
day is a ~4pt square whose only encoding is opacity — the difference between 3
and 5 pomodoros is 25% of an alpha channel on a square smaller than the
pointer's tip. The heatmap is the densest data in the app and the only view
that cannot be read at all.

## Scope

In: a hover readout and a hover highlight for the Week/Month bar chart and the
Year heatmap; the pure hit-testing and text-formatting behind them; a preview
flag so the hovered state renders headlessly.

Out:

- The stat tiles and the list rows. Both already print their numbers; a
  tooltip there would restate what is on screen.
- A floating tooltip card that follows the pointer. At the panel's 300pt a
  card wide enough to read "Jul 28 · 4 pomodoros" covers roughly a third of
  the graph, sitting on top of the bars being compared, and on 4pt heatmap
  cells it jitters as the pointer slides. See Alternatives.
- Click-to-pin the readout. Hover answers the question; a pinned state needs a
  dismiss affordance and a second thing for Escape to mean.
- Keyboard or VoiceOver traversal of individual days. The graphs keep their
  present summary-level accessibility values, and the list below already
  exposes every day's count as its own element.

## Interaction

At rest, the readout under the graph shows the visible range's total:

```
25 pomodoros in the last 7 days
38 pomodoros in the last 30 days
142 pomodoros in the last year
```

While the pointer is over a bar or a cell, it names that day instead:

```
Today · 4 pomodoros
Yesterday · 1 pomodoro
Jul 28 · 0 pomodoros
```

The day name comes from the existing `dayLabel(_:)`, so Today and Yesterday
read as words. Pluralisation matches the accessibility strings already in
`HistoryTab` — `count == 1 ? "pomodoro" : "pomodoros"` — which makes zero read
as "0 pomodoros" rather than a special case worth inventing wording for.

The readout is one line of `.caption`, `palette.textDim` at rest and
`palette.text` while hovering. **Its space is reserved in both states**, so the
panel never resizes as the pointer crosses the graph — `PanelTabScroller` sizes
the tab to its content's ideal height, and a readout that appears on hover
would grow the panel out from under the pointer that summoned it.

The highlight, so the readout can't be misread as describing some other day:

- **Bar chart:** the hovered bar keeps its full gradient; every other bar drops
  to 45% opacity. With nothing hovered, all bars are at full opacity.
- **Heatmap:** the hovered cell gets a 1pt stroke in `palette.text`, drawn
  expanded by 0.5pt so the ring lands in the 1pt gap between cells rather than
  eating into the 4pt cell it marks. An inset ring on a 4pt square leaves
  nothing to see.

Leaving the graph clears the hover and the readout returns to the range total.

## Architecture

### Pure logic, tested

Per the codebase's rule that tested logic is extracted from SwiftUI, all four
pieces below are pure functions with unit tests, and the views are thin over
them.

`HeatmapLayout` (existing, in `Heatmap.swift`) gains:

- `metrics(columns:size:) -> (cell: CGFloat, gap: CGFloat)` — the cell-size
  arithmetic currently inline in `HeatmapView`'s `Canvas` closure.
- `hitTest(_ point: CGPoint, cells:columns:size:) -> Int?` — the pointer's cell,
  or nil in a gap or outside the grid.

**Both must read their geometry from `metrics`.** That is the point of
extracting it: a hit test that recomputed the cell size independently could
drift from the draw loop and highlight a different square than the one the
readout names. `HeatmapView`'s draw loop is rewritten to call `metrics` too.

The returned index is an index into `cells`, which `cells(for:)` builds 1:1 and
in order from `stats` — so it is also the index into the `[DayStat]` the
readout formats from. A test pins that correspondence rather than leaving it to
the reader.

New `HistoryReadout` (new file, `Sources/PomodoroCount/HistoryReadout.swift`):

- `index(for date: Date, in series: [DayStat], calendar:) -> Int?` — snaps a
  date from `ChartProxy` to a day in the series.
- `text(hoveredIndex:series:days:) -> String` — the readout string, resting or
  hovered. The resting total is summed from `series`; `days` only picks the
  wording, and 365 is spelled "in the last year" while every other value is
  "in the last N days". An out-of-range index falls back to the resting text
  rather than trapping.

### Views

`HistoryTab` holds `@State private var hoveredIndex: Int?`, resets it when
`range` changes, and renders the readout beneath whichever graph is showing.

- **Chart:** `.chartOverlay { proxy in ... }` over a clear, `contentShape`d
  `Rectangle`, with `.onContinuousHover`. The pointer's x goes through
  `proxy.value(atX:as: Date.self)` — which accounts for the leading y-axis, so
  the plot area's inset is never hand-computed — and then through
  `HistoryReadout.index(for:in:)`. `.chartOverlay` rather than a `RuleMark`:
  on seven bars a rule reads as clutter, and the opacity drop already says
  which bar is live.
- **Heatmap:** `HeatmapView` takes `@Binding var hovered: Int?` and applies
  `.onContinuousHover` to the `Canvas`, routing the point through
  `HeatmapLayout.hitTest`.

Hover is a tracking area, not a gesture recognizer, so it is expected to work
in the non-activating panel where `List.onMove` and drag sessions do not — the
existing hover-reactive button styles are the precedent. **That is the one
assumption to verify by hand in the real panel before building on it**, and the
`ReorderHarness` rule applies: a success reproduced in the harness would not be
evidence.

### Preview

Two flags, parsed in `Entry.main` alongside `--hover`:

- `--hover-graph <index>` sets `PreviewOverrides.hoveredGraphIndex`, which the
  chart and the heatmap both honour as a forced hover.
- `--history-range <Week|Month|Year>` sets the History tab's initial range, so
  the heatmap can be rendered at all — today `--preview` only ever shows the
  Week chart, leaving the Year view with no headless coverage.

The preview seeds seven days of history, so a Year render is seven filled cells
among ~358 empty ones. That is enough to check the ring against both a filled
and an empty cell, which is what the flag is for.

## Testing

New unit tests in `Tests/PomodoroCountTests` (swift-testing), failing first:

- `HeatmapLayout.metrics` returns the same cell size the draw loop uses, for a
  full year and for a short series.
- `hitTest` finds the first, a middle, and the last cell from their centres;
  returns nil for a point in a gap, past the last column, and below the last
  row.
- A hit-test index addresses the same day in `stats` as in `cells`.
- `HistoryReadout.index(for:in:)`: exact match; a date before the series; a
  date after it; an empty series.
- `HistoryReadout.text`: resting text for 7 / 30 / 365 days; hovered text for
  today, yesterday, an older day, a count of 1, a count of 0; an out-of-range
  index falling back to resting.

Then, by hand in the real panel: hover the week chart and the year heatmap and
confirm the readout tracks and the panel does not resize. Headlessly:
`--preview` with `--hover-graph` at each range.

CHANGELOG gets an entry — this is user-visible.

## Alternatives considered

**A floating tooltip near the pointer.** The familiar form, and what was asked
for first. Rejected on measurement: 300pt of panel minus padding leaves ~276pt
of graph, and "Jul 28 · 4 pomodoros" at `.caption` is near 120pt — a card
covering 40% of the plot, anchored to a 4pt cell, moving as the pointer moves.
It obscures the comparison the hover exists to support.

**This rejection was overturned — see the amendment below.** The measurement
was sound but the premise wasn't: it priced a card carrying the readout line's
wording, and the wording was never fixed.

**A readout line with no highlight.** Simpler, and adequate for seven bars. It
fails on the heatmap: 53 columns of 4pt squares under a pointer whose hotspot
is bigger than a cell, with no mark saying which one was read.

**A `RuleMark` on the chart and no readout.** Charts-idiomatic and it does mark
the bar, but it carries no number unless annotated, and an annotation is the
floating card again — with the same width problem, in the same 300pt.

---

## Amendment — the readout line becomes a cursor tooltip

*2026-07-30, after the readout shipped on the branch and was looked at.*

The readout line under the graph is replaced by a small card floating at the
cursor. The hover plumbing, the hit test, the bar dimming and the heatmap ring
are all unchanged — this swaps the display, not the mechanism.

### Why the original rejection doesn't hold

The rejection above priced the wrong card. It costed "Jul 28 · 4 pomodoros" —
the readout line's wording, chosen for a line that had a whole 276pt row to
itself. A card doesn't need the noun: the pointer is over a graph of pomodoros
in an app about pomodoros, and the count is the only number on screen.

Dropping it changes the arithmetic that drove the decision:

| content | width at `.caption2` | share of the ~276pt plot |
|---|---|---|
| `Jul 28 · 4 pomodoros` | ~120pt | 40% |
| `Jul 28 · 4` | ~62pt | 22% |

22% is a different affordance from 40%. The objection was real and is now
answered by making the card smaller, not by deciding the objection was wrong.

### What it costs

The window total goes with the line. It only ever existed because a line whose
height must be reserved needs something to say when nothing is hovered; a card
that isn't shown needs nothing. Nothing else displayed it, so Month and Year
lose their only visible total. A third stat tile would restore it — deliberately
not built, because it wasn't wanted before the line invented the need.

### Placement

- **Horizontally:** centred on the cursor, clamped so the card never crosses
  the graph's edges. At 300pt of panel the clamp is load-bearing, not a
  formality — a card centred on the last heatmap column would otherwise leave
  the panel.
- **Vertically:** 10pt above the cursor, flipping to 10pt below when it would
  not fit above *within the graph's own bounds*. On the 108pt chart it sits
  above nearly always; on the 40pt heatmap it flips below nearly always. Both
  read correctly, and the rule is one sentence rather than two special cases.
- **Vertical position is not clamped.** A flipped card overlaps the stat tiles
  beneath, and that is correct — it floats. Clamping it back would park it under
  the pointer, hiding the square it describes.

`TooltipPlacement.origin(cursor:tooltip:in:)` owns all of that and is pure and
unit-tested, so the clamp and the flip are assertable rather than eyeballed —
the same split `HeatmapLayout` and `HistoryReadout` already follow.

### Rendering

An `.overlay` on the graph's container, `.allowsHitTesting(false)` so it can
never steal the hover that summons it. Two things it must not be:

- **Not a popover.** A popover is its own window; it would take key status from
  the panel and dismiss the very panel it floats over.
- **Not drawn inside the `Canvas`.** `Canvas` clips to its bounds — that is what
  clipped the highlight ring on every edge cell, and a card that flips below a
  40pt heatmap is entirely outside those bounds.

The card measures itself through a `PreferenceKey`, because placement needs its
width before it can be clamped. Sizing it by hand would drift the first time a
label ran from "Today" to "Wednesday".

### Headless verification

A render has no cursor, so `--hover-graph <n>` anchors the card to the hovered
item's geometric centre. That is what makes the clamp checkable at all: index 0
and the last column are exactly the cases a live pointer is least likely to
land on and most likely to break.
