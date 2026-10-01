#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$CAPTURE_DIR/catalog.sh"
source "$CAPTURE_DIR/card.sh"

BUILD_DIR="$OUT_DIR/video-build"
TRANSITION_DURATION=0.6
MAX_CLIP_SHORTFALL=3.0
MAX_CLIP_OVERRUN=0.5
MAX_SPEEDUP=8
PICTURE_LABEL=faded
FINAL_LABEL=vout
DURATION_TOLERANCE=0.1
BG=0x$PALETTE_BG
FG=0x$PALETTE_FG
CAPTION_FONT_SIZE=30
CAPTION_CANVAS_HEIGHT=80
CAPTION_MARGIN_RIGHT=40
CAPTION_MARGIN_BOTTOM=30
CAPTION_BORDER=16

SEGMENTS=(
  "card|3.5|vekrona|Fedora + Sway + DankMaterialShell|"
  "clip|5.0|hero|Hyper + 1..0  —  Sway workspaces, always visible|"
  "clip|6.0|spotlight|Hyper + Space  —  Spotlight|"
  "clip|4.5|control-center|Hyper + ,  —  Control Center|"
  "clip|4.5|notifications|Hyper + N  —  Notifications|"
  "clip|4.5|clipboard|Hyper + V  —  Clipboard history|"
  "clip|6.5|keybindings|Hyper + /  —  Keybindings help|"
  "clip|7.5|theme-cycle|Hyper + Shift + T  —  Cycle themes|"
  "clip|13.0|terminal|./install.sh --skip 10-nvidia 70  —  Verify stage|compress:6.5:2.5"
  "clip|7.5|lock|Hyper + Escape  —  Lock screen|"
  "card|4.5|github.com/vekrona/vekrona|Fedora 44  ·  Sway  ·  DankMaterialShell|"
)

require_commands ffmpeg ffprobe magick awk grep mv chmod

SEGMENT_SPEEDUPS=()
SEGMENT_NORMAL_SPEED_UNTIL=()
SEGMENT_NORMAL_SPEED_FROM=()

duration_of() {
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"
}

segment_path() {
  printf '%s/segment-%02d.mp4' "$BUILD_DIR" "$1"
}

total_duration() {
  local entry seconds total=0
  for entry in "${SEGMENTS[@]}"; do
    IFS='|' read -r _ seconds _ <<<"$entry"
    total="$(awk -v a="$total" -v b="$seconds" 'BEGIN { print a + b }')"
  done
  awk -v a="$total" -v n="${#SEGMENTS[@]}" -v t="$TRANSITION_DURATION" 'BEGIN { printf "%.3f", a - (n - 1) * t }'
}

within() {
  awk -v actual="$1" -v expected="$2" -v tolerance="$3" 'BEGIN { exit !(actual >= expected - tolerance && actual <= expected + tolerance) }'
}

