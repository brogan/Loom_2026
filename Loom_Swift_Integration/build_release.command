#!/bin/bash
# build_release.command
# Double-click in Finder to build a release Loom.app and create a .dmg for installation.
# Requires Xcode Command Line Tools (swift, hdiutil).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Loom"
BUNDLE_ID="com.broganbunt.loom"
SIGN_IDENTITY="Loom Dev"
VERSION="1.0"
BUILD_NUMBER="$(git -C "$SCRIPT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

RELEASE_DIR="$SCRIPT_DIR/.build/release"
APP_BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
DMG_STAGING="$SCRIPT_DIR/build/dmg_staging"
DMG_PATH="$SCRIPT_DIR/build/$APP_NAME.dmg"

ICON_SRC="/Users/broganbunt/Loom_2026/loom_engine/Loom.app/Contents/Resources/AppIcon.icns"

# ── Clean previous build output ───────────────────────────────────────────────
echo "Cleaning previous build…"
rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$SCRIPT_DIR/build"

# ── Build release binary ───────────────────────────────────────────────────────
echo "Building release (this may take a minute)…"
swift build -c release 2>&1
echo "Build complete."

# Code-sign the raw binary now, while it's still a flat file outside any .app
# structure. Ad-hoc signing (the linker's default) hashes the binary's raw bytes,
# so every rebuild gets a fresh, never-before-seen signature and TCC (Full Disk
# Access, etc.) has no stable identity to bind a grant to. Signing with a real
# (even self-signed) identity keeps the signing identity constant across
# rebuilds, so permission grants survive. This has to happen before the binary
# is copied into Contents/MacOS — codesign auto-detects bundle context from a
# Contents/MacOS/ path and then refuses to sign because the SwiftPM resource
# bundle below sits loose at the app-bundle root (outside Contents/, where
# Bundle.module needs it), which trips codesign's "unsealed contents present
# in the bundle root" check. Signing the flat file first sidesteps that; the
# embedded signature survives the copy into the bundle.
echo "Code-signing with \"$SIGN_IDENTITY\"…"
codesign --force --sign "$SIGN_IDENTITY" "$RELEASE_DIR/$APP_NAME"

# ── Assemble .app bundle ──────────────────────────────────────────────────────
echo "Assembling $APP_NAME.app…"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary (already signed above)
cp "$RELEASE_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundle — must be at Bundle.main.bundleURL root
cp -R "$RELEASE_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/${APP_NAME}_${APP_NAME}.bundle"

# App icon
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    ICON_KEY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
    ICON_KEY=""
    echo "  (no icon found — continuing without one)"
fi

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
    $ICON_KEY
</dict>
</plist>
PLIST

# Register the bundle type with macOS
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP_BUNDLE" 2>/dev/null || true

echo "$APP_NAME.app assembled."

# ── Build .dmg ────────────────────────────────────────────────────────────────
echo "Creating disk image…"

mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo ""
echo "────────────────────────────────────────────"
echo "  Done!"
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo ""
echo "  To install: open the .dmg and drag Loom"
echo "  to your Applications folder."
echo "  Or: cp -R \"$APP_BUNDLE\" /Applications/"
echo "────────────────────────────────────────────"

# Open the build folder in Finder
open "$SCRIPT_DIR/build"
