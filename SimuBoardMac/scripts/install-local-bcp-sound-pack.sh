#!/bin/zsh
set -euo pipefail

if (( $# > 2 )); then
  print -u2 "Usage: $0 [asset-root] [library-root]"
  exit 64
fi

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DEFAULT_ASSET_ROOT="$PROJECT_DIR/build/BCP-rendered-assets"
DEFAULT_LIBRARY_ROOT="$HOME/Library/Application Support/SimuBoard/SoundPacks"
ASSET_ROOT=${1:-$DEFAULT_ASSET_ROOT}
LIBRARY_ROOT=${2:-$DEFAULT_LIBRARY_ROOT}
ASSET_ROOT=${ASSET_ROOT:A}
DEFAULT_LIBRARY_ROOT=${DEFAULT_LIBRARY_ROOT:A}
LIBRARY_ROOT=${LIBRARY_ROOT:A}

SHOULD_MIGRATE_LEGACY_SELECTION=0
if [[ "$LIBRARY_ROOT" == "$DEFAULT_LIBRARY_ROOT" ]]; then
  SHOULD_MIGRATE_LEGACY_SELECTION=1
fi

PACK_UUID="15d04652-5265-4ea7-a376-8a7e11ff6813"
PACK_NAME="BCP (Suit80)"
PACK_FAMILY="线性"
PACK_TONE="厚实、木感"
PACK_LAYOUT_ID="mac-ansi-tkl-v1"
PACK_BASE_PROFILE_ID="holypanda"
PACK_SELECTION_ID="custom:15d04652-5265-4ea7-a376-8a7e11ff6813"
ATTRIBUTION_TITLE="【打字声音】Suit80｜BCP轴｜GMK Ursa 大熊 - Original.mp4"
ATTRIBUTION_AUTHOR="J_Eason001"
ATTRIBUTION_NOTICE="Permission unverified. Local evaluation only. Do not redistribute."
PACK_DIRECTORY_NAME="${PACK_UUID}.simuboardpack"
DEFAULTS_DOMAIN=${SIMUBOARD_DEFAULTS_DOMAIN:-com.simuboard.mac}
DEFAULTS_EXECUTABLE=${SIMUBOARD_DEFAULTS_EXECUTABLE:-defaults}
FAIL_AT=${SIMUBOARD_INSTALLER_FAIL_AT:-}
TIMESTAMP_OVERRIDE=${SIMUBOARD_INSTALLER_NOW:-}

typeset -a EXPECTED_RECORDS=(
  'press|GENERIC_R0|row|R0'
  'press|GENERIC_R1|row|R1'
  'press|GENERIC_R2|row|R2'
  'press|GENERIC_R3|row|R3'
  'press|GENERIC_R4|row|R4'
  'press|GENERIC_R0_ALT|override|digit2,digit4,digit6,digit8,digit0,equal'
  'press|GENERIC_R1_ALT|override|w,r,y,i,p,rightBracket'
  'press|GENERIC_R2_ALT|override|s,f,h,k,semicolon'
  'press|GENERIC_R3_ALT|override|x,v,n,comma,slash'
  'press|GENERIC_R4_ALT|override|f2,f4,f6,f8,f10,f12,upArrow,rightArrow'
  'press|SHIFT|override|leftShift,rightShift'
  'press|BACKSPACE|special|backspace'
  'press|ENTER|special|enter'
  'press|SPACE|special|space'
  'release|GENERIC_R0|row|R0'
  'release|GENERIC_R1|row|R1'
  'release|GENERIC_R2|row|R2'
  'release|GENERIC_R3|row|R3'
  'release|GENERIC_R4|row|R4'
  'release|GENERIC_R0_ALT|override|digit2,digit4,digit6,digit8,digit0,equal'
  'release|GENERIC_R1_ALT|override|w,r,y,i,p,rightBracket'
  'release|GENERIC_R2_ALT|override|s,f,h,k,semicolon'
  'release|GENERIC_R3_ALT|override|x,v,n,comma,slash'
  'release|GENERIC_R4_ALT|override|f2,f4,f6,f8,f10,f12,upArrow,rightArrow'
  'release|SHIFT|override|leftShift,rightShift'
  'release|BACKSPACE|special|backspace'
  'release|ENTER|special|enter'
  'release|SPACE|special|space'
)

typeset -a SHIFT_ONLY_EXPECTED_RECORDS=(
  'press|GENERIC_R0|row|R0'
  'press|GENERIC_R1|row|R1'
  'press|GENERIC_R2|row|R2'
  'press|GENERIC_R3|row|R3'
  'press|GENERIC_R4|row|R4'
  'press|SHIFT|override|leftShift,rightShift'
  'press|BACKSPACE|special|backspace'
  'press|ENTER|special|enter'
  'press|SPACE|special|space'
  'release|GENERIC_R0|row|R0'
  'release|GENERIC_R1|row|R1'
  'release|GENERIC_R2|row|R2'
  'release|GENERIC_R3|row|R3'
  'release|GENERIC_R4|row|R4'
  'release|SHIFT|override|leftShift,rightShift'
  'release|BACKSPACE|special|backspace'
  'release|ENTER|special|enter'
  'release|SPACE|special|space'
)

typeset -a LEGACY_EXPECTED_RECORDS=(
  'press|GENERIC_R0|row|R0'
  'press|GENERIC_R1|row|R1'
  'press|GENERIC_R2|row|R2'
  'press|GENERIC_R3|row|R3'
  'press|GENERIC_R4|row|R4'
  'press|BACKSPACE|special|backspace'
  'press|ENTER|special|enter'
  'press|SPACE|special|space'
  'release|GENERIC_R0|row|R0'
  'release|GENERIC_R1|row|R1'
  'release|GENERIC_R2|row|R2'
  'release|GENERIC_R3|row|R3'
  'release|GENERIC_R4|row|R4'
  'release|BACKSPACE|special|backspace'
  'release|ENTER|special|enter'
  'release|SPACE|special|space'
)

typeset -a EXPECTED_OVERRIDE_KEYS=(
  digit2 digit4 digit6 digit8 digit0 equal
  w r y i p rightBracket
  s f h k semicolon
  x v n comma slash
  f2 f4 f6 f8 f10 f12 upArrow rightArrow
  leftShift rightShift
)

typeset -a SHIFT_ONLY_OVERRIDE_KEYS=(leftShift rightShift)

STAT_BIN=/usr/bin/stat
if [[ ! -x "$STAT_BIN" ]]; then
  STAT_BIN=$(command -v stat || true)
fi

DESTINATION_PACK="$LIBRARY_ROOT/$PACK_DIRECTORY_NAME"
STAGE_ROOT=""
STAGED_PACK_ROOT=""
BACKUP_PACK_ROOT=""
ASSET_LINES=""
PRESS_ROWS_LINES=""
PRESS_SPECIALS_LINES=""
PRESS_OVERRIDES_LINES=""
RELEASE_ROWS_LINES=""
RELEASE_SPECIALS_LINES=""
RELEASE_OVERRIDES_LINES=""
ASSETS_OBJECT_FILE=""
PRESS_ROWS_FILE=""
PRESS_SPECIALS_FILE=""
PRESS_OVERRIDES_FILE=""
RELEASE_ROWS_FILE=""
RELEASE_SPECIALS_FILE=""
RELEASE_OVERRIDES_FILE=""
TARGET_FINGERPRINT_FILE=""
EXISTING_CREATED_AT=""
EXISTING_MODIFIED_AT=""
EXISTING_FINGERPRINT=""
PREVIOUS_PACK_PRESENT=0
BACKUP_CREATED=0
DESTINATION_INSTALLED=0
INSTALL_COMMITTED=0

fail() {
  print -u2 "$1"
  exit "${2:-65}"
}

warn() {
  print -u2 "Warning: $1"
}

cleanup_on_exit() {
  local exit_status=$1
  local rollback_failed=0

  if (( INSTALL_COMMITTED == 0 )); then
    rollback_installation || rollback_failed=1
  elif (( BACKUP_CREATED == 1 )) && [[ -e "$BACKUP_PACK_ROOT" ]]; then
    rm -rf "$BACKUP_PACK_ROOT"
    BACKUP_CREATED=0
  fi

  if [[ -n "$STAGE_ROOT" && -d "$STAGE_ROOT" ]]; then
    rm -rf "$STAGE_ROOT"
  fi

  if (( rollback_failed == 1 )); then
    warn "Manual recovery may be required for $DESTINATION_PACK"
  fi
  exit "$exit_status"
}
trap 'cleanup_on_exit $?' EXIT

for command_name in ffmpeg ffprobe jq shasum od date; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Missing required command: $command_name" 69
  fi
done
[[ -n "$STAT_BIN" ]] || fail "Missing required command: stat" 69

file_size_bytes() {
  local path=$1

  if "$STAT_BIN" -f '%z' "$path" >/dev/null 2>&1; then
    "$STAT_BIN" -f '%z' "$path"
  else
    "$STAT_BIN" -c '%s' "$path"
  fi
}

sha256_of() {
  local checksum

  checksum=$(shasum -a 256 "$1")
  print -- "${checksum%% *}"
}

installer_timestamp() {
  if [[ -n "$TIMESTAMP_OVERRIDE" ]]; then
    print -- "$TIMESTAMP_OVERRIDE"
  else
    date -u +%Y-%m-%dT%H:%M:%SZ
  fi
}

maybe_fail_at() {
  local point=$1

  if [[ "$FAIL_AT" == "$point" ]]; then
    fail "Injected installer failure at $point" 73
  fi
}

ensure_safe_directory_root() {
  local path=$1

  case "$path" in
    ''|/|/private|/tmp|/private/tmp)
      fail "Refusing unsafe destination root: $path"
      ;;
  esac
}

ensure_directory_root_ready() {
  ensure_safe_directory_root "$LIBRARY_ROOT"

  if [[ -e "$LIBRARY_ROOT" && ! -d "$LIBRARY_ROOT" ]]; then
    fail "Library root is not a directory: $LIBRARY_ROOT"
  fi
  if [[ -L "$LIBRARY_ROOT" ]]; then
    fail "Library root must not be a symlink: $LIBRARY_ROOT"
  fi
  mkdir -p "$LIBRARY_ROOT"
}

setup_work_paths() {
  local backup_suffix

  STAGE_ROOT=$(mktemp -d "$LIBRARY_ROOT/.bcp-pack-staging.XXXXXX")
  STAGED_PACK_ROOT="$STAGE_ROOT/$PACK_DIRECTORY_NAME"
  ASSET_LINES="$STAGE_ROOT/assets.jsonl"
  PRESS_ROWS_LINES="$STAGE_ROOT/press-rows.jsonl"
  PRESS_SPECIALS_LINES="$STAGE_ROOT/press-specials.jsonl"
  PRESS_OVERRIDES_LINES="$STAGE_ROOT/press-overrides.jsonl"
  RELEASE_ROWS_LINES="$STAGE_ROOT/release-rows.jsonl"
  RELEASE_SPECIALS_LINES="$STAGE_ROOT/release-specials.jsonl"
  RELEASE_OVERRIDES_LINES="$STAGE_ROOT/release-overrides.jsonl"
  ASSETS_OBJECT_FILE="$STAGE_ROOT/assets-object.json"
  PRESS_ROWS_FILE="$STAGE_ROOT/press-rows.json"
  PRESS_SPECIALS_FILE="$STAGE_ROOT/press-specials.json"
  PRESS_OVERRIDES_FILE="$STAGE_ROOT/press-overrides.json"
  RELEASE_ROWS_FILE="$STAGE_ROOT/release-rows.json"
  RELEASE_SPECIALS_FILE="$STAGE_ROOT/release-specials.json"
  RELEASE_OVERRIDES_FILE="$STAGE_ROOT/release-overrides.json"
  TARGET_FINGERPRINT_FILE="$STAGE_ROOT/target-fingerprint.json"

  backup_suffix="${$}-$(date -u +%Y%m%d%H%M%S)"
  BACKUP_PACK_ROOT="$LIBRARY_ROOT/.${PACK_UUID}.backup-${backup_suffix}.simuboardpack"
  while [[ -e "$BACKUP_PACK_ROOT" ]]; do
    backup_suffix="${backup_suffix}x"
    BACKUP_PACK_ROOT="$LIBRARY_ROOT/.${PACK_UUID}.backup-${backup_suffix}.simuboardpack"
  done
}

ensure_exact_asset_tree() {
  local -a expected_paths=()
  local -a actual_paths=()
  local record phase sample_name relative_path sample_file

  for record in "${EXPECTED_RECORDS[@]}"; do
    IFS='|' read -r phase sample_name _ <<< "$record"
    expected_paths+=("$phase/$sample_name.wav")
  done

  while IFS= read -r sample_file; do
    [[ -n "$sample_file" ]] || continue
    relative_path=${sample_file#$ASSET_ROOT/}
    actual_paths+=("$relative_path")
  done < <(find "$ASSET_ROOT" -type f | LC_ALL=C sort)

  if [[ "$(printf '%s\n' "${actual_paths[@]}")" != "$(printf '%s\n' "${expected_paths[@]}" | LC_ALL=C sort)" ]]; then
    print -u2 "Unexpected asset tree under $ASSET_ROOT"
    print -u2 "Expected:"
    printf '%s\n' "${expected_paths[@]}" | LC_ALL=C sort >&2
    print -u2 "Actual:"
    printf '%s\n' "${actual_paths[@]}" >&2
    exit 65
  fi
}

validate_audio_file() {
  local file=$1
  local relative_path=$2
  local metadata codec_name sample_rate channels bits_per_sample duration_seconds byte_count last_sample

  metadata=$(ffprobe \
    -v error \
    -of json \
    -show_entries stream=codec_name,sample_rate,channels,bits_per_sample:format=duration \
    "$file")
  codec_name=$(jq -r '.streams[0].codec_name // empty' <<< "$metadata")
  sample_rate=$(jq -r '.streams[0].sample_rate // empty' <<< "$metadata")
  channels=$(jq -r '.streams[0].channels // empty' <<< "$metadata")
  bits_per_sample=$(jq -r '.streams[0].bits_per_sample // empty' <<< "$metadata")
  duration_seconds=$(jq -r '.format.duration // empty' <<< "$metadata")

  [[ "$codec_name" == "pcm_s16le" ]] || fail "Unexpected codec for $relative_path: $codec_name"
  [[ "$sample_rate" == "48000" ]] || fail "Unexpected sample rate for $relative_path: $sample_rate"
  [[ "$channels" == "1" ]] || fail "Unexpected channel count for $relative_path: $channels"
  [[ "$bits_per_sample" == "16" ]] || fail "Unexpected bit depth for $relative_path: $bits_per_sample"
  awk "BEGIN { exit !($duration_seconds >= 0.005 && $duration_seconds <= 5.0) }" \
    || fail "Audio duration out of range for $relative_path: $duration_seconds"

  byte_count=$(file_size_bytes "$file")
  (( byte_count > 0 )) || fail "Audio file is empty: $relative_path"

  last_sample=$(ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -i "$file" \
    -f s16le \
    -ac 1 \
    -ar 48000 \
    - 2>/dev/null \
    | tail -c 2 \
    | od -An -td2 \
    | tr -d '[:space:]')
  [[ "$last_sample" == "0" ]] || fail "Audio must end on an exact zero sample: $relative_path"

  print -- "$duration_seconds|$byte_count"
}

append_assignment() {
  local phase=$1
  local assignment_kind=$2
  local assignment_key=$3
  local asset_id=$4
  local target_file override_key

  case "$phase:$assignment_kind" in
    press:row) target_file=$PRESS_ROWS_LINES ;;
    press:special) target_file=$PRESS_SPECIALS_LINES ;;
    press:override) target_file=$PRESS_OVERRIDES_LINES ;;
    release:row) target_file=$RELEASE_ROWS_LINES ;;
    release:special) target_file=$RELEASE_SPECIALS_LINES ;;
    release:override) target_file=$RELEASE_OVERRIDES_LINES ;;
    *) fail "Unknown assignment bucket: $phase/$assignment_kind" ;;
  esac

  if [[ "$assignment_kind" == override ]]; then
    for override_key in ${(s:,:)assignment_key}; do
      jq -n \
        --arg key "$override_key" \
        --arg assetID "$asset_id" \
        '{key: $key, value: {kind: "asset", assetID: $assetID}}' >> "$target_file"
    done
  else
    jq -n \
      --arg key "$assignment_key" \
      --arg value "$asset_id" \
      '{key: $key, value: $value}' >> "$target_file"
  fi
}