plan_clip() {
  local index="$1" name="$2" slot="$3" fit="$4" clip="$OUT_DIR/$2.mp4" actual head tail extra speedup
  validate_clip_names "$name" || exit 1
  [ -f "$clip" ] || fail "missing $clip (record it with record.sh $name)"
  actual="$(duration_of "$clip")"
  awk -v actual="$actual" -v slot="$slot" -v shortfall="$MAX_CLIP_SHORTFALL" 'BEGIN { exit !(actual >= slot - shortfall) }' \
    || fail "$clip lasts ${actual}s but its slot in SEGMENTS is ${slot}s and a clip may be at most ${MAX_CLIP_SHORTFALL}s shorter (frozen on its last frame); change the slot or re-record the clip"
  SEGMENT_SPEEDUPS[index]=1
  case "$fit" in
    "")
      awk -v actual="$actual" -v slot="$slot" -v overrun="$MAX_CLIP_OVERRUN" 'BEGIN { exit !(actual <= slot + overrun) }' \
        || fail "$clip lasts ${actual}s but its slot in SEGMENTS is ${slot}s and a clip may be at most ${MAX_CLIP_OVERRUN}s longer (cut off); give the segment fit compress:HEAD:TAIL, change the slot or re-record the clip"
      ;;
    compress:*)
      IFS=: read -r _ head tail extra <<<"$fit"
      [ -n "$head" ] && [ -n "$tail" ] && [ -z "$extra" ] \
        || fail "segment $name: fit '$fit' must read compress:HEAD:TAIL (seconds kept at normal speed at the start and at the end)"
      awk -v head="$head" -v tail="$tail" -v slot="$slot" 'BEGIN { exit !(head > 0 && tail > 0 && head + tail < slot) }' \
        || fail "segment $name: fit '$fit' needs a head and a tail longer than 0 whose sum is shorter than the ${slot}s slot"
      speedup="$(awk -v actual="$actual" -v slot="$slot" -v head="$head" -v tail="$tail" 'BEGIN { if (actual <= slot) print 1; else printf "%.4f", (actual - head - tail) / (slot - head - tail) }')"
      awk -v speedup="$speedup" -v max="$MAX_SPEEDUP" 'BEGIN { exit !(speedup <= max) }' \
        || fail "$clip lasts ${actual}s: fitting the ${slot}s slot with the first ${head}s and the last ${tail}s untouched needs ${speedup}x, more than the allowed ${MAX_SPEEDUP}x; re-record a shorter clip or lengthen the slot"
      SEGMENT_SPEEDUPS[index]="$speedup"
      SEGMENT_NORMAL_SPEED_UNTIL[index]="$head"
      SEGMENT_NORMAL_SPEED_FROM[index]="$(awk -v actual="$actual" -v tail="$tail" 'BEGIN { printf "%.4f", actual - tail }')"
      [ "$speedup" = 1 ] || echo "segment $name: ${actual}s recorded, played ${speedup}x faster except its first ${head}s and last ${tail}s, to fit the ${slot}s slot"
      ;;
    *) fail "segment $name: unknown fit '$fit' (expected empty or compress:HEAD:TAIL)" ;;
  esac
}

