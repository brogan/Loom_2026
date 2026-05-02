#!/bin/bash
# launch_loom.command
# Double-click in Finder to build and launch the integrated Loom app.
# Wraps the binary in a temporary .app bundle so macOS gives it full
# keyboard focus (avoids the terminal-stdin capture that swift run causes).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_BUNDLE="/tmp/Loom.app"
BINARY_PATH="$SCRIPT_DIR/.build/debug/Loom"
PLIST_PATH="$APP_BUNDLE/Contents/Info.plist"

echo "Building Loom…"
swift build 2>&1
if [ $? -ne 0 ]; then
    echo "Build failed." >&2
    exit 1
fi

echo "Packaging…"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/Loom"

cat > "$PLIST_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>Loom</string>
    <key>CFBundleIdentifier</key>      <string>com.loom.integration</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "Launching…"
open "$APP_BUNDLE"
