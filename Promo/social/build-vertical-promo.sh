#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_PATH="${1:-$REPO_DIR/media/battuta-social-vertical-v4.mp4}"
PLATFORM_VARIANT="${2:-generic}"
COVER_PATH="${OUTPUT_PATH%.*}-cover.png"
PROMO_TMP_DIR="$(mktemp -d /tmp/battuta-social.XXXXXX)"

case "$PLATFORM_VARIANT" in
    generic|xiaohongshu|douyin|moments) ;;
    *)
        echo "unknown platform variant: $PLATFORM_VARIANT" >&2
        echo "usage: $0 [OUTPUT_PATH] [generic|xiaohongshu|douyin|moments]" >&2
        exit 2
        ;;
esac
cleanup() {
    rm -rf -- "$PROMO_TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUTPUT_PATH")"
mkdir -p "$PROMO_TMP_DIR/overlays"

if [[ "$PLATFORM_VARIANT" == "generic" || "$PLATFORM_VARIANT" == "moments" ]]; then
    swift "$REPO_DIR/Promo/generate_download_qr.swift"
fi
swift "$SCRIPT_DIR/render_overlays.swift" "$PROMO_TMP_DIR/overlays" "$PLATFORM_VARIANT"

ICON="$REPO_DIR/shared/brand/source/AppIconSquare.png"
SOUND_VIDEO="$REPO_DIR/media/battuta-sound-demo-polished.mp4"
STATS_VIDEO="$REPO_DIR/media/battuta-stats-demo-polished-v2.mp4"
DIY_IMAGE="$REPO_DIR/media/battuta-diy-editor.png"
QR_IMAGE="$REPO_DIR/Promo/battuta-download-qr.png"

STATS_DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$STATS_VIDEO")"
STATS_FADE_OUT="$(awk -v duration="$STATS_DURATION" 'BEGIN { printf "%.6f", duration - 0.20 }')"
POST_SOUND_SILENCE_DURATION="$(awk -v duration="$STATS_DURATION" 'BEGIN { printf "%.6f", duration + 12 }')"
TOTAL_DURATION="$(awk -v duration="$STATS_DURATION" 'BEGIN { printf "%.6f", duration + 27 }')"

COMMON_VIDEO=(-r 30 -an -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p)

ffmpeg -y -v error \
    -loop 1 -t 3 -i "$ICON" \
    -loop 1 -t 3 -i "$PROMO_TMP_DIR/overlays/intro.png" \
    -filter_complex \
    "[0:v]split=2[bgsrc][iconsrc]; \
     [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=42:2,eq=brightness=-0.58:saturation=0.72[bg]; \
     [iconsrc]scale=340:340[icon]; \
     [bg][icon]overlay=(W-w)/2:250[base]; \
     [1:v]format=rgba[overlay]; \
     [base][overlay]overlay=0:0,fade=t=in:st=0:d=0.22,fade=t=out:st=2.78:d=0.22,format=yuv420p[out]" \
    -map "[out]" -t 3 "${COMMON_VIDEO[@]}" "$PROMO_TMP_DIR/scene-1.mp4"

render_sound_scene() {
    local scene_path="$1"
    local source_start="$2"
    local overlay_path="$3"

    ffmpeg -y -v error \
        -ss "$source_start" -t 4 -i "$SOUND_VIDEO" \
        -loop 1 -t 4 -i "$overlay_path" \
        -filter_complex \
        "[0:v]split=2[bgsrc][fgsrc]; \
         [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=34:2,eq=brightness=-0.58:saturation=0.68[bg]; \
         [fgsrc]scale=1000:750,pad=1024:774:12:12:color=0x242823[fg]; \
         [bg][fg]overlay=28:420[base]; \
         [1:v]format=rgba[overlay]; \
         [base][overlay]overlay=0:0,fade=t=in:st=0:d=0.20,fade=t=out:st=3.80:d=0.20,format=yuv420p[out]" \
        -map "[out]" -t 4 "${COMMON_VIDEO[@]}" "$scene_path"
}

