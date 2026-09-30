#!/usr/bin/env bash
set -euo pipefail

SCENES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCENES_DIR/lib.sh"

capture_init() {
  vm_scp_to "$SCENES_DIR/vekrona-banner.sh" /tmp/vekrona-banner.sh
  vm_exec <<'EOF'
chmod +x /tmp/vekrona-banner.sh
vekrona-caffeine 2h >/dev/null
vekrona-theme tokyo-night >/dev/null
EOF
}

close_all_windows() {
  vm_exec <<'EOF'
pkill -TERM -f "rofi -dmenu" 2>/dev/null || true
dms ipc call notifications dismissAllPopups >/dev/null 2>&1 || true
dms ipc call spotlight close >/dev/null 2>&1 || true
dms ipc call control-center close >/dev/null 2>&1 || true
dms ipc call notifications close >/dev/null 2>&1 || true
dms ipc call clipboard close >/dev/null 2>&1 || true
dms ipc call powermenu close >/dev/null 2>&1 || true
mapfile -t ids < <(swaymsg -t get_tree -r | jq -r '.. | objects | select(.app_id) | .id')
for id in "${ids[@]}"; do
  swaymsg "[con_id=$id]" kill >/dev/null 2>&1 || true
done
wait_for "empty workspace" 8 bash -c '[ "$(window_count)" -eq 0 ]'
swaymsg workspace number 1 >/dev/null
EOF
}

open_background_windows() {
  vm_exec <<'EOF'
swaymsg exec 'ghostty --title=vekrona-top -e top -d 1' >/dev/null
wait_for "first ghostty window" 8 tree_has '.. | objects | select(.app_id=="com.mitchellh.ghostty")'
swaymsg exec "ghostty --title=vekrona-info -e bash -c '/tmp/vekrona-banner.sh; exec bash'" >/dev/null
wait_for "second ghostty window" 8 bash -c '[ "$(window_count)" -ge 2 ]'
settle 1.6
EOF
}

scene_hero() {
  close_all_windows
  open_background_windows
  vm_capture_png "$1"
}

scene_spotlight() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
dms ipc call spotlight open >/dev/null
settle 0.5
EOF
  vm_capture_png "$1"
  vm_exec <<'EOF'
dms ipc call spotlight close >/dev/null
EOF
}

scene_control_center() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
dms ipc call control-center open >/dev/null
wait_for "control center visible" 5 bash -c '[ "$(dms ipc call control-center status)" = visible ]'
settle 0.5
EOF
  vm_capture_png "$1"
  vm_exec <<'EOF'
dms ipc call control-center close >/dev/null
EOF
}

scene_notifications() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
dms ipc call notifications clearAll >/dev/null 2>&1 || true
settle 0.3
notify-send -a vekrona "vekrona" "Fedora 44 + Sway + DankMaterialShell is ready."
settle 0.4
notify-send -a Ghostty "Update" "Ghostty config reloaded."
settle 0.4
notify-send -a Firefox "Download complete" "vekrona-4k-wallpaper.png"
dms ipc call notifications open >/dev/null
settle 0.5
EOF
  vm_capture_png "$1"
  vm_exec <<'EOF'
dms ipc call notifications close >/dev/null
EOF
}

scene_clipboard() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
printf '%s' 'vekrona: Fedora 44 + Sway + DankMaterialShell' | wl-copy >/dev/null 2>&1 &
disown
settle 0.4
printf '%s' 'Hyper+Space opens Spotlight' | wl-copy >/dev/null 2>&1 &
disown
settle 0.4
printf '%s' 'github.com/vekrona/vekrona' | wl-copy >/dev/null 2>&1 &
disown
settle 0.4
dms ipc call clipboard open >/dev/null
settle 0.5
EOF
  vm_capture_png "$1"
  vm_exec <<'EOF'
dms ipc call clipboard close >/dev/null
EOF
}

scene_keybindings() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
nohup vekrona-keybindings >/tmp/vekrona-keybindings.log 2>&1 &
disown
wait_for "rofi keybindings panel" 8 bash -c 'pgrep -f "rofi -dmenu" >/dev/null'
settle 0.5
EOF
  vm_capture_png "$1"
  vm_exec <<'EOF'
