# BCP (Suit80) Built-in Sound Profile Design

## Goal

Add a local built-in `BCP (Suit80)` keyboard profile to Battuta from the supplied Bilibili recording, preserving the recording's thick, woody character while reducing stationary room noise and retaining natural press/release variation.

## Scope

- Add one built-in linear-switch profile with raw identifier `bcp`.
- Export five matched normal-key press/release pairs as row variants (`GENERIC_R0` through `GENERIC_R4`).
- Use the explicitly identified sequence at `01:36-01:41` to export dedicated `BACKSPACE`, `ENTER`, and `SPACE` press/release pairs.
- Treat both Shift strikes in that sequence as normal-key candidates because Battuta maps Shift through the generic row samples rather than a dedicated special-key slot.
- Keep the source video unchanged.
- Preserve all existing absolute-volume worktree changes.

The resulting profile contains 16 WAV files: ten generic row files plus six dedicated large-key files.

## Source Selection

The main typing section runs continuously, so candidate normal keys must be selected as complete, non-overlapping press/release cycles with a visible low-energy valley between the two mechanical events. Selection uses a 4 ms RMS envelope, spectral flux, and manual waveform inspection.

For `01:36-01:41`, video order supplies the semantic labels:

1. Shift: normal-key candidate
2. Backspace: dedicated `BACKSPACE`
3. Enter: dedicated `ENTER`
4. Shift: normal-key candidate
5. Space presses: dedicated `SPACE`, choosing the cleanest complete cycle

The waveform determines press/release boundaries; the video sequence determines the key label.

## Audio Processing

1. Decode the 48 kHz stereo AAC track and downmix it to mono.
2. Measure stationary noise from low-energy gaps surrounding the large-key sequence and from other nearby room-tone gaps.
3. Compare FFmpeg `afftdn` and `anlmdn` at conservative strengths. Select the setting that lowers gap RMS without materially changing transient peak level, spectral centroid, or press/release timing.
4. Apply a 55 Hz high-pass filter, a small low-mid lift near 180 Hz, a mild upper-mid reduction near 3.2 kHz, and a 12 kHz low-pass filter only when the measured output stays within the established Battuta BCP target range.
5. Retain about 2 ms of pre-roll, add a 4 ms press tail fade, and add 2 ms/4 ms release head/tail fades.
6. Preserve relative variation while targeting conservative headroom: roughly -10 to -6 dBFS press peaks and -16 to -11 dBFS release peaks.
7. Export 48 kHz, mono, 16-bit PCM WAV.

Noise reduction must not use a hard gate or aggressive compression. If either denoiser audibly or measurably smears the attack, fall back to high-pass/EQ plus conservative trimming.

## Application Integration

- Add `bcp` to `SwitchProfile` with display name `BCP (Suit80)`, family `线性`, and tone `厚实、木感`.
- Mark the profile as having dedicated special-key samples and row-specific release samples.
- Place audio under `SimuBoardMac/SimuBoardMac/Resources/Audio/bcp/press` and `release`.
- Rely on the existing folder-reference resource copy and `SwitchProfile.allCases` discovery; no audio-engine, menu, library, or Xcode project wiring changes are required.

## Validation

- Add a resource-integrity test before adding the profile/resources. It must require all 16 filenames and validate the profile flags.
- Verify every output is 48 kHz mono 16-bit PCM, non-empty, below clipping, and within safe one-shot duration limits.
- Compare pre/post-denoise gap RMS, transient peaks, spectral centroid, and waveform timing.
- Run the DIY core harness and the audio-variant harness, reporting pre-existing failures separately from BCP failures.
- Build with full Xcode if available; otherwise report the local toolchain limitation rather than claiming a successful app build.
- Produce a short before/after audition file and a profile preview for user review.

## Distribution Boundary

The source is an externally authored Bilibili recording whose redistribution rights are not verified. The profile is for local evaluation only. Do not commit or push the extracted WAV files, and do not include them in a public DMG or release until the recording rightsholder grants redistribution permission.
