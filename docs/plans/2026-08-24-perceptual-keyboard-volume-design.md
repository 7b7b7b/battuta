# Perceptual Keyboard Volume Design

## Goal

Give the keyboard-volume slider useful precision at quiet levels while preserving Battuta's existing audible level during upgrade. The macOS absolute-volume compensation remains independent and continues to operate in decibels.

## Decision

Treat the keyboard slider as a perceptual control position rather than a linear amplitude. Convert its `0...1` position to playback gain with a cubic taper:

```text
gain = position ^ 3
```

This follows the cubic UI taper used by mature audio stacks such as Qt, OBS, and PulseAudio. It is continuous at silence, keeps full scale at `100%`, and gives substantially more travel to quiet levels without the complexity of a professional IEC fader. Pointer volume remains linear and unchanged.

## Settings Migration

Version the keyboard-volume representation in `UserDefaults`. Existing stored values are linear gains, so migrate them exactly once with:

```text
newPosition = cubeRoot(oldLinearGain)
```

After migration, `newPosition ^ 3 == oldLinearGain`, preserving audible output. The legacy default gain of `0.42` therefore becomes a slider position of about `0.749`. New installs use the same perceptual position and audible default. Pointer-volume seeding continues to use the keyboard's resolved linear gain, so its behavior does not change.

## Data Flow

`AppSettings.volume` stores and displays the perceptual slider position. A read-only `keyboardPlaybackGain` converts that position to linear gain. All keyboard playback and previews pass this converted gain to `KeyboardAudioEngine`; pointer playback continues to pass `pointerVolume` directly. The existing Core Audio scalar-to-decibel lookup and inverse compensation stages are untouched.

## Tests

- Prove the cubic curve at silence, quarter, half, three-quarter, and full positions.
- Prove legacy volume migration preserves linear gain and runs only once.
- Prove the default audible level and pointer default remain unchanged.
- Prove keyboard and preview routes use `keyboardPlaybackGain` while pointer routing remains linear.
- Run every native core harness and a Release Xcode build before installing locally.
