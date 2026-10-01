#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$CAPTURE_DIR/catalog.sh"
validate_screenshot_names "$@"
selected=("${@:-${SCREENSHOT_NAMES[@]}}")
source "$CAPTURE_DIR/scenes.sh"
require_scene_functions "${selected[@]}"

HERO_PASSES=2

run_step capture_init capture_init

if selection_has hero "${selected[@]}"; then
  for ((pass = 1; pass <= HERO_PASSES; pass++)); do
    run_step "scene hero (pass $pass of $HERO_PASSES)" scene_hero "$RAW_DIR/hero.png"
    run_step "images.sh hero" "$CAPTURE_DIR/images.sh" hero
    run_step "sync_site" sync_site
  done
  run_step og.sh "$CAPTURE_DIR/og.sh"
fi

others=()
for name in "${selected[@]}"; do
  [ "$name" = hero ] && continue
  run_step "scene $name" "$(scene_function "$name")" "$RAW_DIR/$name.png"
  others+=("$name")
done

if [ "${#others[@]}" -gt 0 ]; then
  run_step images.sh "$CAPTURE_DIR/images.sh" "${others[@]}"
fi
run_step check-images.sh "$CAPTURE_DIR/check-images.sh"

echo "screenshots done: $ASSETS_IMG_DIR"