pkill -TERM -f "rofi -dmenu" || true
EOF
}

scene_lock() {
  close_all_windows
  vm_exec <<'EOF'
dms ipc call lock lock >/dev/null
wait_for "session locked" 8 bash -c '[ "$(lock_status_field sessionLockLocked)" = true ]'
settle 0.8
EOF
  vm_screenshot_ppm_to_png "$1"
  vm_exec <<'EOF'
dms ipc call lock unlock >/dev/null
wait_for "session unlocked" 8 bash -c '[ "$(lock_status_field sessionLockLocked)" = false ]'
EOF
}

scene_greeter() {
  local out="$1"
  vm_exec <<'EOF'
swaymsg exit >/dev/null 2>&1 || true
EOF
  vm_wait_for_greeter
  vm_screenshot_ppm_to_png "$out"
  vm_relogin
}

vm_wait_for_greeter() {
  local waited=0
  until ! ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_IP" 'ls /run/user/1000/sway-ipc.*.sock' >/dev/null 2>&1; do
    waited=$((waited + 1))
    [ "$waited" -lt 30 ] || { echo "timed out waiting for sway session to exit" >&2; return 1; }
    sleep 0.5
  done
  settle 1.5
}

vm_relogin() {
  vm_type "$VM_USER"
  vm_key KEY_ENTER
  local waited=0
  until ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_IP" 'ls /run/user/1000/sway-ipc.*.sock' >/dev/null 2>&1; do
    waited=$((waited + 1))
    [ "$waited" -lt 30 ] || { echo "timed out waiting for sway session to restart" >&2; return 1; }
    sleep 1
  done
  vm_exec <<'EOF'
wait_for "dms ipc ready" 20 bash -c 'dms ipc call lock status >/dev/null 2>&1'
EOF
  capture_init
}

vm_hyper_shift_key() {
  vm_key "KEY_LEFTCTRL KEY_LEFTALT KEY_LEFTMETA KEY_LEFTSHIFT $1"
}

