#!/usr/bin/env bash
# Wraps dist/Sentrel.app in a drag-to-install .dmg.
#   ./package.sh            # build the dmg
#   ./package.sh --upload   # build it and publish to S3
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Sentrel"
APP="dist/$APP_NAME.app"
DMG="dist/$APP_NAME.dmg"
STAGE="build/dmg"
BUCKET="s3://static.scribemd.ai"
KEY_PREFIX="sentrel"

[ -d "$APP" ] || { echo "no $APP — run ./build.sh first"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"

echo "==> Staging $APP_NAME ${VERSION}…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
# The /Applications symlink is what makes the window a drag-to-install target.
ln -s /Applications "$STAGE/Applications"

echo "==> Building disk image…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Built $DMG ($(du -h "$DMG" | cut -f1))"

if [ "${1:-}" = "--upload" ]; then
  echo "==> Uploading…"
  # Versioned copy is immutable; Sentrel.dmg is the stable URL the site links to
  # and must not be cached for long, or a release goes unnoticed for a day.
  aws s3 cp "$DMG" "$BUCKET/$KEY_PREFIX/$APP_NAME-$VERSION.dmg" \
    --content-type application/x-apple-diskimage \
    --cache-control "public, max-age=31536000, immutable"
  aws s3 cp "$DMG" "$BUCKET/$KEY_PREFIX/$APP_NAME.dmg" \
    --content-type application/x-apple-diskimage \
    --cache-control "public, max-age=300"
  echo
  echo "Live: https://static.scribemd.ai/$KEY_PREFIX/$APP_NAME.dmg"
  echo "      https://static.scribemd.ai/$KEY_PREFIX/$APP_NAME-$VERSION.dmg"
fi