render_sound_scene "$PROMO_TMP_DIR/scene-2.mp4" 3.8 "$PROMO_TMP_DIR/overlays/sound-g915.png"
render_sound_scene "$PROMO_TMP_DIR/scene-3.mp4" 11.95 "$PROMO_TMP_DIR/overlays/sound-ink.png"
render_sound_scene "$PROMO_TMP_DIR/scene-4.mp4" 19.5 "$PROMO_TMP_DIR/overlays/sound-tealios.png"

ffmpeg -y -v error \
    -loop 1 -t 4 -i "$DIY_IMAGE" \
    -loop 1 -t 4 -i "$PROMO_TMP_DIR/overlays/diy.png" \
    -filter_complex \
    "[0:v]split=2[bgsrc][fgsrc]; \
     [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=34:2,eq=brightness=-0.60:saturation=0.68[bg]; \
     [fgsrc]scale=1000:634,pad=1024:658:12:12:color=0x242823[fg]; \
     [bg][fg]overlay=28:440[base]; \
     [1:v]format=rgba[overlay]; \
     [base][overlay]overlay=0:0,fade=t=in:st=0:d=0.20,fade=t=out:st=3.80:d=0.20,format=yuv420p[out]" \
    -map "[out]" -t 4 "${COMMON_VIDEO[@]}" "$PROMO_TMP_DIR/scene-5.mp4"

ffmpeg -y -v error \
    -loop 1 -t 4 -i "$ICON" \
    -loop 1 -t 4 -i "$PROMO_TMP_DIR/overlays/community.png" \
    -filter_complex \
    "[0:v]split=2[bgsrc][iconsrc]; \
     [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=42:2,eq=brightness=-0.62:saturation=0.72[bg]; \
     [iconsrc]scale=220:220[icon]; \
     [bg][icon]overlay=(W-w)/2:430[base]; \
     [1:v]format=rgba[overlay]; \
     [base][overlay]overlay=0:0,fade=t=in:st=0:d=0.20,fade=t=out:st=3.80:d=0.20,format=yuv420p[out]" \
    -map "[out]" -t 4 "${COMMON_VIDEO[@]}" "$PROMO_TMP_DIR/scene-6.mp4"

ffmpeg -y -v error \
    -i "$STATS_VIDEO" \
    -loop 1 -t "$STATS_DURATION" -i "$PROMO_TMP_DIR/overlays/stats.png" \
    -filter_complex \
    "[0:v]setpts=PTS-STARTPTS,split=2[bgsrc][fgsrc]; \
     [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=34:2,eq=brightness=-0.60:saturation=0.68[bg]; \
     [fgsrc]scale=1000:750,pad=1024:774:12:12:color=0x242823[fg]; \
     [bg][fg]overlay=28:420[base]; \
     [1:v]format=rgba[overlay]; \
     [base][overlay]overlay=0:0,fade=t=in:st=0:d=0.20,fade=t=out:st=${STATS_FADE_OUT}:d=0.20,format=yuv420p[out]" \
    -map "[out]" -t "$STATS_DURATION" "${COMMON_VIDEO[@]}" "$PROMO_TMP_DIR/scene-7.mp4"

if [[ "$PLATFORM_VARIANT" == "generic" || "$PLATFORM_VARIANT" == "moments" ]]; then
    ffmpeg -y -v error \
        -loop 1 -t 4 -i "$ICON" \
        -loop 1 -t 4 -i "$QR_IMAGE" \
        -loop 1 -t 4 -i "$PROMO_TMP_DIR/overlays/outro.png" \
        -filter_complex \
        "[0:v]split=2[bgsrc][iconsrc]; \
         [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=42:2,eq=brightness=-0.60:saturation=0.72[bg]; \
         [iconsrc]scale=260:260[icon]; \
         [1:v]scale=300:300:flags=neighbor[qr]; \
         [bg][icon]overlay=(W-w)/2:215[base1]; \
         [base1][qr]overlay=390:925[base2]; \
         [2:v]format=rgba[overlay]; \
         [base2][overlay]overlay=0:0,fade=t=in:st=0:d=0.20,fade=t=out:st=3.70:d=0.30,format=yuv420p[out]" \
        -map "[out]" -t 4 "${COMMON_VIDEO[@]}" "$PROMO_TMP_DIR/scene-8.mp4"
