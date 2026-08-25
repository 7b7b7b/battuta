#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: $0 <source-mp4>"
  exit 64
fi

SOURCE_VIDEO=${1:A}
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_ROOT="$PROJECT_DIR/build"
DEFAULT_OUTPUT_ROOT="$BUILD_ROOT/BCP-rendered-assets"
OUTPUT_ROOT=${DEFAULT_OUTPUT_ROOT:A}
PREVIEW_ROOT="$BUILD_ROOT/BCP-audition"
STAGE_DIR=
MASTER_FILE="$STAGE_DIR/bcp-master.wav"
RAW_MONO_FILE="$STAGE_DIR/source-mono.wav"
TARGET_ROOT="$STAGE_DIR/bcp"
PREVIEW_STAGE_ROOT="$STAGE_DIR/BCP-audition"
SILENCE_FILE="$STAGE_DIR/silence-180ms.wav"
OUTPUT_BACKUP_ROOT="$STAGE_DIR/output-backup"
PREVIEW_BACKUP_ROOT="$STAGE_DIR/preview-backup"
TEST_FAIL_AT=${SIMUBOARD_BCP_RENDER_TEST_FAIL_AT:-}
TRANSACTION_COMMITTED=0
OUTPUT_ORIGINAL_PRESENT=0
OUTPUT_ORIGINAL_MOVED=0
OUTPUT_NEW_INSTALLED=0
PREVIEW_ORIGINAL_PRESENT=0
PREVIEW_ORIGINAL_MOVED=0
PREVIEW_NEW_INSTALLED=0
MASTER_FILTER='pan=mono|c0=0.5*c0+0.5*c1,volume=-3dB,highpass=f=55,afftdn=nr=6:nf=-51:tn=1:ad=0.25:fo=1:gs=1,atrim=start=0.025,asetpts=PTS-STARTPTS'
RAW_MONO_FILTER='pan=mono|c0=0.5*c0+0.5*c1,asetpts=PTS-STARTPTS'
RESIDUAL_FILTER='pan=mono|c0=0.5*c0+0.5*c1,volume=-3dB,highpass=f=55,afftdn=nr=6:nf=-51:tn=1:ad=0.25:fo=1:gs=1:om=n,atrim=start=95.525:end=102.025,asetpts=PTS-STARTPTS'
GENERIC_PRESS_FILTER='highpass=f=95'
GENERIC_RELEASE_FILTER='highpass=f=108'

typeset -a CLIPS=(
  'press|GENERIC_R0|16.539|16.598|4.0'
  'release|GENERIC_R0|16.616|16.710|2.0'
  'press|GENERIC_R1|40.512|40.566|1.0'
  'release|GENERIC_R1|40.615|40.678|6.5'
  'press|GENERIC_R2|58.248|58.344|3.5'
  'release|GENERIC_R2|58.355|58.420|3.0'
  'press|GENERIC_R3|59.050|59.107|1.0'
  'release|GENERIC_R3|59.125|59.171|4.5'
  'press|GENERIC_R4|66.579|66.612|4.5'
  'release|GENERIC_R4|66.671|66.736|6.5'
  'press|GENERIC_R0_ALT|20.000|20.077|-4.0'
  'release|GENERIC_R0_ALT|20.107|20.145|2.0'
  'press|GENERIC_R1_ALT|39.165|39.231|2.0'
  'release|GENERIC_R1_ALT|39.261|39.299|-4.7'
  'press|GENERIC_R2_ALT|43.650|43.727|0.0'
  'release|GENERIC_R2_ALT|43.761|43.807|-4.9'
  'press|GENERIC_R3_ALT|49.506|49.596|-0.5'
  'release|GENERIC_R3_ALT|49.610|49.634|-3.3'
  'press|GENERIC_R4_ALT|72.798|72.891|-0.5'
  'release|GENERIC_R4_ALT|72.915|72.961|-4.7'
  'press|SHIFT|99.524|99.608|0.0'
  'release|SHIFT|99.659|99.782|0.0'
  'press|BACKSPACE|97.648|97.714|2.0'
  'release|BACKSPACE|97.726|97.844|2.0'
  'press|ENTER|98.663|98.713|2.0'
  'release|ENTER|98.726|98.846|2.0'
  'press|SPACE|101.444|101.498|-0.5'
  'release|SPACE|101.522|101.626|2.0'
)

