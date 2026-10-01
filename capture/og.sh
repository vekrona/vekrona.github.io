#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$CAPTURE_DIR/card.sh"

OG_IMAGE="$ASSETS_IMG_DIR/og.png"
OG_WIDTH=1200
OG_HEIGHT=630

require_commands magick mktemp awk sed
OG_PARTIAL="$(mktemp --suffix=.png)"
trap 'rm -f "$OG_PARTIAL"' EXIT

render_card "$OG_WIDTH" "$OG_HEIGHT" "$WORDMARK" "$(page_tagline)" "$OG_PARTIAL" -strip -colors 256
publish_files "$OG_PARTIAL" "$OG_IMAGE"

echo "og image built: $OG_IMAGE"
