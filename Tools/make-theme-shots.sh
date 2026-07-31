#!/usr/bin/env bash
# Crops the Focus tab out of both panel renders for README.md's "Two themes"
# section.
#
# Run this after re-rendering docs/panel-*.png, or the pair goes stale while the
# hero above it does not — which is worse than both being stale, because the
# page then contradicts itself. The panel screenshots have gone stale once
# already; a derived image nobody can regenerate goes stale faster than its
# source, which is why this is a script and not a one-off crop.
#
# Regenerate the sources first:
#   APP="build/Pomodoro Count.app/Contents/MacOS/PomodoroCount"
#   "$APP" --preview docs/panel-classic.png   --theme classic
#   "$APP" --preview docs/panel-synthwave.png --theme synthwave
#   ./Tools/make-theme-shots.sh
#
# sips rather than Python: it ships with macOS, and this repo has no Python
# dependency to justify adding one for a crop. Verified byte-identical to the
# equivalent Pillow crop.
set -euo pipefail
cd "$(dirname "$0")/.."

# The Focus tab's bounds, as the union of both themes' content extents.
# Synthwave's neon bleeds about 28px wider and taller than Classic's flat
# surfaces, so a box fitted to Classic alone clips the glow off the countdown
# and the Start focus button — measured from the renders, not guessed.
X=24; Y=24; W=624; H=1096

for theme in classic synthwave; do
    src="docs/panel-$theme.png"
    out="docs/theme-$theme.png"
    [ -f "$src" ] || { echo "missing $src — render the panels first" >&2; exit 1; }
    sips -c "$H" "$W" --cropOffset "$Y" "$X" "$src" --out "$out" >/dev/null
    echo "$out  ($(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/{printf "%s ", $2}'))"
done
