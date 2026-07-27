# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- **Launch at login** toggle when installed as an app.
- Daily rollover: the visible count returns to zero at midnight and when the Mac
  wakes, while past days stay in history.
- The panel closes as soon as a pomodoro is logged, so logging is a single click.
- Version shown in the panel footer.

### Notes

- Releases are unsigned. macOS Gatekeeper asks for a one-time confirmation on
  first launch — see [Installing](README.md#install) for the two-second step.

[Unreleased]: https://github.com/markgustetic/pomodoro-count/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/markgustetic/pomodoro-count/releases/tag/v1.0.0
