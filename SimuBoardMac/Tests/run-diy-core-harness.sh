#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h:h}
HARNESS_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/simuboard-diy-core-harness.XXXXXX")
trap 'rm -rf "$HARNESS_TEMP"' EXIT

cd "$PROJECT_ROOT"

xcrun --sdk macosx swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -parse-as-library \
  -module-cache-path "$HARNESS_TEMP/module-cache" \
  SimuBoardMac/SimuBoardMac/Localization.swift \
  SimuBoardMac/SimuBoardMac/Models/KeySound.swift \
  SimuBoardMac/SimuBoardMac/Models/PointerSound.swift \
  SimuBoardMac/SimuBoardMac/Models/SwitchProfile.swift \
  SimuBoardMac/SimuBoardMac/Models/AppSettings.swift \
  SimuBoardMac/SimuBoardMac/Models/KeyboardLayout.swift \
  SimuBoardMac/SimuBoardMac/Models/SoundPack.swift \
  SimuBoardMac/SimuBoardMac/Models/SemanticVersion.swift \
  SimuBoardMac/SimuBoardMac/Models/ReleaseSummary.swift \
  SimuBoardMac/SimuBoardMac/Services/SoundPackResolver.swift \
  SimuBoardMac/SimuBoardMac/Services/AudioImportService.swift \
  SimuBoardMac/SimuBoardMac/Services/AudioSplitService.swift \
  SimuBoardMac/SimuBoardMac/Services/SoundPackLibrary.swift \
  SimuBoardMac/SimuBoardMac/Services/SoundPackArchiveService.swift \
  SimuBoardMac/SimuBoardMac/Services/GitHubReleaseClient.swift \
  SimuBoardMac/SimuBoardMac/Services/UpdateController.swift \
  SimuBoardMac/SimuBoardMac/Services/LaunchAtLoginController.swift \
  SimuBoardMac/SimuBoardMac/Services/KeyboardMonitor.swift \
  SimuBoardMac/Tests/DIYCoreHarness.swift \
  -o "$HARNESS_TEMP/diy-core-harness"

"$HARNESS_TEMP/diy-core-harness"
