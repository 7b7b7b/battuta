# SimuBoard audio sources

This inventory records the provenance and redistribution status of audio that
is bundled with SimuBoard. Derived files are trimmed and/or resampled to
48 kHz mono PCM WAV unless noted otherwise.

## Bundled sources

| SimuBoard profiles | Upstream | Upstream revision | License | Processing |
| --- | --- | --- | --- | --- |
| Original 13 profiles | [tplai/kbsim](https://github.com/tplai/kbsim) | See the original import history | MIT | Existing MP3 samples; decoded and resampled to 48 kHz in memory |
| Kailh BOX White | [Mange/clicketyclack](https://github.com/Mange/clicketyclack) | `bb87dc501a18a082675e51193a8a06134deb2a56` | MIT | Five matched press/release recordings resampled; upstream README says contributed switch sounds must be self-recorded and not taken from elsewhere |
| Logitech G915 TKL Brown | [keyboard-sounds/keyboardsounds-pro](https://github.com/keyboard-sounds/keyboardsounds-pro/tree/main/desktop/bundled-profiles/logitech-g915-tkl-brown) | `bac56ac700635c512e57621f35780c5b79eba4cd` | MIT | Five matched normal-key press/release variations plus dedicated large-key recordings selected from the upstream profile; leading room tone is trimmed while retaining about 2 ms before the first useful transient; profile gain compensation is applied, with extra gain for the much quieter alternate large-key release |
| Studio Tactile and Studio Clicky | [StavSounds: Mechanical Keyboards](https://freesound.org/people/StavSounds/packs/42151/) | Freesound IDs `766625`, `766632`–`766635`, `766605`–`766606`, `766622`–`766624` | CC0 1.0 | Ten public HQ preview MP3s downmixed and resampled; leading room tone is trimmed while retaining about 2 ms before the first useful transient; each upstream file is already one complete key press |
| Keychron Red Linear | [Typing on Keychron V1 Ultra (Red Linear Switch)](https://commons.wikimedia.org/wiki/File:Typing_on_Keychron_V1_Ultra_(Red_Linear_Switch).wav) by C40115 | Wikimedia file revision available on the source page | CC BY 4.0 | Five 180 ms excerpts selected from the original 48 kHz WAV, downmixed to mono, and faded for 4 ms at the tail |
| Kailh Low-profile Blue | [Fast Typing on Mechanical Keyboard](https://freesound.org/people/HeinzBBQ/sounds/502653/) by HeinzBBQ | Freesound ID `502653` | CC0 1.0 | Five 220 ms excerpts selected from the public HQ preview, downmixed and resampled |
| Cherry MX Clear | [Mechanical keyboard clicking. Different keys (4)](https://freesound.org/people/humi74/sounds/412926/) by humi74 | Freesound ID `412926` | CC0 1.0 | Five 220 ms excerpts selected from the public HQ preview, downmixed and resampled |

The imported files can be reproduced with:

```bash
./scripts/import-open-soundpacks.sh \
  /path/to/clicketyclack \
  /path/to/keyboardsounds-pro \
  /path/to/stavsounds-preview-directory \
  /path/to/keychron-red-linear.wav \
  /path/to/kailh-low-profile-blue-audio \
  /path/to/cherry-mx-clear-audio
```

The importer rejects a different Git revision, a modified source directory, or
any of the 13 downloaded files whose SHA-256 does not match this audited import.
It renders all seven profiles in a staging directory before replacing the
previous generated copies, so stale files cannot survive a re-import.

The copyright notices and license terms required for redistribution are in
`SimuBoardMac/Resources/THIRD_PARTY_NOTICES.txt` and the repository-level
`THIRD_PARTY_NOTICES.md`.

## Evaluated but not bundled

| Source | Result |
| --- | --- |
| [hainguyents13/mechvibes](https://github.com/hainguyents13/mechvibes) built-in Cherry ABS/PBT and Everglide packs | The repository has a root MIT license, but most audio packs have no pack-level author/provenance statement. The official licensing guide also warns that community packs can be licensed only by the recording rightsholder. Excluded from the DMG pending written confirmation from the maintainer. |
| [sahaj-b/wayvibes](https://github.com/sahaj-b/wayvibes) | 1,456 audio files inspected. Most packs have no pack-level license and several are credited only to Discord/community sources, so they are not redistributed. |
| Wayvibes Banana Split, MX Speed Silver, and Razer Green packs | Pack-local GPL-3.0 text exists. Excluded to keep SimuBoard's bundled audio set permissive and simple to redistribute. |
| [Nesdood007/kde-plasma-ringtones](https://github.com/Nesdood007/kde-plasma-ringtones) | Author-recorded IBM Model M audio is CC BY-SA 4.0, but it overlaps the existing buckling-spring profile and adds ShareAlike obligations. |
| [webdevcody/type-joy](https://github.com/webdevcody/type-joy) | MIT and technically usable, but the switch/keyboard model is not identified. Kept out of the axis-specific picker. |
| Other Freesound CC0 candidates | Hako Violet, Alps Orange, lubricated Gateron Yellow, Cherry MX Red, Kailh White, and BOX Pale Blue were catalogued. Their original files require a Freesound account, so no original-file download endpoint was bypassed. |

Repository-level software licenses do not automatically clear unrelated or
uncredited community audio. SimuBoard therefore does not bundle YouTube rips,
unlicensed community packs, or resources whose original license cannot be
traced.
