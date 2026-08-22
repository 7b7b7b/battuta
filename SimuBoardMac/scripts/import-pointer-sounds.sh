#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: $0 <kenney-ui-audio-directory>"
  exit 64
fi

SOURCE_ROOT=${1:A}
PRESS_SOURCE="$SOURCE_ROOT/Audio/mouseclick1.ogg"
RELEASE_SOURCE="$SOURCE_ROOT/Audio/mouserelease1.ogg"
LICENSE_SOURCE="$SOURCE_ROOT/License.txt"
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
FINAL_TARGET_ROOT="$PROJECT_DIR/SimuBoardMac/Resources/Audio/pointer"
STAGE_DIR=$(mktemp -d /private/tmp/simuboard-pointer-import.XXXXXX)
TARGET_ROOT="$STAGE_DIR/pointer"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

for command_name in ffmpeg ffprobe shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing required command: $command_name"
    exit 69
  fi
done

for source_file in "$PRESS_SOURCE" "$RELEASE_SOURCE" "$LICENSE_SOURCE"; do
  if [[ ! -f "$source_file" ]]; then
    print -u2 "Missing Kenney UI Audio source file: $source_file"
    exit 66
  fi
done

verify_sha256() {
  local source_file=$1
  local expected_hash=$2
  local checksum

  checksum=$(shasum -a 256 "$source_file")
  checksum=${checksum%% *}
  if [[ "$checksum" != "$expected_hash" ]]; then
    print -u2 "SHA-256 mismatch for $source_file"
    exit 65
  fi
}

verify_sha256 "$PRESS_SOURCE" ece1210c62ccae6c9ea4f4c59466d9d453d6b357c7d4b1a6c31196e5e6fea1bf
verify_sha256 "$RELEASE_SOURCE" 23cb78cea76d8f1bb1266af228101a09b5d62063f4ac87ead15b1d395c6181f0
verify_sha256 "$LICENSE_SOURCE" 4f88ab3c885c87874834441a0d009cea8942f57461d7b870be65cf4e31362073

render_sample() {
  local source_file=$1
  local target_file=$2
  local style_filter=$3

  mkdir -p "${target_file:h}"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$source_file" \
    -af "pan=mono|c0=0.5*c0+0.5*c1,${style_filter},silenceremove=start_periods=1:start_duration=0:start_threshold=-45dB:start_silence=0.002:detection=rms:window=0.00025,asetpts=N/SR/TB,areverse,asetpts=N/SR/TB,afade=t=in:st=0:d=0.004,areverse,asetpts=N/SR/TB" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

render_profile() {
  local profile=$1
  local press_filter=$2
  local release_filter=$3

  render_sample "$PRESS_SOURCE" "$TARGET_ROOT/$profile/press/PRIMARY.wav" "$press_filter"
  render_sample "$RELEASE_SOURCE" "$TARGET_ROOT/$profile/release/PRIMARY.wav" "$release_filter"
}

# The names describe simulated tonal treatments, not recordings of particular
# mouse brands or switches. Pitch is lowered independently of duration, then
# press/release-specific filtering controls the original 6–14 kHz transient.
# Output levels retain ample headroom after filtering.
render_profile classic \
  "asetrate=32640,aresample=48000,atempo=1.47058824,lowpass=f=6500:p=2,equalizer=f=3000:t=q:w=1:g=2,volume=0dB" \
  "asetrate=26880,aresample=48000,atempo=1.78571429,lowpass=f=6000:p=2,equalizer=f=2800:t=q:w=1:g=2,volume=0dB"
render_profile silent \
  "asetrate=29760,aresample=48000,atempo=1.61290323,lowpass=f=3600:p=2,lowpass=f=4300:p=2,equalizer=f=1400:t=q:w=1:g=2,volume=2dB" \
  "asetrate=24960,aresample=48000,atempo=1.92307692,lowpass=f=3200:p=2,lowpass=f=3800:p=2,equalizer=f=1200:t=q:w=1:g=2,volume=2dB"
render_profile crisp \
  "asetrate=37440,aresample=48000,atempo=1.28205128,highpass=f=300:p=1,lowpass=f=7500:p=2,lowpass=f=9000:p=2,equalizer=f=4200:t=q:w=1:g=3,volume=-2dB" \
  "asetrate=32640,aresample=48000,atempo=1.47058824,highpass=f=300:p=1,lowpass=f=7000:p=2,lowpass=f=8500:p=2,equalizer=f=3800:t=q:w=1:g=3,volume=-2dB"
render_profile heavy \
  "asetrate=24960,aresample=48000,atempo=1.92307692,lowpass=f=3600:p=2,lowpass=f=4300:p=2,equalizer=f=1000:t=q:w=0.8:g=3,bass=g=4:f=180:w=0.7,volume=4dB" \
  "asetrate=21120,aresample=48000,atempo=2.27272727,lowpass=f=3200:p=2,lowpass=f=3800:p=2,equalizer=f=850:t=q:w=0.8:g=3,bass=g=4:f=160:w=0.7,volume=4dB"
render_profile glass \
  "asetrate=39360,aresample=48000,atempo=1.21951220,highpass=f=500:p=1,lowpass=f=8000:p=2,lowpass=f=10000:p=2,equalizer=f=5000:t=q:w=1:g=3,volume=-3dB" \
  "asetrate=35520,aresample=48000,atempo=1.35135135,highpass=f=500:p=1,lowpass=f=7600:p=2,lowpass=f=9500:p=2,equalizer=f=4500:t=q:w=1:g=3,volume=-3dB"

generated_count=$(find "$TARGET_ROOT" -type f -name '*.wav' | wc -l | tr -d ' ')
if [[ "$generated_count" != 10 ]]; then
  print -u2 "Unexpected generated pointer sample count: $generated_count"
  exit 65
fi

for sample_file in "$TARGET_ROOT"/*/{press,release}/PRIMARY.wav; do
  codec_name=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$sample_file")
  sample_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$sample_file")
  channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$sample_file")
  if [[ "$codec_name" != pcm_s16le || "$sample_rate" != 48000 || "$channels" != 1 ]]; then
    print -u2 "Unexpected output format for $sample_file: $codec_name, $sample_rate Hz, $channels channel(s)"
    exit 65
  fi
done

if [[ -e "$FINAL_TARGET_ROOT" ]]; then
  backup_root="$STAGE_DIR/previous-pointer"
  mv "$FINAL_TARGET_ROOT" "$backup_root"
  if ! mv "$TARGET_ROOT" "$FINAL_TARGET_ROOT"; then
    mv "$backup_root" "$FINAL_TARGET_ROOT"
    exit 1
  fi
else
  mkdir -p "${FINAL_TARGET_ROOT:h}"
  mv "$TARGET_ROOT" "$FINAL_TARGET_ROOT"
fi

print "Imported $generated_count pointer samples from Kenney UI Audio (CC0)."
find "$FINAL_TARGET_ROOT" -type f -name '*.wav' -print0 | sort -z | xargs -0 shasum -a 256
