# Pomodoro Count — task runner
# Run `just` with no arguments to list all recipes.

app_name    := "Pomodoro Count"
exe         := "PomodoroCount"
bundle      := "build" / (app_name + ".app")
install_dir := "/Applications"
installed   := install_dir / (app_name + ".app")

# List available recipes
default:
    @just --list

# First-time setup: check the toolchain, then build and install into /Applications
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v swift >/dev/null; then
        echo "Swift toolchain not found. Install it with:  xcode-select --install"
        exit 1
    fi
    echo "Swift: $(swift --version 2>/dev/null | head -1)"
    just install
    echo
    echo "Done. Open the app's Settings → 'Launch at login' to start it with your Mac."

# Build the .app bundle into ./build (compiles release + assembles + icon)
build:
    ./build-app.sh

# Alias for build
rebuild: build

# Rebuild and move it over: install into /Applications (replacing any copy) and relaunch
install: build
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Stopping any running instance…"
    pkill -x "{{exe}}" 2>/dev/null || true
    sleep 1
    echo "Installing → {{installed}}"
    rm -rf "{{installed}}"
    cp -R "{{bundle}}" "{{install_dir}}/"
    echo "Launching…"
    open "{{installed}}"
    echo "Installed and running."

# Build, then run the bundle from ./build (without installing to /Applications)
run: build
    open "{{bundle}}"

# Run straight from source for development (no bundle; notifications disabled)
dev:
    swift run {{exe}}

# Run the test suite
test:
    #!/usr/bin/env bash
    set -euo pipefail
    # swift-testing and XCTest ship with Xcode, not the Command Line Tools. If the
    # active toolchain is the CLT, borrow Xcode for this command only — that needs
    # no sudo, unlike switching the toolchain with `xcode-select -s`.
    xctest_path="Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
    if [ ! -d "$(xcode-select -p)/$xctest_path" ]; then
        if [ -d "/Applications/Xcode.app/Contents/Developer/$xctest_path" ]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
        else
            echo "Tests need the full Xcode (the Command Line Tools ship no test framework)."
            echo "Install Xcode from the App Store, then rerun.  Everything else works without it."
            exit 1
        fi
    fi
    swift test

# Render the popover UI to a PNG and open it (headless preview, no menu bar needed)
preview:
    #!/usr/bin/env bash
    set -euo pipefail
    out="$(mktemp -d)/pomodoro-panel.png"
    swift run {{exe}} --preview "$out"
    open "$out"

# Regenerate the app icon (Resources/AppIcon.icns) from Tools/make-icon.swift
icon:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -f Resources/AppIcon.icns
    ./build-app.sh >/dev/null
    echo "Regenerated Resources/AppIcon.icns"

# Tag the current VERSION and push it, which publishes a release
release:
    #!/usr/bin/env bash
    set -euo pipefail
    version="$(tr -d '[:space:]' < VERSION)"
    if ! grep -q "^## \[$version\]" CHANGELOG.md; then
        echo "CHANGELOG.md has no '## [$version]' section — write the release notes first."
        exit 1
    fi
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree is dirty; commit or stash first."
        exit 1
    fi
    if git rev-parse "v$version" >/dev/null 2>&1; then
        echo "Tag v$version already exists. Bump VERSION for a new release."
        exit 1
    fi
    # A pushed tag is awkward to retract, and with the workflow off it would
    # publish nothing at all — so check before tagging, not after.
    if command -v gh >/dev/null 2>&1; then
        state="$(gh workflow list --all --json name,state \
            --jq '.[] | select(.name=="Release") | .state' 2>/dev/null || true)"
        if [ "$state" = "disabled_manually" ]; then
            echo "The Release workflow is disabled, so pushing v$version would publish nothing."
            echo "Re-enable it first:  gh workflow enable Release"
            exit 1
        fi
    fi
    just test
    git tag -a "v$version" -m "Pomodoro Count $version"
    git push origin "v$version"
    echo "Pushed v$version. Follow the build with:  gh run watch"

# Remove build artifacts (.build and ./build)
clean:
    rm -rf .build build

# Stop the running app
stop:
    -pkill -x "{{exe}}"
