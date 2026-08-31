#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h:h}
HARNESS_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/simuboard-typing-stats-harness.XXXXXX")
trap 'rm -rf "$HARNESS_TEMP"' EXIT

cd "$PROJECT_ROOT"

xcrun --sdk macosx swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -parse-as-library \
  -module-cache-path "$HARNESS_TEMP/module-cache" \
  SimuBoardMac/SimuBoardMac/Localization.swift \
  SimuBoardMac/SimuBoardMac/Models/PointerSound.swift \
  SimuBoardMac/SimuBoardMac/Models/SwitchProfile.swift \
  SimuBoardMac/SimuBoardMac/Models/AppSettings.swift \
  SimuBoardMac/SimuBoardMac/Models/TypingStats.swift \
  SimuBoardMac/SimuBoardMac/Services/KeyboardMonitor.swift \
  SimuBoardMac/SimuBoardMac/Services/TypingStatsStore.swift \
  SimuBoardMac/SimuBoardMac/Services/TypingStatsModel.swift \
  SimuBoardMac/Tests/TypingStatsCoreHarness.swift \
  -o "$HARNESS_TEMP/typing-stats-core-harness"

"$HARNESS_TEMP/typing-stats-core-harness"
