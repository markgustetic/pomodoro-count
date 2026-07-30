#!/bin/bash
# Builds "Pomodoro Count.app" — a real menu-bar app bundle you can drag to
# /Applications and add to login items. Requires the Swift toolchain (comes
# with Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pomodoro Count"
EXE="PomodoroCount"
BUNDLE_ID="com.markg.pomodorocount"
# `releases/latest/download/<asset>` always redirects to the newest release, so
# the feed URL never needs updating.
SPARKLE_FEED_URL="https://github.com/markgustetic/pomodoro-count/releases/latest/download/appcast.xml"
# VERSION is the single source of truth for the released version number; the
# release workflow tags from it and the app shows it in its footer.
VERSION="$(tr -d '[:space:]' < VERSION)"

echo "Building release binary…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXE"

# App icon: generate Resources/AppIcon.icns once if it's missing (best-effort).
if [ ! -f Resources/AppIcon.icns ]; then
    echo "Generating app icon…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    if swift Tools/make-icon.swift "$ICONSET" && iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns; then
        echo "  → Resources/AppIcon.icns"
    else
        echo "  (icon generation failed; building without a custom icon)"
    fi
fi

APP="build/$APP_NAME.app"
echo "Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle ships as an XCFramework that SwiftPM only unpacks into .build. A bundle
# that leaves it there launches fine here and dies with a dyld error anywhere
# else, so copy it in and point the executable at the copy.
SPARKLE_FW="$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*' | head -1)"
if [ -z "$SPARKLE_FW" ]; then
    echo "Sparkle.framework not found — run 'swift package resolve' first." >&2
    exit 1
fi
echo "Embedding $(basename "$SPARKLE_FW") …"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$EXE" 2>/dev/null || true

# The public key verifies downloaded updates. Without it Sparkle would refuse
# every update, so the app hides its updater UI instead of pretending.
# One-time setup lives in packaging/sparkle/README.md.
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(cat packaging/sparkle/public-key.txt 2>/dev/null || true)}"
SPARKLE_KEYS=""
if [ -n "$SPARKLE_PUBLIC_KEY" ]; then
    SPARKLE_KEYS="
    <key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>"
else
    echo "  (no Sparkle public key; building without the updater)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array><string>pomodorocount</string></array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key><string>Pomodoro Count</string>$SPARKLE_KEYS
</dict>
</plist>
PLIST

# Signing. CODESIGN_IDENTITY defaults to ad-hoc, which is enough for macOS to
# treat this as a stable, launchable app on the machine that built it. A release
# passes a real Developer ID; that path also needs the hardened runtime (the
# notary service rejects submissions without it) and a secure timestamp (which
# keeps the signature valid after the certificate expires).
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "Signing (ad-hoc)…"
    SIGN=(codesign --force --sign - --timestamp=none)
else
    echo "Signing as $CODESIGN_IDENTITY …"
    SIGN=(codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp)
fi

# Nested code must be signed before the thing that contains it, innermost first —
# signing the outer bundle first would seal a hash the inner signatures then
# invalidate.
#
# The list is explicit and a missing entry is fatal, because the failure it
# replaces was silent: a `find -maxdepth 3` here never reached
# Versions/*/XPCServices, so both XPC services kept the ad-hoc signature Sparkle
# ships them with. Invisible while everything was ad-hoc, fatal under a Developer
# ID. A Sparkle upgrade that moves these should break the build here, loudly,
# rather than at Apple's notary service, obscurely.
FW="$APP/Contents/Frameworks/Sparkle.framework"
# "B" today — read, not hardcoded. Named diagnostic to match the four checks
# below: readlink fails silently (no message, just a nonzero exit), and under
# `set -e` a bare assignment here would kill the script with no clue why.
FW_VER="$(readlink "$FW/Versions/Current")" || {
    echo "Sparkle.framework has no Versions/Current symlink — did its layout change?" >&2
    exit 1
}
for nested in \
    "XPCServices/Downloader.xpc" \
    "XPCServices/Installer.xpc" \
    "Updater.app" \
    "Autoupdate"
do
    target="$FW/Versions/$FW_VER/$nested"
    [ -e "$target" ] || {
        echo "Sparkle.framework has no $nested — did its layout change?" >&2
        exit 1
    }
    "${SIGN[@]}" "$target"
done
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"

echo "Done → $APP"
echo "Run it with:  open \"$APP\""
echo "Install it with:  cp -R \"$APP\" /Applications/"
