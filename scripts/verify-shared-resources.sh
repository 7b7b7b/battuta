#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
AUDIO_ROOT="$REPOSITORY_ROOT/shared/audio/builtin"
BUNDLED_PACKS_ROOT="$REPOSITORY_ROOT/shared/soundpacks/bundled"
BCP_PACK_ID="15d04652-5265-4ea7-a376-8a7e11ff6813"
BCP_PACK_ROOT="$BUNDLED_PACKS_ROOT/$BCP_PACK_ID.simuboardpack"
BROWSER_AUDIO_ROOT="$REPOSITORY_ROOT/audio"
MAC_AUDIO_LINK="$REPOSITORY_ROOT/SimuBoardMac/SimuBoardMac/Resources/Audio"
MAC_BUNDLED_PACKS_LINK="$REPOSITORY_ROOT/SimuBoardMac/SimuBoardMac/Resources/BundledSoundPacks"
WINDOWS_PROJECT="$REPOSITORY_ROOT/BattutaWindows/src/Battuta.Windows/Battuta.Windows.csproj"

fail() {
  print -u2 "shared resource verification failed: $1"
  exit 1
}

count_files() {
  find "$1" -type f -name "$2" | wc -l | tr -d ' '
}

[[ -d "$AUDIO_ROOT" ]] || fail "missing canonical audio directory: $AUDIO_ROOT"

mp3_count=$(count_files "$AUDIO_ROOT" '*.mp3')
wav_count=$(count_files "$AUDIO_ROOT" '*.wav')
audio_count=$(( mp3_count + wav_count ))
[[ "$mp3_count" == 151 ]] || fail "expected 151 MP3 files, found $mp3_count"
[[ "$wav_count" == 86 ]] || fail "expected 86 WAV files, found $wav_count"
[[ "$audio_count" == 237 ]] || fail "expected 237 audio files, found $audio_count"

keyboard_profile_count=$(find "$AUDIO_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name pointer | wc -l | tr -d ' ')
pointer_profile_count=$(find "$AUDIO_ROOT/pointer" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ "$keyboard_profile_count" == 20 ]] || fail "expected 20 keyboard profiles, found $keyboard_profile_count"
[[ "$pointer_profile_count" == 5 ]] || fail "expected 5 pointer profiles, found $pointer_profile_count"

for forbidden_name in bcp suit80; do
  if find "$AUDIO_ROOT" -iname "*$forbidden_name*" -print -quit | grep -q .; then
    fail "bundled sound-pack asset '$forbidden_name' must not be duplicated in the base audio tree"
  fi
done

