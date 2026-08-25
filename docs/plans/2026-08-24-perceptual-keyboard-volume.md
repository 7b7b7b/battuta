# Perceptual Keyboard Volume Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Battuta's linear keyboard slider mapping with a cubic perceptual taper while preserving every existing user's audible volume across upgrade.

**Architecture:** `AppSettings.volume` remains the UI position. Pure curve helpers expose cubic playback gain and inverse legacy migration; a versioned `UserDefaults` migration runs once. `AppModel` passes only the converted keyboard gain to keyboard and preview playback, while pointer volume remains independent and both paths follow the normal macOS output volume.

**Tech Stack:** Swift 6, SwiftUI, Combine, Foundation/UserDefaults, AVFAudio, zsh core harnesses, Xcode.

---

### Task 1: Define the curve and migration contract

**Files:**
- Modify: `SimuBoardMac/Tests/DIYCoreHarness.swift`

1. Add assertions for cubic gain values, inverse migration, the migrated legacy default, one-time persistence, and unchanged pointer seeding.
2. Add source-contract assertions that all keyboard and preview paths use `settings.keyboardPlaybackGain`, while pointer playback still uses `settings.pointerVolume`.
3. Run `SimuBoardMac/Tests/run-diy-core-harness.sh`; verify the new assertions fail because the curve API and migration do not exist.

### Task 2: Implement the perceptual keyboard control

**Files:**
- Modify: `SimuBoardMac/SimuBoardMac/Models/AppSettings.swift`
- Modify: `SimuBoardMac/SimuBoardMac/Services/AppModel.swift`

1. Add a pure cubic `KeyboardVolumeCurve` with clamped forward and inverse conversions.
2. Add a version key and migrate legacy linear values with the inverse curve exactly once.
3. Expose `keyboardPlaybackGain` and seed missing pointer volume from that linear gain.
4. Pass `keyboardPlaybackGain` to keyboard playback and previews; leave pointer playback unchanged.
5. Run the DIY harness and confirm it passes.

### Task 3: Verify and deliver

**Files:**
- Modify only if verification exposes a defect.

1. Run all five native core harnesses.
2. Run a clean Release Xcode build.
3. Inspect the diff and commit the feature.
4. Push the feature branch, install the built app locally, relaunch it, and verify the running bundle and version.
