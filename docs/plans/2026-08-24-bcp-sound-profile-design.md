# BCP (Suit80) Local Custom Sound Pack Design

> Release update (2026-08-25): redistribution permission was subsequently
> confirmed by the Battuta maintainer. Battuta 1.1.1 therefore ships the
> audited package as a read-only bundled sound pack; the local-only statements
> below document the earlier design constraint rather than the current release.

## Goal

Turn the supplied Bilibili recording into a local-only `BCP (Suit80)` custom
sound pack that can be auditioned and installed on one machine without adding a
new built-in switch profile, app-bundled resources, or redistributable release
artifacts.

## Final Architecture

- `scripts/render-local-bcp-profile.sh` renders deterministic local WAV assets
  into the ignored repo paths `SimuBoardMac/build/BCP-rendered-assets` and
  `SimuBoardMac/build/BCP-audition`.
- `scripts/install-local-bcp-sound-pack.sh` validates those WAVs and installs a
  fixed-UUID custom pack into
  `~/Library/Application Support/SimuBoard/SoundPacks`.
- The app discovers the installed pack through the existing custom
  `SoundPackLibrary`, so it appears in the same picker as built-in sounds with
  selection ID `custom:15d04652-5265-4ea7-a376-8a7e11ff6813`.
- No `SwitchProfile.bcp` case is added.
- No `SimuBoardMac/Resources/Audio/bcp` tree is added.
- No BCP audio enters the app bundle, public build, DMG, appcast, or release.

## Render Specification

The renderer keeps the source video unchanged, stages all output in a temp
directory, and only swaps the fixed local output roots after validation.

Exact master filter:

```text
pan=mono|c0=0.5*c0+0.5*c1,volume=-3dB,highpass=f=55,afftdn=nr=6:nf=-51:tn=1:ad=0.25:fo=1:gs=1,atrim=start=0.025,asetpts=PTS-STARTPTS
```

Raw-preview filter:

```text
pan=mono|c0=0.5*c0+0.5*c1,asetpts=PTS-STARTPTS
```

Residual-preview filter:

```text
pan=mono|c0=0.5*c0+0.5*c1,volume=-3dB,highpass=f=55,afftdn=nr=6:nf=-51:tn=1:ad=0.25:fo=1:gs=1:om=n,atrim=start=95.525:end=102.025,asetpts=PTS-STARTPTS
```

Audited cut list:

```text
press|GENERIC_R0|16.539|16.598|4.0
release|GENERIC_R0|16.616|16.710|2.0
press|GENERIC_R1|40.512|40.566|1.0
release|GENERIC_R1|40.615|40.678|6.5
press|GENERIC_R2|58.248|58.344|3.5
release|GENERIC_R2|58.355|58.420|3.0
press|GENERIC_R3|59.050|59.107|1.0
release|GENERIC_R3|59.125|59.171|4.5
press|GENERIC_R4|66.579|66.612|4.5
release|GENERIC_R4|66.671|66.736|6.5
press|GENERIC_R0_ALT|20.000|20.077|-4.0
release|GENERIC_R0_ALT|20.107|20.145|2.0
press|GENERIC_R1_ALT|39.165|39.231|2.0
release|GENERIC_R1_ALT|39.261|39.299|-4.7
press|GENERIC_R2_ALT|43.650|43.727|0.0
release|GENERIC_R2_ALT|43.761|43.807|-4.9
press|GENERIC_R3_ALT|49.506|49.596|-0.5
release|GENERIC_R3_ALT|49.610|49.634|-3.3
press|GENERIC_R4_ALT|72.798|72.891|-0.5
release|GENERIC_R4_ALT|72.915|72.961|-4.7
press|SHIFT|99.524|99.608|0.0
release|SHIFT|99.659|99.782|0.0
press|BACKSPACE|97.648|97.714|2.0
release|BACKSPACE|97.726|97.844|2.0
press|ENTER|98.663|98.713|2.0
release|ENTER|98.726|98.846|2.0
press|SPACE|101.444|101.498|-0.5
release|SPACE|101.522|101.626|2.0
```

Exact fade policy:

- Generic press: apply listed gain, trim by exact sample index, add a light
  `95 Hz` high-pass to limit stacked desk resonance during rapid typing, fade
  out over 192 samples (`4 ms`), then pad one zero sample. The R1 cut excludes
  its late secondary impact.
- Generic release: apply listed gain and a light `108 Hz` high-pass, fade in
  over 48 samples (`1 ms`), fade out over 192 samples (`4 ms`), trim to
  `sample_count - 1`, then pad one zero sample. The R3 base and alternate cuts
  exclude their late secondary impacts.