[[ -d "$BUNDLED_PACKS_ROOT" ]] || fail "missing canonical bundled sound-pack directory"
bundled_pack_count=$(find "$BUNDLED_PACKS_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*.simuboardpack' | wc -l | tr -d ' ')
[[ "$bundled_pack_count" == 1 ]] || fail "expected one bundled sound pack, found $bundled_pack_count"
[[ -d "$BCP_PACK_ROOT" ]] || fail "missing authorized BCP sound pack"

bcp_wav_count=$(count_files "$BCP_PACK_ROOT/assets" '*.wav')
bcp_file_count=$(find "$BCP_PACK_ROOT" -type f | wc -l | tr -d ' ')
[[ "$bcp_wav_count" == 28 ]] || fail "expected 28 BCP WAV files, found $bcp_wav_count"
[[ "$bcp_file_count" == 30 ]] || fail "expected 30 BCP package files, found $bcp_file_count"
[[ -f "$BCP_PACK_ROOT/manifest.json" ]] || fail "missing BCP manifest"
[[ -f "$BCP_PACK_ROOT/licenses/BCP-Suit80-PERMISSION.txt" ]] || fail "missing BCP permission notice"
grep -Fq "\"id\": \"$BCP_PACK_ID\"" "$BCP_PACK_ROOT/manifest.json" \
  || fail "BCP manifest UUID differs from the release contract"
grep -Fq '"name": "BCP (Suit80)"' "$BCP_PACK_ROOT/manifest.json" \
  || fail "BCP manifest name differs from the release contract"
grep -Fq 'Redistribution of the derived BCP (Suit80) audio assets' \
  "$BCP_PACK_ROOT/licenses/BCP-Suit80-PERMISSION.txt" \
  || fail "BCP permission notice does not record redistribution status"

while IFS= read -r bcp_asset; do
  expected_hash=${bcp_asset:t:r}
  actual_hash=$(shasum -a 256 "$bcp_asset" | awk '{print $1}')
  [[ "$actual_hash" == "$expected_hash" ]] \
    || fail "BCP asset hash differs from its content-addressed filename: ${bcp_asset:t}"
  grep -Fq "\"$expected_hash\"" "$BCP_PACK_ROOT/manifest.json" \
    || fail "BCP asset is absent from the manifest: ${bcp_asset:t}"
done < <(find "$BCP_PACK_ROOT/assets" -type f -name '*.wav' | sort)

browser_count=$(count_files "$BROWSER_AUDIO_ROOT" '*.mp3')
[[ "$browser_count" == 151 ]] || fail "expected 151 browser MP3 files, found $browser_count"
while IFS= read -r browser_file; do
  relative_path=${browser_file#"$BROWSER_AUDIO_ROOT/"}
  shared_file="$AUDIO_ROOT/$relative_path"
  [[ -f "$shared_file" ]] || fail "browser sample missing from shared tree: $relative_path"
  cmp -s "$browser_file" "$shared_file" || fail "browser/shared sample differs: $relative_path"
done < <(find "$BROWSER_AUDIO_ROOT" -type f -name '*.mp3' | sort)

[[ -L "$MAC_AUDIO_LINK" ]] || fail "macOS Audio path must be a relative symlink"
[[ "${MAC_AUDIO_LINK:A}" == "${AUDIO_ROOT:A}" ]] || fail "macOS Audio link does not resolve to shared/audio/builtin"
[[ -L "$MAC_BUNDLED_PACKS_LINK" ]] || fail "macOS BundledSoundPacks path must be a relative symlink"
[[ "${MAC_BUNDLED_PACKS_LINK:A}" == "${BUNDLED_PACKS_ROOT:A}" ]] \
  || fail "macOS BundledSoundPacks link does not resolve to shared/soundpacks/bundled"

for brand_file in AppIconPrompt.md AppIconSource.png AppIconSquare.png; do
  [[ -f "$REPOSITORY_ROOT/shared/brand/source/$brand_file" ]] || fail "missing brand source: $brand_file"
done

[[ -f "$REPOSITORY_ROOT/shared/licenses/AUDIO_SOURCES.md" ]] || fail "missing audio provenance"
[[ -f "$REPOSITORY_ROOT/shared/contracts/SOUND_PACK_FORMAT.md" ]] || fail "missing sound-pack contract"

grep -Fq '..\..\..\shared\audio\builtin\**\*.*' "$WINDOWS_PROJECT" \
  || fail "Windows project is not consuming shared audio"
grep -Fq '..\..\..\shared\soundpacks\bundled\**\*.*' "$WINDOWS_PROJECT" \
  || fail "Windows project is not consuming shared bundled sound packs"
grep -Fq '..\..\..\shared\brand\source\AppIconSquare.png' "$WINDOWS_PROJECT" \
  || fail "Windows project is not consuming the shared brand source"
if grep -Eq 'SimuBoardMac[/\\]' "$WINDOWS_PROJECT"; then
  fail "Windows project still depends on macOS-owned assets"
fi
if grep -R -q -E 'SimuBoardMac[/\\]' \
  --include='*.cs' --include='*.csproj' --include='*.ps1' \
  "$REPOSITORY_ROOT/BattutaWindows/src" \
  "$REPOSITORY_ROOT/BattutaWindows/tests" \
  "$REPOSITORY_ROOT/BattutaWindows/scripts"; then
  fail "Windows code, tests, or scripts still depend on macOS-owned assets"
fi

total_keyboard_profiles=$(( keyboard_profile_count + bundled_pack_count ))
total_recordings=$(( audio_count + bcp_wav_count ))
[[ "$total_keyboard_profiles" == 21 ]] || fail "expected 21 total keyboard profiles, found $total_keyboard_profiles"
[[ "$total_recordings" == 265 ]] || fail "expected 265 total recordings, found $total_recordings"

print "shared resources verified: $total_keyboard_profiles keyboard profiles, $pointer_profile_count pointer profiles, $total_recordings recordings ($audio_count base + $bcp_wav_count bundled)"