build_manifest_maps() {
  jq -sS 'reduce .[] as $item ({}; .[$item.id] = $item)' "$ASSET_LINES" > "$ASSETS_OBJECT_FILE"
  jq -sS 'reduce .[] as $item ({}; .[$item.key] = $item.value)' "$PRESS_ROWS_LINES" > "$PRESS_ROWS_FILE"
  jq -sS 'reduce .[] as $item ({}; .[$item.key] = $item.value)' "$PRESS_SPECIALS_LINES" > "$PRESS_SPECIALS_FILE"
  jq -sS 'reduce .[] as $item ({}; .[$item.key] = $item.value)' "$PRESS_OVERRIDES_LINES" > "$PRESS_OVERRIDES_FILE"
  jq -sS 'reduce .[] as $item ({}; .[$item.key] = $item.value)' "$RELEASE_ROWS_LINES" > "$RELEASE_ROWS_FILE"
  jq -sS 'reduce .[] as $item ({}; .[$item.key] = $item.value)' "$RELEASE_SPECIALS_LINES" > "$RELEASE_SPECIALS_FILE"
  jq -sS 'reduce .[] as $item ({}; .[$item.key] = $item.value)' "$RELEASE_OVERRIDES_LINES" > "$RELEASE_OVERRIDES_FILE"
}

