#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DIR="$PROJECT_DIR/build/DerivedData"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_PATH="$DERIVED_DIR/Build/Products/Release/SimuBoard.app"
DMG_PATH="$OUTPUT_DIR/SimuBoard-0.3.1-unnotarized.dmg"
STAGE_DIR=$(mktemp -d /private/tmp/simuboard-dmg.XXXXXX)
LOCAL_SIGNING_COMMON_NAME="SimuBoard Local Code Signing"
LOCAL_SIGNING_KEYCHAIN=${SIMUBOARD_SIGNING_KEYCHAIN:-"$HOME/Library/Keychains/SimuBoardRelease.keychain-db"}
LOCAL_SIGNING_PASSWORD_FILE=${SIMUBOARD_SIGNING_PASSWORD_FILE:-"$HOME/Library/Application Support/SimuBoardBuild/signing-keychain-password"}
LOCAL_KEYCHAIN_WAS_UNLOCKED=false

cleanup() {
  rm -rf "$STAGE_DIR"
  if [[ "$LOCAL_KEYCHAIN_WAS_UNLOCKED" == true ]]; then
    security lock-keychain "$LOCAL_SIGNING_KEYCHAIN" 2>/dev/null || true
  fi
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

SIGNING_IDENTITY=${SIMUBOARD_SIGNING_IDENTITY:-}
SIGNING_KEYCHAIN_ARGS=()
if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ ! -f "$LOCAL_SIGNING_KEYCHAIN" || ! -f "$LOCAL_SIGNING_PASSWORD_FILE" ]]; then
    print -u2 "No stable SimuBoard code-signing identity was found."
    print -u2 "Run ./scripts/create-local-signing-identity.sh once, or set SIMUBOARD_SIGNING_IDENTITY."
    exit 1
  fi
  LOCAL_SIGNING_PASSWORD=$(<"$LOCAL_SIGNING_PASSWORD_FILE")
  security unlock-keychain -p "$LOCAL_SIGNING_PASSWORD" "$LOCAL_SIGNING_KEYCHAIN"
  LOCAL_KEYCHAIN_WAS_UNLOCKED=true
  SIGNING_IDENTITY=$(
    (security find-certificate -a -c "$LOCAL_SIGNING_COMMON_NAME" -Z "$LOCAL_SIGNING_KEYCHAIN" 2>/dev/null || true) \
      | awk '/SHA-1 hash:/{print $3; exit}'
  )
  SIGNING_KEYCHAIN_ARGS=(--keychain "$LOCAL_SIGNING_KEYCHAIN")
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  print -u2 "No stable SimuBoard code-signing identity was found."
  print -u2 "Run ./scripts/create-local-signing-identity.sh once, or set SIMUBOARD_SIGNING_IDENTITY."
  exit 1
fi

codesign \
  --force \
  --deep \
  --options runtime \
  --sign "$SIGNING_IDENTITY" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --timestamp=none \
  "$STAGE_DIR/SimuBoard.app"

codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/SimuBoard.app"
DESIGNATED_REQUIREMENT=$(codesign -d -r- "$STAGE_DIR/SimuBoard.app" 2>&1)
if [[ "$DESIGNATED_REQUIREMENT" == *"cdhash"* ]]; then
  print -u2 "Refusing to package an ad-hoc identity because it breaks Input Monitoring after updates."
  print -u2 "$DESIGNATED_REQUIREMENT"
  exit 1
fi
print "$DESIGNATED_REQUIREMENT"
if [[ -f "$LOCAL_SIGNING_KEYCHAIN" && ${#SIGNING_KEYCHAIN_ARGS[@]} -gt 0 ]]; then
  security lock-keychain "$LOCAL_SIGNING_KEYCHAIN"
  LOCAL_KEYCHAIN_WAS_UNLOCKED=false
fi
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
hdiutil create \
  -volname SimuBoard \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

print "Created $DMG_PATH"