validate_segments() {
  local index=0 entry kind slot name text fit
  for entry in "${SEGMENTS[@]}"; do
    IFS='|' read -r kind slot name text fit <<<"$entry"
    case "$kind" in
      card) [ -z "$fit" ] || fail "segment $index is a card and takes no fit option" ;;
      clip)
        [[ "$text" != *[\'\\:%]* ]] || fail "segment $index (caption '$text') contains a quote, backslash, colon or percent sign, which drawtext would misread"
        plan_clip "$index" "$name" "$slot" "$fit"
        ;;
      *) fail "unknown segment kind '$kind' in SEGMENTS" ;;
    esac
    index=$((index + 1))
  done
}

assert_duration() {
  local path="$1" expected="$2" actual
  actual="$(duration_of "$path")"
  within "$actual" "$expected" "$DURATION_TOLERANCE" || fail "$path lasts ${actual}s, expected ${expected}s (the total of SEGMENTS)"
}

assert_page_states_duration() {
  local total="$1" whole minutes seconds
  whole="${total%.*}"
  [ "$(awk -v t="$total" -v w="$whole" 'BEGIN { print (t == w) }')" = 1 ] || fail "the video lasts ${total}s; index.html states whole seconds, so make SEGMENTS add up to a whole number"
  minutes=$((whole / 60))
  seconds=$((whole % 60))
  grep -q "Video tour, $whole seconds" "$INDEX_HTML" \
    || fail "index.html does not say 'Video tour, $whole seconds' in the video heading; update it to match SEGMENTS (${total}s)"
  grep -q "vekrona in $whole seconds" "$INDEX_HTML" \
    || fail "index.html does not say 'vekrona in $whole seconds' in the VideoObject name; update it to match SEGMENTS (${total}s)"
  grep -q "\"duration\": \"PT${minutes}M${seconds}S\"" "$INDEX_HTML" \
    || fail "index.html does not say \"duration\": \"PT${minutes}M${seconds}S\" in the VideoObject JSON-LD; update it to match SEGMENTS (${total}s)"
}

make_card() {
  local index="$1" out="$2" duration="$3" title="$4" subtitle="$5" image="$BUILD_DIR/card-$1.png"
  render_card 1920 1080 "$title" "$subtitle" "$image"
  ffmpeg -y -v error -loop 1 -framerate 30 -t "$duration" -i "$image" -vf "format=yuv420p" -c:v libx264 -pix_fmt yuv420p "$out"
}

make_clip_segment() {
  local in="$1" out="$2" target="$3" speedup="$4" normal_speed_until="$5" normal_speed_from="$6" source_label="0:v" filter=""
  local framing="fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,tpad=stop_mode=clone:stop_duration=10,trim=duration=${target},setpts=PTS-STARTPTS"
  if [ "$speedup" != 1 ]; then
    filter="[0:v]split=3[head][middle][tail];[head]trim=end=${normal_speed_until},setpts=PTS-STARTPTS[intro];[middle]trim=start=${normal_speed_until}:end=${normal_speed_from},setpts=(PTS-STARTPTS)/${speedup}[fast];[tail]trim=start=${normal_speed_from},setpts=PTS-STARTPTS[outro];[intro][fast][outro]concat=n=3:v=1:a=0[joined];"
    source_label="joined"
  fi
  ffmpeg -y -v error -i "$in" -filter_complex "${filter}[${source_label}]${framing}[out]" -map "[out]" \
    -an -c:v libx264 -pix_fmt yuv420p "$out"
}

build_segments() {
  local index=0 entry kind seconds name text
  for entry in "${SEGMENTS[@]}"; do
    IFS='|' read -r kind seconds name text _ <<<"$entry"
    case "$kind" in
      card) make_card "$index" "$(segment_path "$index")" "$seconds" "$name" "$text" ;;
      clip) make_clip_segment "$OUT_DIR/$name.mp4" "$(segment_path "$index")" "$seconds" "${SEGMENT_SPEEDUPS[index]}" "${SEGMENT_NORMAL_SPEED_UNTIL[index]:-}" "${SEGMENT_NORMAL_SPEED_FROM[index]:-}" ;;
    esac
    index=$((index + 1))
  done
}

