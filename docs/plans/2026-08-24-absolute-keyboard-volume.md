# Absolute Keyboard Volume Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep Battuta keyboard playback at the slider's target digital level whenever the current macOS output is not muted, without changing global volume or pointer-sound behavior.

**Architecture:** A Core Audio reader resolves the default output device's mute state and effective attenuation. Pure compensation logic turns that snapshot into up to five neutral gain stages, while `KeyboardAudioEngine` routes keyboard and pointer voices through separate buses so only keyboard audio is compensated.

**Tech Stack:** Swift 6, AVFAudio/AVAudioEngine, Core Audio `AudioObject` properties, zsh core harnesses, SwiftUI, Xcode project file wiring.

---

### Task 1: Pure Compensation Model

**Files:**
- Create: `SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift`
- Create: `SimuBoardMac/Tests/AbsoluteVolumeCoreHarness.swift`
- Create: `SimuBoardMac/Tests/run-absolute-volume-core-harness.sh`

**Step 1: Write the failing test**

Create the harness and assert the required output plan:

```swift
let maximum = KeyboardAbsoluteVolumeCompensation.plan(
    for: .init(isMuted: false, attenuationDB: 0)
)
try check(maximum.shouldPlay && maximum.stageGainsDB.allSatisfy { $0 == 0 })

let reduced = KeyboardAbsoluteVolumeCompensation.plan(
    for: .init(isMuted: false, attenuationDB: -37.75)
)
try check(abs(reduced.stageGainsDB.reduce(0, +) - 37.75) < 0.001)
try check(reduced.stageGainsDB.allSatisfy { (0...24).contains($0) })

let muted = KeyboardAbsoluteVolumeCompensation.plan(
    for: .init(isMuted: true, attenuationDB: -40)
)
try check(!muted.shouldPlay && muted.stageGainsDB.allSatisfy { $0 == 0 })
```

The shell script compiles the placeholder service and harness with Swift 6 strict concurrency.

**Step 2: Run the test to verify it fails**

Run: `SimuBoardMac/Tests/run-absolute-volume-core-harness.sh`

Expected: FAIL because `SystemOutputVolumeSnapshot` and `KeyboardAbsoluteVolumeCompensation` are not defined.

**Step 3: Write the minimal implementation**

Add the pure values and stage splitter:

```swift
struct SystemOutputVolumeSnapshot: Equatable, Sendable {
    let isMuted: Bool
    let attenuationDB: Float?
}

struct KeyboardAbsoluteVolumePlan: Equatable, Sendable {
    let shouldPlay: Bool
    let stageGainsDB: [Float]
}

enum KeyboardAbsoluteVolumeCompensation {
    static let stageCount = 5
    static let maximumStageGainDB: Float = 24

    static func plan(for snapshot: SystemOutputVolumeSnapshot) -> KeyboardAbsoluteVolumePlan {
        guard !snapshot.isMuted else { return silentPlan }
        guard let attenuation = snapshot.attenuationDB, attenuation.isFinite else {
            return passthroughPlan
        }
        return plan(totalGainDB: max(0, min(120, -attenuation)))
    }
}
```

Treat an unsupported device (`attenuationDB == nil`) as `0 dB` compensation. Add cases for `-100 dB`, positive/invalid attenuation, and exact `24 dB` boundaries.

**Step 4: Run the test to verify it passes**

Run: `SimuBoardMac/Tests/run-absolute-volume-core-harness.sh`

Expected: PASS with all compensation assertions.

**Step 5: Commit**

```bash
git add SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift \
  SimuBoardMac/Tests/AbsoluteVolumeCoreHarness.swift \
  SimuBoardMac/Tests/run-absolute-volume-core-harness.sh
git commit -m "test: define absolute volume compensation"
```

### Task 2: Core Audio Output Snapshot Reader

**Files:**
- Modify: `SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift`
- Modify: `SimuBoardMac/Tests/AbsoluteVolumeCoreHarness.swift`

**Step 1: Write the failing resolver tests**

Test platform-independent channel observations before calling Core Audio:

