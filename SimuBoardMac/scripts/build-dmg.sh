#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DIR="$PROJECT_DIR/build/DerivedData"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_PATH="$DERIVED_DIR/Build/Products/Release/Battuta.app"
STAGE_DIR=$(mktemp -d /private/tmp/simuboard-dmg.XXXXXX)
CERTIFICATE_CHECK_DIR=$(mktemp -d /private/tmp/simuboard-certificate-check.XXXXXX)
LOCAL_SIGNING_COMMON_NAME="SimuBoard Local Code Signing"
LOCAL_SIGNING_KEYCHAIN=${SIMUBOARD_SIGNING_KEYCHAIN:-"$HOME/Library/Keychains/SimuBoardRelease.keychain-db"}
LOCAL_SIGNING_PASSWORD_FILE=${SIMUBOARD_SIGNING_PASSWORD_FILE:-"$HOME/Library/Application Support/SimuBoardBuild/signing-keychain-password"}
LOCAL_KEYCHAIN_WAS_UNLOCKED=false
USER_KEYCHAIN_SEARCH_LIST_WAS_CAPTURED=false
USER_KEYCHAIN_SEARCH_LIST_IS_MODIFIED=false
ORIGINAL_USER_KEYCHAINS=()

cleanup() {
  rm -rf "$STAGE_DIR"
  rm -rf "$CERTIFICATE_CHECK_DIR"
  if [[ "$USER_KEYCHAIN_SEARCH_LIST_WAS_CAPTURED" == true \
    && "$USER_KEYCHAIN_SEARCH_LIST_IS_MODIFIED" == true ]]; then
    security list-keychains -d user -s "${ORIGINAL_USER_KEYCHAINS[@]}" 2>/dev/null || true
  fi
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

APP_BUILD_VERSION=$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist"
)
if [[ ! "$APP_BUILD_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Invalid Battuta version in built app: $APP_BUILD_VERSION"
  exit 1
fi
DMG_PATH="$OUTPUT_DIR/Battuta-$APP_BUILD_VERSION-unnotarized.dmg"

cp -R "$APP_PATH" "$STAGE_DIR/Battuta.app"
# The workspace may attach File Provider/Finder metadata. Stage outside it,
# strip metadata from the copy, then sign the exact app placed in the DMG.
xattr -cr "$STAGE_DIR/Battuta.app"

STAGED_INFO_PLIST="$STAGE_DIR/Battuta.app/Contents/Info.plist"
SPARKLE_INFO_PLIST="$STAGE_DIR/Battuta.app/Contents/Frameworks/Sparkle.framework/Resources/Info.plist"
if [[ ! -f "$SPARKLE_INFO_PLIST" ]]; then
  print -u2 "Sparkle.framework is missing from the release app."
  exit 1
fi
SPARKLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SPARKLE_INFO_PLIST")
if [[ "$SPARKLE_VERSION" != 2.9.6 ]]; then
  print -u2 "Unexpected Sparkle version in release app: $SPARKLE_VERSION"
  exit 1
fi
if [[ ! -f "$STAGE_DIR/Battuta.app/Contents/Resources/SPARKLE_LICENSE.txt" ]]; then
  print -u2 "Sparkle license is missing from the release app."
  exit 1
fi
SPARKLE_FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$STAGED_INFO_PLIST")
SPARKLE_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$STAGED_INFO_PLIST")
SPARKLE_VERIFY_BEFORE_EXTRACTION=$(
  /usr/libexec/PlistBuddy -c "Print :SUVerifyUpdateBeforeExtraction" "$STAGED_INFO_PLIST"
)
if [[ "$SPARKLE_FEED_URL" != "https://github.com/7b7b7b/battuta/releases/latest/download/appcast.xml" \
  || -z "$SPARKLE_PUBLIC_KEY" \
  || "$SPARKLE_VERIFY_BEFORE_EXTRACTION" != true ]]; then
  print -u2 "Sparkle release configuration is incomplete."
  exit 1
fi

SIGNING_IDENTITY=${SIMUBOARD_SIGNING_IDENTITY:-}
SIGNING_KEYCHAIN_ARGS=()
SIGNING_TIMESTAMP_ARGS=(--timestamp)
MAIN_APP_ENTITLEMENTS_ARGS=()
if [[ -n "$SIGNING_IDENTITY" \
  && "$SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
  print -u2 "SIMUBOARD_SIGNING_IDENTITY must name a Developer ID Application certificate."
  print -u2 "Use the built-in local identity for self-signed packages."
  exit 1
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ ! -f "$LOCAL_SIGNING_KEYCHAIN" || ! -f "$LOCAL_SIGNING_PASSWORD_FILE" ]]; then
    print -u2 "No stable SimuBoard code-signing identity was found."
    print -u2 "Run ./scripts/create-local-signing-identity.sh once, or set SIMUBOARD_SIGNING_IDENTITY."
    exit 1
  fi
  LOCAL_SIGNING_PASSWORD=$(<"$LOCAL_SIGNING_PASSWORD_FILE")
  security unlock-keychain -p "$LOCAL_SIGNING_PASSWORD" "$LOCAL_SIGNING_KEYCHAIN"
  LOCAL_KEYCHAIN_WAS_UNLOCKED=true
  USER_KEYCHAIN_LIST_OUTPUT=$(security list-keychains -d user)
  while IFS= read -r user_keychain; do
    if [[ -n "$user_keychain" ]]; then
      ORIGINAL_USER_KEYCHAINS+=("$user_keychain")
    fi
  done < <(
    print -r -- "$USER_KEYCHAIN_LIST_OUTPUT" \
      | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
  )
  if [[ ${#ORIGINAL_USER_KEYCHAINS[@]} -eq 0 ]]; then
    print -u2 "The user keychain search list is empty; refusing to modify it for signing."
    exit 1
  fi
  USER_KEYCHAIN_SEARCH_LIST_WAS_CAPTURED=true

  # codesign only embeds a complete certificate chain when the identity's
  # keychain is also in the user search list, even if --keychain is supplied.
  # Add it only for signing and restore the exact original list afterwards.
  SIGNING_USER_KEYCHAINS=("${ORIGINAL_USER_KEYCHAINS[@]}")
  LOCAL_SIGNING_KEYCHAIN_ABSOLUTE=${LOCAL_SIGNING_KEYCHAIN:A}
  LOCAL_KEYCHAIN_IS_LISTED=false
  for user_keychain in "${SIGNING_USER_KEYCHAINS[@]}"; do
    if [[ "${user_keychain:A}" == "$LOCAL_SIGNING_KEYCHAIN_ABSOLUTE" ]]; then
      LOCAL_KEYCHAIN_IS_LISTED=true
      break
    fi
  done
  if [[ "$LOCAL_KEYCHAIN_IS_LISTED" == false ]]; then
    SIGNING_USER_KEYCHAINS+=("$LOCAL_SIGNING_KEYCHAIN_ABSOLUTE")
  fi
  USER_KEYCHAIN_SEARCH_LIST_IS_MODIFIED=true
  security list-keychains -d user -s "${SIGNING_USER_KEYCHAINS[@]}"
  SIGNING_IDENTITY=$(
    (security find-certificate -a -c "$LOCAL_SIGNING_COMMON_NAME" -Z "$LOCAL_SIGNING_KEYCHAIN" 2>/dev/null || true) \
      | awk '/SHA-1 hash:/{print $3; exit}'
  )
  SIGNING_KEYCHAIN_ARGS=(--keychain "$LOCAL_SIGNING_KEYCHAIN")
  SIGNING_TIMESTAMP_ARGS=(--timestamp=none)
  # A local self-signed certificate has no Apple Team ID, so Library Validation
  # cannot recognize the embedded Sparkle framework as same-team code. Keep the
  # rest of Hardened Runtime enabled, but relax this one check on the main app.
  MAIN_APP_ENTITLEMENTS_ARGS=(
    --entitlements "$PROJECT_DIR/Signing/LocalSelfSigned.entitlements"
  )
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  print -u2 "No stable SimuBoard code-signing identity was found."
  print -u2 "Run ./scripts/create-local-signing-identity.sh once, or set SIMUBOARD_SIGNING_IDENTITY."
  exit 1
fi

SPARKLE_FRAMEWORK="$STAGE_DIR/Battuta.app/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"

# Sparkle's helpers have different entitlement requirements. Sign them
# inside-out instead of using --deep, then sign only the main executable with
# the local Library Validation exception when a Developer ID is unavailable.
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" "${SIGNING_TIMESTAMP_ARGS[@]}" \
  "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
codesign --force --options runtime --preserve-metadata=entitlements \
  --sign "$SIGNING_IDENTITY" "${SIGNING_KEYCHAIN_ARGS[@]}" "${SIGNING_TIMESTAMP_ARGS[@]}" \
  "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" "${SIGNING_TIMESTAMP_ARGS[@]}" \
  "$SPARKLE_VERSION_DIR/Autoupdate"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" "${SIGNING_TIMESTAMP_ARGS[@]}" \
  "$SPARKLE_VERSION_DIR/Updater.app"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" "${SIGNING_TIMESTAMP_ARGS[@]}" \
  "$SPARKLE_FRAMEWORK"
codesign --force --options runtime "${MAIN_APP_ENTITLEMENTS_ARGS[@]}" \
  --sign "$SIGNING_IDENTITY" "${SIGNING_KEYCHAIN_ARGS[@]}" "${SIGNING_TIMESTAMP_ARGS[@]}" \
  "$STAGE_DIR/Battuta.app"

if [[ ${#SIGNING_KEYCHAIN_ARGS[@]} -gt 0 ]]; then
  # Validate like a recipient that does not have the private release keychain:
  # remove it from the search list, lock it, then inspect the embedded chain.
  VALIDATION_USER_KEYCHAINS=()
  for user_keychain in "${ORIGINAL_USER_KEYCHAINS[@]}"; do
    if [[ "${user_keychain:A}" != "$LOCAL_SIGNING_KEYCHAIN_ABSOLUTE" ]]; then
      VALIDATION_USER_KEYCHAINS+=("$user_keychain")
    fi
  done
  security list-keychains -d user -s "${VALIDATION_USER_KEYCHAINS[@]}"
  security lock-keychain "$LOCAL_SIGNING_KEYCHAIN"
  LOCAL_KEYCHAIN_WAS_UNLOCKED=false
fi

codesign --verify --deep --strict --all-architectures --verbose=2 "$STAGE_DIR/Battuta.app"
EMBEDDED_CERTIFICATE_PREFIX="$CERTIFICATE_CHECK_DIR/embedded-signing-certificate-"
codesign -d --extract-certificates="$EMBEDDED_CERTIFICATE_PREFIX" \
  "$STAGE_DIR/Battuta.app" >/dev/null 2>&1
if [[ ! -s "${EMBEDDED_CERTIFICATE_PREFIX}0" ]]; then
  print -u2 "The packaged app does not contain its signing certificate chain."
  exit 1
fi
MAIN_SIGNING_DETAILS=$(codesign -d --verbose=4 "$STAGE_DIR/Battuta.app" 2>&1)
if [[ "$MAIN_SIGNING_DETAILS" != *"runtime"* ]]; then
  print -u2 "The packaged app is missing Hardened Runtime."
  exit 1
fi
if [[ "$MAIN_SIGNING_DETAILS" != *"TeamIdentifier=not set"* \
  && ! -s "${EMBEDDED_CERTIFICATE_PREFIX}1" ]]; then
  print -u2 "The Developer ID signature is missing its intermediate certificate."
  exit 1
fi
if [[ ${#MAIN_APP_ENTITLEMENTS_ARGS[@]} -gt 0 ]]; then
  MAIN_APP_ENTITLEMENTS=$(
    codesign -d --entitlements - --xml "$STAGE_DIR/Battuta.app" 2>&1
  )
  if [[ "$MAIN_APP_ENTITLEMENTS" != *"com.apple.security.cs.disable-library-validation"* \
    || "$MAIN_APP_ENTITLEMENTS" != *"<true/>"* ]]; then
    print -u2 "The local self-signed app is missing its Library Validation exception."
    exit 1
  fi
fi
DESIGNATED_REQUIREMENT=$(codesign -d -r- "$STAGE_DIR/Battuta.app" 2>&1)
if [[ "$DESIGNATED_REQUIREMENT" == *"cdhash"* ]]; then
  print -u2 "Refusing to package an ad-hoc identity because it breaks Input Monitoring after updates."
  print -u2 "$DESIGNATED_REQUIREMENT"
  exit 1
fi
print "$DESIGNATED_REQUIREMENT"
if [[ "$USER_KEYCHAIN_SEARCH_LIST_WAS_CAPTURED" == true ]]; then
  security list-keychains -d user -s "${ORIGINAL_USER_KEYCHAINS[@]}"
  USER_KEYCHAIN_SEARCH_LIST_IS_MODIFIED=false
fi
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
hdiutil create \
  -volname Battuta \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

print "Created $DMG_PATH"
