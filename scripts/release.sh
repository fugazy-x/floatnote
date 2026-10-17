#!/bin/bash
# Builds FloatNote.dmg for one version:   ./scripts/release.sh 1.0.1
# With --publish (after the build): tag v<version>, push the tag, make the GitHub release with FloatNote.dmg.
# Without --publish it only builds and changes nothing on GitHub.
# Steps (R1): version + build number, Release build (arm64 + x86_64), sign, verify, .dmg. Output: build/
# The build number is kept in scripts/BUILD_NUMBER (the last one used); each run adds 1.
set -euo pipefail
cd "$(dirname "$0")/.."

STEP="start"
trap 'echo "FAILED at step: $STEP" >&2' ERR
step() { STEP="$1"; echo "==> $1"; }

PUBLISH=no
VERSION=""
for a in "$@"; do
  case "$a" in
    --publish) PUBLISH=yes ;;
    *) VERSION="$a" ;;
  esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: ./scripts/release.sh <version> [--publish]   (example: 1.0.1)" >&2; exit 1; }
ID="local.floatnote"
IDENTITY="FloatNote Local Signing"          # fixed certificate: same for every version (keeps user permissions)
MINOS="26.0"
BUILD_DIR="build"
APP="$BUILD_DIR/FloatNote.app"
DMG="$BUILD_DIR/FloatNote.dmg"

step "1. Version $VERSION and build number"
LAST=$(cat scripts/BUILD_NUMBER 2>/dev/null || echo 0)
BUILD=$((LAST + 1))
echo "   version $VERSION, build $BUILD"

step "2. Release build (swiftc -O, macOS $MINOS)"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target "arm64-apple-macos$MINOS" FloatNote.swift -o "$BUILD_DIR/obj/FloatNote-arm64"

step "3. Universal binary (arm64 + x86_64)"
if swiftc -O -swift-version 5 -target "x86_64-apple-macos$MINOS" FloatNote.swift -o "$BUILD_DIR/obj/FloatNote-x86_64" 2> "$BUILD_DIR/obj/x86_64.log"; then
  lipo -create "$BUILD_DIR/obj/FloatNote-arm64" "$BUILD_DIR/obj/FloatNote-x86_64" -output "$APP/Contents/MacOS/FloatNote"
else
  echo "   x86_64 build failed (see $BUILD_DIR/obj/x86_64.log); arm64 only."
  cp "$BUILD_DIR/obj/FloatNote-arm64" "$APP/Contents/MacOS/FloatNote"
fi
echo "   architectures: $(lipo -archs "$APP/Contents/MacOS/FloatNote")"

# App icon from the 1024 px PNG.
ICONSET="$BUILD_DIR/obj/FloatNote.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s floatnote-icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) floatnote-icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/FloatNote.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FloatNote</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>FloatNote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>FloatNote</string>
  <key>LSMinimumSystemVersion</key><string>$MINOS</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

step "4. Sign with \"$IDENTITY\""
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || { echo "Certificate \"$IDENTITY\" not found." >&2; false; }
perl -e 'alarm 120; exec @ARGV' codesign --force --deep -s "$IDENTITY" -i "$ID" "$APP"

step "5. Verify the signature"
codesign --verify --deep --strict --verbose=2 "$APP"

step "6. Make the .dmg (hdiutil)"
STAGE="$BUILD_DIR/obj/dmg"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift scripts/dmg-background.swift "$STAGE/.background/background.png"
RW="$BUILD_DIR/obj/FloatNote-rw.dmg"
hdiutil create -quiet -volname "FloatNote" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
osascript <<OSA
tell application "Finder"
  tell disk "FloatNote"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:background.png"
    set position of item "FloatNote.app" of container window to {150, 170}
    set position of item "Applications" of container window to {450, 170}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
rm -rf "$MNT/.fseventsd"                     # no other files in the .dmg
sync
hdiutil detach -quiet "$MNT"

step "7. FloatNote.dmg (compressed, no version in the name)"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"

step "8. Clean up (all output stays in $BUILD_DIR/)"
rm -rf "$BUILD_DIR/obj"
echo "$BUILD" > scripts/BUILD_NUMBER

if [ "$PUBLISH" = yes ]; then
  TAG="v$VERSION"
  NOTES="FloatNote shows one note in a small box that floats above your other apps.
Your notes are plain .txt files in Documents/FloatNote. Tap Right Option to show or hide the box.

Install:
1. Open FloatNote.dmg and drag FloatNote to Applications.
2. Open FloatNote. macOS says that it cannot verify the app. Click Done.
3. Open System Settings > Privacy & Security. Scroll down and click Open Anyway."
  step "9. Tag $TAG"
  git tag "$TAG"
  step "10. Push the tag"
  git push origin "$TAG"
  step "11. GitHub release \"FloatNote $VERSION\" with FloatNote.dmg"
  gh release create "$TAG" "$DMG" --title "FloatNote $VERSION" --notes "$NOTES"
fi
trap - ERR
echo "Done: $(cd "$BUILD_DIR" && pwd)/FloatNote.dmg"