last_clip_index() {
  local i kind last=-1
  for ((i = 0; i < ${#SEGMENTS[@]}; i++)); do
    IFS='|' read -r kind _ <<<"${SEGMENTS[$i]}"
    [ "$kind" != clip ] || last=$i
  done
  echo "$last"
}

segment_starts() {
  local entry seconds running=0
  for entry in "${SEGMENTS[@]}"; do
    IFS='|' read -r _ seconds _ <<<"$entry"
    printf '%s\n' "$running"
    running="$(awk -v r="$running" -v t="$TRANSITION_DURATION" -v d="$seconds" 'BEGIN { printf "%.3f", r - t + d }')"
  done
}

crossfade_filter() {
  local filter="" previous_label="0:v" i out_label
  mapfile -t starts < <(segment_starts)
  for ((i = 1; i < ${#SEGMENTS[@]}; i++)); do
    out_label="v$i"
    [ "$i" -lt $((${#SEGMENTS[@]} - 1)) ] || out_label="$PICTURE_LABEL"
    filter="${filter}[${previous_label}][$i:v]xfade=transition=fade:duration=${TRANSITION_DURATION}:offset=${starts[i]}[${out_label}];"
    previous_label="$out_label"
  done
  printf '%s' "${filter%;}"
}

caption_filter() {
  local filter="" previous_label="$PICTURE_LABEL" last_caption i kind seconds text half start visible fade_out_start out_label
  mapfile -t starts < <(segment_starts)
  last_caption="$(last_clip_index)"
  half="$(awk -v t="$TRANSITION_DURATION" 'BEGIN { printf "%.3f", t / 2 }')"
  for ((i = 0; i < ${#SEGMENTS[@]}; i++)); do
    IFS='|' read -r kind seconds _ text _ <<<"${SEGMENTS[$i]}"
    [ "$kind" = clip ] || continue
    start="$(awk -v s="${starts[i]}" -v h="$half" 'BEGIN { printf "%.3f", s + h }')"
    visible="$(awk -v d="$seconds" -v t="$TRANSITION_DURATION" 'BEGIN { printf "%.3f", d - t }')"
    fade_out_start="$(awk -v v="$visible" -v h="$half" 'BEGIN { printf "%.3f", v - h }')"
    out_label="c$i"
    [ "$i" -lt "$last_caption" ] || out_label="$FINAL_LABEL"
    filter="${filter}color=c=black@0:s=1920x${CAPTION_CANVAS_HEIGHT}:r=30:d=${visible},format=rgba,drawtext=fontfile=${FONT_BOLD}:text='${text}':fontsize=${CAPTION_FONT_SIZE}:fontcolor=${FG}:x=w-text_w-${CAPTION_MARGIN_RIGHT}:y=(h-text_h)/2:box=1:boxcolor=${BG}@1:boxborderw=${CAPTION_BORDER},fade=t=in:st=0:d=${half}:alpha=1,fade=t=out:st=${fade_out_start}:d=${half}:alpha=1,setpts=PTS+${start}/TB[caption$i];"
    filter="${filter}[${previous_label}][caption$i]overlay=y=H-h-${CAPTION_MARGIN_BOTTOM}:eof_action=pass:format=auto[${out_label}];"
    previous_label="$out_label"
  done
  printf '%s' "${filter%;}"
}

mkdir -p "$ASSETS_VIDEO_DIR" "$BUILD_DIR"

total="$(total_duration)"
assert_page_states_duration "$total"
validate_segments

rm -f "$BUILD_DIR"/segment-*.mp4 "$BUILD_DIR"/vekrona-promo.* "$BUILD_DIR"/poster.webp
build_segments

inputs=()
for ((i = 0; i < ${#SEGMENTS[@]}; i++)); do
  inputs+=(-i "$(segment_path "$i")")
done

ffmpeg -y -v error "${inputs[@]}" -filter_complex "$(crossfade_filter);$(caption_filter)" -map "[$FINAL_LABEL]" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart -r 30 "$BUILD_DIR/final.mp4"
assert_duration "$BUILD_DIR/final.mp4" "$total"

ffmpeg -y -v error -i "$BUILD_DIR/final.mp4" -vf "scale=out_range=tv,format=yuv420p" -c:v libvpx-vp9 -b:v 0 -crf 34 -row-mt 1 -an \
  "$BUILD_DIR/vekrona-promo.webm"
assert_duration "$BUILD_DIR/vekrona-promo.webm" "$total"

ffmpeg -y -v error -i "$BUILD_DIR/final.mp4" -vf "scale=out_range=tv,format=yuv420p" -c:v libx264 -crf 22 -preset slow -an -movflags +faststart \
  "$BUILD_DIR/vekrona-promo.mp4"
assert_duration "$BUILD_DIR/vekrona-promo.mp4" "$total"

ffmpeg -y -v error -i "$OUT_DIR/hero.mp4" -vframes 1 -ss 0.8 -vf "scale=1280:-2:flags=lanczos:out_range=tv,format=yuv420p" -quality 85 \
  "$BUILD_DIR/poster.webp"

publish_files "$BUILD_DIR/vekrona-promo.webm" "$BUILD_DIR/vekrona-promo.mp4" "$BUILD_DIR/poster.webp" "$ASSETS_VIDEO_DIR/"

echo "video assets built (${total}s): $ASSETS_VIDEO_DIR"
