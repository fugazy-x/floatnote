#!/bin/bash
# Builds FloatNote.app into ~/Applications and starts it.
# Run it from the folder that has FloatNote.swift:   bash install.sh
# Re-run any time to rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/FloatNote.app"
ID="local.floatnote"
AGENT="$HOME/Library/LaunchAgents/$ID.plist"

if [ ! -f FloatNote.swift ]; then
  echo "Put FloatNote.swift in the same folder as this script, then run it again."
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Apple's command line tools aren't installed yet."
  echo "Run:  xcode-select --install   — then run this script again."
  exit 1
fi

# Version: the latest vX.Y.Z git tag, build: scripts/BUILD_NUMBER (both from scripts/release.sh).
VERSION=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//'); VERSION=${VERSION:-1.0}
BUILD=$(cat scripts/BUILD_NUMBER 2>/dev/null || echo 1)

echo "Building FloatNote $VERSION ($BUILD)…"
# Compile first: if it fails, the installed app is left as it was.
BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TMP"' EXIT
swiftc -O -swift-version 5 FloatNote.swift -o "$BUILD_TMP/FloatNote"
pkill -x FloatNote 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv "$BUILD_TMP/FloatNote" "$APP/Contents/MacOS/FloatNote"

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
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# App icon from the 1024 px PNG (same as scripts/release.sh).
if [ -f floatnote-icon-1024.png ]; then
  ICONSET="$(mktemp -d)/FloatNote.iconset"; mkdir -p "$ICONSET" "$APP/Contents/Resources"
  for s in 16 32 128 256 512; do
    sips -z $s $s floatnote-icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) floatnote-icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/FloatNote.icns" && \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string FloatNote" "$APP/Contents/Info.plist" >/dev/null
fi

# Sign with a stable local certificate so macOS remembers permissions (Accessibility)
# across rebuilds. Falls back to ad-hoc if the cert is missing or signing doesn't finish.
IDENTITY="FloatNote Local Signing"
SIGNED=no
if [ -z "${FLOATNOTE_ADHOC:-}" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  if perl -e 'alarm 60; exec @ARGV' codesign --force --deep -s "$IDENTITY" -i "$ID" "$APP" >/dev/null 2>&1; then
    SIGNED=yes
  else
    echo "Signing with \"$IDENTITY\" failed or timed out; using ad-hoc signing."
  fi
fi
[ "$SIGNED" = yes ] || codesign --force --sign - -i "$ID" "$APP" >/dev/null 2>&1 || true

# Not run from a terminal (or FLOATNOTE_KEEP_LOGIN set): keep the current login setting.
if [ -t 0 ] && [ -z "${FLOATNOTE_KEEP_LOGIN:-}" ]; then
  read -r -p "Start FloatNote automatically when you log in? (y/n) " LOGIN
else
  [ -f "$AGENT" ] && LOGIN=y || LOGIN=n
fi
if [[ "$LOGIN" =~ ^[Yy] ]]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ID</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/FloatNote</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
else
  rm -f "$AGENT"
fi

# Only ~/Applications/FloatNote.app should be installed; report (never delete) other copies.
# The release build in build/ is skipped.
while IFS= read -r p; do
  [ "$p" = "$APP" ] && continue
  case "$p" in "$PWD/build/"*|"$HOME/.Trash/"*) continue ;; esac
  echo "Note: another FloatNote copy exists at $p (not removed)."
done < <(mdfind "kMDItemCFBundleIdentifier == '$ID'" 2>/dev/null)

open "$APP"
echo "Done — FloatNote is in the top-right corner. Tap Right Option to jump in and out."
