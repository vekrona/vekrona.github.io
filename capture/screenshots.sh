#!/usr/bin/env bash
set -euo pipefail

CAPTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CAPTURE_DIR/scenes.sh"

RAW_DIR="$OUT_DIR/screenshots"
mkdir -p "$RAW_DIR"

to_webp() {
  local src="$1" dst="$2"
  magick "$src" -quality 85 "$dst"
}

capture_init

scene_hero "$RAW_DIR/hero.png"
to_webp "$RAW_DIR/hero.png" "$ASSETS_IMG_DIR/hero.webp"
magick "$RAW_DIR/hero.png" -gravity center -crop 1200x630+0-60 +repage "$ASSETS_IMG_DIR/og.png"

scene_spotlight "$RAW_DIR/spotlight.png"
to_webp "$RAW_DIR/spotlight.png" "$ASSETS_IMG_DIR/spotlight.webp"

scene_control_center "$RAW_DIR/control-center.png"
to_webp "$RAW_DIR/control-center.png" "$ASSETS_IMG_DIR/control-center.webp"

scene_notifications "$RAW_DIR/notifications.png"
to_webp "$RAW_DIR/notifications.png" "$ASSETS_IMG_DIR/notifications.webp"

scene_clipboard "$RAW_DIR/clipboard.png"
to_webp "$RAW_DIR/clipboard.png" "$ASSETS_IMG_DIR/clipboard.webp"

scene_keybindings "$RAW_DIR/keybindings.png"
to_webp "$RAW_DIR/keybindings.png" "$ASSETS_IMG_DIR/keybindings.webp"

for theme_name in tokyo-night catppuccin-mocha gruvbox-dark; do
  close_all_windows
  vm_exec <<EOF
vekrona-theme "$theme_name" >/dev/null
EOF
  open_background_windows
  vm_capture_png "$RAW_DIR/theme-$theme_name.png"
  to_webp "$RAW_DIR/theme-$theme_name.png" "$ASSETS_IMG_DIR/theme-$theme_name.webp"
done
vm_exec <<'EOF'
vekrona-theme tokyo-night >/dev/null
EOF

scene_lock "$RAW_DIR/lock.png"
to_webp "$RAW_DIR/lock.png" "$ASSETS_IMG_DIR/lock.webp"

scene_terminal_ops "$RAW_DIR/terminal-ops.png"
to_webp "$RAW_DIR/terminal-ops.png" "$ASSETS_IMG_DIR/terminal-ops.webp"

scene_greeter "$RAW_DIR/greeter.png"
to_webp "$RAW_DIR/greeter.png" "$ASSETS_IMG_DIR/greeter.webp"

close_all_windows

echo "screenshots done: $ASSETS_IMG_DIR"
ls -la "$ASSETS_IMG_DIR"