else
    ffmpeg -y -v error \
        -loop 1 -t 4 -i "$ICON" \
        -loop 1 -t 4 -i "$PROMO_TMP_DIR/overlays/outro.png" \
        -filter_complex \
        "[0:v]split=2[bgsrc][iconsrc]; \
         [bgsrc]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=42:2,eq=brightness=-0.60:saturation=0.72[bg]; \
         [iconsrc]scale=260:260[icon]; \
         [bg][icon]overlay=(W-w)/2:235[base]; \
         [1:v]format=rgba[overlay]; \
         [base][overlay]overlay=0:0,fade=t=in:st=0:d=0.20,fade=t=out:st=3.70:d=0.30,format=yuv420p[out]" \
        -map "[out]" -t 4 "${COMMON_VIDEO[@]}" "$PROMO_TMP_DIR/scene-8.mp4"
fi

ffmpeg -y -v error \
    -i "$PROMO_TMP_DIR/scene-1.mp4" \
    -i "$PROMO_TMP_DIR/scene-2.mp4" \
    -i "$PROMO_TMP_DIR/scene-3.mp4" \
    -i "$PROMO_TMP_DIR/scene-4.mp4" \
    -i "$PROMO_TMP_DIR/scene-5.mp4" \
    -i "$PROMO_TMP_DIR/scene-6.mp4" \
    -i "$PROMO_TMP_DIR/scene-7.mp4" \
    -i "$PROMO_TMP_DIR/scene-8.mp4" \
    -ss 3.8 -t 4 -i "$SOUND_VIDEO" \
    -ss 11.95 -t 4 -i "$SOUND_VIDEO" \
    -ss 19.5 -t 4 -i "$SOUND_VIDEO" \
    -filter_complex \
    "[0:v]setsar=1,setpts=PTS-STARTPTS[v0]; \
     [1:v]setsar=1,setpts=PTS-STARTPTS[v1]; \
     [2:v]setsar=1,setpts=PTS-STARTPTS[v2]; \
     [3:v]setsar=1,setpts=PTS-STARTPTS[v3]; \
     [4:v]setsar=1,setpts=PTS-STARTPTS[v4]; \
     [5:v]setsar=1,setpts=PTS-STARTPTS[v5]; \
     [6:v]setsar=1,setpts=PTS-STARTPTS[v6]; \
     [7:v]setsar=1,setpts=PTS-STARTPTS[v7]; \
     [v0][v1][v2][v3][v4][v5][v6][v7]concat=n=8:v=1:a=0[video]; \
     anullsrc=channel_layout=stereo:sample_rate=48000:d=3[intro_silence]; \
     [8:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:4,asetpts=PTS-STARTPTS[g915]; \
     [9:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:4,asetpts=PTS-STARTPTS[ink]; \
     [10:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:4,asetpts=PTS-STARTPTS[tealios]; \
     anullsrc=channel_layout=stereo:sample_rate=48000:d=${POST_SOUND_SILENCE_DURATION}[outro_silence]; \
     [intro_silence][g915][ink][tealios][outro_silence]concat=n=5:v=0:a=1[audio]" \
    -map "[video]" -map "[audio]" \
    -c:v libx264 -preset slow -crf 17 -profile:v high -level 4.1 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 48000 -movflags +faststart -t "$TOTAL_DURATION" \
    "$OUTPUT_PATH"

ffmpeg -y -v error -ss 0.9 -i "$OUTPUT_PATH" -frames:v 1 "$COVER_PATH"

printf 'platform: %s\nvideo: %s\ncover: %s\n' "$PLATFORM_VARIANT" "$OUTPUT_PATH" "$COVER_PATH"
