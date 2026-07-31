<h1 align="center">Pomodoro Count</h1>

<p align="center">
  A tiny macOS menu bar app that counts the pomodoros you finish
  <em>somewhere else</em>.
</p>

<p align="center">
  <a href="https://github.com/markgustetic/pomodoro-count/actions/workflows/ci.yml"><img src="https://github.com/markgustetic/pomodoro-count/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/markgustetic/pomodoro-count/releases/latest"><img src="https://img.shields.io/github/v/release/markgustetic/pomodoro-count" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/panel-classic.png" alt="The Focus, History, and Settings tabs" width="900">
</p>

## Why

Physical pomodoro timers are lovely — a cube you twist, a dial you turn, no
screen involved. What they don't do is remember. Turn the cube twenty times in a
week and you have no idea you did.

Pomodoro Count is the tally that hardware is missing. Finish a pomodoro on your
timer, hit one button (or one keystroke), and it's counted. It has a built-in
timer too, if you want one, but that's not the point of it.

## Install

### Homebrew

```bash
brew install --cask markgustetic/tap/pomodoro-count
```

### Download

Grab the zip from the [latest release](https://github.com/markgustetic/pomodoro-count/releases/latest),
unzip it, and drag **Pomodoro Count.app** to `/Applications`. Releases are
signed with an Apple Developer ID and notarized by Apple, so it opens like
anything else — no right-click, no warning to dismiss.

Each release also ships a `.sha256` file, if you'd rather check the download
yourself:

```bash
shasum -a 256 -c PomodoroCount-*.zip.sha256
```

### From source

Needs the Swift toolchain (Xcode or `xcode-select --install`) and
[`just`](https://github.com/casey/just):

```bash
git clone https://github.com/markgustetic/pomodoro-count.git
cd pomodoro-count
just setup     # build, install to /Applications, launch
```

## Using it

**It lives in the menu bar** and has no Dock icon — after launching, **look at
the top-right of your screen**, not the Dock.

**Log a pomodoro.** Click the menu bar icon and hit **Log completed pomodoro**.
The panel closes and the count goes up. Mis-tapped? **Undo last**.

**Without opening anything.** <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd>
logs one from any app. Record your own combo in Settings, or turn it off.

**From hardware and scripts.** `open "pomodorocount://log"` logs one too —
wire it to a Stream Deck button, a Shortcuts automation, or whatever your
physical timer can trigger. Add `?category=Deep%20Work` to aim it at a
category; a name your list doesn't hold falls back to the bucket, and either
way a notification confirms the count.

**Right-click the menu bar icon** to quit without opening the panel.

**The menu bar shows** today's count when idle, or a live countdown while a
session runs — with a cup glyph on breaks and a pause glyph when paused. If your
menu bar is crowded, turn off **Show count in menu bar** and it shrinks to just
the icon while idle, still showing the timer during a session.

**Run a timer** if you want one. 50 / 10 minutes by default, configurable, with
a completion sound and a notification. Every 4th completed session earns a
longer break (15 minutes, adjustable). Locking the screen pauses a running
session — time away never counts as focus.

**The break waits for you.** When a focus session ends, the Focus tab holds the
break ready rather than dropping back to idle: the big button becomes **Start
break**, the panel says how long it will be, and the menu bar shows a cup beside
your count until you take it. The stop button skips it — and a skipped long
break stays owed, so you still get it after the next session. Prefer not to be
asked, turn on **Auto-start break after focus** in Settings and it just begins.

**History** gives you a Week / Month chart, a Year heatmap, a per-day list, and
this-week and all-time totals. Hover any bar or heatmap square and a card at the
pointer names that day and its count — the other bars dim, or the square takes a
ring, so it's clear which day you're reading. Today's count resets at midnight;
past days stay in history.
**Export CSV…** writes the lot to a spreadsheet — one row per pomodoro, so you
can group it however you like.

**Categories** are optional. Turn them on in Settings and the log button becomes
one row per category, each with its own daily goal — Work 4, AI study 1, Music 1
— so the day's progress is the first thing you see.

**Click a row to aim the session at it.** The outlined row is where a finished
pomodoro goes. The list is also a priority ranking: meet a goal and the target
falls to the highest row that still has one left, and each new day starts back at
the top. Aim at a category you have already finished and it stays put, so a
deliberate overshoot lasts longer than a single pomodoro — clicking that row
again hands control back to the ranking. Turn the automatic part off entirely
with **Follow the category order** in Settings, and the target then only ever
moves when you move it.

**The ± at the right of each row** is how you log by hand once categories are on:
it files a pomodoro to that category, or takes one back if you counted one too
many. History gains a **By category** view too, and deleting a category never
deletes its history.

**Streaks and reminders.** Two or more consecutive days with a pomodoro puts a
flame and a count in the header — and an empty morning doesn't break
yesterday's run. An optional end-of-day reminder says how many are left if the
day's goal isn't met yet, and stays quiet once it is.

**VoiceOver** works throughout. The menu bar item announces today's count, or
the phase and time remaining while a session runs.

**Two themes** — Classic and Synthwave.

<p align="center">
  <img src="docs/panel-synthwave.png" alt="The same three tabs in the Synthwave theme" width="900">
</p>

## Your data

One plain-text JSON file:

```
~/Library/Application Support/PomodoroCount/data.json
```

Timestamps of your pomodoros and your settings. That's everything. Back it up or
edit it as you like.

The app talks to the network for exactly one reason: checking whether a newer
version exists. No telemetry, no analytics, nothing about your usage leaves your
machine — and you can turn the check off in Settings. Updates are verified
against a signing key built into the app, so a tampered download is refused.

## Uninstall

```bash
brew uninstall --cask --zap pomodoro-count      # Homebrew, removes data too
```

Or drag the app to the Trash and, if you want the history gone as well:

```bash
rm -rf ~/Library/Application\ Support/PomodoroCount
```

Turn off **Launch at login** in Settings first, or macOS keeps a stale login item.

## Development

```bash
just            # list every recipe
just dev        # run from source
just test       # run the test suite
just preview    # render all three tabs to a PNG, no menu bar needed
just build      # build the .app into ./build
```

Tests need full Xcode — the Command Line Tools ship no test framework — but
`just test` finds it for you. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
details, project layout, and what kinds of changes fit.
[CHANGELOG.md](CHANGELOG.md) records what changed in every release.

## License

[MIT](LICENSE).
