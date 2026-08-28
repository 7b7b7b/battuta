#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

bash "$SCRIPT_DIR/build-vertical-promo.sh" \
    "$REPO_DIR/media/battuta-xiaohongshu-vertical-v1.mp4" \
    xiaohongshu

bash "$SCRIPT_DIR/build-vertical-promo.sh" \
    "$REPO_DIR/media/battuta-douyin-vertical-v1.mp4" \
    douyin

bash "$SCRIPT_DIR/build-vertical-promo.sh" \
    "$REPO_DIR/media/battuta-moments-vertical-v1.mp4" \
    moments

printf '\nAll platform videos are ready in %s/media\n' "$REPO_DIR"
