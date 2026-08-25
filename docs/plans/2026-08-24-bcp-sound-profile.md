# BCP (Suit80) Local Custom Sound Pack Final Plan

Status: implemented in the current working tree as a local custom-pack workflow, not a built-in
bundled switch profile.

> Release update (2026-08-25): redistribution permission was subsequently
> confirmed by the Battuta maintainer. The local-only shipping boundary in
> this historical plan is superseded for Battuta 1.1.1, which embeds the same
> audited package as a read-only bundled sound pack. The rendering and mapping
> decisions below remain the reproducibility record.

## Goal

Provide a deterministic local pipeline that:

- renders 28 audited BCP WAV assets plus audition files from the supplied MP4
- installs them as one fixed custom sound pack in Application Support
- surfaces that pack in the existing sound picker beside built-in sounds
- keeps all BCP artifacts out of the app bundle and release outputs

## Delivered Components

- `SimuBoardMac/scripts/render-local-bcp-profile.sh`
  - fixed source argument
  - fixed ignored output roots:
    `SimuBoardMac/build/BCP-rendered-assets` and
    `SimuBoardMac/build/BCP-audition`
  - transactional replacement of both local output roots
  - source hash/mtime verification before and after install
- `SimuBoardMac/scripts/install-local-bcp-sound-pack.sh`
  - validates exactly 28 rendered WAV files
  - installs fixed UUID
    `15d04652-5265-4ea7-a376-8a7e11ff6813.simuboardpack`
    into `~/Library/Application Support/SimuBoard/SoundPacks`
  - emits a manifest with row/special press/release assignments and one
    attribution record
  - migrates legacy built-in `bcp` selection to the custom selection ID when
    the install target is the default library root
- `SimuBoardMac/Tests/DIYCoreHarness.swift`
  - defines the local BCP installer contract, timestamp semantics, picker
    discovery, and installer rollback behavior
- `docs/plans/2026-08-24-bcp-sound-profile-design.md`
  - records the final architecture and local-only release boundary

## Deterministic Render Contract

Master filter:

```text
pan=mono|c0=0.5*c0+0.5*c1,volume=-3dB,highpass=f=55,afftdn=nr=6:nf=-51:tn=1:ad=0.25:fo=1:gs=1,atrim=start=0.025,asetpts=PTS-STARTPTS
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

Fade and export rules:

- Generic press clips: exact-sample trim, listed gain, light `95 Hz` high-pass
  to limit stacked desk resonance during rapid typing, `4 ms` fade-out, and
  one zero sample pad; the R1 cut ends before its late secondary impact
- Generic release clips: exact-sample trim at the independent release transient,
  listed gain, light `108 Hz` high-pass, `1 ms` fade-in, `4 ms` fade-out, and
  one zero sample pad; the R3 base and alternate cuts end before their late
  secondary impacts
- Dedicated big-key release clips retain their prior `2 ms` fade-in and
  otherwise unchanged processing
- Every output: `48 kHz` mono `pcm_s16le`
- Audition outputs:
  `BCP-raw-preview.wav`, `BCP-processed-preview.wav`,
  `BCP-rapid-typing-preview.wav`, `BCP-denoise-residual.wav`

## Installed Pack Contract

Installed pack manifest:

- `id`: `15d04652-5265-4ea7-a376-8a7e11ff6813`
- `name`: `BCP (Suit80)`
- `family`: `线性`
- `tone`: `厚实、木感`
- `layoutID`: `mac-ansi-tkl-v1`
- `baseProfileID`: `holypanda`
- `press.generic = nil`, `release.generic = nil`
- `press.rows` and `release.rows` cover `R0` through `R4`
- `press.specials` and `release.specials` cover `backspace`, `enter`, `space`
- `press.keyOverrides` and `release.keyOverrides` map both Shift keys to their
  dedicated phase assets and alternate approximately half of each small-key row
  onto the five additional real-recording pairs

Picker integration:

- The pack is discovered from `SoundPackLibrary` as a custom descriptor.
- It appears in the same picker as built-in sounds.
- No `SwitchProfile.bcp` is introduced.

## Transaction And Migration Rules

Renderer:

- stage all files under `mktemp`
- validate output inventory and encoding before swap
- replace `build/BCP-rendered-assets` and `build/BCP-audition` atomically
- roll back both roots on any injected or real failure before commit

Installer:

- reject invalid pre-existing fixed BCP manifests
- upgrade both the prior valid 16-asset pack and the Shift-only 18-asset pack to
  the 28-asset alternate-small-key shape
- tolerate ordinary non-symlink `.DS_Store` files at the pack root and
  `assets/`, while rejecting other extra entries
- back up the previous fixed BCP pack before publish
- restore the exact previous pack on failure after backup or after install
- remove partial first installs if publish fails without an older pack
- preserve unrelated packs

Selection migration:

- rewrite `selectedProfile = "bcp"` to
  `custom:15d04652-5265-4ea7-a376-8a7e11ff6813`
  only when the install target is the default Application Support library root,
  including explicit use of that default path
- do not rewrite selection for non-default explicit library roots

Timestamp rules:

- preserve `createdAt` across reinstalls of the fixed UUID
- preserve `modifiedAt` for byte-stable reinstalls
- update `modifiedAt` only when the manifest fingerprint changes

## Verification

Current final verification in the working tree:

- `./Tests/run-diy-core-harness.sh` passed with `493` assertions
- `./Tests/run-audio-variant-core-harness.sh` remains blocked by the
  pre-existing `KeyboardAbsoluteVolumeCompensator` symbol drift on the separate
  absolute-volume workstream
- `./Tests/run-typing-stats-core-harness.sh` passed with `163` assertions
- `./Tests/run-update-installer-core-harness.sh` passed with `8` assertions

Automated verification scope:

- The DIY harness exercises the installer contract only: manifest shape,
  library discovery, legacy `bcp` selection migration, timestamp semantics, and
  installer rollback/failure handling.
- The repository does not include the source MP4 fixture, so renderer exact
  cuts are not asserted by an automated harness.

Real-source smoke verification scope:

- Renderer exact cuts, source hash/mtime integrity, repeatability, and renderer
  rollback are validated separately with explicit runs against the real source,
  injected renderer failures, and `ffprobe` checks on the generated WAV tree.

## Non-Goals

- Do not add `SwitchProfile.bcp`.
- Do not add `SimuBoardMac/Resources/Audio/bcp`.
- Do not ship BCP assets in the bundle, DMG, appcast, release, or public repo.
- Do not treat the BCP recording as a licensed bundled source.

## Historical Decision Note

The original built-in-profile plan is obsolete. After quality and release
review, the implementation pivoted to a local custom sound pack because the
recording is only cleared for local evaluation and must not become a shipped
bundled asset.
