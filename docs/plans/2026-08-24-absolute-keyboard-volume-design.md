# Absolute Keyboard Volume Design

## Goal

Make the keyboard-volume slider represent Battuta's target digital output level instead of a gain that is multiplied by the current macOS output volume. System mute and an effective zero output level must remain silent. Mouse and trackpad sounds keep their existing relative-volume behavior.

## Decision

Use application-side inverse gain compensation. Battuta will never change the macOS output volume or mute state.

For the current default output device, read the output mute state and channel volume scalars through Core Audio. Convert the scalar values to decibels with the device's own scalar-to-decibel mapping, then apply the inverse attenuation to the keyboard-only audio bus. Devices without a software volume control need no compensation; devices that expose a scalar but not a conversion use a conservative scalar-based fallback.

The slider continues to store `0...1`. At maximum system output, playback is unchanged. At a lower nonzero output level, neutral gain stages offset the reported device attenuation before the signal reaches the system output. Natural per-keystroke gain and rate variation remain in place.

## Audio Architecture

- Add a Core Audio output-volume reader that returns a pure snapshot: supported state, mute state, and output attenuation in decibels.
- Add pure compensation math that maps a snapshot to zero or more gain stages. Each neutral `AVAudioUnitEQ` stage stays within Apple's `+24 dB` limit; five stages cover up to `+120 dB`.
- Split the existing voice routing into keyboard and pointer paths inside the same `AVAudioEngine`.
- Route keyboard voices through the compensation stages before the main mixer.
- Route pointer voices directly to the main mixer so their behavior does not change.
- Refresh the snapshot before keyboard playback and listen for output-volume or default-device changes. Stop short keyboard tails before changing a large shared gain so a stale boost cannot become a loud transient when the user raises system volume.

## Boundaries and Fallbacks

- A muted device or an effective zero output level produces no keyboard playback and no positive compensation.
- Battuta does not modify global audio state and therefore cannot affect other applications' volume.
- Hardware controls downstream of macOS, including headphone knobs and external amplifiers, remain outside Battuta's control.
- If the active device reports no macOS software volume property, compensation is `0 dB` because macOS is not attenuating that route.
- If a device exposes incomplete or inconsistent volume metadata, use the safest available estimate and never apply a non-finite gain.

## UI

Rename the control to `键盘绝对音量` and add concise help text explaining that system mute is still respected. Do not add a mode toggle or migrate the stored slider value.

## Tests

Use TDD around a new pure core harness before connecting Core Audio:

- maximum output needs `0 dB` compensation;
- a reported negative attenuation produces the equal positive compensation;
- compensation is split into stages no larger than `24 dB`;
- mute and zero output remain silent;
- invalid or unsupported metadata cannot create unsafe gain;
- keyboard and pointer playback use separate routes;
- existing browser, audio-variant, DIY, typing-statistics, and updater harnesses remain green.
