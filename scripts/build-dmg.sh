#!/usr/bin/env bash
# Build a release Tabby.app and package it as a distributable DMG.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PBXPROJ="$PROJECT_DIR/Tabby.xcodeproj/project.pbxproj"
VERSION="$(grep 'MARKETING_VERSION' "$PBXPROJ" | head -1 | sed -E 's/.*= ([^;]+);/\1/' | tr -d '[:space:]')"
VERSION="${VERSION:-1.1}"

APP_NAME="Tabby"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$PROJECT_DIR/dmg-staging"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Building ${APP_NAME} ${VERSION} (Release)..."
if command -v xcpretty &>/dev/null; then
  xcodebuild \
    -project Tabby.xcodeproj \
    -scheme Tabby \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build | xcpretty
else
  xcodebuild \
    -project Tabby.xcodeproj \
    -scheme Tabby \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app at $APP_PATH" >&2
  exit 1
fi

echo "==> Staging DMG contents..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -sf /Applications "$STAGING_DIR/Applications"
cp "$SCRIPT_DIR/INSTALL.txt" "$STAGING_DIR/INSTALL.txt"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating ${DMG_NAME}..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "Done: $DMG_PATH ($SIZE)"
echo "Share this file. Recipients should read INSTALL.txt inside the DMG."
