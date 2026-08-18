# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Pause when the screen locks**, a new setting on the Settings tab. Off by
  default — turn it on if you'd rather the timer meant time at this Mac, and a
  running session will stop when the screen locks or the displays sleep.

### Changed

- **The timer no longer stops when your screen locks.** Locking the Mac or
  letting the displays sleep used to pause a running session. It doesn't
  any more — a pomodoro you're running while away from this keyboard is
  exactly the kind this app is built to count. If you'd rather the timer
  meant time at this Mac, **Pause when the screen locks** in Settings brings
  the old behaviour back.
- **A new day starts on focus.** Leave the app overnight with a break waiting
  or running and it used to still be on that break in the morning, counting
  yesterday's sessions towards the next long one. When the date changes the
  timer now drops back to a fresh focus session, and the every-fourth-session
  rhythm starts over. A focus session actually running at midnight is left
  alone — it's about to become a record.

## [1.4.0] - 2026-07-31

### Added

- **The History graphs will tell you their numbers** — hover a bar in Week or
  Month, or a square in the Year heatmap, and a small card at the pointer
  names that day and its count. The other bars dim, or the square takes a
  ring, so it's clear which day you're reading. The heatmap needed this most:
  a day there is a four-point square whose only encoding was how dark it was.

### Changed

- **The app is signed and notarized, so it just opens.** Releases now carry an
  Apple Developer ID signature and a notarization ticket from Apple. The
  first-launch warning is gone, and with it the right-click → **Open** dance and
  the `xattr -dr com.apple.quarantine` workaround. Homebrew no longer needs
  `--no-quarantine` — plain
  `brew install --cask markgustetic/tap/pomodoro-count` is now the way.
  Updating from an earlier version happens as usual; nothing to reinstall.
- **The category list is now a priority ranking.** When a category meets its
  daily goal the session target falls to the highest-ranked category that still
  has a goal left, rather than to whichever one happens to sit below it. Each new
  day starts at the top of the list again.
- **Re-picking a finished category now holds there.** Pointing the target at a
  category you have already completed keeps it there for as many pomodoros as
  follow, instead of moving on after one — the target line under the countdown
  reads `pinned to …` while it does. Picking a category that still has a goal
  left holds the same way it always did, and when you finish it, it now hands to
  the top of the list.
- The Settings toggle "Move on when a goal is met" is now "Follow the category
  order". Your existing setting is kept.
- **Click a category on the Focus tab to send finished pomodoros there.** The
  target dropdown is gone — it listed the same categories as the rows below it,
  without the counts that make one worth picking. The line it occupied still
  says where pomodoros are going.
- Clicking the category you're already pinned to hands control back to the
  category order, instead of holding there for another pomodoro.
- **Adjusting a category's count for today moved to a `±` at the right of each
  row,** so the row itself is free to aim the target instead. A count can come
  down as well as up, so correcting a mis-tap no longer means reaching for
  "Undo last" and hoping nothing has landed on another category since — and
  VoiceOver's one-swipe adjustment now lives there too, not on the row.
- The target row now stays outlined while the timer is idle or paused, not only
  while a session runs, so you can see what you picked before pressing Start.

### Fixed

- **Clicking a notification now opens the app you already have running,** rather
  than starting a second copy of it. The click never reached the running app at
  all: it asked macOS to open Pomodoro Count by name, and if more than one copy
  was on the machine — an installed one, a downloaded one, a build — macOS was
  free to start whichever it liked. Two copies then shared one history file and
  took turns overwriting each other. A second copy now hands over to the one
  already running and quits, and the click drops the panel open where you can
  see it.
- **Opening the panel now clears the notification that sent you there.** Banners
  stacked up in Notification Center until you cleared them by hand, so acting on
  one still left you the same news to dismiss a second time.

- **VoiceOver now reads a category row properly.** The rows announced their name
  but never their progress, were not announced as buttons, and could not be
  activated at all. A row now reads as "Alpha, 2 of 5 pomodoros, goal met",
  takes a press, and can be focused from the keyboard. Nothing about how the
  rows look has changed.
- **A long category name no longer pushes the Focus tab off the panel.** The
  target line under the countdown now truncates with an ellipsis — instead of
  drawing itself, the timer card and the Start focus button past both edges of
  the panel. Screen readers still hear the whole name.
- **Settings' "Add category" and "Remove category" popovers now follow the
  Synthwave theme.** Both drew on the system's light background while the panel
  behind them stayed dark, which left the "New category" caption and the note
  about what survives a removal too faint to read.

## [1.3.0] - 2026-07-30

### Changed

- **A finished focus session now offers the break** — with "Auto-start break"
  off, a completed session no longer drops back to idle. The Focus tab holds the
  break at its configured length (the long one when you have earned it), the big
  button becomes "Start break", and the menu bar shows a cup beside your count.
  The stop button skips it, and skipping a long break keeps it owed.
- **Synthwave's "Start focus" button is no longer blinding** — it shared its
  near-white cyan with the countdown glowing right above it, which made the
  Focus tab bloom into one bright blob and left the white label barely legible
  against the button's own fill. The button now sits in a deeper cyan.

