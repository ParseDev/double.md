#!/usr/bin/env bash
# Builds Sentrel.app — a native WKWebView shell around https://sentrel.ai.
# Needs only the Xcode command line tools (swiftc, sips, iconutil).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Sentrel"
BUILD_DIR="build"
DIST_DIR="dist"
APP="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
FALLBACK_ICON="../mobile/assets/icon.png"
# A hand-authored logo wins when present; the blobatar knobs below are the fallback.
ICON_SOURCE="${ICON_SOURCE:-icon.svg}"
ICON_SEED="${ICON_SEED:-Sentrel}"
ICON_EXPRESSION="${ICON_EXPRESSION:-happy}"
ICON_BACKGROUND="${ICON_BACKGROUND:-none}"
ICON_HUE="${ICON_HUE:-180}"
ICON_TONE="${ICON_TONE:-0.9}"

rm -rf "$BUILD_DIR" "$APP"
mkdir -p "$BUILD_DIR" "$CONTENTS/MacOS" "$CONTENTS/Resources"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
SOURCES=(Sources/Config.swift Sources/Palette.swift Sources/ErrorView.swift Sources/BrowserWindowController.swift Sources/AppDelegate.swift Sources/main.swift)

compile() {
  local arch="$1" out="$2"
  swiftc -O -sdk "$SDK" -target "${arch}-apple-macos13.0" \
    -framework Cocoa -framework WebKit \
    -o "$out" "${SOURCES[@]}"
}

# Universal binary when both slices build, otherwise just this machine's arch.
echo "==> Compiling (arm64)…"
compile arm64 "$BUILD_DIR/$APP_NAME-arm64"

if echo "==> Compiling (x86_64)…" && compile x86_64 "$BUILD_DIR/$APP_NAME-x86_64" 2>/dev/null; then
  lipo -create -output "$CONTENTS/MacOS/$APP_NAME" \
    "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"
  echo "==> Universal binary (arm64 + x86_64)"
else
  cp "$BUILD_DIR/$APP_NAME-arm64" "$CONTENTS/MacOS/$APP_NAME"
  echo "==> arm64 only (x86_64 slice unavailable on this toolchain)"
fi
chmod +x "$CONTENTS/MacOS/$APP_NAME"

cp Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Icon: render the product's own blobatar for this seed, then cut the .icns.
# Falls back to the mobile app icon if node or the blobatar package is missing.
echo "==> Building icon…"
ICONSET="$BUILD_DIR/AppIcon.iconset"
MASTER="$BUILD_DIR/icon-1024.png"
mkdir -p "$ICONSET"

if [ -f "$ICON_SOURCE" ]; then
  ICON_ARGS=(--source="$ICON_SOURCE")
else
  ICON_ARGS=(--seed="$ICON_SEED" --expression="$ICON_EXPRESSION" --background="$ICON_BACKGROUND" --hue="$ICON_HUE" --tone="$ICON_TONE")
fi

if command -v node >/dev/null && node tools/make-icon.mjs "$BUILD_DIR/icon.svg" "${ICON_ARGS[@]}"; then
  # WebKit rasterises it — same engine the app renders with, so no extra tooling.
  swiftc -O -sdk "$SDK" -target "arm64-apple-macos13.0" \
    -framework Cocoa -framework WebKit -o "$BUILD_DIR/svg2png" tools/svg2png.swift
  # A tile follows the 824-in-1024 app-icon convention; a free-form silhouette
  # sizes itself inside the full canvas, so it is rasterised edge to edge.
  if [ -f "$ICON_SOURCE" ] || [ "$ICON_BACKGROUND" = "none" ]; then
    "$BUILD_DIR/svg2png" "$BUILD_DIR/icon.svg" "$MASTER" 1024 1024
  else
    "$BUILD_DIR/svg2png" "$BUILD_DIR/icon.svg" "$MASTER" 1024 824
  fi
elif [ -f "$FALLBACK_ICON" ]; then
  echo "    blobatar unavailable — falling back to $FALLBACK_ICON"
  cp "$FALLBACK_ICON" "$MASTER"
else
  echo "    no icon source — building without one"
  MASTER=""
fi

if [ -n "$MASTER" ]; then
  for size in 16 32 128 256 512; do
    sips -z $size $size "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
fi

# Ad-hoc signature: keeps the keychain/cookie identity stable across rebuilds.
echo "==> Signing…"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "    (ad-hoc signing skipped)"

rm -rf "$BUILD_DIR"
echo
echo "Built $APP  ($(du -sh "$APP" | cut -f1))"
echo "Run it:      open $APP"
echo "Install it:  cp -R $APP /Applications/"