- Dedicated big-key release assets retain the prior 96-sample (`2 ms`) fade-in.
- All exported files are `48 kHz`, mono, `pcm_s16le`.

The renderer also emits:

- `build/BCP-audition/BCP-raw-preview.wav`
- `build/BCP-audition/BCP-processed-preview.wav`
- `build/BCP-audition/BCP-rapid-typing-preview.wav`
- `build/BCP-audition/BCP-denoise-residual.wav`

## Installed Pack Shape

The installer creates a fixed package
`15d04652-5265-4ea7-a376-8a7e11ff6813.simuboardpack` with:

- `name`: `BCP (Suit80)`
- `family`: `线性`
- `tone`: `厚实、木感`
- `layoutID`: `mac-ansi-tkl-v1`
- `baseProfileID`: `holypanda`
- one attribution entry naming the local source filename and visible uploader
  `J_Eason001`, with a local-only non-redistribution notice

Manifest assignment policy:

- `press.generic = nil`
- `release.generic = nil`
- `press.rows` maps `R0` through `R4` to the five generic press assets
- `release.rows` maps `R0` through `R4` to the five generic release assets
- alternate per-key overrides distribute five additional matched press/release
  recordings across approximately half of each small-key row
- `press.specials` maps `backspace`, `enter`, and `space` to the dedicated
  press assets
- `release.specials` maps `backspace`, `enter`, and `space` to the dedicated
  release assets
- `press.keyOverrides` and `release.keyOverrides` retain dedicated Shift assets
  while also assigning the five alternate small-key pairs

This keeps the BCP pack in the same picker as built-in sounds while remaining a
custom pack loaded from Application Support.

## Migration And Failure Semantics

Renderer transaction boundary:

- Validate the source hash/mtime before and after rendering.
- Validate all 28 rendered WAVs and all 4 audition WAVs before installation.
- Replace `build/BCP-rendered-assets` and `build/BCP-audition` transactionally.
- Roll back both output roots if a swap or final verification fails.

Installer transaction boundary:

- Refuse to overwrite an existing fixed BCP pack with an invalid manifest.
- Strictly validate and upgrade both the prior 16-asset BCP pack and the
  Shift-only 18-asset pack while preserving their creation timestamps.
- Tolerate regular, non-symlink Finder `.DS_Store` files only at the pack root
  and `assets/`; continue rejecting every other extra entry.
- Stage the full `.simuboardpack` under the target library root first.
- Back up the previous fixed BCP pack before swapping in the new one.
- Roll back exactly to the previous pack if failure occurs after backup or
  after install but before commit.
- Leave unrelated custom packs untouched.

Legacy selection migration:

- If the install target is the default
  `~/Library/Application Support/SimuBoard/SoundPacks` path, migrate
  `selectedProfile = "bcp"` to
  `selectedProfile = "custom:15d04652-5265-4ea7-a376-8a7e11ff6813"`.
- This also applies when the caller passes the default library root explicitly.
- Non-default explicit library roots do not rewrite the user's selection.

Timestamp semantics:

- `createdAt` is preserved from the first successful install of this fixed UUID.
- `modifiedAt` is preserved for byte-identical reinstalls.
- `modifiedAt` advances to the new install time only when the manifest
  fingerprint changes.

## Validation

Latest working-tree verification for this design:

- `./Tests/run-diy-core-harness.sh` -> `493` assertions
- `./Tests/run-audio-variant-core-harness.sh` -> blocked by the pre-existing
  `KeyboardAbsoluteVolumeCompensator` symbol drift on the separate
  absolute-volume workstream
- `./Tests/run-typing-stats-core-harness.sh` -> `163` assertions
- `./Tests/run-update-installer-core-harness.sh` -> `8` assertions

Automated coverage:

- The DIY harness covers the local BCP installer contract: manifest validity,
  picker discovery, legacy selection migration, timestamp behavior, and
  installer rollback behavior.
- The typing-stats and update-installer auxiliary harnesses confirm those
  unaffected paths. The audio-variant harness is tracked separately from BCP.

Renderer coverage against the real source is explicit rather than repo-embedded:

- The repository does not ship the source MP4 fixture.
- Exact cuts, source hash/mtime integrity, repeatability, and renderer rollback
  are verified with real-source smoke runs, injected renderer failures, and
  `ffprobe` validation of the generated WAV inventory.

## Historical Note

This work started as a built-in `SwitchProfile.bcp` proposal. Quality review
and release-boundary review rejected that direction because the recording is
local-only and permission to redistribute is unverified. The final design
therefore pivots to an Application Support custom pack with ignored local render
artifacts and an installer-managed lifecycle.
