# Battuta audio sources

This inventory records the provenance, processing, and redistribution status of
audio used by Battuta's shipped bundles.
Derived files are trimmed and/or resampled to 48 kHz mono PCM WAV unless noted
otherwise.

The public desktop resource tree lives at `shared/audio/builtin`. Both desktop
applications consume this directory; platform projects must not keep a second
canonical copy. Permissioned packaged sound packs live separately under
`shared/soundpacks/bundled` so they retain their manifest and permission notice.

## Bundled sources

| Battuta profiles | Upstream | Upstream revision | License | Processing |
| --- | --- | --- | --- | --- |
| Original 13 profiles | [tplai/kbsim](https://github.com/tplai/kbsim) | See the original import history | MIT | Existing MP3 samples; decoded and resampled to 48 kHz in memory |
| Kailh BOX White | [Mange/clicketyclack](https://github.com/Mange/clicketyclack) | `bb87dc501a18a082675e51193a8a06134deb2a56` | MIT | Five matched press/release recordings resampled; upstream README says contributed switch sounds must be self-recorded and not taken from elsewhere |
| Logitech G915 TKL Brown | [keyboard-sounds/keyboardsounds-pro](https://github.com/keyboard-sounds/keyboardsounds-pro/tree/main/desktop/bundled-profiles/logitech-g915-tkl-brown) | `bac56ac700635c512e57621f35780c5b79eba4cd` | MIT | Five matched normal-key press/release variations plus dedicated large-key recordings selected from the upstream profile; leading room tone is trimmed while retaining about 2 ms before the first useful transient; profile gain compensation is applied, with extra gain for the much quieter alternate large-key release |
| Studio Tactile and Studio Clicky | [StavSounds: Mechanical Keyboards](https://freesound.org/people/StavSounds/packs/42151/) | Freesound IDs `766625`, `766632`–`766635`, `766605`–`766606`, `766622`–`766624` | CC0 1.0 | Ten public HQ preview MP3s downmixed and resampled; leading room tone is trimmed while retaining about 2 ms before the first useful transient; each complete keystroke is separated at the audited energy valley before its release event |
| Keychron Red Linear | [Typing on Keychron V1 Ultra (Red Linear Switch)](https://commons.wikimedia.org/wiki/File:Typing_on_Keychron_V1_Ultra_(Red_Linear_Switch).wav) by C40115 | Wikimedia file revision available on the source page | CC BY 4.0 | Five 180 ms excerpts selected from the original 48 kHz WAV and downmixed to mono; each complete keystroke is separated into press/release samples, with later neighboring keystrokes excluded |
| Kailh Low-profile Blue | [Fast Typing on Mechanical Keyboard](https://freesound.org/people/HeinzBBQ/sounds/502653/) by HeinzBBQ | Freesound ID `502653` | CC0 1.0 | Five 220 ms excerpts selected from the public HQ preview, downmixed and resampled; click and bottom-out remain in press while the later release event is separated and neighboring keystrokes are excluded |
| Cherry MX Clear | [Mechanical keyboard clicking. Different keys (4)](https://freesound.org/people/humi74/sounds/412926/) by humi74 | Freesound ID `412926` | CC0 1.0 | Five 220 ms excerpts selected from the public HQ preview, downmixed and resampled, then separated at the audited energy valley before release; one excerpt without a usable release reuses the closest clean release variation from the same recording |
| BCP (Suit80) | `【打字声音】Suit80｜BCP轴｜GMK Ursa 大熊 - Original.mp4`, visible uploader `J_Eason001` | Maintainer-supplied source recording; redistribution permission confirmed 2026-08-25 and retained privately by the Battuta maintainer | Used with permission for Battuta | Rendered with `SimuBoardMac/scripts/render-local-bcp-profile.sh`: stereo downmix, `-3 dB` headroom, `55 Hz` high-pass, conservative `afftdn` denoise with measured `25 ms` latency compensation, then 28 audited press/release cuts. Five base row pairs and five alternate small-key pairs use separated transients, a light `95 Hz` press high-pass, a light `108 Hz` release high-pass, and `1 ms` release fade-in. Three late secondary impacts are excluded to prevent cumulative desk resonance during rapid typing; dedicated Shift, Backspace, Enter, and Space pairs retain their audited cuts. The release package is stored as a read-only bundled `.simuboardpack`. |
| Pointer Classic, Silent, Crisp, Heavy, and Glass | [Kenney UI Audio](https://kenney.nl/assets/ui-audio) by Kenney Vleugels | Archive downloaded 2026-08-22; original files `mouseclick1.ogg` and `mouserelease1.ogg` | CC0 1.0 | The matched press/release recordings are downmixed and rendered as five generic simulated tonal treatments. Each phase is pitch-lowered with compensation for the associated tempo change, then receives profile-specific low-pass filtering, restrained midrange EQ and level adjustment; Crisp and Glass retain a gentle low cut for definition without the former high-frequency boost. Leading signal below −45 dBFS is removed while retaining up to 2 ms of pre-roll; all outputs have a 4 ms tail fade and are 48 kHz mono 16-bit PCM WAV. The profile names do not identify or claim to reproduce a particular mouse brand or switch. |

The imported files can be reproduced with:

```bash
./SimuBoardMac/scripts/import-open-soundpacks.sh \
  /path/to/clicketyclack \
  /path/to/keyboardsounds-pro \
  /path/to/stavsounds-preview-directory \
  /path/to/keychron-red-linear.wav \
  /path/to/kailh-low-profile-blue-audio \
  /path/to/cherry-mx-clear-audio
```

The five pointer profiles can be reproduced separately from the unmodified
Kenney UI Audio archive with:

```bash
./SimuBoardMac/scripts/import-pointer-sounds.sh /path/to/kenney-ui-audio
```

The pointer importer verifies SHA-256 for both source OGG files and Kenney's
pack license before rendering ten files. The source files are stereo Vorbis at
44.1 kHz; the importer downmixes them, lowers pitch while compensating the
associated tempo change,
and applies press/release-specific low-pass, EQ, low-cut and level treatments.
It retains conservative headroom and writes 48 kHz mono 16-bit PCM WAV files.
It removes only the leading floor below −45 dBFS while retaining up to 2 ms
before the first measurable click signal, reducing playback latency without
cutting the press/release transient. Relative to the 0.5.0 masters, the 0.5.1
set lowers median spectral centroid by about 40%, median energy above 8 kHz by
about 91%, and median energy from 6–14 kHz by about 72%. Consecutive imports
are verified byte-for-byte identical.

The importer rejects a different Git revision, a modified source directory, or
any of the 13 downloaded files whose SHA-256 does not match this audited import.
For the five full-keystroke sources, the importer uses the per-recording split
manifest in `SimuBoardMac/scripts/split-full-keystrokes.py`. Split points were selected from
4 ms RMS energy and spectral-flux features: press ends at the quiet valley
before the release event, while explicit release end points exclude the next
keystroke in continuous recordings. Press tails fade for 4 ms; release samples
fade in for 2 ms and out for 4 ms. Three obvious release-level outliers receive
small −5 dB or +6 dB corrections, recorded in the same manifest. The importer
renders all seven profiles in a staging directory before replacing the previous
generated copies, so stale files cannot survive a re-import.

The copyright notices and license terms required for redistribution are in
`SimuBoardMac/SimuBoardMac/Resources/THIRD_PARTY_NOTICES.txt` and the repository-level
`THIRD_PARTY_NOTICES.md`.

BCP (Suit80) is shipped from
`shared/soundpacks/bundled/15d04652-5265-4ea7-a376-8a7e11ff6813.simuboardpack`.
Its manifest and bundled permission notice record the authorized release status;
the underlying permission correspondence remains private with the maintainer.
The ignored `SimuBoardMac/build/BCP-rendered-assets` directory remains only a
deterministic re-rendering workspace and is not used directly by the runtime.

## Evaluated but not bundled

| Source | Result |
| --- | --- |
| [hainguyents13/mechvibes](https://github.com/hainguyents13/mechvibes) built-in Cherry ABS/PBT and Everglide packs | The repository has a root MIT license, but most audio packs have no pack-level author/provenance statement. The official licensing guide also warns that community packs can be licensed only by the recording rightsholder. Excluded from the DMG pending written confirmation from the maintainer. |
| [sahaj-b/wayvibes](https://github.com/sahaj-b/wayvibes) | 1,456 audio files inspected. Most packs have no pack-level license and several are credited only to Discord/community sources, so they are not redistributed. |
| Wayvibes Banana Split, MX Speed Silver, and Razer Green packs | Pack-local GPL-3.0 text exists. Excluded to keep Battuta's bundled audio set permissive and simple to redistribute. |
| [Nesdood007/kde-plasma-ringtones](https://github.com/Nesdood007/kde-plasma-ringtones) | Author-recorded IBM Model M audio is CC BY-SA 4.0, but it overlaps the existing buckling-spring profile and adds ShareAlike obligations. |
| [webdevcody/type-joy](https://github.com/webdevcody/type-joy) | MIT and technically usable, but the switch/keyboard model is not identified. Kept out of the axis-specific picker. |
| Other Freesound CC0 candidates | Hako Violet, Alps Orange, lubricated Gateron Yellow, Cherry MX Red, Kailh White, and BOX Pale Blue were catalogued. Their original files require a Freesound account, so no original-file download endpoint was bypassed. |

Repository-level software licenses do not automatically clear unrelated or
uncredited community audio. Battuta therefore does not bundle YouTube rips,
unlicensed community packs, or resources whose original license cannot be
traced.
