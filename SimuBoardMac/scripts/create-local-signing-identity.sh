#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
COMMON_NAME="SimuBoard Local Code Signing"
KEYCHAIN_PATH=${SIMUBOARD_SIGNING_KEYCHAIN:-"$HOME/Library/Keychains/SimuBoardRelease.keychain-db"}
CONFIG_DIR=${SIMUBOARD_SIGNING_CONFIG_DIR:-"$HOME/Library/Application Support/SimuBoardBuild"}
PASSWORD_FILE=${SIMUBOARD_SIGNING_PASSWORD_FILE:-"$CONFIG_DIR/signing-keychain-password"}
KEYCHAIN_WAS_UNLOCKED=false
TEMP_DIR=""

cleanup() {
  if [[ "$TEMP_DIR" == /private/tmp/simuboard-signing.* ]]; then
    rm -f "$TEMP_DIR/signing-key.pem" "$TEMP_DIR/signing-cert.pem" "$TEMP_DIR/signing-identity.p12"
    rmdir "$TEMP_DIR" 2>/dev/null || true
  fi
  if [[ "$KEYCHAIN_WAS_UNLOCKED" == true ]]; then
    security lock-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  fi
}
trap cleanup EXIT

command -v openssl >/dev/null || {
  print -u2 "OpenSSL is required to create the local signing certificate."
  exit 1
}

umask 077
if [[ -f "$KEYCHAIN_PATH" ]]; then
  if [[ ! -f "$PASSWORD_FILE" ]]; then
    print -u2 "The SimuBoard signing keychain exists, but its password file is missing: $PASSWORD_FILE"
    exit 1
  fi
  KEYCHAIN_PASSWORD=$(<"$PASSWORD_FILE")
else
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
  print -rn -- "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 300 "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
KEYCHAIN_WAS_UNLOCKED=true

existing_fingerprint=$(
  (security find-certificate -a -c "$COMMON_NAME" -Z "$KEYCHAIN_PATH" 2>/dev/null || true) \
    | awk '/SHA-1 hash:/{print $3; exit}'
)
if [[ -n "$existing_fingerprint" ]]; then
  if ! security find-key -l "$COMMON_NAME" -s -t private "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    print -u2 "The signing certificate exists, but its private key is missing from $KEYCHAIN_PATH"
    print -u2 "Restore the original keychain backup instead of generating a new release identity."
    exit 1
  fi
  print "Existing signing certificate found: $existing_fingerprint"
  print "Nothing changed. Keep this certificate and its private key for every future release."
  security lock-keychain "$KEYCHAIN_PATH"
  KEYCHAIN_WAS_UNLOCKED=false
  exit 0
fi

TEMP_DIR=$(mktemp -d /private/tmp/simuboard-signing.XXXXXX)
PRIVATE_KEY="$TEMP_DIR/signing-key.pem"
CERTIFICATE="$TEMP_DIR/signing-cert.pem"
IDENTITY_P12="$TEMP_DIR/signing-identity.p12"
P12_PASSWORD=$(openssl rand -hex 32)

openssl req \
  -new \
  -newkey rsa:3072 \
  -nodes \
  -x509 \
  -sha256 \
  -days 3650 \
  -config "$SCRIPT_DIR/codesign-openssl.cnf" \
  -keyout "$PRIVATE_KEY" \
  -out "$CERTIFICATE"

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -name "$COMMON_NAME" \
  -passout "pass:$P12_PASSWORD" \
  -out "$IDENTITY_P12"

security import "$IDENTITY_P12" \
  -k "$KEYCHAIN_PATH" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign

security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

fingerprint=$(
  security find-certificate -a -c "$COMMON_NAME" -Z "$KEYCHAIN_PATH" \
    | awk '/SHA-1 hash:/{print $3; exit}'
)
guard_message="Keep this certificate and its private key for every future SimuBoard release."
print "Created $COMMON_NAME in $KEYCHAIN_PATH"
print "Certificate fingerprint: $fingerprint"
print "$guard_message"
print "Back up $KEYCHAIN_PATH and $PASSWORD_FILE securely; never commit either file to Git."
security lock-keychain "$KEYCHAIN_PATH"
KEYCHAIN_WAS_UNLOCKED=false
