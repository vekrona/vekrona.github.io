#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$CAPTURE_DIR/catalog.sh"
validate_clip_names "$@"
selected=("${@:-${CLIP_NAMES[@]}}")
source "$CAPTURE_DIR/scenes.sh"
require_clip_functions "${selected[@]}"

run_step capture_init capture_init

for name in "${selected[@]}"; do
  run_step "clip $name" record_clip "$name"
done

echo "clips recorded: $OUT_DIR"
