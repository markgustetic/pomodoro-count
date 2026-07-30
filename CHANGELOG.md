# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/markgustetic/pomodoro-count/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/markgustetic/pomodoro-count/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/markgustetic/pomodoro-count/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/markgustetic/pomodoro-count/releases/tag/v1.0.0
