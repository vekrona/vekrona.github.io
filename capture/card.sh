source "$(dirname "${BASH_SOURCE[0]}")/fonts.sh"

CARD_REFERENCE_WIDTH=1200
CARD_TITLE_POINTSIZE=128
CARD_SUBTITLE_POINTSIZE=38
CARD_TITLE_OFFSET=-40
CARD_SUBTITLE_OFFSET=70
CARD_BLUR_SIGMA=3
CARD_TITLE_MAX_WIDTH_SHARE=0.75
WORDMARK=vekrona
HERO_SOURCE="$RAW_DIR/hero.png"

page_tagline() {
  local title
  title="$(sed -n 's:.*<title>\(.*\)</title>.*:\1:p' "$INDEX_HTML")"
  [[ "$title" == "$WORDMARK — "* ]] || fail "the <title> of $INDEX_HTML ('$title') does not start with '$WORDMARK — '"
  printf '%s' "${title#"$WORDMARK — "}"
}

card_scaled() {
  awk -v value="$1" -v width="$2" -v reference="$CARD_REFERENCE_WIDTH" 'BEGIN { printf "%.2f", value * width / reference }'
}

card_fitted_pointsize() {
  local font="$1" text="$2" pointsize="$3" max_width="$4" measured
  measured="$(magick -font "$font" -pointsize "$pointsize" "label:$text" -format %w info:)"
  awk -v size="$pointsize" -v measured="$measured" -v max="$max_width" 'BEGIN { printf "%.2f", (measured > max) ? size * max / measured : size }'
}

render_card() {
  local width="$1" height="$2" title="$3" subtitle="$4" out="$5"; shift 5
  local title_size subtitle_size
  [ -f "$HERO_SOURCE" ] || fail "missing $HERO_SOURCE (run screenshots.sh first)"
  title_size="$(card_fitted_pointsize "$FONT_BOLD" "$title" "$(card_scaled "$CARD_TITLE_POINTSIZE" "$width")" "$(awk -v w="$width" -v s="$CARD_TITLE_MAX_WIDTH_SHARE" 'BEGIN { print w * s }')")"
  subtitle_size="$(card_scaled "$CARD_SUBTITLE_POINTSIZE" "$width")"
  magick "$HERO_SOURCE" \
    -resize "${width}x${height}^" -gravity center -extent "${width}x${height}" \
    -blur "0x$(card_scaled "$CARD_BLUR_SIGMA" "$width")" -fill "#$PALETTE_BG" -colorize 50% \
    -font "$FONT_BOLD" -pointsize "$title_size" -fill "#$PALETTE_FG" -annotate "+0$(card_scaled "$CARD_TITLE_OFFSET" "$width")" "$title" \
    -font "$FONT_REGULAR" -pointsize "$subtitle_size" -fill "#$PALETTE_ACCENT" -annotate "+0+$(card_scaled "$CARD_SUBTITLE_OFFSET" "$width")" "$subtitle" \
    "$@" "$out"
}
