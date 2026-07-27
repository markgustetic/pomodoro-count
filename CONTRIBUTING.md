# Contributing

Thanks for taking a look. This is a small, deliberately focused app — a menu bar
counter for pomodoros finished on external hardware. Contributions that keep it
small are very welcome.

## Getting set up

You need the Swift toolchain, which comes with either Xcode or the Command Line
Tools (`xcode-select --install`).

```bash
git clone https://github.com/markgustetic/pomodoro-count.git
cd pomodoro-count
just            # list every recipe
just dev        # run straight from source
just test       # run the test suite
just install    # build and install into /Applications
```

[`just`](https://github.com/casey/just) is optional (`brew install just`); every
recipe is a short shell command you can also run by hand.

### One wrinkle with tests

swift-testing and XCTest ship with **full Xcode**, not the Command Line Tools.
`just test` handles this: if your active toolchain is the CLT it borrows Xcode
for that one command via `DEVELOPER_DIR`, which needs no `sudo`. If you have
only the Command Line Tools installed, everything except `just test` still works.

## Making a change

1. Branch off `main`.
2. Write a test. The suite lives in `Tests/PomodoroCountTests/` and is fast
   (well under a second) — there is no excuse not to.
3. Make sure `just test` passes and the app still builds (`just build`).
4. Open a pull request. CI runs the tests and a bundle build on every PR.

### What makes a good change here

- **Fixing something that's wrong** — always welcome.
- **Small, self-contained features** that fit the app's one job. If it needs a
  new tab, a new dependency, or a preferences window, please open an issue to
  talk it through first.
- **Not** a rewrite, a new architecture, or a dependency that could be twenty
  lines of AppKit.

### Dependencies

There is exactly one: [Sparkle](https://sparkle-project.org), which handles
updates. It earns its place — macOS ships no updater, and a hand-rolled one
means implementing signature verification for downloaded executables, which is
precisely the code you do not want to write yourself.

That's the bar for a second one. Please open an issue before adding anything.

## Style

Match the surrounding code. Some conventions worth knowing:

- Comments explain *why*, not *what*. If a workaround is non-obvious — see
  `MenuBarPanel.dismiss()` — say what breaks without it.
- Views are small `private var` chunks of `RootView` rather than a deep tree of
  files.
- Colours come from `Palette` so both themes stay in sync. Don't hardcode one.
- Anything touching `AppModel` is `@MainActor`.

## Project layout

| Path | Purpose |
|------|---------|
| `Sources/PomodoroCount/Model.swift` | Data model, timer engine, persistence |
| `Sources/PomodoroCount/PomodoroCountApp.swift` | App entry, `MenuBarExtra`, panel dismissal |
| `Sources/PomodoroCount/RootView.swift` | The panel UI (Focus / History / Settings) |
| `Sources/PomodoroCount/Theme.swift` | `Palette` — every colour in both themes |
| `Sources/PomodoroCount/Styles.swift` | Shared button and control styles |
| `Sources/PomodoroCount/StatusIcon.swift` | Menu bar icon + text rendering |
| `Sources/PomodoroCount/HotKey.swift` | Global hotkey (Carbon `RegisterEventHotKey`) |
| `Sources/PomodoroCount/ShortcutRecorder.swift` | Click-to-record shortcut control |
| `Sources/PomodoroCount/PreviewRenderer.swift` | `--preview` headless panel render |
| `Tests/PomodoroCountTests/` | The test suite |
| `Tools/make-icon.swift` | Draws the app icon (`Resources/AppIcon.icns`) |
| `build-app.sh` | Compiles and assembles the `.app` bundle |
| `packaging/homebrew/` | Cask template and tap setup |

## Testing UI behaviour

Logic is covered by the test suite. The panel itself is a `MenuBarExtra`, which
no test framework drives well — for that, `just preview` renders all three tabs
to a PNG without needing a menu bar, which catches layout problems quickly. CI
runs the same render on every PR as a crash check.

The renderer hosts the view in an offscreen window and draws the real AppKit
hierarchy rather than using SwiftUI's `ImageRenderer`, which cannot rasterize
NSView-backed controls — with `ImageRenderer` the switches and steppers came out
as yellow placeholder blocks and the History day-list vanished entirely. If you
add a control that renders oddly in a preview, suspect that boundary first.

One honest limitation: the offscreen window is never key, so controls draw in
their inactive state. Switches look grey in a preview and accent-tinted in the
running app. That's the renderer, not your change.

## Releasing

Maintainers only:

1. Update `VERSION` and add a `CHANGELOG.md` section for it.
2. Merge to `main`; CI checks the two agree.
3. Run `just release`. It re-checks those, runs the tests, tags `vX.Y.Z`, and
   pushes the tag. The release workflow then builds, zips, checksums, and
   publishes the GitHub Release, and updates the Homebrew cask.

> **CI and Release are currently disabled.** GitHub Actions can't run on this
> account while the repo is private, so both workflows are switched off rather
> than failing on every push. `just release` refuses to tag while they're off.
> To turn them back on:
>
> ```bash
> gh workflow enable CI
> gh workflow enable Release
> ```