typeset -a CYCLES=(
  'GENERIC_R0|16.539|16.710'
  'GENERIC_R1|40.512|40.678'
  'GENERIC_R2|58.248|58.420'
  'GENERIC_R3|59.050|59.171'
  'GENERIC_R4|66.579|66.736'
  'GENERIC_R0_ALT|20.000|20.145'
  'GENERIC_R1_ALT|39.165|39.299'
  'GENERIC_R2_ALT|43.650|43.807'
  'GENERIC_R3_ALT|49.506|49.634'
  'GENERIC_R4_ALT|72.798|72.961'
  'SHIFT|99.524|99.782'
  'BACKSPACE|97.648|97.844'
  'ENTER|98.663|98.846'
  'SPACE|101.444|101.626'
)

typeset -a RAPID_SEQUENCE=(
  GENERIC_R2 GENERIC_R1_ALT GENERIC_R3_ALT GENERIC_R2_ALT GENERIC_R1
  GENERIC_R0_ALT GENERIC_R2 GENERIC_R3 GENERIC_R1_ALT GENERIC_R2_ALT
  GENERIC_R1 GENERIC_R2_ALT GENERIC_R3 GENERIC_R2 GENERIC_R0
  GENERIC_R1_ALT GENERIC_R3_ALT GENERIC_R2_ALT GENERIC_R1 GENERIC_R4_ALT
)

for command_name in ffmpeg ffprobe shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing required command: $command_name"
    exit 69
  fi
done

STAT_BIN=/usr/bin/stat
if [[ ! -x "$STAT_BIN" ]]; then
  STAT_BIN=$(command -v stat || true)
fi
if [[ -z "$STAT_BIN" ]]; then
  print -u2 "Missing required command: stat"
  exit 69
fi

if [[ -L "$BUILD_ROOT" ]]; then
  print -u2 "Build root must not be a symlink: $BUILD_ROOT"
  exit 65
fi
if [[ -e "$BUILD_ROOT" && ! -d "$BUILD_ROOT" ]]; then
  print -u2 "Build root is not a directory: $BUILD_ROOT"
  exit 65
fi
mkdir -p "$BUILD_ROOT"
STAGE_DIR=$(mktemp -d "$BUILD_ROOT/.bcp-render-staging.XXXXXX")
MASTER_FILE="$STAGE_DIR/bcp-master.wav"
RAW_MONO_FILE="$STAGE_DIR/source-mono.wav"
TARGET_ROOT="$STAGE_DIR/bcp"
PREVIEW_STAGE_ROOT="$STAGE_DIR/BCP-audition"
SILENCE_FILE="$STAGE_DIR/silence-180ms.wav"
OUTPUT_BACKUP_ROOT="$STAGE_DIR/output-backup"
PREVIEW_BACKUP_ROOT="$STAGE_DIR/preview-backup"

is_fixed_target_directory() {
  local path=$1

  [[ "$path" == "$OUTPUT_ROOT" || "$path" == "$PREVIEW_ROOT" ]]
}

validate_fixed_target_directory() {
  local path=$1

  if ! is_fixed_target_directory "$path"; then
    print -u2 "Refusing unexpected target directory: $path"
    exit 65
  fi
  if [[ -L "$path" ]]; then
    print -u2 "Target path must not be a symlink: $path"
    exit 65
  fi
  if [[ -e "$path" && ! -d "$path" ]]; then
    print -u2 "Target path is not a directory: $path"
    exit 65
  fi
}

maybe_inject_failure() {
  local point=$1

  if [[ -n "$TEST_FAIL_AT" && "$TEST_FAIL_AT" == "$point" ]]; then
    print -u2 "Injected transactional test failure at: $point"
    exit 70
  fi
}