### Fixed

- Buttons that are switched off now look switched off. The stop button in the
  Focus tab was drawn exactly like a live one while the timer sat idle, so it
  invited a press that did nothing — most visibly now that it is the control you
  toggle between idle and a waiting break.

## [1.2.0] - 2026-07-29

### Added

- **The target follows the day's plan** — when a category meets its daily goal,
  the session target moves on by itself to the next category with a goal left,
  and the Focus tab's "towards …" pill says so straight away. Picking a finished
  category by hand still sticks, so overshooting one on purpose works, and a
  session already under way keeps the target it started against — logging a
  pomodoro from your hardware partway through can't re-aim it. Switch the whole
  thing off with "Move on when a goal is met" in Settings.

## [1.1.0] - 2026-07-29

### Fixed

- A data file that fails to read is now backed up before the app's next save
  can overwrite it, so a corrupted store can never silently erase your history.

### Added

- **Reorder categories** — drag a category by the grip handle on its Settings
  row to change the order categories appear in, both in Settings and in the
  Focus panel; the other rows part to show where it will land. Each row also
  carries "Move up" and "Move down" actions for VoiceOver.
- **Log from anywhere** — `open "pomodorocount://log"` (optionally with
  `?category=Name`) records a pomodoro from a Stream Deck button, a Shortcuts
  automation, or a script, and confirms with a notification. An unknown
  category logs to the bucket; a URL can never invent one.
- **Long breaks** — every fourth completed focus session earns a longer break
  (15 minutes by default, adjustable in Settings).
- **Auto-pause when the Mac goes unattended** — locking the screen or the
  displays sleeping pauses a running session, so time away never counts as
  focus. Resuming stays your call.
- **Streaks** — a flame and a count in the header once you're two or more
  consecutive days in. Today being empty doesn't break yesterday's streak; it
  just hasn't grown yet.
- **End-of-day reminder** — optional, at an hour you pick: one notification if
  the day's goal isn't met yet, silence once it is.
- **Year heatmap** — History gains a Year range showing each day of the last
  365 as a grid, ink proportional to the count.
- **Tooltips everywhere, and goals that glow** — every button explains itself
  on hover, and a category row washes in the accent colour once its daily
  goal is met.
- **The panel uses your screen** — Settings and History now grow to what the
  display can spare instead of stopping at a fixed height, and History got
  more air between its sections.
- **Timer first** — the Focus tab now leads with the timer and Start focus,
  with the log rows and today's count below, and the tab picker holds the
  same top position on every tab.

## [1.0.0] - 2026-07-28

First public release.

### Added

- **Log completed pomodoro** — one click records a pomodoro finished on external
  hardware (a physical timer, a cube), with **Undo last** for mis-taps.
- **Global shortcut** — log from any app without opening the panel. Defaults to
  <kbd>⌃⌥⌘P</kbd>; record your own combo or turn it off in Settings.
- **Menu bar item** — a custom tomato icon showing today's count when idle, or a
  live countdown with a cup glyph on breaks and a pause glyph when paused.
  Right-click it for a menu with **Quit**, so the app can be quit without
  opening the panel first.
- **Built-in timer** — configurable focus and break lengths, defaulting to
  50 / 10 minutes, with optional auto-start break, sound, and notification.
- **Categories with daily goals** — optional named categories, each with a daily
  goal. Tapping a category's row logs a pomodoro to it, and focus sessions can
  be aimed at one. Anything not aimed at a category lands in a catch-all bucket,
  named **General** by default, which you can rename and give a goal of its own.
  Removing a category asks first, and archives rather than deletes: its
  pomodoros stay in your history, totals and CSV export, and adding the name
  back reunites it with them.
- **History** — Week / Month bar chart, per-day list, a **By category**
  breakdown, and this-week and all-time totals, with **CSV export** of the whole
  history.
- **VoiceOver support** throughout, including the menu bar item, which announces
  today's count or the time remaining in the current session.
- **Themes** — switchable Classic and Synthwave palettes.
- **Icon-only menu bar option** — hides the idle count to give the width back to
  a crowded menu bar. The countdown still shows during a session.
- The panel opens by itself the first time the app runs, so a menu-bar-only app
  doesn't launch to nothing at all.
- **Launch at login** toggle when installed as an app.
- **Automatic updates** via Sparkle, verified against a signing key built into
  the app. Checks daily; can be turned off, or run on demand, in Settings.
- Daily rollover: the visible count returns to zero at midnight and when the Mac
  wakes, while past days stay in history.
- The panel closes as soon as a pomodoro is logged, so logging is a single click.
- Version shown in the panel footer.

### Notes

- Releases are unsigned. macOS Gatekeeper asks for a one-time confirmation on
  first launch — see [Installing](README.md#install) for the two-second step.

[Unreleased]: https://github.com/markgustetic/pomodoro-count/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/markgustetic/pomodoro-count/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/markgustetic/pomodoro-count/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/markgustetic/pomodoro-count/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/markgustetic/pomodoro-count/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/markgustetic/pomodoro-count/releases/tag/v1.0.0
