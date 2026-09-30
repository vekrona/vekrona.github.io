#!/usr/bin/env bash
set -euo pipefail

CAPTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CAPTURE_DIR/scenes.sh"

capture_init

record_hero "$OUT_DIR/hero.mp4"
record_spotlight "$OUT_DIR/spotlight.mp4"
record_control_center "$OUT_DIR/control-center.mp4"
record_notifications "$OUT_DIR/notifications.mp4"
record_clipboard "$OUT_DIR/clipboard.mp4"
record_keybindings "$OUT_DIR/keybindings.mp4"
record_theme_cycle "$OUT_DIR/theme-cycle.mp4"
record_terminal "$OUT_DIR/terminal.mp4"
record_lock "$OUT_DIR/lock.mp4"

close_all_windows

echo "clips recorded: $OUT_DIR"
ls -la "$OUT_DIR"/*.mp4
