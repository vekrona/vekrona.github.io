#!/usr/bin/env bash
set -euo pipefail

CAPTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_REPO="$(cd "$CAPTURE_DIR/.." && pwd)"
OUT_DIR="$CAPTURE_DIR/out"
ASSETS_VIDEO_DIR="$SITE_REPO/assets/video"
BUILD_DIR="$OUT_DIR/video-build"
CLIPS_DIR="$OUT_DIR"

mkdir -p "$ASSETS_VIDEO_DIR" "$BUILD_DIR"
rm -f "$BUILD_DIR"/segment-*.mp4

FONT_REGULAR=""
for candidate in \
  /usr/share/fonts/omedora-nerd-fonts/JetBrainsMonoNerdFont-Regular.ttf \
  "$HOME/.local/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf" \
  /usr/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf
do
  if [ -f "$candidate" ]; then
    FONT_REGULAR="$candidate"
    break
  fi
done
[ -n "$FONT_REGULAR" ] || { echo "video.sh: no JetBrainsMono Nerd Font Regular.ttf found in known locations" >&2; exit 1; }

FONT_BOLD=""
for candidate in \
  /usr/share/fonts/omedora-nerd-fonts/JetBrainsMonoNerdFont-Bold.ttf \
  "$HOME/.local/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-Bold.ttf" \
  /usr/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-Bold.ttf
do
  if [ -f "$candidate" ]; then
    FONT_BOLD="$candidate"
    break
  fi
done
[ -n "$FONT_BOLD" ] || { echo "video.sh: no JetBrainsMono Nerd Font Bold.ttf found in known locations" >&2; exit 1; }

TRANSITION_DURATION=0.6
BG=0x11131a
FG=0xe8e8f0
ACCENT=0x7aa2f7

make_card() {
  local out="$1" duration="$2" line1="$3" line2="$4"
  ffmpeg -y -v error -f lavfi -i "color=c=${BG}:s=1920x1080:d=${duration}:r=30" \
    -vf "format=yuv420p,drawtext=fontfile=${FONT_BOLD}:text='${line1}':fontsize=84:fontcolor=${FG}:x=(w-text_w)/2:y=(h-text_h)/2-40,drawtext=fontfile=${FONT_REGULAR}:text='${line2}':fontsize=38:fontcolor=${ACCENT}:x=(w-text_w)/2:y=(h-text_h)/2+70" \
    -c:v libx264 -pix_fmt yuv420p "$out"
}

make_clip_segment() {
  local in="$1" out="$2" target="$3" caption="$4"
  ffmpeg -y -v error -i "$in" -vf "fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,tpad=stop_mode=clone:stop_duration=10,trim=duration=${target},setpts=PTS-STARTPTS,drawtext=fontfile=${FONT_BOLD}:text='${caption}':fontsize=34:fontcolor=${FG}:x=60:y=h-110:box=1:boxcolor=${BG}@0.72:boxborderw=18" \
    -an -c:v libx264 -pix_fmt yuv420p "$out"
}

make_card "$BUILD_DIR/segment-00.mp4" 5.0 "vekrona" "Fedora + Sway + DankMaterialShell"
make_clip_segment "$CLIPS_DIR/hero.mp4" "$BUILD_DIR/segment-01.mp4" 6.0 "Hyper + 1..0  —  Sway workspaces, always visible"
make_clip_segment "$CLIPS_DIR/spotlight.mp4" "$BUILD_DIR/segment-02.mp4" 6.0 "Hyper + Space  —  Spotlight"
make_clip_segment "$CLIPS_DIR/control-center.mp4" "$BUILD_DIR/segment-03.mp4" 5.5 "Hyper + ,  —  Control Center"
make_clip_segment "$CLIPS_DIR/notifications.mp4" "$BUILD_DIR/segment-04.mp4" 5.5 "Hyper + N  —  Notifications"
make_clip_segment "$CLIPS_DIR/clipboard.mp4" "$BUILD_DIR/segment-05.mp4" 5.5 "Hyper + V  —  Clipboard history"
make_clip_segment "$CLIPS_DIR/keybindings.mp4" "$BUILD_DIR/segment-06.mp4" 5.5 "Hyper + /  —  Keybindings help"
make_clip_segment "$CLIPS_DIR/theme-cycle.mp4" "$BUILD_DIR/segment-07.mp4" 7.5 "Hyper + Shift + T  —  Cycle themes"
make_clip_segment "$CLIPS_DIR/terminal.mp4" "$BUILD_DIR/segment-08.mp4" 7.5 "./install.sh --skip 10-nvidia 70  —  Idempotent, verified"
make_clip_segment "$CLIPS_DIR/lock.mp4" "$BUILD_DIR/segment-09.mp4" 6.0 "Hyper + Escape  —  Lock screen"
make_card "$BUILD_DIR/segment-10.mp4" 7.0 "github.com/vekrona/vekrona" "Fedora 44  ·  Sway  ·  DankMaterialShell"

durations=(5.0 6.0 6.0 5.5 5.5 5.5 5.5 7.5 7.5 6.0 7.0)
segment_count=${#durations[@]}

filter=""
running="${durations[0]}"
prev_label="0:v"
for ((i = 1; i < segment_count; i++)); do
  dur="${durations[$i]}"
  offset="$(awk -v r="$running" -v t="$TRANSITION_DURATION" 'BEGIN { printf "%.3f", r - t }')"
  out_label="v$i"
  if [ "$i" -eq $((segment_count - 1)) ]; then
    out_label="vout"
  fi
  filter="${filter}[${prev_label}][$i:v]xfade=transition=fade:duration=${TRANSITION_DURATION}:offset=${offset}[${out_label}];"
  running="$(awk -v r="$running" -v t="$TRANSITION_DURATION" -v d="$dur" 'BEGIN { printf "%.3f", r - t + d }')"
  prev_label="$out_label"
done

inputs=()
for ((i = 0; i < segment_count; i++)); do
  inputs+=(-i "$BUILD_DIR/segment-$(printf '%02d' "$i").mp4")
done

ffmpeg -y -v error "${inputs[@]}" -filter_complex "$filter" -map "[vout]" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart -r 30 "$BUILD_DIR/final.mp4"

ffmpeg -y -v error -i "$BUILD_DIR/final.mp4" -vf "scale=out_range=tv,format=yuv420p" -c:v libvpx-vp9 -b:v 0 -crf 34 -row-mt 1 -an \
  "$ASSETS_VIDEO_DIR/vekrona-promo.webm"

ffmpeg -y -v error -i "$BUILD_DIR/final.mp4" -vf "scale=out_range=tv,format=yuv420p" -c:v libx264 -crf 22 -preset slow -an -movflags +faststart \
  "$ASSETS_VIDEO_DIR/vekrona-promo.mp4"

ffmpeg -y -v error -i "$BUILD_DIR/final.mp4" -vframes 1 -ss 4.5 -vf "scale=out_range=tv,format=yuv420p" -quality 85 \
  "$ASSETS_VIDEO_DIR/poster.webp"

echo "video assets built:"
ls -la "$ASSETS_VIDEO_DIR"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 "$ASSETS_VIDEO_DIR/vekrona-promo.mp4"
