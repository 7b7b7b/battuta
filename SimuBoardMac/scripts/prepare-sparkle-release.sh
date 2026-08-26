#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DIR="$PROJECT_DIR/build/DerivedData"
OUTPUT_DIR="$PROJECT_DIR/build"
PROJECT_FILE="$PROJECT_DIR/SimuBoardMac.xcodeproj"
SOURCE_INFO_PLIST="$PROJECT_DIR/SimuBoardMac/Info.plist"
KEY_ACCOUNT=${BATTUTA_SPARKLE_KEY_ACCOUNT:-com.simuboard.mac.sparkle}
REPOSITORY=${BATTUTA_GITHUB_REPOSITORY:-wormforce/battuta}
RELEASE_NOTES_FILE=${1:-}
RELEASE_STAGE=$(mktemp -d /private/tmp/battuta-sparkle-release.XXXXXX)
CERTIFICATE_CHECK_DIR=$(mktemp -d /private/tmp/battuta-certificate-check.XXXXXX)
DMG_MOUNT_POINT=$(mktemp -d /private/tmp/battuta-sparkle-mount.XXXXXX)
DMG_IS_MOUNTED=false

cleanup() {
  if [[ "$DMG_IS_MOUNTED" == true ]]; then
    hdiutil detach "$DMG_MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rmdir "$DMG_MOUNT_POINT" 2>/dev/null || true
  rm -rf "$CERTIFICATE_CHECK_DIR"
  rm -rf "$RELEASE_STAGE"
}
trap cleanup EXIT

if [[ ${BATTUTA_SKIP_DMG_BUILD:-false} != true ]]; then
  "$SCRIPT_DIR/build-dmg.sh"
fi

BUILD_SETTINGS=$(xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme SimuBoardMac \
  -configuration Release \
  -showBuildSettings)
VERSION=$(awk '/^[[:space:]]*MARKETING_VERSION = /{print $3; exit}' <<< "$BUILD_SETTINGS")
BUILD=$(awk '/^[[:space:]]*CURRENT_PROJECT_VERSION = /{print $3; exit}' <<< "$BUILD_SETTINGS")
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$BUILD" =~ '^[0-9]+$' ]]; then
  print -u2 "Invalid release version/build: $VERSION ($BUILD)"
  exit 1
fi

DMG_PATH="$OUTPUT_DIR/Battuta-$VERSION-unnotarized.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
  print -u2 "Release DMG not found: $DMG_PATH"
  exit 1
fi

SPARKLE_BIN_DIR=${BATTUTA_SPARKLE_BIN_DIR:-"$DERIVED_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin"}
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
GENERATE_KEYS="$SPARKLE_BIN_DIR/generate_keys"
SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"
for tool in "$GENERATE_APPCAST" "$GENERATE_KEYS" "$SIGN_UPDATE"; do
  if [[ ! -x "$tool" ]]; then
    print -u2 "Sparkle release tool not found: $tool"
    print -u2 "Resolve/build the Xcode project first, or set BATTUTA_SPARKLE_BIN_DIR."
    exit 1
  fi
done

APP_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$SOURCE_INFO_PLIST")
if ! KEYCHAIN_PUBLIC_KEY=$("$GENERATE_KEYS" --account "$KEY_ACCOUNT" -p); then
  print -u2 -- "$KEYCHAIN_PUBLIC_KEY"
  print -u2 "Restore the existing Sparkle signing key for Keychain account '$KEY_ACCOUNT'."
  exit 1