build_target_fingerprint() {
  jq -ncS \
    --arg packID "$PACK_UUID" \
    --arg name "$PACK_NAME" \
    --arg family "$PACK_FAMILY" \
    --arg tone "$PACK_TONE" \
    --arg layoutID "$PACK_LAYOUT_ID" \
    --arg baseProfileID "$PACK_BASE_PROFILE_ID" \
    --arg title "$ATTRIBUTION_TITLE" \
    --arg author "$ATTRIBUTION_AUTHOR" \
    --arg notice "$ATTRIBUTION_NOTICE" \
    --slurpfile assets "$ASSETS_OBJECT_FILE" \
    --slurpfile pressRows "$PRESS_ROWS_FILE" \
    --slurpfile pressSpecials "$PRESS_SPECIALS_FILE" \
    --slurpfile pressOverrides "$PRESS_OVERRIDES_FILE" \
    --slurpfile releaseRows "$RELEASE_ROWS_FILE" \
    --slurpfile releaseSpecials "$RELEASE_SPECIALS_FILE" \
    --slurpfile releaseOverrides "$RELEASE_OVERRIDES_FILE" \
    '{
      schemaVersion: 1,
      id: $packID,
      name: $name,
      author: null,
      family: $family,
      tone: $tone,
      notes: null,
      baseProfileID: $baseProfileID,
      layoutID: $layoutID,
      press: {
        generic: null,
        rows: $pressRows[0],
        specials: $pressSpecials[0],
        keyOverrides: $pressOverrides[0]
      },
      release: {
        generic: null,
        rows: $releaseRows[0],
        specials: $releaseSpecials[0],
        keyOverrides: $releaseOverrides[0]
      },
      assets: $assets[0],
      attributions: [
        {
          title: $title,
          author: $author,
          sourceURL: null,
          licenseName: null,
          notice: $notice
        }
      ]
    }' > "$TARGET_FINGERPRINT_FILE"
}