```swift
let stereo = SystemOutputVolumeResolver.snapshot(
    muteValue: false,
    channels: [
        .init(scalar: 0.62, decibels: -38),
        .init(scalar: 0.62, decibels: -38),
    ],
    hasSoftwareVolume: true
)
try check(stereo == .init(isMuted: false, attenuationDB: -38))

let zero = SystemOutputVolumeResolver.snapshot(
    muteValue: false,
    channels: [.init(scalar: 0, decibels: -100)],
    hasSoftwareVolume: true
)
try check(zero.isMuted)

let external = SystemOutputVolumeResolver.snapshot(
    muteValue: false,
    channels: [],
    hasSoftwareVolume: false
)
try check(external.attenuationDB == nil && !external.isMuted)
```

Also test asymmetric stereo chooses the least-attenuated channel, preserving the user's channel balance without over-boosting the louder side.

**Step 2: Run the test to verify it fails**

Run: `SimuBoardMac/Tests/run-absolute-volume-core-harness.sh`

Expected: FAIL because the observation and resolver types are missing.

**Step 3: Implement the resolver and reader**

Add:

```swift
protocol SystemOutputVolumeReading: Sendable {
    func snapshot() -> SystemOutputVolumeSnapshot
}

struct CoreAudioSystemOutputVolumeReader: SystemOutputVolumeReading {
    func snapshot() -> SystemOutputVolumeSnapshot {
        // Read kAudioHardwarePropertyDefaultOutputDevice.
        // Read kAudioDevicePropertyMute on the output scope when present.
        // Read preferred stereo channel scalars.
        // Convert each scalar with kAudioDevicePropertyVolumeScalarToDecibels.
        // Delegate safety decisions to SystemOutputVolumeResolver.
    }
}
```

Use `AudioObjectHasProperty` before each read, check every `OSStatus`, reject non-finite values, and fall back to `20 * log10(scalar)` only when a valid nonzero scalar exists but the device cannot translate it. A device with no software volume property returns passthrough; scalar zero is silent even if the mute property is absent.

**Step 4: Run the focused and existing audio tests**

Run:

```bash
SimuBoardMac/Tests/run-absolute-volume-core-harness.sh
SimuBoardMac/Tests/run-audio-variant-core-harness.sh
```

Expected: both PASS under Swift 6 strict concurrency.

**Step 5: Commit**

```bash
git add SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift \
  SimuBoardMac/Tests/AbsoluteVolumeCoreHarness.swift
git commit -m "feat: read macOS output attenuation"
```

### Task 3: Keyboard-Only Compensated Audio Route

**Files:**
- Modify: `SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift:129-173,235-299,390-421`
- Modify: `SimuBoardMac/Tests/AudioVariantCoreHarness.swift`
- Modify: `SimuBoardMac/Tests/run-audio-variant-core-harness.sh:17-25`
- Modify: `SimuBoardMac/SimuBoardMac.xcodeproj/project.pbxproj`

**Step 1: Write failing routing assertions**

Extend the audio harness to verify the engine exposes testable route state or add a narrow source-routing check that proves:

```swift
try check(engineSource.contains("keyboardVoices"))
try check(engineSource.contains("pointerVoices"))
try check(engineSource.contains("refreshKeyboardOutputCompensation"))
try check(engineSource.contains("keyboardGainStages"))
```

The check must also prove pointer playback selects `pointerVoices` and never calls the keyboard compensation refresh.

**Step 2: Run the test to verify it fails**

Run: `SimuBoardMac/Tests/run-audio-variant-core-harness.sh`

Expected: FAIL on the missing separate routes.

**Step 3: Implement the audio graph**

- Replace the shared voice list/cursor with separate keyboard and pointer voice pools.
- Add a keyboard mixer and five zero-band `AVAudioUnitEQ` nodes.
- Connect keyboard voices through `keyboardMixer -> gain stages -> mainMixer`.
- Connect pointer voices directly to `mainMixer`.
- Inject `any SystemOutputVolumeReading`, defaulting to `CoreAudioSystemOutputVolumeReader`.
- Before keyboard playback, obtain a fresh snapshot, stop active keyboard voices if the gain plan changed, apply every stage's `globalGain`, and skip scheduling when `shouldPlay` is false.
- Keep pointer playback and `pointerVolume` unchanged.
- Treat DIY preview as keyboard playback.
- Reapply the current compensation plan after `AVAudioEngineConfigurationChange`.

