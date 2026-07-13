# Pomodoro Count

A tiny macOS **menu bar** app for running pomodoros and — the main reason it
exists — **counting pomodoros you complete on external hardware** (a physical
timer, a cube, etc.) that doesn't keep a running total.

Click the menu bar icon, hit **Log completed pomodoro**, and it's counted toward
your day and history. That's it.

## Features

- **Menu bar only** — no Dock icon. A custom tomato icon shows today's count when
  idle, or a live countdown (with a cup glyph on breaks, a pause glyph when paused)
  while a session runs.
- **Log completed pomodoro** — one click to record a pomodoro finished outside
  the app, with **Undo last** for mis-taps.
- **Global shortcut** — log a completed pomodoro from any app, without opening
  the panel. Defaults to **⌃⌥⌘P**; click-to-record your own combo (or toggle it
  off) in Settings.
- **Built-in timer** — configurable, defaults to **50 min focus / 10 min break**,
  with optional auto-start break, completion sound, and notification.
- **Daily count** front and center.
- **History** — a **Week / Month** bar chart plus a per-day list, with this-week
  and all-time totals.
- **Launch at login** toggle (when run as an installed app).

Data lives in `~/Library/Application Support/PomodoroCount/data.json`.

## Build & install

Requires the Swift toolchain (Xcode or the Command Line Tools — `xcode-select
--install`).

With [`just`](https://github.com/casey/just) (`brew install just`):

```bash
just setup      # first time: build + install into /Applications + launch
just install    # rebuild and move it over (replaces /Applications copy, relaunches)
just run        # build and run from ./build without installing
just test       # run the logic self-checks
just            # list every recipe
```

Or without `just`:

```bash
./build-app.sh                      # produces build/Pomodoro Count.app
open "build/Pomodoro Count.app"     # run it now (look top-right in the menu bar)
cp -R "build/Pomodoro Count.app" /Applications/   # install it
```

Once it's in `/Applications`, open **Settings → Launch at login** in the app so
it starts with your Mac.

## Develop

```bash
swift run PomodoroCount             # run straight from source
swift run PomodoroCount --selftest  # run the logic self-checks
```

## Layout

| File | Purpose |
|------|---------|
| `Sources/PomodoroCount/Model.swift` | Data model, timer engine, persistence |
| `Sources/PomodoroCount/PomodoroCountApp.swift` | App entry + `MenuBarExtra` |
| `Sources/PomodoroCount/RootView.swift` | The popover UI (Focus / History / Settings) |
| `Sources/PomodoroCount/StatusIcon.swift` | Custom menu bar icon + text rendering |
| `Sources/PomodoroCount/HotKey.swift` | Global hotkey (Carbon `RegisterEventHotKey`) |
| `Sources/PomodoroCount/ShortcutRecorder.swift` | Click-to-record shortcut control |
| `Sources/PomodoroCount/SelfTest.swift` | `--selftest` logic checks |
| `Tools/make-icon.swift` | Renders the app icon (`Resources/AppIcon.icns`) |
| `build-app.sh` | Compiles and assembles the `.app` bundle |

The app is menu-bar-only (`LSUIElement`), so it doesn't sit in the Dock while
running — but it now has a proper tomato icon in Finder, Get Info, and Spotlight.
To regenerate the icon, delete `Resources/AppIcon.icns` and rerun `build-app.sh`.
