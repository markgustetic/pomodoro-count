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

The app deliberately has **zero third-party dependencies**. Please keep it that way.

## Style

Match the surrounding code. Some conventions worth knowing:

- Comments explain *why*, not *what*. If a workaround is non-obvious — see
  `MenuBarPanel.dismiss()` — say what breaks without it.
- Views are small `private var` chunks of `RootView` rather than a deep tree of
  files.
- Colours come from `Palette` so both themes stay in sync. Don't hardcode one.
- Anything touching `AppModel` is `@MainActor`.

## Testing UI behaviour

Logic is covered by the test suite. The panel itself is a `MenuBarExtra`, which
no test framework drives well — for that, `just preview` renders all three tabs
to a PNG without needing a menu bar, which catches layout problems quickly.

## Releasing

Maintainers only:

1. Update `VERSION` and add a `CHANGELOG.md` section for it.
2. Merge to `main`; CI checks the two agree.
3. Tag `vX.Y.Z` and push the tag. The release workflow builds, zips, checksums,
   and publishes the GitHub Release, then updates the Homebrew cask.
