#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh v1.8.0 "feat: Sparkle auto-update"

VERSION="${1:?Usage: release.sh <version-tag> <release-title>}"
TITLE="${2:?Usage: release.sh <version-tag> <release-title>}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AIMETER_DIR="$PROJECT_DIR/AIMeter"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/AIMeter.xcarchive"
APP_PATH="$BUILD_DIR/AIMeter.app"
ZIP_PATH="$BUILD_DIR/AIMeter-${VERSION}.zip"
APPCAST_DIR="$BUILD_DIR/appcast"
SIGN_UPDATE="$PROJECT_DIR/scripts/sparkle-tools/sign_update"
GENERATE_APPCAST="$PROJECT_DIR/scripts/sparkle-tools/generate_appcast"

# Preflight checks
for tool in "$SIGN_UPDATE" "$GENERATE_APPCAST"; do
    if [[ ! -x "$tool" ]]; then
        echo "ERROR: $tool not found or not executable."
        echo "Build Sparkle tools first (see docs/plans/2026-03-05-sparkle-auto-update-design.md Task 1)"
        exit 1
    fi
done

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required. Install: brew install gh"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "ERROR: xcodebuild required."; exit 1; }

echo "==> Bumping version in project.yml..."
SEMVER="${VERSION#v}"
PROJ_YML="$AIMETER_DIR/project.yml"
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJ_YML" | sed 's/.*"\([0-9]*\)".*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$SEMVER\"/" "$PROJ_YML"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJ_YML"
echo "    MARKETING_VERSION: $SEMVER"
echo "    CURRENT_PROJECT_VERSION: $NEW_BUILD (was $CURRENT_BUILD)"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Regenerating Xcode project..."
cd "$AIMETER_DIR"
xcodegen generate

echo "==> Archiving AIMeter..."
xcodebuild archive \
    -project AIMeter.xcodeproj \
    -scheme AIMeter \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | tail -3

echo "==> Exporting .app from archive..."
cp -R "$ARCHIVE_PATH/Products/Applications/AIMeter.app" "$APP_PATH"

echo "==> Re-signing with AIMeter Dev..."
codesign --force --deep --sign "AIMeter Dev" "$APP_PATH"

echo "==> Creating zip..."
cd "$BUILD_DIR"
ditto -c -k --keepParent "AIMeter.app" "$(basename "$ZIP_PATH")"

echo "==> Generating appcast..."
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/"
"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/Khairul989/ai-meter/releases/download/${VERSION}/" \
    "$APPCAST_DIR"

NOTES="## What's New

$TITLE

## Install

Download AIMeter-${VERSION}.zip, unzip, and move AIMeter.app to /Applications.
First launch: right-click -> Open to bypass Gatekeeper."

echo "==> Creating GitHub Release $VERSION..."
gh release create "$VERSION" \
    --repo Khairul989/ai-meter \
    --title "$TITLE" \
    --notes "$NOTES" \
    "$ZIP_PATH" \
    "$APPCAST_DIR/appcast.xml"

echo ""
echo "==> Release $VERSION published!"
echo "    https://github.com/Khairul989/ai-meter/releases/tag/$VERSION"
