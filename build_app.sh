#!/bin/sh
# Build Moomer.app: a menu-bar launcher that spawns the moomer capture tool.
#
#   ./build_app.sh              # build the .app into ./dist/Moomer.app
#   ./build_app.sh install      # also copy it to /Applications
#
# The launcher lives in Contents/MacOS/moomer-launcher and owns the menu-bar
# icon + Cmd+Shift+2 global hotkey. The capture binary sits beside it as
# Contents/MacOS/moomer and is spawned fresh on every trigger.

set -e

APP_NAME="Moomer"
BUNDLE_ID="com.moomer.launcher"
DIST="dist"
APP="$DIST/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> compiling binaries"
odin build . -out:moomer
odin build launcher -out:moomer-launcher

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp moomer "$MACOS/moomer"
cp moomer-launcher "$MACOS/moomer-launcher"

# Menu-bar icon. The "light" variant is the black silhouette; we use it as a
# macOS template image so it's auto-recolored for light and dark menu bars.
cp icons/cow-icon-light-64.png "$RES/menubar-icon.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>moomer-launcher</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<!-- Agent app: menu-bar only, no Dock icon. -->
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc code sign so screen-recording permission sticks to the bundle
# identity instead of being lost on every rebuild.
echo "==> ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
	echo "   (codesign skipped/failed; app still runnable)"

echo "==> built $APP"

if [ "$1" = "install" ]; then
	echo "==> installing to /Applications"
	rm -rf "/Applications/$APP_NAME.app"
	cp -R "$APP" "/Applications/$APP_NAME.app"
	echo "    installed. Launch it from /Applications or Spotlight."
	echo "    Grant Screen Recording permission when prompted, then relaunch."
fi

echo "done."
