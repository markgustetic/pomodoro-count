# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Categories with daily goals.** Optional named categories, each with a daily
  goal. Tapping a category's row logs a pomodoro to it, focus sessions can be
  aimed at one, and History gains a By category breakdown. Deleting a category
  archives it — its pomodoros stay in your history, totals, and CSV export.
- CSV export gains a `category` column.
- **Right-clicking the menu bar icon** shows a menu with **Quit**, so the app can
  be quit without opening the panel first.

### Fixed

- **Synthwave is readable again.** On a Mac set to Light appearance, the
  switches, steppers, text fields and popovers in the Synthwave theme kept
  drawing their light-mode selves on top of its near-black panel — white text
  fields and all-but-invisible stepper arrows. They now follow the theme rather
  than the system. Alongside that, Synthwave's secondary text, card edges,
  unfilled goal dots and rules were all lifted out of the background, and its
  text buttons (Undo last, Export CSV…, Add category, Quit) and icon buttons no
  longer rest in the same colour as the caption text beside them.

### Changed

- **History and Settings are their own pages.** Today's count and the category
  log rows now appear on Focus only. They sat above every tab, so opening
  Settings meant scrolling past a count card and four log buttons to reach the
  first setting; the panel is roughly 250pt shorter on both tabs now. The
  Focus / History / Settings strip stays where it is.
- The History day list now respects the Week / Month range, instead of always
  showing up to 30 populated days regardless of the selected range. This
  changes History's behaviour even with categories switched off.
- CSV export gains a `category` column, appended after the existing columns.
  Anything that parses the export should account for the new column.

## [1.0.0] - 2026-07-27

First public release.

### Added

- **Log completed pomodoro** — one click records a pomodoro finished on external
  hardware (a physical timer, a cube), with **Undo last** for mis-taps.
- **Global shortcut** — log from any app without opening the panel. Defaults to
  <kbd>⌃⌥⌘P</kbd>; record your own combo or turn it off in Settings.
- **Menu bar item** — a custom tomato icon showing today's count when idle, or a
  live countdown with a cup glyph on breaks and a pause glyph when paused.
- **Built-in timer** — configurable focus and break lengths, defaulting to
  50 / 10 minutes, with optional auto-start break, sound, and notification.
- **History** — Week / Month bar chart, per-day list, and this-week and all-time
  totals, with **CSV export** of the whole history.
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

[Unreleased]: https://github.com/markgustetic/pomodoro-count/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/markgustetic/pomodoro-count/releases/tag/v1.0.0
