#!/bin/zsh
set -euo pipefail

if (( $# != 6 )); then
  print -u2 "Usage: $0 <clicketyclack-repo> <keyboardsounds-pro-repo> <stavsounds-dir> <keychron-red-wav> <kailh-low-profile-blue-audio> <cherry-mx-clear-audio>"
  exit 64
fi

CLICKETYCLACK_REPO=$1
KEYBOARD_SOUNDS_REPO=$2
STAVSOUNDS_DIR=$3
KEYCHRON_RED_AUDIO=$4
LOW_PROFILE_BLUE_AUDIO=$5
MX_CLEAR_AUDIO=$6
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SPLIT_SCRIPT="$SCRIPT_DIR/split-full-keystrokes.py"
FINAL_TARGET_ROOT="$PROJECT_DIR/SimuBoardMac/Resources/Audio"
STAGE_DIR=$(mktemp -d /private/tmp/simuboard-open-sound-import.XXXXXX)
TARGET_ROOT="$STAGE_DIR/new"
BACKUP_ROOT="$STAGE_DIR/backup"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

for command_name in ffmpeg git python3 shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing required command: $command_name"
    exit 69
  fi
done

if [[ ! -d "$FINAL_TARGET_ROOT" ]]; then
  print -u2 "Missing target audio directory: $FINAL_TARGET_ROOT"
  exit 66
fi
if [[ ! -f "$SPLIT_SCRIPT" ]]; then
  print -u2 "Missing full-keystroke splitter: $SPLIT_SCRIPT"
  exit 66
fi
if [[ ! -f "$CLICKETYCLACK_REPO/LICENSE" ]]; then
  print -u2 "Invalid clicketyclack checkout: $CLICKETYCLACK_REPO"
  exit 66
fi
if [[ ! -f "$KEYBOARD_SOUNDS_REPO/LICENSE" ]]; then
  print -u2 "Invalid keyboardsounds-pro checkout: $KEYBOARD_SOUNDS_REPO"
  exit 66
fi

verify_repository() {
  local repository=$1
  local expected_revision=$2
  local source_path=$3
  local actual_revision

  actual_revision=$(git -C "$repository" rev-parse HEAD 2>/dev/null) || {
    print -u2 "Source is not a Git checkout: $repository"
    exit 65
  }
  if [[ "$actual_revision" != "$expected_revision" ]]; then
    print -u2 "Unexpected revision for $repository: $actual_revision"
    exit 65
  fi
  if [[ -n "$(git -C "$repository" status --porcelain --untracked-files=all -- "$source_path")" ]]; then
    print -u2 "Source path has local modifications: $repository/$source_path"
    exit 65
  fi
}

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

verify_repository \
  "$CLICKETYCLACK_REPO" \
  bb87dc501a18a082675e51193a8a06134deb2a56 \
  resources/kailh_white
verify_repository \
  "$KEYBOARD_SOUNDS_REPO" \
  bac56ac700635c512e57621f35780c5b79eba4cd \
  desktop/bundled-profiles/logitech-g915-tkl-brown

for source_file in \
  "$STAVSOUNDS_DIR/766625.mp3" \
  "$STAVSOUNDS_DIR/766632.mp3" \
  "$STAVSOUNDS_DIR/766633.mp3" \
  "$STAVSOUNDS_DIR/766634.mp3" \
  "$STAVSOUNDS_DIR/766635.mp3" \
  "$STAVSOUNDS_DIR/766605.mp3" \
  "$STAVSOUNDS_DIR/766606.mp3" \
  "$STAVSOUNDS_DIR/766622.mp3" \
  "$STAVSOUNDS_DIR/766623.mp3" \
  "$STAVSOUNDS_DIR/766624.mp3" \
  "$KEYCHRON_RED_AUDIO" \
  "$LOW_PROFILE_BLUE_AUDIO" \
  "$MX_CLEAR_AUDIO"; do
  if [[ ! -f "$source_file" ]]; then
    print -u2 "Missing source audio: $source_file"
    exit 66
  fi
done

verify_sha256 "$STAVSOUNDS_DIR/766625.mp3" 41bd66f756a6387b2598316a8259f92b17bba328472934bdfa0b4ea002303cf5
verify_sha256 "$STAVSOUNDS_DIR/766632.mp3" 0be1fe122b8da67c0ce97ca2b098dc2626513f007341250ea7e6feed0a4a8d92
verify_sha256 "$STAVSOUNDS_DIR/766633.mp3" 2c3509bd80ebec134a2276a8cb4411773ac0331894fea056efb182935413cb2d
verify_sha256 "$STAVSOUNDS_DIR/766634.mp3" ecb1701717091d954949ff23ba41d19348a790deea22478506f5cd625bc47508
verify_sha256 "$STAVSOUNDS_DIR/766635.mp3" b66c58738b2d02b210df2bd57f8b1f56719054a67bf22f1f318324f1028fcb3c
verify_sha256 "$STAVSOUNDS_DIR/766605.mp3" 9d29d4da0c99ea4cad8fcc07fa8acfb202f2dd8993a3d3e776fba3fa9cab937c
verify_sha256 "$STAVSOUNDS_DIR/766606.mp3" 3c771be33c5f0c9f778035465a6237065b9381062e8f7d665ef3101d2b645303
verify_sha256 "$STAVSOUNDS_DIR/766622.mp3" 28a500c964b56e622e682652651bc42bb646cb96a60304595813c21cb57f6b3e
verify_sha256 "$STAVSOUNDS_DIR/766623.mp3" ccb6d6eab32c404b364428ad1305d71201bec26eb775f2aaf278a7a1ce0a5b44
verify_sha256 "$STAVSOUNDS_DIR/766624.mp3" d49bdfcd322aa423b117ebab8e5052b5d88c29a35991523604100ce0f3b78aa6
verify_sha256 "$KEYCHRON_RED_AUDIO" 85947c590e3831cf835609c11ceddce64dd5acd34eda08d24714c0bcc054ae4d
verify_sha256 "$LOW_PROFILE_BLUE_AUDIO" 3a87ddd9da07ba03614041328678e7dc4579f76c4736b8e990599e4606de82f9
verify_sha256 "$MX_CLEAR_AUDIO" 0a9ec897f71e3c5eb2aef632fc6843a5212106408ce934d54cce9b6c2d7ba765

convert_file() {
  local source_file=$1
  local target_file=$2
  local gain_db=${3:-0}
  local trim_start=${4:-0}

  mkdir -p "${target_file:h}"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$source_file" \
    -af "atrim=start=${trim_start},asetpts=PTS-STARTPTS,volume=${gain_db}dB,areverse,afade=t=in:st=0:d=0.004,areverse" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

extract_timed_clip() {
  local source_file=$1
  local start_time=$2
  local duration=$3
  local target_file=$4

  mkdir -p "${target_file:h}"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -y \
    -i "$source_file" \
    -af "atrim=start=${start_time}:duration=${duration},asetpts=PTS-STARTPTS,areverse,afade=t=in:st=0:d=0.004,areverse" \
    -ac 1 \
    -ar 48000 \
    -c:a pcm_s16le \
    -map_metadata -1 \
    "$target_file"
}

import_box_white() {
  local source_dir="$CLICKETYCLACK_REPO/resources/kailh_white"
  local target_dir="$TARGET_ROOT/boxwhite"

  convert_file "$source_dir/down1.wav" "$target_dir/press/GENERIC_R0.wav"
  convert_file "$source_dir/down2.wav" "$target_dir/press/GENERIC_R1.wav"
  convert_file "$source_dir/down3.wav" "$target_dir/press/GENERIC_R2.wav"
  convert_file "$source_dir/down4.wav" "$target_dir/press/GENERIC_R3.wav"
  convert_file "$source_dir/down5.wav" "$target_dir/press/GENERIC_R4.wav"
  convert_file "$source_dir/up1.wav" "$target_dir/release/GENERIC_R0.wav"
  convert_file "$source_dir/up2.wav" "$target_dir/release/GENERIC_R1.wav"
  convert_file "$source_dir/up3.wav" "$target_dir/release/GENERIC_R2.wav"
  convert_file "$source_dir/up4.wav" "$target_dir/release/GENERIC_R3.wav"
  convert_file "$source_dir/up5.wav" "$target_dir/release/GENERIC_R4.wav"
}

import_g915_brown() {
  local source_dir="$KEYBOARD_SOUNDS_REPO/desktop/bundled-profiles/logitech-g915-tkl-brown"
  local target_dir="$TARGET_ROOT/g915brown"

  convert_file "$source_dir/key-press-1.wav" "$target_dir/press/GENERIC_R0.wav" 10 0.020
  convert_file "$source_dir/key-press-2.wav" "$target_dir/press/GENERIC_R1.wav" 10 0.044
  convert_file "$source_dir/key-press-3.wav" "$target_dir/press/GENERIC_R2.wav" 10 0.026
  convert_file "$source_dir/key-press-4.wav" "$target_dir/press/GENERIC_R3.wav" 10 0.004
  convert_file "$source_dir/key-press-5.wav" "$target_dir/press/GENERIC_R4.wav" 10
  convert_file "$source_dir/space-press-1.wav" "$target_dir/press/SPACE.wav" 10 0.002
  convert_file "$source_dir/enter-press-1.wav" "$target_dir/press/ENTER.wav" 10 0.011
  convert_file "$source_dir/enter-press-2.wav" "$target_dir/press/BACKSPACE.wav" 10 0.034
  convert_file "$source_dir/key-release-1.wav" "$target_dir/release/GENERIC_R0.wav" 10 0.052
  convert_file "$source_dir/key-release-2.wav" "$target_dir/release/GENERIC_R1.wav" 10 0.035
  convert_file "$source_dir/key-release-3.wav" "$target_dir/release/GENERIC_R2.wav" 10 0.026
  convert_file "$source_dir/key-release-4.wav" "$target_dir/release/GENERIC_R3.wav" 10 0.028
  convert_file "$source_dir/key-release-5.wav" "$target_dir/release/GENERIC_R4.wav" 10 0.024
  convert_file "$source_dir/space-release-1.wav" "$target_dir/release/SPACE.wav" 10 0.013
  convert_file "$source_dir/enter-release-1.wav" "$target_dir/release/ENTER.wav" 10 0.004
  convert_file "$source_dir/enter-release-2.wav" "$target_dir/release/BACKSPACE.wav" 23.5 0.035
}

import_stavsounds() {
  local target_dir="$TARGET_ROOT/studiotactile/full"
  convert_file "$STAVSOUNDS_DIR/766625.mp3" "$target_dir/GENERIC_R0.wav" 0 0.030
  convert_file "$STAVSOUNDS_DIR/766632.mp3" "$target_dir/GENERIC_R1.wav" 0 0.024
  convert_file "$STAVSOUNDS_DIR/766633.mp3" "$target_dir/GENERIC_R2.wav" 0 0.011
  convert_file "$STAVSOUNDS_DIR/766634.mp3" "$target_dir/GENERIC_R3.wav" 0 0.032
  convert_file "$STAVSOUNDS_DIR/766635.mp3" "$target_dir/GENERIC_R4.wav"

  target_dir="$TARGET_ROOT/studioclicky/full"
  convert_file "$STAVSOUNDS_DIR/766605.mp3" "$target_dir/GENERIC_R0.wav" 0 0.028
  convert_file "$STAVSOUNDS_DIR/766606.mp3" "$target_dir/GENERIC_R1.wav" 0 0.020
  convert_file "$STAVSOUNDS_DIR/766622.mp3" "$target_dir/GENERIC_R2.wav" 0 0.027
  convert_file "$STAVSOUNDS_DIR/766623.mp3" "$target_dir/GENERIC_R3.wav" 0 0.033
  convert_file "$STAVSOUNDS_DIR/766624.mp3" "$target_dir/GENERIC_R4.wav" 0 0.015
}

import_keychron_red() {
  local target_dir="$TARGET_ROOT/keychronred/full"
  extract_timed_clip "$KEYCHRON_RED_AUDIO" 1.081 0.180 "$target_dir/GENERIC_R0.wav"
  extract_timed_clip "$KEYCHRON_RED_AUDIO" 2.091 0.180 "$target_dir/GENERIC_R1.wav"
  extract_timed_clip "$KEYCHRON_RED_AUDIO" 4.476 0.180 "$target_dir/GENERIC_R2.wav"
  extract_timed_clip "$KEYCHRON_RED_AUDIO" 5.612 0.180 "$target_dir/GENERIC_R3.wav"
  extract_timed_clip "$KEYCHRON_RED_AUDIO" 9.797 0.180 "$target_dir/GENERIC_R4.wav"
}

import_low_profile_blue() {
  local target_dir="$TARGET_ROOT/lowprofileblue/full"
  extract_timed_clip "$LOW_PROFILE_BLUE_AUDIO" 0.348 0.220 "$target_dir/GENERIC_R0.wav"
  extract_timed_clip "$LOW_PROFILE_BLUE_AUDIO" 0.734 0.220 "$target_dir/GENERIC_R1.wav"
  extract_timed_clip "$LOW_PROFILE_BLUE_AUDIO" 3.696 0.220 "$target_dir/GENERIC_R2.wav"
  extract_timed_clip "$LOW_PROFILE_BLUE_AUDIO" 6.665 0.220 "$target_dir/GENERIC_R3.wav"
  extract_timed_clip "$LOW_PROFILE_BLUE_AUDIO" 7.248 0.220 "$target_dir/GENERIC_R4.wav"
}

import_mx_clear() {
  local target_dir="$TARGET_ROOT/mxclear/full"
  extract_timed_clip "$MX_CLEAR_AUDIO" 7.369 0.220 "$target_dir/GENERIC_R0.wav"
  extract_timed_clip "$MX_CLEAR_AUDIO" 11.126 0.220 "$target_dir/GENERIC_R1.wav"
  extract_timed_clip "$MX_CLEAR_AUDIO" 24.182 0.220 "$target_dir/GENERIC_R2.wav"
  extract_timed_clip "$MX_CLEAR_AUDIO" 39.965 0.220 "$target_dir/GENERIC_R3.wav"
  extract_timed_clip "$MX_CLEAR_AUDIO" 49.113 0.220 "$target_dir/GENERIC_R4.wav"
}

import_box_white
import_g915_brown
import_stavsounds
import_keychron_red
import_low_profile_blue
import_mx_clear
python3 "$SPLIT_SCRIPT" "$TARGET_ROOT"

generated_count=$(find "$TARGET_ROOT" -type f -name '*.wav' | wc -l | tr -d ' ')
if [[ "$generated_count" != 76 ]]; then
  print -u2 "Expected 76 generated WAV files, found $generated_count"
  exit 70
fi

profiles=(boxwhite g915brown studiotactile studioclicky keychronred lowprofileblue mxclear)
mkdir -p "$BACKUP_ROOT"
published_profiles=()
for profile in $profiles; do
  final_directory="$FINAL_TARGET_ROOT/$profile"
  staged_directory="$TARGET_ROOT/$profile"
  backup_directory="$BACKUP_ROOT/$profile"

  if [[ -e "$final_directory" ]]; then
    mv "$final_directory" "$backup_directory"
  fi
  if ! mv "$staged_directory" "$final_directory"; then
    [[ -e "$backup_directory" ]] && mv "$backup_directory" "$final_directory"
    for published_profile in $published_profiles; do
      mv "$FINAL_TARGET_ROOT/$published_profile" "$TARGET_ROOT/$published_profile"
      [[ -e "$BACKUP_ROOT/$published_profile" ]] \
        && mv "$BACKUP_ROOT/$published_profile" "$FINAL_TARGET_ROOT/$published_profile"
    done
    print -u2 "Failed to publish generated profile: $profile"
    exit 74
  fi
  published_profiles+=("$profile")
done

print "Imported 7 open sound profiles with $generated_count WAV assets."
