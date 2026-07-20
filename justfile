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

# Run the in-process logic self-checks
test:
    swift run {{exe}} --selftest

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

# Remove build artifacts (.build and ./build)
clean:
    rm -rf .build build

# Stop the running app
stop:
    -pkill -x "{{exe}}"
