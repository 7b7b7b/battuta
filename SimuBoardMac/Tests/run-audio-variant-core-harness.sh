#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h:h}
HARNESS_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/battuta-audio-variant-harness.XXXXXX")
trap 'rm -rf "$HARNESS_TEMP"' EXIT

cd "$PROJECT_ROOT"

xcrun --sdk macosx swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -parse-as-library \
  -module-cache-path "$HARNESS_TEMP/module-cache" \
  SimuBoardMac/SimuBoardMac/Models/KeySound.swift \
  SimuBoardMac/SimuBoardMac/Models/PointerSound.swift \
  SimuBoardMac/SimuBoardMac/Models/SwitchProfile.swift \
  SimuBoardMac/SimuBoardMac/Models/KeyboardLayout.swift \
  SimuBoardMac/SimuBoardMac/Models/SoundPack.swift \
  SimuBoardMac/SimuBoardMac/Services/SoundPackResolver.swift \
  SimuBoardMac/SimuBoardMac/Services/KeyboardMonitor.swift \
  SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift \
  SimuBoardMac/Tests/AudioVariantCoreHarness.swift \
  -o "$HARNESS_TEMP/audio-variant-core-harness"

"$HARNESS_TEMP/audio-variant-core-harness"
