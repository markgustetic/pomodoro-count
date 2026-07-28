# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Reorder categories** — drag a category by the grip handle on its Settings
  row to change the order categories appear in, both in Settings and in the
  Focus panel; the other rows part to show where it will land. Each row also
  carries "Move up" and "Move down" actions for VoiceOver.

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

[Unreleased]: https://github.com/markgustetic/pomodoro-count/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/markgustetic/pomodoro-count/releases/tag/v1.0.0
