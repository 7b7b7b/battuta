#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DIR="$PROJECT_DIR/build/DerivedData"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_PATH="$DERIVED_DIR/Build/Products/Release/SimuBoard.app"
DMG_PATH="$OUTPUT_DIR/SimuBoard-0.1.0-unnotarized.dmg"
STAGE_DIR=$(mktemp -d /private/tmp/simuboard-dmg.XXXXXX)

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

xcodebuild \
  -project "$PROJECT_DIR/SimuBoardMac.xcodeproj" \
  -scheme SimuBoardMac \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

cp -R "$APP_PATH" "$STAGE_DIR/SimuBoard.app"
# The workspace may attach File Provider/Finder metadata. Stage outside it,
# strip metadata from the copy, then sign the exact app placed in the DMG.
xattr -cr "$STAGE_DIR/SimuBoard.app"
codesign --force --deep --sign - --timestamp=none "$STAGE_DIR/SimuBoard.app"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
hdiutil create \
  -volname SimuBoard \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

print "Created $DMG_PATH"
