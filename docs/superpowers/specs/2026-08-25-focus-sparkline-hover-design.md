# Hovering the Focus sparkline

The Focus tab's header card carries a seven-day sparkline — seven capsules in
78×22pt, above the streak flame. Hovering one names its day and prints its
count in a card at the pointer, and lights that bar while dimming the rest.

## Why

The sparkline is the only graph in the app that cannot be read. The History
tab's two graphs both answer "how much" on hover, and the list beneath them
prints every day's count in a trailing column. The sparkline prints nothing
and has no axis: a bar is a fraction of the strip's height against a peak that
is itself invisible, so the difference between 3 and 5 is a few points of
capsule on a shape 8.6pt wide.

That is the whole reason it earns a hover and the stat tiles don't. It is not
a smaller History chart — it is the one graph whose numbers exist nowhere else
on the tab it sits on.

## Scope

In: a cursor tooltip and a hover highlight for the Focus header's sparkline;
the pure hit-testing behind it; headless coverage through the existing
preview flag.

Out:

- Click-to-pin. Hover answers the question, and a pinned state needs a dismiss
  affordance and a second meaning for Escape.
- Per-day keyboard or VoiceOver traversal. The sparkline keeps its present
  summary-level `accessibilityValue` ("21 in the last 7 days, today 4"), and
  History's list already exposes each day as its own element.
- The sparkline's seven-day window, and anything in the History tab. This
  change reuses that tab's machinery; it does not touch it.

## Interaction

While the pointer is over the strip, a card at the pointer reads:

```
Today · 4
Yesterday · 1
Wed, Jul 29 · 0
```

Identical wording to the History graphs, because it is literally the same
function — `HistoryReadout.tooltip` exists so every graph phrases a day the
same way, and this is the third graph to use it. The nounless form matters
more here than there: the card floats inside a 272pt header card, not over a
276pt plot.

The highlight follows the History chart's rule. The hovered bar goes to full
opacity and **every** other bar drops to 0.40 — today included, losing its lit
state for the duration of the hover. Nothing is lost by that: the card names
the day outright, which is more than the "you are here" marker was saying.
Leaving the strip clears the hover and today lights again.

Hovering a zero-count day works. Its bar is a 3pt stub, so hit-testing is by
column across the full height of the strip rather than against the drawn
capsule — see below.

## Architecture

### Pure logic, tested

Per the codebase's rule that tested logic is extracted from SwiftUI, the hit
test is a pure function with unit tests and the view is thin over it.

New `SparklineLayout` (`Sources/PomodoroCount/SparklineLayout.swift`):

```swift
static func index(atX x: CGFloat, width: CGFloat, count: Int) -> Int?
```

It divides the strip into `count` equal columns and **ignores the 3pt gaps**,
so both the gaps and the 3pt stubs standing in for zero-count days are
hoverable. Hit-testing the drawn capsule instead would make a zero day
unreachable — which is precisely the value a reader is least able to guess by
eye — and would blink the card off in every gap the pointer crosses.

The columns therefore do not coincide exactly with the capsules: the HStack
spends 18pt of the 78 on gaps, so an equal-column edge sits within about 1.5pt
of the true capsule edge, worst case at the ends. That discrepancy is what
"nearest bar" means, not an error to correct.

Out-of-range `x` returns nil, as does a `count` of zero.

### Views

`Sparkline` (Styles.swift) takes `[DayStat]` instead of `[Int]`, so it has the
dates the single call site currently discards with `.map(\.count)`. Its
`spokenValue` summary is unchanged in wording.

**The hover state lives inside `Sparkline`** — `hoveredIndex`, `hoverPoint`,
and the measured `tooltipSize`, mirroring `HistoryTab`. Not on `RootView`:
that view hosts the countdown and the log rows, and pointer state there would
invalidate the whole Focus tab on every mouse move. The same reasoning that
split `SessionClock` out of `AppModel` applies to a 60Hz pointer.

Hover arrives through `.onContinuousHover`, a tracking area rather than a
gesture recognizer — which is why it works in the non-activating panel where
drag sessions do not. The History graphs are the standing precedent; this is
not a fresh assumption.

