#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$CAPTURE_DIR/catalog.sh"
validate_screenshot_names "$@"
selected=("${@:-${SCREENSHOT_NAMES[@]}}")

VARIANT_WIDTHS=(480 768 1280)
WEBP_QUALITY=90
AVIF_CRF=28

require_commands magick ffmpeg stat mktemp
[[ "$(ffmpeg -hide_banner -encoders)" == *" libaom-av1 "* ]] || fail "ffmpeg has no libaom-av1 encoder (needed for AVIF)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

file_size() {
  stat -c %s "$1"
}

encode_webp() {
  local source="$1" target="$2"
  local lossy="$WORK_DIR/lossy.webp" lossless="$WORK_DIR/lossless.webp"
  magick "$source" -strip -quality "$WEBP_QUALITY" -define webp:method=6 "$lossy"
  magick "$source" -strip -define webp:lossless=true -define webp:method=6 "$lossless"
  if [ "$(file_size "$lossless")" -lt "$(file_size "$lossy")" ]; then
    mv "$lossless" "$target"
  else
    mv "$lossy" "$target"
  fi
}

encode_avif() {
  local source="$1" target="$2"
  ffmpeg -y -v error -i "$source" \
    -vf "scale=out_color_matrix=bt709:out_range=pc,format=yuv444p" \
    -c:v libaom-av1 -crf "$AVIF_CRF" -b:v 0 -cpu-used 4 -still-picture 1 \
    -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range pc \
    "$target"
}

encode() {
  local source="$1" target_base="$2"
  encode_webp "$source" "$target_base.webp"
  encode_avif "$source" "$target_base.avif"
}

build_image() {
  local name="$1"
  local source="$RAW_DIR/$name.png" staging="$WORK_DIR/staged/$name" source_width width resized
  [ -f "$source" ] || fail "missing $source (run screenshots.sh first)"
  source_width="$(magick identify -format %w "$source")"

  mkdir -p "$staging"
  encode "$source" "$staging/$name"

  for width in "${VARIANT_WIDTHS[@]}"; do
    [ "$width" -lt "$source_width" ] || continue
    resized="$WORK_DIR/$name-$width.png"
    magick "$source" -filter Lanczos -resize "${width}x" "$resized"
    encode "$resized" "$staging/$name-$width"
  done

  rm -f "$ASSETS_IMG_DIR/$name".{webp,avif} "$ASSETS_IMG_DIR/$name"-[0-9]*.{webp,avif}
  publish_files "$staging"/* "$ASSETS_IMG_DIR/"
  echo "image built: $name"
}

mkdir -p "$ASSETS_IMG_DIR"
for name in "${selected[@]}"; do
  build_image "$name"
done
