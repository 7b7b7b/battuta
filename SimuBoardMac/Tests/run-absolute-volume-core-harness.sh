#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h:h}
HARNESS_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/simuboard-absolute-volume-harness.XXXXXX")
trap 'rm -rf "$HARNESS_TEMP"' EXIT

cd "$PROJECT_ROOT"

swift_sources=(
  SimuBoardMac/Tests/AbsoluteVolumeCoreHarness.swift
)

if [[ -f SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift ]]; then
  swift_sources=(
    SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift
    "${swift_sources[@]}"
  )
fi

xcrun --sdk macosx swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -parse-as-library \
  -module-cache-path "$HARNESS_TEMP/module-cache" \
  "${swift_sources[@]}" \
  -o "$HARNESS_TEMP/absolute-volume-core-harness"

"$HARNESS_TEMP/absolute-volume-core-harness"
