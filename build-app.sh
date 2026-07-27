#!/bin/bash
# Builds "Pomodoro Count.app" — a real menu-bar app bundle you can drag to
# /Applications and add to login items. Requires the Swift toolchain (comes
# with Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pomodoro Count"
EXE="PomodoroCount"
BUNDLE_ID="com.markg.pomodorocount"
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
    <key>NSHumanReadableCopyright</key><string>Pomodoro Count</string>
</dict>
</plist>
PLIST

# Ad-hoc code signature so macOS treats it as a stable, launchable app.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Done → $APP"
echo "Run it with:  open \"$APP\""
echo "Install it with:  cp -R \"$APP\" /Applications/"