Add `SystemOutputVolume.swift` to the Xcode Services group and Sources build phase. Add it to the audio harness compilation command.

**Step 4: Run focused tests**

Run:

```bash
SimuBoardMac/Tests/run-absolute-volume-core-harness.sh
SimuBoardMac/Tests/run-audio-variant-core-harness.sh
SimuBoardMac/Tests/run-diy-core-harness.sh
plutil -lint SimuBoardMac/SimuBoardMac.xcodeproj/project.pbxproj
```

Expected: all harnesses PASS and the project file reports `OK`.

**Step 5: Commit**

```bash
git add SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift \
  SimuBoardMac/SimuBoardMac/Services/SystemOutputVolume.swift \
  SimuBoardMac/Tests/AudioVariantCoreHarness.swift \
  SimuBoardMac/Tests/run-audio-variant-core-harness.sh \
  SimuBoardMac/SimuBoardMac.xcodeproj/project.pbxproj
git commit -m "feat: compensate keyboard output volume"
```

### Task 4: Absolute-Volume UI Contract

**Files:**
- Modify: `SimuBoardMac/SimuBoardMac/Views/MenuBarView.swift:237-248`
- Modify: `SimuBoardMac/README.md:1-55`
- Modify: `SimuBoardMac/Tests/DIYCoreHarness.swift`

**Step 1: Write the failing UI contract test**

Read `MenuBarView.swift` from the existing DIY harness and assert it contains `键盘绝对音量`, the matching accessibility label, and help copy stating that system mute is respected.

**Step 2: Run the test to verify it fails**

Run: `SimuBoardMac/Tests/run-diy-core-harness.sh`

Expected: FAIL because the menu still says `键盘音量`.

**Step 3: Update visible copy and native README**

Change only the keyboard slider block:

```swift
Text("键盘绝对音量")
Slider(value: $settings.volume, in: 0...1, step: 0.01)
    .accessibilityLabel("键盘绝对音量")
    .help("系统未静音时保持此键盘响度；系统静音时不播放")
```

Document the same boundary in `SimuBoardMac/README.md`. Do not add a toggle or change stored defaults.

**Step 4: Run the test to verify it passes**

Run: `SimuBoardMac/Tests/run-diy-core-harness.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add SimuBoardMac/SimuBoardMac/Views/MenuBarView.swift \
  SimuBoardMac/README.md SimuBoardMac/Tests/DIYCoreHarness.swift
git commit -m "docs: explain absolute keyboard volume"
```

### Task 5: Full Verification and Review

**Files:**
- Verify only; fix any task-owned regression in the file introduced by the responsible task.

**Step 1: Run every repository harness**

Run:

```bash
npm test
SimuBoardMac/Tests/run-absolute-volume-core-harness.sh
SimuBoardMac/Tests/run-audio-variant-core-harness.sh
SimuBoardMac/Tests/run-diy-core-harness.sh
SimuBoardMac/Tests/run-typing-stats-core-harness.sh
SimuBoardMac/Tests/run-update-installer-core-harness.sh
```

Expected: all commands exit `0` with no failed assertions. Existing macOS 27 deprecation warnings may remain but no new warnings are accepted.

**Step 2: Verify repository integrity**

Run:

```bash
git diff --check origin/main...HEAD
plutil -lint SimuBoardMac/SimuBoardMac.xcodeproj/project.pbxproj
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: no whitespace errors, project file `OK`, clean feature worktree, and only absolute-volume commits on the branch.

**Step 3: Review requirements manually**

Confirm from the diff that Battuta never calls `AudioObjectSetPropertyData`, keyboard and pointer routes are separate, mute/zero paths cannot add gain, and the BCP work in `/Users/admin/Codes/simuboard` remains untouched.
