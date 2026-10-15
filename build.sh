#!/bin/sh
# Builds Ornata Lights.app (native, arm64) and installs it in ~/Applications.
set -e
cd "$(dirname "$0")"
BUILD=build
APP="$BUILD/Ornata Lights.app"
DEST="$HOME/Applications/Ornata Lights.app"
TARGET=arm64-apple-macos14.0

rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

clang -c -O2 -target $TARGET -Wall -o "$BUILD/OrnataUSB.o" Sources/OrnataUSB.c
xcrun swiftc -O -parse-as-library -swift-version 5 -target $TARGET \
  -import-objc-header Sources/OrnataUSB.h \
  Sources/*.swift "$BUILD/OrnataUSB.o" \
  -framework IOKit -framework CoreFoundation \
  -o "$APP/Contents/MacOS/Ornata Lights"

cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ornata Lights</string>
  <key>CFBundleDisplayName</key><string>Ornata Lights</string>
  <key>CFBundleIdentifier</key><string>local.ornata-lights</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Ornata Lights</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>Personal build</string>
</dict>
</plist>
EOF

# Ad-hoc signature: enough to run locally; Apple Silicon refuses unsigned code.
codesign --force --sign - "$APP"

# Replace the installed copy (quitting it first if it's running).
osascript -e 'tell application id "local.ornata-lights" to quit' >/dev/null 2>&1 || true
pkill -x "Ornata Lights" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$APP" "$DEST"
echo "Installed $DEST"
