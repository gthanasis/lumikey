#!/bin/sh
# Builds Lumikey.app (universal: Apple Silicon and Intel) and installs it in ~/Applications.
#   ./build.sh               build and install
#   ./build.sh --no-install  build only (what the release workflow uses)
# VERSION sets the version shown in Finder and in test reports.
set -e
cd "$(dirname "$0")"
BUILD=build
APP="$BUILD/Lumikey.app"
DEST="$HOME/Applications/Lumikey.app"
VERSION=${VERSION:-2.1}
INSTALL=1
[ "$1" = "--no-install" ] && INSTALL=0

rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  TARGET=$ARCH-apple-macos14.0
  clang -c -O2 -target $TARGET -Wall -o "$BUILD/RazerUSB-$ARCH.o" Sources/RazerUSB.c
  xcrun swiftc -O -parse-as-library -swift-version 5 -target $TARGET \
    -import-objc-header Sources/RazerUSB.h \
    Sources/*.swift "$BUILD/RazerUSB-$ARCH.o" \
    -framework IOKit -framework CoreFoundation \
    -o "$BUILD/Lumikey-$ARCH"
done
lipo -create -output "$APP/Contents/MacOS/Lumikey" "$BUILD/Lumikey-arm64" "$BUILD/Lumikey-x86_64"

cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lumikey</string>
  <key>CFBundleDisplayName</key><string>Lumikey</string>
  <key>CFBundleIdentifier</key><string>io.github.gthanasis.lumikey</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Lumikey</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Thanasis Gliatis. MIT licence.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run; Apple Silicon refuses unsigned code. It isn't a
# Developer ID signature, so a downloaded copy needs "Open Anyway" once (see README).
codesign --force --sign - "$APP"
echo "Built $APP"

[ $INSTALL = 1 ] || exit 0
# Replace the installed copy (quitting it first if it's running).
osascript -e 'tell application id "io.github.gthanasis.lumikey" to quit' >/dev/null 2>&1 || true
pkill -x "Lumikey" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$APP" "$DEST"
echo "Installed $DEST"