fi
if [[ "$APP_PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]]; then
  print -u2 "The app's SUPublicEDKey does not match Keychain account '$KEY_ACCOUNT'."
  exit 1
fi

EXPECTED_FEED_URL="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
APP_FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$SOURCE_INFO_PLIST")
if [[ "$APP_FEED_URL" != "$EXPECTED_FEED_URL" ]]; then
  print -u2 "Unexpected SUFeedURL: $APP_FEED_URL"
  print -u2 "Expected: $EXPECTED_FEED_URL"
  exit 1
fi

ARCHIVE_NAME=${DMG_PATH:t}
STAGED_DMG_PATH="$RELEASE_STAGE/$ARCHIVE_NAME"
cp "$DMG_PATH" "$STAGED_DMG_PATH"

hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$DMG_MOUNT_POINT" \
  "$STAGED_DMG_PATH"
DMG_IS_MOUNTED=true

PACKAGED_APP="$DMG_MOUNT_POINT/Battuta.app"
PACKAGED_INFO_PLIST="$PACKAGED_APP/Contents/Info.plist"
PACKAGED_SPARKLE_INFO_PLIST="$PACKAGED_APP/Contents/Frameworks/Sparkle.framework/Resources/Info.plist"
PACKAGED_BCP_ROOT="$PACKAGED_APP/Contents/Resources/BundledSoundPacks/15d04652-5265-4ea7-a376-8a7e11ff6813.simuboardpack"
PACKAGED_BCP_MANIFEST="$PACKAGED_BCP_ROOT/manifest.json"
if [[ ! -d "$PACKAGED_APP" || ! -f "$PACKAGED_INFO_PLIST" ]]; then
  print -u2 "The DMG does not contain Battuta.app at its top level."
  exit 1
fi
codesign --verify --deep --strict --all-architectures --verbose=2 "$PACKAGED_APP"
PACKAGED_SIGNING_DETAILS=$(codesign -d --verbose=4 "$PACKAGED_APP" 2>&1)
if [[ "$PACKAGED_SIGNING_DETAILS" != *"runtime"* ]]; then
  print -u2 "The packaged app is missing Hardened Runtime."
  exit 1
fi
if [[ "$PACKAGED_SIGNING_DETAILS" == *"TeamIdentifier=not set"* ]]; then
  PACKAGED_ENTITLEMENTS=$(codesign -d --entitlements - --xml "$PACKAGED_APP" 2>&1)
  if [[ "$PACKAGED_ENTITLEMENTS" != *"com.apple.security.cs.disable-library-validation"* \
    || "$PACKAGED_ENTITLEMENTS" != *"<true/>"* ]]; then
    print -u2 "The self-signed app cannot load its embedded Sparkle framework."
    exit 1
  fi
fi
PACKAGED_CERTIFICATE_PREFIX="$CERTIFICATE_CHECK_DIR/packaged-signing-certificate-"
codesign -d --extract-certificates="$PACKAGED_CERTIFICATE_PREFIX" \
  "$PACKAGED_APP" >/dev/null 2>&1
if [[ ! -s "${PACKAGED_CERTIFICATE_PREFIX}0" ]]; then
  print -u2 "The packaged app does not contain its signing certificate chain."
  exit 1
fi
if [[ "$PACKAGED_SIGNING_DETAILS" != *"TeamIdentifier=not set"* \
  && ! -s "${PACKAGED_CERTIFICATE_PREFIX}1" ]]; then
  print -u2 "The packaged Developer ID signature is missing its intermediate certificate."
  exit 1
fi
DESIGNATED_REQUIREMENT=$(codesign -d -r- "$PACKAGED_APP" 2>&1)
if [[ "$DESIGNATED_REQUIREMENT" == *"cdhash"* ]]; then
  print -u2 "Refusing to sign an ad-hoc application update."
  exit 1
fi
lipo "$PACKAGED_APP/Contents/MacOS/Battuta" -verify_arch x86_64
lipo "$PACKAGED_APP/Contents/MacOS/Battuta" -verify_arch arm64

PACKAGED_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PACKAGED_INFO_PLIST")
PACKAGED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PACKAGED_INFO_PLIST")
PACKAGED_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PACKAGED_INFO_PLIST")
PACKAGED_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PACKAGED_INFO_PLIST")
PACKAGED_FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PACKAGED_INFO_PLIST")
PACKAGED_VERIFY_BEFORE_EXTRACTION=$(
  /usr/libexec/PlistBuddy -c "Print :SUVerifyUpdateBeforeExtraction" "$PACKAGED_INFO_PLIST"
)
if [[ "$PACKAGED_BUNDLE_ID" != com.simuboard.mac \
  || "$PACKAGED_VERSION" != "$VERSION" \
  || "$PACKAGED_BUILD" != "$BUILD" \
  || "$PACKAGED_PUBLIC_KEY" != "$APP_PUBLIC_KEY" \
  || "$PACKAGED_FEED_URL" != "$EXPECTED_FEED_URL" \
  || "$PACKAGED_VERIFY_BEFORE_EXTRACTION" != true ]]; then
  print -u2 "The packaged app does not match the current release configuration."
  exit 1
fi
if [[ ! -f "$PACKAGED_SPARKLE_INFO_PLIST" \
  || ! -f "$PACKAGED_APP/Contents/Resources/SPARKLE_LICENSE.txt" ]]; then
  print -u2 "The packaged app is missing Sparkle or its license."
  exit 1
fi
PACKAGED_SPARKLE_VERSION=$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PACKAGED_SPARKLE_INFO_PLIST"
)
if [[ "$PACKAGED_SPARKLE_VERSION" != 2.9.6 ]]; then
  print -u2 "Unexpected packaged Sparkle version: $PACKAGED_SPARKLE_VERSION"
  exit 1
fi

if [[ ! -f "$PACKAGED_BCP_MANIFEST" \
  || ! -f "$PACKAGED_BCP_ROOT/licenses/BCP-Suit80-PERMISSION.txt" ]]; then
  print -u2 "The packaged app is missing the authorized BCP (Suit80) sound pack or notice."
  exit 1
fi
if ! jq -e '
  (.schemaVersion == 1)
  and (.id == "15d04652-5265-4ea7-a376-8a7e11ff6813")
  and (.name == "BCP (Suit80)")
  and (.assets | type == "object" and length == 28)
  and (.attributions == [{
    title: "【打字声音】Suit80｜BCP轴｜GMK Ursa 大熊 - Original.mp4",
    author: "J_Eason001",
    sourceURL: null,
    licenseName: "Used with permission",
    notice: "Redistribution authorized; the permission record is retained by the Battuta maintainer."
  }])
' "$PACKAGED_BCP_MANIFEST" >/dev/null; then
  print -u2 "The packaged BCP (Suit80) manifest does not match the release contract."
  exit 1
fi

PACKAGED_BCP_ASSET_COUNT=$(find "$PACKAGED_BCP_ROOT/assets" -type f -name '*.wav' | wc -l | tr -d ' ')
if [[ "$PACKAGED_BCP_ASSET_COUNT" != 28 ]]; then
  print -u2 "The packaged BCP (Suit80) asset inventory is incomplete."
  exit 1
fi
while IFS=$'\t' read -r relative_path expected_hash expected_bytes; do
  packaged_asset="$PACKAGED_BCP_ROOT/$relative_path"
  if [[ ! -f "$packaged_asset" \
    || "$(stat -f%z "$packaged_asset")" != "$expected_bytes" \
    || "$(shasum -a 256 "$packaged_asset" | awk '{print $1}')" != "$expected_hash" ]]; then
    print -u2 "Packaged BCP asset verification failed: $relative_path"
    exit 1
  fi
done < <(jq -r '.assets[] | [.relativePath, .sha256, (.byteCount | tostring)] | @tsv' "$PACKAGED_BCP_MANIFEST")

hdiutil detach "$DMG_MOUNT_POINT"
DMG_IS_MOUNTED=false
rmdir "$DMG_MOUNT_POINT"

if [[ -n "$RELEASE_NOTES_FILE" ]]; then
  if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    print -u2 "Release notes file not found: $RELEASE_NOTES_FILE"
    exit 1
  fi
  cp "$RELEASE_NOTES_FILE" "$RELEASE_STAGE/${ARCHIVE_NAME:r}.md"
fi

DOWNLOAD_PREFIX="https://github.com/$REPOSITORY/releases/download/v$VERSION/"
RELEASE_LINK="https://github.com/$REPOSITORY/releases/tag/v$VERSION"
"$GENERATE_APPCAST" \
  --account "$KEY_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "$RELEASE_LINK" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  --embed-release-notes \
  -o "$RELEASE_STAGE/appcast.xml" \
  "$RELEASE_STAGE"

APPCAST_PATH="$OUTPUT_DIR/appcast.xml"
cp "$RELEASE_STAGE/appcast.xml" "$APPCAST_PATH"
/usr/bin/xmllint --noout "$APPCAST_PATH"

ENCLOSURE_URL=$(/usr/bin/xmllint --xpath 'string((//*[local-name()="enclosure"]/@url)[1])' "$APPCAST_PATH")
ENCLOSURE_LENGTH=$(/usr/bin/xmllint --xpath 'string((//*[local-name()="enclosure"]/@length)[1])' "$APPCAST_PATH")
ENCLOSURE_SIGNATURE=$(/usr/bin/xmllint --xpath 'string((//*[local-name()="enclosure"]/@*[local-name()="edSignature"])[1])' "$APPCAST_PATH")
EXPECTED_URL="$DOWNLOAD_PREFIX$ARCHIVE_NAME"
ACTUAL_LENGTH=$(stat -f%z "$DMG_PATH")

if [[ "$ENCLOSURE_URL" != "$EXPECTED_URL" ]]; then
  print -u2 "Unexpected appcast enclosure URL: $ENCLOSURE_URL"
  exit 1
fi
if [[ "$ENCLOSURE_LENGTH" != "$ACTUAL_LENGTH" ]]; then
  print -u2 "Appcast enclosure length does not match the DMG."
  exit 1
fi
if [[ -z "$ENCLOSURE_SIGNATURE" ]]; then
  print -u2 "Appcast is missing the Sparkle Ed25519 signature."
  exit 1
fi

"$SIGN_UPDATE" --account "$KEY_ACCOUNT" --verify "$DMG_PATH" "$ENCLOSURE_SIGNATURE"

SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
print "Prepared Sparkle release $VERSION ($BUILD)"
print "DMG:     $DMG_PATH"
print "Appcast: $APPCAST_PATH"
print "SHA-256: $SHA256"
print "Upload both files to GitHub Release v$VERSION."