record_hero() {
  close_all_windows
  open_background_windows
  vm_record_start /tmp/vekrona-clip.mp4
  settle 1.2
  vm_hyper_key KEY_2
  settle 1.0
  vm_hyper_key KEY_1
  settle 1.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_spotlight() {
  close_all_windows
  open_background_windows
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.5
  vm_hyper_key KEY_SPACE
  settle 1.0
  vm_type "ghostty"
  settle 1.2
  vm_hyper_key KEY_SPACE
  settle 0.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_control_center() {
  close_all_windows
  open_background_windows
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.5
  vm_hyper_key KEY_COMMA
  settle 2.0
  vm_hyper_key KEY_COMMA
  settle 0.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_notifications() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
dms ipc call notifications clearAll >/dev/null 2>&1 || true
notify-send -a vekrona "vekrona" "Fedora 44 + Sway + DankMaterialShell is ready."
settle 0.3
notify-send -a Ghostty "Update" "Ghostty config reloaded."
settle 0.3
notify-send -a Firefox "Download complete" "vekrona-4k-wallpaper.png"
EOF
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.5
  vm_hyper_key KEY_N
  settle 2.0
  vm_hyper_key KEY_N
  settle 0.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_clipboard() {
  close_all_windows
  open_background_windows
  vm_exec <<'EOF'
printf '%s' 'vekrona: Fedora 44 + Sway + DankMaterialShell' | wl-copy >/dev/null 2>&1 &
disown
settle 0.4
printf '%s' 'Hyper+Space opens Spotlight' | wl-copy >/dev/null 2>&1 &
disown
settle 0.4
printf '%s' 'github.com/vekrona/vekrona' | wl-copy >/dev/null 2>&1 &
disown
settle 0.4
EOF
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.5
  vm_hyper_key KEY_V
  settle 2.0
  vm_hyper_key KEY_V
  settle 0.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_keybindings() {
  close_all_windows
  open_background_windows
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.5
  vm_hyper_key KEY_SLASH
  settle 2.2
  vm_key KEY_ESC
  settle 0.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_theme_cycle() {
  close_all_windows
  vm_exec <<'EOF'
vekrona-theme tokyo-night >/dev/null
EOF
  open_background_windows
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.8
  vm_hyper_shift_key KEY_T
  settle 1.6
  vm_hyper_shift_key KEY_T
  settle 1.6
  vm_hyper_shift_key KEY_T
  settle 1.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
  vm_exec <<'EOF'
vekrona-theme tokyo-night >/dev/null
EOF
}

record_terminal() {
  close_all_windows
  vm_exec <<'EOF'
swaymsg exec ghostty >/dev/null
wait_for "ghostty window" 8 tree_has '.. | objects | select(.app_id=="com.mitchellh.ghostty")'
settle 0.8
EOF
  vm_record_start /tmp/vekrona-clip.mp4
  settle 0.4
  vm_type 'cd vekrona && ./install.sh --skip 10-nvidia 70'
  vm_key KEY_ENTER
  settle 3.6
  vm_record_stop
  vm_scp_from /tmp/vekrona-clip.mp4 "$1"
}

record_lock() {
  close_all_windows
  local frames_dir="$OUT_DIR/lock-frames"
  rm -rf "$frames_dir"
  mkdir -p "$frames_dir"
  vm_exec <<'EOF'
dms ipc call lock lock >/dev/null
wait_for "session locked" 8 bash -c '[ "$(lock_status_field sessionLockLocked)" = true ]'
EOF
  local i=0 start_ts end_ts elapsed input_fps
  start_ts="$(date +%s.%N)"
  local deadline=$((SECONDS + 2))
  while [ "$SECONDS" -lt "$deadline" ]; do
    printf -v frame "%s/frame-%04d.png" "$frames_dir" "$i"
    vm_screenshot_ppm_to_png "$frame"
    i=$((i + 1))
  done
  vm_type "$VM_USER"
  local unlock_deadline=$((SECONDS + 2))
  while [ "$SECONDS" -lt "$unlock_deadline" ]; do
    printf -v frame "%s/frame-%04d.png" "$frames_dir" "$i"
    vm_screenshot_ppm_to_png "$frame"
    i=$((i + 1))
  done
  vm_key KEY_ENTER
  wait_for_local "session unlocked" 10 lock_is_unlocked_locally
  end_ts="$(date +%s.%N)"
  elapsed="$(awk -v a="$start_ts" -v b="$end_ts" 'BEGIN { print b - a }')"
  input_fps="$(awk -v n="$i" -v t="$elapsed" 'BEGIN { print n / t }')"
  ffmpeg -y -framerate "$input_fps" -i "$frames_dir/frame-%04d.png" -c:v libx264 -pix_fmt yuv420p -vf "fps=30" "$1" -v error
}

lock_is_unlocked_locally() {
  local status
  status="$(vm_exec <<<'lock_status_field sessionLockLocked' 2>/dev/null)"
  [ "$status" = "false" ]
}

wait_for_local() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0 max=$((timeout * 5))
  until "$@" >/dev/null 2>&1; do
    waited=$((waited + 1))
    [ "$waited" -lt "$max" ] || { echo "timed out after ${timeout}s waiting for: $desc" >&2; return 1; }
    sleep 0.2
  done
}

scene_terminal_ops() {
  vm_exec <<'EOF'
{
  echo '$ vekrona-rollback --help'
  vekrona-rollback --help 2>&1 || true
  echo
  echo '$ sudo vekrona-snapshot "vekrona promo capture"'
  sudo -n /home/vekrona/.local/bin/vekrona-snapshot "vekrona promo capture"
  echo
  echo '$ ./install.sh --skip 10-nvidia 70'
  cd /home/vekrona/vekrona && ./install.sh --skip 10-nvidia 70 2>&1 | tail -22
} > /tmp/vekrona-term-snippet.txt
EOF
  close_all_windows
  vm_exec <<'EOF'
swaymsg exec "ghostty --title=vekrona-ops -e bash -c 'cat /tmp/vekrona-term-snippet.txt; exec bash'" >/dev/null
wait_for "ops ghostty window" 8 tree_has '.. | objects | select(.app_id=="com.mitchellh.ghostty")'
settle 0.5
EOF
  vm_capture_png "$1"
}