rollback_target() {
  local final_root=$1
  local backup_root=$2
  local original_present=$3
  local original_moved=$4
  local new_installed=$5

  if ! is_fixed_target_directory "$final_root"; then
    return
  fi

  if (( original_moved )); then
    [[ -e "$final_root" || -L "$final_root" ]] && rm -rf "$final_root"
    if [[ -e "$backup_root" || -L "$backup_root" ]]; then
      mv "$backup_root" "$final_root"
    fi
  elif (( ! original_present && new_installed )); then
    [[ -e "$final_root" || -L "$final_root" ]] && rm -rf "$final_root"
  fi
}

cleanup() {
  if (( ! TRANSACTION_COMMITTED )); then
    rollback_target \
      "$PREVIEW_ROOT" \
      "$PREVIEW_BACKUP_ROOT" \
      "$PREVIEW_ORIGINAL_PRESENT" \
      "$PREVIEW_ORIGINAL_MOVED" \
      "$PREVIEW_NEW_INSTALLED"
    rollback_target \
      "$OUTPUT_ROOT" \
      "$OUTPUT_BACKUP_ROOT" \
      "$OUTPUT_ORIGINAL_PRESENT" \
      "$OUTPUT_ORIGINAL_MOVED" \
      "$OUTPUT_NEW_INSTALLED"
  fi
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [[ ! -f "$SOURCE_VIDEO" || ! -r "$SOURCE_VIDEO" ]]; then
  print -u2 "Missing or unreadable source video: $SOURCE_VIDEO"
  exit 66
fi

file_mtime() {
  local path=$1

  if "$STAT_BIN" -f '%m' "$path" >/dev/null 2>&1; then
    "$STAT_BIN" -f '%m' "$path"
  else
    "$STAT_BIN" -c '%Y' "$path"
  fi
}

sha256_of() {
  local checksum

  checksum=$(shasum -a 256 "$1")
  print -- "${checksum%% *}"
}

verify_source_unchanged() {
  local current_sha current_mtime

  current_sha=$(sha256_of "$SOURCE_VIDEO")
  current_mtime=$(file_mtime "$SOURCE_VIDEO")

  if [[ "$TEST_FAIL_AT" == final-verify && $OUTPUT_NEW_INSTALLED -eq 1 && $PREVIEW_NEW_INSTALLED -eq 1 ]]; then
    print -u2 "Injected transactional test failure at: final-verify"
    exit 70
  fi

  if [[ "$current_sha" != "$SOURCE_SHA_BEFORE" || "$current_mtime" != "$SOURCE_MTIME_BEFORE" ]]; then
    print -u2 "Source changed during render:"
    print -u2 "  before sha256=$SOURCE_SHA_BEFORE mtime=$SOURCE_MTIME_BEFORE"
    print -u2 "  after  sha256=$current_sha mtime=$current_mtime"
    exit 65
  fi
}

format_seconds() {
  printf '%.6f' "$1"
}

timestamp_to_samples() {
  local timestamp=$1
  local milliseconds=${timestamp//./}

  print -- $(( 10#$milliseconds * 48 ))
}

render_master() {
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$SOURCE_VIDEO" \
    -vn \
    -af "$MASTER_FILTER" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_f32le \
    -map_metadata -1 \
    "$MASTER_FILE"
}

render_raw_mono_source() {
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$SOURCE_VIDEO" \
    -vn \
    -af "$RAW_MONO_FILTER" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$RAW_MONO_FILE"
}

render_segment() {
  local phase=$1
  local sample_name=$2
  local start_seconds=$3
  local end_seconds=$4
  local -F 6 gain_db=$5
  local -i start_sample=0
  local -i end_sample=0
  local -i sample_count=0
  local -i fade_in_samples=0
  local -i fade_out_samples=0
  local -i fade_out_start_sample=0
  local target_file="$TARGET_ROOT/$phase/$sample_name.wav"
  local filter_chain

  start_sample=$(timestamp_to_samples "$start_seconds")
  end_sample=$(timestamp_to_samples "$end_seconds")
  (( sample_count = end_sample - start_sample ))
  if (( sample_count <= 0 )); then
    print -u2 "Invalid clip duration for $phase/$sample_name"
    exit 65
  fi

  if [[ "$phase" == press ]]; then
    (( fade_out_samples = sample_count < 192 ? sample_count : 192 ))
  else
    if [[ "$sample_name" == GENERIC_* ]]; then
      (( fade_in_samples = sample_count < 48 ? sample_count : 48 ))
    else
      (( fade_in_samples = sample_count < 96 ? sample_count : 96 ))
    fi
    (( fade_out_samples = sample_count < 192 ? sample_count : 192 ))
  fi
  (( fade_out_start_sample = sample_count - fade_out_samples ))

  filter_chain="atrim=start_sample=${start_sample}:end_sample=${end_sample},asetpts=PTS-STARTPTS,volume=$(printf '%.1f' "$gain_db")dB"
  if [[ "$sample_name" == GENERIC_* ]]; then
    if [[ "$phase" == press ]]; then
      filter_chain+=",$GENERIC_PRESS_FILTER"
    else
      filter_chain+=",$GENERIC_RELEASE_FILTER"
    fi
  fi
  if [[ "$phase" == release ]]; then
    filter_chain+=",afade=t=in:ss=0:ns=${fade_in_samples}"
  fi
  filter_chain+=",afade=t=out:ss=${fade_out_start_sample}:ns=${fade_out_samples},atrim=end_sample=$(( sample_count - 1 )),apad=pad_len=1"

  mkdir -p "${target_file:h}"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$MASTER_FILE" \
    -af "$filter_chain" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

render_residual_preview() {
  mkdir -p "$PREVIEW_STAGE_ROOT"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$SOURCE_VIDEO" \
    -vn \
    -af "$RESIDUAL_FILTER" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$PREVIEW_STAGE_ROOT/BCP-denoise-residual.wav"
}

render_raw_preview_cycle() {
  local sample_name=$1
  local start_seconds=$2
  local end_seconds=$3
  local -i start_sample=0
  local -i end_sample=0
  local target_file="$STAGE_DIR/raw-cycle-$sample_name.wav"

  start_sample=$(timestamp_to_samples "$start_seconds")
  end_sample=$(timestamp_to_samples "$end_seconds")

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$RAW_MONO_FILE" \
    -af "atrim=start_sample=${start_sample}:end_sample=${end_sample},asetpts=PTS-STARTPTS" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

render_processed_preview_cycle() {
  local sample_name=$1
  local target_file="$STAGE_DIR/processed-cycle-$sample_name.wav"

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$TARGET_ROOT/press/$sample_name.wav" \
    -i "$TARGET_ROOT/release/$sample_name.wav" \
    -filter_complex '[0:a][1:a]concat=n=2:v=0:a=1' \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

render_rapid_typing_preview() {
  local -a input_args=()
  local filter_complex=""
  local mix_inputs=""
  local sample_name
  local -i event_index=0
  local -i input_index=0
  local -i press_delay_samples=0
  local -i release_delay_samples=0

  for sample_name in "${RAPID_SEQUENCE[@]}"; do
    press_delay_samples=$(( event_index * 4000 ))
    release_delay_samples=$(( press_delay_samples + 2496 ))

    input_args+=(-i "$TARGET_ROOT/press/$sample_name.wav")
    if [[ -n "$filter_complex" ]]; then
      filter_complex+=";"
    fi
    filter_complex+="[${input_index}:a]adelay=${press_delay_samples}S:all=1[p${event_index}]"
    mix_inputs+="[p${event_index}]"
    (( input_index += 1 ))

    input_args+=(-i "$TARGET_ROOT/release/$sample_name.wav")
    filter_complex+=";[${input_index}:a]adelay=${release_delay_samples}S:all=1[r${event_index}]"
    mix_inputs+="[r${event_index}]"
    (( input_index += 1 ))
    (( event_index += 1 ))
  done

  filter_complex+=";${mix_inputs}amix=inputs=${input_index}:normalize=0:dropout_transition=0,volume=0.8[out]"

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    "${input_args[@]}" \
    -filter_complex "$filter_complex" \
    -map '[out]' \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$PREVIEW_STAGE_ROOT/BCP-rapid-typing-preview.wav"
}

render_silence_bridge() {
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -f lavfi \
    -i 'anullsrc=channel_layout=mono:sample_rate=48000' \
    -t 0.180 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$SILENCE_FILE"
}

concat_segments() {
  local target_file=$1
  local include_silence=$2
  shift 2
  local list_file="$STAGE_DIR/${target_file:t:r}.ffconcat"
  local segment_file
  local segment_count=$#
  local index=1

  {
    print 'ffconcat version 1.0'
    for segment_file in "$@"; do
      print "file '$segment_file'"
      if [[ "$include_silence" == yes && $index -lt $segment_count ]]; then
        print "file '$SILENCE_FILE'"
      fi
      (( index++ ))
    done
  } > "$list_file"

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -f concat \
    -safe 0 \
    -i "$list_file" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

concat_plain() {
  concat_segments "$1" no "${@:2}"
}

concat_with_silence() {
  concat_segments "$1" yes "${@:2}"
}

install_output_root() {
  validate_fixed_target_directory "$OUTPUT_ROOT"
  mkdir -p "${OUTPUT_ROOT:h}"

  if [[ -e "$OUTPUT_ROOT" ]]; then
    OUTPUT_ORIGINAL_PRESENT=1
    mv "$OUTPUT_ROOT" "$OUTPUT_BACKUP_ROOT"
    OUTPUT_ORIGINAL_MOVED=1
  fi

  mv "$TARGET_ROOT" "$OUTPUT_ROOT"
  OUTPUT_NEW_INSTALLED=1
  maybe_inject_failure after-output-install
}

install_preview_root() {
  validate_fixed_target_directory "$PREVIEW_ROOT"
  mkdir -p "${PREVIEW_ROOT:h}"

  if [[ -e "$PREVIEW_ROOT" ]]; then
    PREVIEW_ORIGINAL_PRESENT=1
    mv "$PREVIEW_ROOT" "$PREVIEW_BACKUP_ROOT"
    PREVIEW_ORIGINAL_MOVED=1
  fi

  maybe_inject_failure before-preview-install
  mv "$PREVIEW_STAGE_ROOT" "$PREVIEW_ROOT"
  PREVIEW_NEW_INSTALLED=1
}

validate_rendered_tree() {
  local root=$1
  local -a expected_paths=()
  local -a actual_paths=()
  local relative_path sample_file codec_name sample_rate channels bits_per_sample duration_seconds

  for sample_name in \
    GENERIC_R0 GENERIC_R1 GENERIC_R2 GENERIC_R3 GENERIC_R4 \
    GENERIC_R0_ALT GENERIC_R1_ALT GENERIC_R2_ALT GENERIC_R3_ALT GENERIC_R4_ALT \
    SHIFT BACKSPACE ENTER SPACE; do
    expected_paths+=("press/$sample_name.wav")
    expected_paths+=("release/$sample_name.wav")
  done

  while IFS= read -r -d '' sample_file; do
    relative_path=${sample_file#$root/}
    actual_paths+=("$relative_path")
  done < <(find "$root" -type f -name '*.wav' -print0 | LC_ALL=C sort -z)

  if [[ "$(printf '%s\n' "${actual_paths[@]}")" != "$(printf '%s\n' "${expected_paths[@]}" | LC_ALL=C sort)" ]]; then
    print -u2 "Unexpected generated file set under $root"
    print -u2 "Expected:"
    printf '%s\n' "${expected_paths[@]}" | LC_ALL=C sort >&2
    print -u2 "Actual:"
    printf '%s\n' "${actual_paths[@]}" >&2
    exit 65
  fi

  for relative_path in "${actual_paths[@]}"; do
    sample_file="$root/$relative_path"
    codec_name=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$sample_file")
    sample_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$sample_file")
    channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$sample_file")
    bits_per_sample=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_sample -of default=noprint_wrappers=1:nokey=1 "$sample_file")
    duration_seconds=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$sample_file")
    if [[ "$codec_name" != pcm_s16le || "$sample_rate" != 48000 || "$channels" != 1 || "$bits_per_sample" != 16 ]]; then
      print -u2 "Unexpected output format for $relative_path: $codec_name, $sample_rate Hz, $channels channel(s), $bits_per_sample bits"
      exit 65
    fi
    if ! awk "BEGIN { exit !($duration_seconds > 0) }"; then
      print -u2 "Generated file has non-positive duration: $relative_path ($duration_seconds)"
      exit 65
    fi
  done
}

validate_preview_tree() {
  local preview_root=$1
  local preview_count

  preview_count=$(find "$preview_root" -type f -name '*.wav' | wc -l | tr -d ' ')
  if [[ "$preview_count" != 4 ]]; then
    print -u2 "Unexpected preview artifact count: $preview_count"
    exit 65
  fi

  for preview_file in \
    "$preview_root/BCP-raw-preview.wav" \
    "$preview_root/BCP-processed-preview.wav" \
    "$preview_root/BCP-rapid-typing-preview.wav" \
    "$preview_root/BCP-denoise-residual.wav"; do
    if [[ ! -f "$preview_file" ]]; then
      print -u2 "Missing preview artifact: $preview_file"
      exit 65
    fi
    codec_name=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$preview_file")
    sample_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$preview_file")
    channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$preview_file")
    bits_per_sample=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_sample -of default=noprint_wrappers=1:nokey=1 "$preview_file")
    if [[ "$codec_name" != pcm_s16le || "$sample_rate" != 48000 || "$channels" != 1 || "$bits_per_sample" != 16 ]]; then
      print -u2 "Unexpected preview format for $preview_file"
      exit 65
    fi
  done
}

render_bcp_assets() {
  local record phase sample_name start_seconds end_seconds gain_db

  for record in "${CLIPS[@]}"; do
    IFS='|' read -r phase sample_name start_seconds end_seconds gain_db <<< "$record"
    render_segment "$phase" "$sample_name" "$start_seconds" "$end_seconds" "$gain_db"
  done
}

render_previews() {
  local record sample_name start_seconds end_seconds
  local -a raw_cycle_files=()
  local -a processed_cycle_files=()

  mkdir -p "$PREVIEW_STAGE_ROOT"
  render_silence_bridge

  for record in "${CYCLES[@]}"; do
    IFS='|' read -r sample_name start_seconds end_seconds <<< "$record"
    render_raw_preview_cycle "$sample_name" "$start_seconds" "$end_seconds"
    render_processed_preview_cycle "$sample_name"
    raw_cycle_files+=("$STAGE_DIR/raw-cycle-$sample_name.wav")
    processed_cycle_files+=("$STAGE_DIR/processed-cycle-$sample_name.wav")
  done

  concat_plain "$PREVIEW_STAGE_ROOT/BCP-raw-preview.wav" "${raw_cycle_files[@]}"
  concat_with_silence "$PREVIEW_STAGE_ROOT/BCP-processed-preview.wav" "${processed_cycle_files[@]}"
  render_rapid_typing_preview
  render_residual_preview
}

SOURCE_SHA_BEFORE=$(sha256_of "$SOURCE_VIDEO")
SOURCE_MTIME_BEFORE=$(file_mtime "$SOURCE_VIDEO")

validate_fixed_target_directory "$OUTPUT_ROOT"
validate_fixed_target_directory "$PREVIEW_ROOT"
render_master
render_raw_mono_source
render_bcp_assets
validate_rendered_tree "$TARGET_ROOT"
render_previews
validate_preview_tree "$PREVIEW_STAGE_ROOT"
verify_source_unchanged
install_output_root
install_preview_root
verify_source_unchanged
TRANSACTION_COMMITTED=1

print "Rendered $(find "$OUTPUT_ROOT" -type f -name '*.wav' | wc -l | tr -d ' ') BCP samples into $OUTPUT_ROOT"
print "Rendered $(find "$PREVIEW_ROOT" -type f -name '*.wav' | wc -l | tr -d ' ') local preview files into $PREVIEW_ROOT"
print "Source SHA-256: $SOURCE_SHA_BEFORE"
print "Source mtime: $SOURCE_MTIME_BEFORE"