validate_manifest_file() {
  local manifest_path=$1
  local context_message=$2

  [[ -f "$manifest_path" ]] || fail "$context_message"
  [[ ! -L "$manifest_path" ]] || fail "$context_message"
  jq -e . "$manifest_path" >/dev/null 2>&1 || fail "$context_message"
}

validate_iso8601_utc_timestamp() {
  local timestamp=$1
  local roundtrip=""

  [[ "$timestamp" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' ]] || return 1
  roundtrip=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$timestamp" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) \
    || return 1
  [[ "$roundtrip" == "$timestamp" ]]
}

manifest_fingerprint_of() {
  local manifest_path=$1

  jq -cS \
    '{schemaVersion,id,name,author,family,tone,notes,baseProfileID,layoutID,press,release,assets,attributions}' \
    "$manifest_path"
}

validate_fixed_bcp_pack() {
  local pack_root=$1
  local context_message=$2
  local allow_legacy=${3:-0}
  local manifest_path=$pack_root/manifest.json
  local assets_root=$pack_root/assets
  local created_at modified_at top_level_listing asset_listing finder_metadata_path
  local -i expected_count=28
  local -A seen_asset_ids=()
  local -a expected_asset_paths=()
  local -a validation_records=("${EXPECTED_RECORDS[@]}")
  local -a expected_override_keys=("${EXPECTED_OVERRIDE_KEYS[@]}")
  local record phase sample_name assignment_kind assignment_key asset_id asset_relative_path
  local first_override_key override_key mapped_asset_id
  local original_filename asset_file validation actual_duration actual_byte_count manifest_duration
  local manifest_byte_count asset_sha expected_override_keys_json

  [[ -d "$pack_root" ]] || fail "$context_message"
  [[ ! -L "$pack_root" ]] || fail "$context_message"
  [[ "${pack_root##*/}" == "$PACK_DIRECTORY_NAME" ]] || fail "$context_message"
  [[ -d "$assets_root" ]] || fail "$context_message"
  [[ ! -L "$assets_root" ]] || fail "$context_message"

  validate_manifest_file "$manifest_path" "$context_message"

  if (( allow_legacy )) && jq -e '
    (.assets | type == "object" and length == 16)
    and (.press.keyOverrides == {})
    and (.release.keyOverrides == {})
  ' "$manifest_path" >/dev/null 2>&1; then
    expected_count=16
    validation_records=("${LEGACY_EXPECTED_RECORDS[@]}")
    expected_override_keys=()
  elif (( allow_legacy )) && jq -e '
    (.assets | type == "object" and length == 18)
    and ((.press.keyOverrides | keys | sort) == ["leftShift","rightShift"])
    and ((.release.keyOverrides | keys | sort) == ["leftShift","rightShift"])
  ' "$manifest_path" >/dev/null 2>&1; then
    expected_count=18
    validation_records=("${SHIFT_ONLY_EXPECTED_RECORDS[@]}")
    expected_override_keys=("${SHIFT_ONLY_OVERRIDE_KEYS[@]}")
  fi

  expected_override_keys_json=$(jq -nc --args \
    '$ARGS.positional | sort' "${expected_override_keys[@]}") || fail "$context_message"

  jq -e \
    --argjson expectedAssetCount "$expected_count" \
    --argjson expectedOverrideKeys "$expected_override_keys_json" \
    --arg packID "$PACK_UUID" \
    --arg name "$PACK_NAME" \
    --arg family "$PACK_FAMILY" \
    --arg tone "$PACK_TONE" \
    --arg layoutID "$PACK_LAYOUT_ID" \
    --arg baseProfileID "$PACK_BASE_PROFILE_ID" \
    --arg title "$ATTRIBUTION_TITLE" \
    --arg author "$ATTRIBUTION_AUTHOR" \
    --arg notice "$ATTRIBUTION_NOTICE" \
    '
      (.schemaVersion == 1)
      and (.id == $packID)
      and (.name == $name)
      and (.author == null)
      and (.family == $family)
      and (.tone == $tone)
      and (.notes == null)
      and (.baseProfileID == $baseProfileID)
      and (.layoutID == $layoutID)
      and (.createdAt | type == "string")
      and (.modifiedAt | type == "string")
      and (.press | type == "object")
      and (.release | type == "object")
      and ((.press | keys | sort) == ["generic","keyOverrides","rows","specials"])
      and ((.release | keys | sort) == ["generic","keyOverrides","rows","specials"])
      and (.press.generic == null)
      and (.release.generic == null)
      and ((.press.keyOverrides | keys | sort) == $expectedOverrideKeys)
      and ((.release.keyOverrides | keys | sort) == $expectedOverrideKeys)
      and (all(.press.keyOverrides[]; .kind == "asset"))
      and (all(.release.keyOverrides[]; .kind == "asset"))
      and ((.press.rows | type == "object" and (keys | sort) == ["R0","R1","R2","R3","R4"]))
      and ((.release.rows | type == "object" and (keys | sort) == ["R0","R1","R2","R3","R4"]))
      and ((.press.specials | type == "object" and (keys | sort) == ["backspace","enter","space"]))
      and ((.release.specials | type == "object" and (keys | sort) == ["backspace","enter","space"]))
      and (.assets | type == "object" and length == $expectedAssetCount)
      and (.attributions == [{
        title: $title,
        author: $author,
        sourceURL: null,
        licenseName: null,
        notice: $notice
      }])
    ' "$manifest_path" >/dev/null 2>&1 || fail "$context_message"

  created_at=$(jq -r '.createdAt' "$manifest_path") || fail "$context_message"
  modified_at=$(jq -r '.modifiedAt' "$manifest_path") || fail "$context_message"
  validate_iso8601_utc_timestamp "$created_at" || fail "$context_message"
  validate_iso8601_utc_timestamp "$modified_at" || fail "$context_message"

  for finder_metadata_path in "$pack_root/.DS_Store" "$assets_root/.DS_Store"; do
    if [[ -e "$finder_metadata_path" || -L "$finder_metadata_path" ]]; then
      [[ -f "$finder_metadata_path" && ! -L "$finder_metadata_path" ]] || fail "$context_message"
    fi
  done

  top_level_listing=$(find "$pack_root" -mindepth 1 -maxdepth 1 ! -name '.DS_Store' -print | LC_ALL=C sort)
  [[ "$top_level_listing" == $pack_root/assets$'\n'$pack_root/manifest.json ]] || fail "$context_message"

  for record in "${validation_records[@]}"; do
    IFS='|' read -r phase sample_name assignment_kind assignment_key <<< "$record"
    case "$assignment_kind" in
      row)
        asset_id=$(jq -r --arg phase "$phase" --arg key "$assignment_key" '
          if $phase == "press" then .press.rows[$key] else .release.rows[$key] end // empty
        ' "$manifest_path") || fail "$context_message"
        ;;
      special)
        asset_id=$(jq -r --arg phase "$phase" --arg key "$assignment_key" '
          if $phase == "press" then .press.specials[$key] else .release.specials[$key] end // empty
        ' "$manifest_path") || fail "$context_message"
        ;;
      override)
        first_override_key=${assignment_key%%,*}
        asset_id=$(jq -r --arg phase "$phase" --arg key "$first_override_key" '
          if $phase == "press"
          then .press.keyOverrides[$key].assetID
          else .release.keyOverrides[$key].assetID
          end // empty
        ' "$manifest_path") || fail "$context_message"
        for override_key in ${(s:,:)assignment_key}; do
          mapped_asset_id=$(jq -r --arg phase "$phase" --arg key "$override_key" '
            if $phase == "press"
            then .press.keyOverrides[$key].assetID
            else .release.keyOverrides[$key].assetID
            end // empty
          ' "$manifest_path") || fail "$context_message"
          [[ "$mapped_asset_id" == "$asset_id" ]] || fail "$context_message"
        done
        ;;
      *) fail "$context_message" ;;
    esac

    [[ "$asset_id" =~ '^[0-9a-f]{64}$' ]] || fail "$context_message"
    [[ -z "${seen_asset_ids[$asset_id]-}" ]] || fail "$context_message"
    seen_asset_ids[$asset_id]=1

    asset_relative_path="assets/$asset_id.wav"
    original_filename="$phase/$sample_name.wav"
    expected_asset_paths+=("$asset_relative_path")
    jq -e \
      --arg id "$asset_id" \
      --arg relativePath "$asset_relative_path" \
      --arg originalFilename "$original_filename" \
      '
        .assets[$id]
        and ((.assets[$id] | keys | sort) == [
          "byteCount",
          "channelCount",
          "durationSeconds",
          "id",
          "license",
          "originalFilename",
          "relativePath",
          "sampleRate",
          "sha256"
        ])
        and (.assets[$id].id == $id)
        and (.assets[$id].sha256 == $id)
        and (.assets[$id].relativePath == $relativePath)
        and (.assets[$id].originalFilename == $originalFilename)
        and (.assets[$id].sampleRate == 48000)
        and (.assets[$id].channelCount == 1)
        and (.assets[$id].license == null)
        and (.assets[$id].durationSeconds | type == "number" and . >= 0.005 and . <= 5)
        and (.assets[$id].byteCount | type == "number" and . > 0)
      ' "$manifest_path" >/dev/null 2>&1 || fail "$context_message"

    asset_file="$pack_root/$asset_relative_path"
    [[ -f "$asset_file" ]] || fail "$context_message"
    [[ ! -L "$asset_file" ]] || fail "$context_message"

    validation=$(validate_audio_file "$asset_file" "$asset_relative_path")
    actual_duration=${validation%%|*}
    actual_byte_count=${validation##*|}
    manifest_duration=$(jq -r --arg id "$asset_id" '.assets[$id].durationSeconds' "$manifest_path") \
      || fail "$context_message"
    manifest_byte_count=$(jq -r --arg id "$asset_id" '.assets[$id].byteCount' "$manifest_path") \
      || fail "$context_message"
    awk "BEGIN { diff = $actual_duration - $manifest_duration; if (diff < 0) diff = -diff; exit !(diff < 0.002) }" \
      || fail "$context_message"
    [[ "$actual_byte_count" == "$manifest_byte_count" ]] || fail "$context_message"

    asset_sha=$(sha256_of "$asset_file")
    [[ "$asset_sha" == "$asset_id" ]] || fail "$context_message"
  done

  (( ${#seen_asset_ids} == expected_count )) || fail "$context_message"
  [[ "$(jq -r '.assets | keys | length' "$manifest_path")" == "$expected_count" ]] || fail "$context_message"

  asset_listing=$(find "$assets_root" -mindepth 1 -maxdepth 1 ! -name '.DS_Store' -print | LC_ALL=C sort)
  [[ "$asset_listing" == "$(printf '%s\n' "${expected_asset_paths[@]}" | sed "s#^#$pack_root/#" | LC_ALL=C sort)" ]] \
    || fail "$context_message"
}

read_existing_pack_state() {
  local manifest_path

  if [[ ! -e "$DESTINATION_PACK" ]]; then
    PREVIOUS_PACK_PRESENT=0
    return
  fi

  [[ -d "$DESTINATION_PACK" ]] || fail "Existing BCP pack path is not a directory: $DESTINATION_PACK"
  [[ ! -L "$DESTINATION_PACK" ]] || fail "Existing BCP pack path must not be a symlink: $DESTINATION_PACK"

  validate_fixed_bcp_pack "$DESTINATION_PACK" \
    "Existing fixed BCP pack is invalid and will not be overwritten" \
    1

  PREVIOUS_PACK_PRESENT=1
  manifest_path="$DESTINATION_PACK/manifest.json"
  EXISTING_CREATED_AT=$(jq -r '.createdAt' "$manifest_path")
  EXISTING_MODIFIED_AT=$(jq -r '.modifiedAt' "$manifest_path")
  EXISTING_FINGERPRINT=$(manifest_fingerprint_of "$manifest_path") \
    || fail "Existing fixed BCP pack manifest could not be fingerprinted"
}

write_manifest() {
  local created_at=$1
  local modified_at=$2

  jq -nS \
    --arg packID "$PACK_UUID" \
    --arg name "$PACK_NAME" \
    --arg family "$PACK_FAMILY" \
    --arg tone "$PACK_TONE" \
    --arg layoutID "$PACK_LAYOUT_ID" \
    --arg baseProfileID "$PACK_BASE_PROFILE_ID" \
    --arg createdAt "$created_at" \
    --arg modifiedAt "$modified_at" \
    --arg title "$ATTRIBUTION_TITLE" \
    --arg author "$ATTRIBUTION_AUTHOR" \
    --arg notice "$ATTRIBUTION_NOTICE" \
    --slurpfile assets "$ASSETS_OBJECT_FILE" \
    --slurpfile pressRows "$PRESS_ROWS_FILE" \
    --slurpfile pressSpecials "$PRESS_SPECIALS_FILE" \
    --slurpfile pressOverrides "$PRESS_OVERRIDES_FILE" \
    --slurpfile releaseRows "$RELEASE_ROWS_FILE" \
    --slurpfile releaseSpecials "$RELEASE_SPECIALS_FILE" \
    --slurpfile releaseOverrides "$RELEASE_OVERRIDES_FILE" \
    '{
      schemaVersion: 1,
      id: $packID,
      name: $name,
      author: null,
      family: $family,
      tone: $tone,
      notes: null,
      baseProfileID: $baseProfileID,
      layoutID: $layoutID,
      createdAt: $createdAt,
      modifiedAt: $modifiedAt,
      press: {
        generic: null,
        rows: $pressRows[0],
        specials: $pressSpecials[0],
        keyOverrides: $pressOverrides[0]
      },
      release: {
        generic: null,
        rows: $releaseRows[0],
        specials: $releaseSpecials[0],
        keyOverrides: $releaseOverrides[0]
      },
      assets: $assets[0],
      attributions: [
        {
          title: $title,
          author: $author,
          sourceURL: null,
          licenseName: null,
          notice: $notice
        }
      ]
    }' > "$STAGED_PACK_ROOT/manifest.json"
}

rollback_installation() {
  local displaced_destination=""

  if (( PREVIOUS_PACK_PRESENT == 1 )); then
    if (( DESTINATION_INSTALLED == 1 )) && [[ -e "$DESTINATION_PACK" ]]; then
      displaced_destination="$STAGE_ROOT/rollback-failed-install.simuboardpack"
      if ! mv "$DESTINATION_PACK" "$displaced_destination"; then
        warn "Rollback could not move the partial BCP pack out of the destination."
        if (( BACKUP_CREATED == 1 )) && [[ -e "$BACKUP_PACK_ROOT" ]]; then
          warn "Recover the previous BCP pack from: $BACKUP_PACK_ROOT"
        fi
        return 1
      fi
    fi

    if (( BACKUP_CREATED == 1 )) && [[ -e "$BACKUP_PACK_ROOT" ]]; then
      if mv "$BACKUP_PACK_ROOT" "$DESTINATION_PACK"; then
        BACKUP_CREATED=0
        DESTINATION_INSTALLED=0
        return 0
      fi
      warn "Rollback could not restore the previous BCP pack."
      warn "Recover the previous BCP pack from: $BACKUP_PACK_ROOT"
      return 1
    fi

    warn "Rollback could not find the previous BCP backup."
    return 1
  fi

  if (( DESTINATION_INSTALLED == 1 )) && [[ -e "$DESTINATION_PACK" ]]; then
    if ! mv "$DESTINATION_PACK" "$STAGE_ROOT/rollback-abandoned-install.simuboardpack"; then
      warn "Rollback could not remove the partially installed BCP pack: $DESTINATION_PACK"
      return 1
    fi
    DESTINATION_INSTALLED=0
  fi

  return 0
}

publish_pack() {
  mkdir -p "$LIBRARY_ROOT"
  validate_fixed_bcp_pack "$STAGED_PACK_ROOT" \
    "Staged fixed BCP pack is invalid before installation"

  if (( PREVIOUS_PACK_PRESENT == 1 )); then
    mv "$DESTINATION_PACK" "$BACKUP_PACK_ROOT"
    BACKUP_CREATED=1
    maybe_fail_at "after-backup"
  fi

  mv "$STAGED_PACK_ROOT" "$DESTINATION_PACK"
  DESTINATION_INSTALLED=1
  maybe_fail_at "after-install-before-commit"

  validate_fixed_bcp_pack "$DESTINATION_PACK" \
    "Installed fixed BCP pack is invalid after installation"

  INSTALL_COMMITTED=1
  if (( BACKUP_CREATED == 1 )) && [[ -e "$BACKUP_PACK_ROOT" ]]; then
    rm -rf "$BACKUP_PACK_ROOT"
    BACKUP_CREATED=0
  fi
}

migrate_legacy_selection_if_needed() {
  local selected_profile=""

  if (( SHOULD_MIGRATE_LEGACY_SELECTION == 0 )); then
    return
  fi

  if ! command -v "$DEFAULTS_EXECUTABLE" >/dev/null 2>&1; then
    warn "Installed the BCP pack but could not find '$DEFAULTS_EXECUTABLE' to migrate the legacy selection."
    return
  fi

  if ! selected_profile=$("$DEFAULTS_EXECUTABLE" read "$DEFAULTS_DOMAIN" selectedProfile 2>/dev/null); then
    return
  fi
  selected_profile=${selected_profile//$'\n'/}

  if [[ "$selected_profile" == "bcp" ]]; then
    if ! "$DEFAULTS_EXECUTABLE" write "$DEFAULTS_DOMAIN" selectedProfile -string "$PACK_SELECTION_ID" >/dev/null 2>&1; then
      warn "Installed the BCP pack, but could not migrate '$DEFAULTS_DOMAIN' from 'bcp' to '$PACK_SELECTION_ID'."
    fi
  fi
}

[[ -d "$ASSET_ROOT" ]] || fail "Missing asset root: $ASSET_ROOT" 66
ensure_directory_root_ready
setup_work_paths
ensure_exact_asset_tree
read_existing_pack_state

mkdir -p "$STAGED_PACK_ROOT/assets"
: > "$ASSET_LINES"
: > "$PRESS_ROWS_LINES"
: > "$PRESS_SPECIALS_LINES"
: > "$PRESS_OVERRIDES_LINES"
: > "$RELEASE_ROWS_LINES"
: > "$RELEASE_SPECIALS_LINES"
: > "$RELEASE_OVERRIDES_LINES"

typeset -A SEEN_HASHES
for record in "${EXPECTED_RECORDS[@]}"; do
  IFS='|' read -r phase sample_name assignment_kind assignment_key <<< "$record"
  source_file="$ASSET_ROOT/$phase/$sample_name.wav"
  relative_path="$phase/$sample_name.wav"
  [[ -f "$source_file" ]] || fail "Missing expected asset: $relative_path" 66

  validation=$(validate_audio_file "$source_file" "$relative_path")
  duration_seconds=${validation%%|*}
  byte_count=${validation##*|}
  asset_id=$(sha256_of "$source_file")
  [[ "$asset_id" =~ '^[0-9a-f]{64}$' ]] || fail "Asset hash must be lowercase SHA-256: $relative_path"
  [[ -z "${SEEN_HASHES[$asset_id]-}" ]] || fail "Duplicate asset content hash detected for $relative_path"
  SEEN_HASHES[$asset_id]=1

  staged_asset="$STAGED_PACK_ROOT/assets/$asset_id.wav"
  cp "$source_file" "$staged_asset"

  jq -n \
    --arg id "$asset_id" \
    --arg relativePath "assets/$asset_id.wav" \
    --arg originalFilename "$relative_path" \
    --argjson durationSeconds "$duration_seconds" \
    --argjson byteCount "$byte_count" \
    '{
      id: $id,
      relativePath: $relativePath,
      sha256: $id,
      originalFilename: $originalFilename,
      durationSeconds: $durationSeconds,
      sampleRate: 48000,
      channelCount: 1,
      byteCount: $byteCount,
      license: null
    }' >> "$ASSET_LINES"

  append_assignment "$phase" "$assignment_kind" "$assignment_key" "$asset_id"
done

(( ${#SEEN_HASHES} == ${#EXPECTED_RECORDS} )) \
  || fail "Expected ${#EXPECTED_RECORDS} unique rendered assets, found ${#SEEN_HASHES}"
build_manifest_maps
build_target_fingerprint

install_time=$(installer_timestamp)
created_at="$install_time"
modified_at="$install_time"
if (( PREVIOUS_PACK_PRESENT == 1 )); then
  created_at="$EXISTING_CREATED_AT"
  current_fingerprint=$(cat "$TARGET_FINGERPRINT_FILE")
  if [[ "$current_fingerprint" == "$EXISTING_FINGERPRINT" ]]; then
    modified_at="$EXISTING_MODIFIED_AT"
  fi
fi

write_manifest "$created_at" "$modified_at"
publish_pack
migrate_legacy_selection_if_needed

print "Installed local BCP pack to $DESTINATION_PACK"
print "Validated ${#EXPECTED_RECORDS} rendered assets from $ASSET_ROOT"