### Placing the card

The card is roughly 90pt wide at `.caption2` — wider than the 78pt strip
whatever the exact figure. That inversion breaks `TooltipPlacement.origin`
against the strip's own frame: its horizontal clamp is
`min(cursor.x - w/2, max(0, container.width - w))`, and with `container.width`
below `w` the second term is 0, so **the result is 0 for all seven bars**. The
card would sit at the strip's leading edge and never move, which is exactly
the one thing it must do — a card that doesn't track the pointer cannot say
which bar it describes. (It would land at panel x 196–286, flush with the
header card's trailing edge, so it does not leave the panel. The defect is the
frozen position, not spill.)

So the card is placed against the **header card** instead. `RootView`'s header
gets a named coordinate space; `Sparkline` reads its own offset within it,
calls `TooltipPlacement.origin` with the header's size, and subtracts that
offset to draw in its own overlay. Against 272pt the clamp becomes live again:
the card runs 142.6–232.6 under the first bar and 182–272 under the last,
tracking the pointer between them and staying inside the card both times. The card then draws outside the strip's
bounds, which is allowed for the same reason `HoverTooltip.swift` already
documents: the overlay is not clipped, which is what lets a History card flip
below a 40pt heatmap.

A **named** coordinate space, never `.local` — the reorder post-mortem's rule,
and here the same trap is available, since the card is an effect of the
pointer position it would be measured against.

`TooltipPlacement.origin`, `HoverTooltip`, and `HistoryReadout` are unchanged.

Vertically the existing rule prefers 10pt above the cursor, which fits, and
lands the card over the status badge. That is transient, and the pointer is
deliberately in that corner — but it is the one thing to look at in a render
before calling this done, and flipping to below is one parameter if it reads
badly.

### Preview

No new flag. `Sparkline` honours the existing
`PreviewOverrides.hoveredGraphIndex` (`--hover-graph <index>`) as a forced
hover, deriving a synthetic hover point at that column's centre and the
strip's mid-height — the same shape as `HistoryTab.effectiveHover`, without
the `ChartProxy` arithmetic, because equal columns need none.

`just preview` renders all three tabs into one PNG, so a single
`--hover-graph 3` lights the Focus card and the History card together. An
index past the seven-day series shows no card rather than trapping:
`--hover-graph 200` is a legitimate request for the Year heatmap.

## Testing

New `SparklineLayoutTests` (swift-testing), failing first:

- Each column's centre returns its own index, for `count` 7.
- A point at the midpoint of a drawn gap still returns a bar — the function is
  total over `[0, width)` — and the test pins which index, rather than
  accepting either neighbour.
- `x = 0` returns 0; `x` just inside `width` returns `count - 1`.
- Negative `x` and `x >= width` return nil.
- `count` of 0 returns nil; `count` of 1 returns 0 across the whole width.

And in `HistoryReadoutTests`, a case pinning that a seven-day series formats
identically to the History series, so the shared phrasing cannot drift apart
unnoticed.

Then headlessly: `--preview` with `--hover-graph` against a seeded store, to
check the card's placement against the header. And by hand in the real panel,
because that is the only place hover in a non-activating panel is finally
evidence.

CHANGELOG gets an entry — this is user-visible.

## Alternatives considered

**Native `.help()` on each capsule.** Two lines. Rejected on three counts: the
~1s delay makes a seven-bar strip tedious to read across, the system tooltip
ignores `Palette` entirely and would sit in Synthwave as a light-mode box, and
whether AppKit tooltips fire inside the non-activating panel would need
verifying before it could be relied on. The app already owns a themed hover
card; declining to use it here to save two lines is the wrong trade.

**Scrubbing the header text instead of a floating card.** While hovering, the
header's big count and its date line become the hovered day's. Cheapest of
all, occludes nothing, and reads naturally since those two elements are
already a count-and-day readout. Rejected because the big number is the app's
live state — the number the menu bar agrees with — and silently rewriting it
under the pointer invites reading a preview as a change.

**Hit-testing the drawn capsules.** More literally correct and worse in every
case that matters: zero days become unhoverable and the card blinks off in
each gap. Covered above.
