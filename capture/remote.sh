set -euo pipefail
shopt -s inherit_errexit

XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR
export WAYLAND_DISPLAY=wayland-1
[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || { echo "no $WAYLAND_DISPLAY socket under $XDG_RUNTIME_DIR (no graphical session logged in?)" >&2; exit 1; }
SWAYSOCK="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)"
[ -n "$SWAYSOCK" ] || { echo "no sway-ipc socket under $XDG_RUNTIME_DIR (no graphical session logged in?)" >&2; exit 1; }
export SWAYSOCK

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/vekrona"
DEFAULT_THEME=tokyo-night
TRAY_UNIT=tailscale-systray.service
RECORDER_UNIT=vekrona-capture-recorder.service
RECORDER_LOG="$REMOTE_DIR/recorder.log"
CLIP_PATH="$REMOTE_DIR/clip.mp4"
FRAME_HASH_FILE="$REMOTE_DIR/frame-hash"
KEYBINDINGS_LOG="$REMOTE_DIR/keybindings.log"
SCREEN_RIGHT_HALF="960,48 960x1032"
SCREEN_BELOW_BAR="0,48 1920x1032"
FIREFOX_PROFILE="$REMOTE_DIR/firefox-profile"
CAPTURE_PROCESSES=(ghostty btop rofi)
SITE_UNIT=vekrona-capture-site.service
SITE_LOG="$REMOTE_DIR/site.log"
SITE_HERO_PREFIX=assets/img/hero
VEKRONA_CHECKOUT="$HOME/vekrona"
SNAPSHOT_BIN="$HOME/.local/bin/vekrona-snapshot"
SNAPSHOT_DESCRIPTION="vekrona promo capture"
TERMINAL_SNIPPET="$REMOTE_DIR/term-snippet.txt"
INSTALLER_PROCESS_PATTERN="$INSTALLER_SCRIPT ${INSTALLER_ARGS[*]}"
AVATAR_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/vekrona-capture"
AVATAR_BACKUP="$AVATAR_STATE_DIR/avatar-previous"
AVATAR_WAS_UNSET_MARKER="$AVATAR_STATE_DIR/avatar-was-unset"
GUEST_COMMANDS=(
  dms swaymsg jq grim wf-recorder systemd-run systemctl notify-send ghostty firefox btop
  vekrona-theme vekrona-error vekrona-keybindings
  tar find sed awk od sort uniq sha256sum cmp timeout pgrep pkill setsid mktemp busctl
  sudo curl ss python3 grep
)
GRIM_TIMEOUT=10
BTOP_GRAPH_PROBE_X=30
BTOP_GRAPH_PROBE_Y=60
BTOP_GRAPH_PROBE_SIZE=16x245
BTOP_GRAPH_MIN_DRAWN_PIXELS=150
BAR_CHIP_REGION="170,12 240x24"
BAR_CHIP_MIN_DRAWN_PIXELS=300
FOCUS_CHIP_TIMEOUT=2
FOCUS_CHIP_ATTEMPTS=3
POLITE_EXIT_TIMEOUT=15
SIGNAL_EXIT_TIMEOUT=5
RESTORE_FAILURES=()

require_guest_commands() {
  local command_name missing=()
  for command_name in "${GUEST_COMMANDS[@]}"; do
    command -v "$command_name" >/dev/null || missing+=("$command_name")
  done
  [ "${#missing[@]}" -eq 0 ] || { echo "the guest lacks: ${missing[*]}" >&2; return 1; }
  sudo -n true || { echo "the site server needs passwordless sudo in the guest" >&2; return 1; }
}

dms_call() {
  local output
  output="$(dms ipc call "$@")" || { echo "dms ipc call $*: dms exited with status $?" >&2; return 1; }
  case "$output" in
    "Function not found."|"Target not found."*|*_FAILED*|*NOT_FOUND*)
      echo "dms ipc call $*: $output" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$output"
}

tree_has() {
  swaymsg -t get_tree -r | jq -e "$1" >/dev/null
}

window_count() {
  swaymsg -t get_tree -r | jq '[.. | objects | select(.app_id? or .window_properties?.class?)] | length'
}

window_count_at_least() {
  [ "$(window_count)" -ge "$1" ]
}

no_windows() {
  [ "$(window_count)" -eq 0 ]
}

window_focused() {
  tree_has '[.. | objects | select(.focused? == true)] | length > 0'
}

keyboard_grabbed_by_overlay() {
  tree_has '[.. | objects | select(.focused? == true)] | length == 0'
}

wait_for_overlay_focus() {
  wait_for "a panel to take keyboard focus" 5 keyboard_grabbed_by_overlay
}

lock_status_field() {
  dms_call lock status | jq -r ".$1"
}

session_locked() {
  [ "$(lock_status_field sessionLockLocked)" = true ]
}

session_unlocked() {
  [ "$(lock_status_field sessionLockLocked)" = false ]
}

dms_ipc_ready() {
  dms_call lock status
}

idle_inhibited() {
  [ "$(dms_call inhibit status)" = "Idle inhibit is enabled" ]
}

output_power_state() {
  swaymsg -t get_outputs -r | jq 'all(.[]; .power)'
}

outputs_powered() {
  [ "$(output_power_state)" = true ]
}

power_on_outputs() {
  swaymsg "output * dpms on" >/dev/null && outputs_powered
}

output_mode_is_1920x1080() {
  swaymsg -t get_outputs -r | jq -e 'all(.[]; .current_mode.width == 1920 and .current_mode.height == 1080)' >/dev/null
}

no_pending_user_jobs() {
  local jobs
  jobs="$(systemctl --user list-jobs --no-legend)" || return 1
  [ -z "$jobs" ]
}

unread_error_count() {
  cat "$STATE_DIR/errors/unread"
}

unread_errors_exist() {
  [ "$(unread_error_count)" -gt 0 ]
}

no_unread_errors() {
  [ "$(unread_error_count)" -eq 0 ]
}

toast_state() {
  dms_call toast status
}

toast_hidden() {
  [ "$(toast_state)" = hidden ]
}

clipboard_entry_count_is() {
  [ "$(dms clipboard history --json | jq length)" -eq "$1" ]
}

current_theme() {
  local theme
  theme="$(cat "$STATE_DIR/theme")" || return 1
  [ -n "$theme" ] || { echo "$STATE_DIR/theme is empty" >&2; return 1; }
  printf '%s\n' "$theme"
}

theme_is() {
  [ "$(current_theme)" = "$1" ]
}

theme_differs_from() {
  local theme
  theme="$(current_theme)" || return 1
  [ "$theme" != "$1" ]
}

no_process() {
  local status=0
  pgrep "$@" >/dev/null || status=$?
  case "$status" in
    0) return 1 ;;
    1) return 0 ;;
    *) echo "pgrep $*: failed with status $status" >&2; return "$WAIT_FOR_ABORT_STATUS" ;;
  esac
}

site_title() {
  sed -n 's:.*<title>\(.*\)</title>.*:\1:p' "$SITE_ROOT/index.html"
}

site_preloaded_assets() {
  sed -n 's/.*rel="preload" href="\([^"]*\)".*/\1/p' "$SITE_ROOT/index.html"
}

site_unit_failed() {
  systemctl is-failed --quiet "$SITE_UNIT"
}

site_answers() {
  site_unit_failed && { echo "$SITE_UNIT failed; its log:"; cat "$SITE_LOG"; return "$WAIT_FOR_ABORT_STATUS"; }
  curl -fsS --max-time 2 -o /dev/null --cacert "$SITE_TLS_DIR/ca.pem" --resolve "$SITE_HOST:$SITE_PORT:127.0.0.1" "https://$SITE_HOST/index.html"
}

site_served() {
  grep -q "\"GET /$1[^\"]* HTTP/[0-9.]*\" 200" "$SITE_LOG"
}

site_served_everything_above_the_fold() {
  local asset
  for asset in "$SITE_HERO_PREFIX" $(site_preloaded_assets); do
    site_served "$asset" || { echo "$asset not served yet"; return 1; }
  done
}

site_unit_loaded() {
  [ "$(systemctl show --property=LoadState --value "$SITE_UNIT")" != not-found ]
}

site_port_free() {
  [ -z "$(ss -H -ltn "sport = :$SITE_PORT")" ]
}

firefox_shows_page() {
  swaymsg -t get_tree -r | jq -e --arg title "$(site_title)" '.. | objects | select(.app_id? == "org.mozilla.firefox" and ((.name? // "") | startswith($title)))' >/dev/null
}

rofi_panel_open() {
  pgrep -x rofi >/dev/null && return 0
  [ ! -f "$KEYBINDINGS_LOG" ] || cat "$KEYBINDINGS_LOG"
  return 1
}

installer_running() {
  pgrep -f "$INSTALLER_PROCESS_PATTERN" >/dev/null
}

installer_finished() {
  no_process -f "$INSTALLER_PROCESS_PATTERN"
}

ensure_desktop_ready() {
  local locked output_powered
  locked="$(lock_status_field sessionLockLocked)"
  if [ "$locked" = true ]; then
    echo "ensure_desktop_ready: the session was locked, unlocking it" >&2
    dms_call lock unlock >/dev/null
    wait_for "session unlock" 10 session_unlocked
  fi
  output_powered="$(output_power_state)"
  if [ "$output_powered" != true ]; then
    echo "ensure_desktop_ready: the output was off, powering it on" >&2
    wait_for "output powered on" 10 power_on_outputs
  fi
}

clean_bar() {
  dms_call notifications dismissAllPopups >/dev/null
  dms_call notifications clearAll >/dev/null
  dms_call toast hide >/dev/null
  vekrona-error ack --all >/dev/null
  wait_for "toast hidden" 5 toast_hidden
  wait_for "error badge cleared" 5 no_unread_errors
}

set_theme() {
  vekrona-theme "$1" >/dev/null
  wait_for "theme switch to $1" 15 theme_is "$1"
}

restore_default_theme() {
  set_theme "$DEFAULT_THEME"
}

stop_tray() {
  systemctl --user is-active --quiet "$TRAY_UNIT" || return 0
  vekrona-error ack --all >/dev/null
  systemctl --user stop "$TRAY_UNIT"
  if systemctl --user is-failed --quiet "$TRAY_UNIT"; then
    wait_for "tray stop recorded as an error" 10 unread_errors_exist
  fi
}

write_btop_config() {
  btop --default-config \
    | sed -e 's/^color_theme = .*/color_theme = "TTY"/' \
          -e 's/^theme_background = .*/theme_background = false/' \
          -e 's/^proc_filter_kernel = .*/proc_filter_kernel = true/' \
          -e 's/^proc_sorting = .*/proc_sorting = "pid"/' \
          -e 's/^proc_reversed = .*/proc_reversed = true/' \
          -e 's/^graph_symbol = .*/graph_symbol = "block"/' \
          -e 's/^update_ms = .*/update_ms = 100/' > "$REMOTE_DIR/btop.conf"
}

set_avatar() {
  local result
  result="$(dms_call profile setImage "$1")"
  [[ "$result" == SUCCESS* ]] || { echo "profile setImage $1: $result" >&2; return 1; }
}

accounts_icon_file() {
  local property
  property="$(busctl --system get-property org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" org.freedesktop.Accounts.User IconFile)" || return 1
  property="${property#s \"}"
  printf '%s\n' "${property%\"}"
}

avatar_matches_backup() {
  cmp -s "$AVATAR_BACKUP" "$(accounts_icon_file)"
}

avatar_cleared() {
  [ -z "$(accounts_icon_file)" ]
}

remember_avatar() {
  local current
  if [ -e "$AVATAR_BACKUP" ] || [ -e "$AVATAR_WAS_UNSET_MARKER" ]; then
    echo "remember_avatar: keeping the avatar that an earlier capture run remembered" >&2
    return 0
  fi
  current="$(accounts_icon_file)"
  mkdir -p "$AVATAR_STATE_DIR"
  if [ -z "$current" ]; then
    : >"$AVATAR_WAS_UNSET_MARKER"
  elif [ -f "$current" ]; then
    cp "$current" "$AVATAR_BACKUP"
  else
    echo "AccountsService names the avatar '$current', which is neither empty nor a readable file" >&2
    return 1
  fi
}

install_capture_avatar() {
  remember_avatar
  set_avatar "$REMOTE_DIR/avatar.png"
}

restore_avatar() {
  if [ -e "$AVATAR_BACKUP" ]; then
    set_avatar "$AVATAR_BACKUP"
    wait_for "the previous avatar to be in place" 10 avatar_matches_backup
  elif [ -e "$AVATAR_WAS_UNSET_MARKER" ]; then
    dms_call profile clearImage >/dev/null
    wait_for "the avatar to be cleared" 10 avatar_cleared
  fi
  rm -rf "$AVATAR_STATE_DIR"
}

prepare_session() {
  wait_for "user services started" 30 no_pending_user_jobs
  stop_tray
  write_btop_config
  dms_call inhibit enable >/dev/null
  wait_for "idle inhibitor active" 5 idle_inhibited
  set_theme "$DEFAULT_THEME"
}

ghostty_window() {
  local title="$1"; shift
  swaymsg exec "ghostty --title=$title --app-notifications=no-config-reload $*" >/dev/null
}

install_terminal() {
  ghostty_window install --font-size=16 "--working-directory=$VEKRONA_CHECKOUT" "$@"
}

wait_for_terminal_window() {
  wait_for "ghostty window" 8 tree_has '.. | objects | select(.app_id=="com.mitchellh.ghostty")'
  swaymsg '[app_id="com.mitchellh.ghostty"] focus' >/dev/null
  wait_for_focused_window
}

open_install_terminal() {
  install_terminal
  wait_for_terminal_window
  wait_for_stable_frame "$SCREEN_BELOW_BAR"
}

frame_hash() {
  timeout "$GRIM_TIMEOUT" grim -g "$1" -t ppm - | sha256sum
}

frame_stable_since_last_poll() {
  local region="$1" baseline="${2:-}" current previous=""
  current="$(frame_hash "$region")" || return "$WAIT_FOR_ABORT_STATUS"
  if [ -f "$FRAME_HASH_FILE" ]; then
    previous="$(cat "$FRAME_HASH_FILE")"
  fi
  printf '%s\n' "$current" > "$FRAME_HASH_FILE"
  [ "$current" != "$baseline" ] && [ "$current" = "$previous" ]
}

wait_for_stable_frame() {
  local region="$1" baseline="${2:-}"
  rm -f "$FRAME_HASH_FILE"
  wait_for "a stable frame in $region" 15 frame_stable_since_last_poll "$region" "$baseline"
}

region_has_ink() {
  local region="$1" minimum="$2"
  timeout "$GRIM_TIMEOUT" grim -g "$region" -t ppm - | tail -n +4 | od -An -v -tx1 -w3 | sort | uniq -c | sort -rn \
    | awk -v min="$minimum" 'NR == 1 { background = $1 } { total += $1 } END { exit !(total - background >= min) }'
}

btop_graph_drawn() {
  region_has_ink "$1" "$BTOP_GRAPH_MIN_DRAWN_PIXELS"
}

focus_chip_drawn() {
  region_has_ink "$BAR_CHIP_REGION" "$BAR_CHIP_MIN_DRAWN_PIXELS"
}

refocus_window() {
  swaymsg 'focus parent' >/dev/null
  swaymsg 'focus child' >/dev/null
}

wait_for_focus_chip() {
  local attempt
  for ((attempt = 1; attempt <= FOCUS_CHIP_ATTEMPTS; attempt++)); do
    wait_for "the bar's focused-window chip to be drawn" "$FOCUS_CHIP_TIMEOUT" focus_chip_drawn 2>/dev/null && return 0
    echo "wait_for_focus_chip: no chip after ${FOCUS_CHIP_TIMEOUT}s, DMS missed the focus event; focusing the window again (attempt $attempt of $FOCUS_CHIP_ATTEMPTS)" >&2
    refocus_window
  done
  wait_for "the bar's focused-window chip to be drawn after $FOCUS_CHIP_ATTEMPTS attempts to focus the window again" "$FOCUS_CHIP_TIMEOUT" focus_chip_drawn
}

wait_for_focused_window() {
  wait_for "a window has keyboard focus" 5 window_focused
  wait_for_focus_chip
}

wait_for_btop_graph() {
  local rect x y
  rect="$(swaymsg -t get_tree -r | jq -r '.. | objects | select(.name? == "btop") | .rect | [.x, .y] | @tsv')"
  [ -n "$rect" ] || { echo "no btop window to read the graph position from" >&2; return 1; }
  read -r x y <<<"$rect"
  wait_for "btop cpu graph drawn" 60 btop_graph_drawn "$((x + BTOP_GRAPH_PROBE_X)),$((y + BTOP_GRAPH_PROBE_Y)) $BTOP_GRAPH_PROBE_SIZE"
}

open_banner_terminal() {
  ghostty_window vekrona -e bash -c "'$REMOTE_DIR/vekrona-banner.sh; exec bash'"
}

start_site_server() {
  if site_unit_loaded; then
    echo "start_site_server: $SITE_UNIT is left over from an earlier run, stopping it" >&2
    stop_site_server
  fi
  sudo -n systemd-run --quiet --unit="$SITE_UNIT" \
    -p User="$(id -un)" -p AmbientCapabilities=CAP_NET_BIND_SERVICE -E SITE_LOG="$SITE_LOG" \
    bash -c 'exec python3 "$@" 2>>"$SITE_LOG"' _ "$REMOTE_DIR/site-server.py" "$SITE_PORT" "$SITE_ROOT" "$SITE_TLS_DIR/server.pem" "$SITE_TLS_DIR/server.key"
  wait_for "the site server to answer on port $SITE_PORT with a certificate for $SITE_HOST" 10 site_answers
}

stop_site_server() {
  site_unit_loaded || return 0
  sudo -n systemctl stop "$SITE_UNIT"
  ! site_unit_failed || sudo -n systemctl reset-failed "$SITE_UNIT"
  wait_for "port $SITE_PORT to be free again" 10 site_port_free
}

open_firefox_site() {
  rm -rf "$FIREFOX_PROFILE"
  mkdir "$FIREFOX_PROFILE"
  cp "$REMOTE_DIR/firefox-user.js" "$FIREFOX_PROFILE/user.js"
  cp "$SITE_TLS_DIR"/nss/* "$FIREFOX_PROFILE/"
  printf 'user_pref("network.dns.localDomains", "%s");\nuser_pref("network.proxy.no_proxies_on", "%s, localhost, 127.0.0.1");\n' "$SITE_HOST" "$SITE_HOST" >>"$FIREFOX_PROFILE/user.js"
  : >"$SITE_LOG"
  swaymsg exec "firefox --new-instance --profile $FIREFOX_PROFILE --new-window https://$SITE_HOST/" >/dev/null
  wait_for "firefox to show the page title" 30 firefox_shows_page
  wait_for "the site server to have served the hero image and the preloaded fonts" 30 site_served_everything_above_the_fold
}

open_window_pair() {
  local open_right_window="$1"
  ghostty_window btop -e btop -c "$REMOTE_DIR/btop.conf"
  wait_for "btop window" 8 tree_has '.. | objects | select(.name? == "btop")'
  "$open_right_window"
  wait_for "second window" 20 window_count_at_least 2
  swaymsg '[all] urgent disable' >/dev/null
  wait_for_focused_window
  wait_for_btop_graph
  wait_for_stable_frame "$SCREEN_RIGHT_HALF"
}

open_dms_panel() {
  local panel="$1" baseline
  baseline="$(frame_hash "$SCREEN_RIGHT_HALF")"
  dms_call "$panel" open >/dev/null
  wait_for_overlay_focus
  wait_for_stable_frame "$SCREEN_RIGHT_HALF" "$baseline"
}

open_keybindings_panel() {
  local baseline
  baseline="$(frame_hash "$SCREEN_RIGHT_HALF")"
  setsid -f vekrona-keybindings >"$KEYBINDINGS_LOG" 2>&1 </dev/null
  wait_for "rofi keybindings panel" 8 rofi_panel_open
  wait_for_stable_frame "$SCREEN_RIGHT_HALF" "$baseline"
}

close_keybindings_panel() {
  pkill -x rofi || [ $? -eq 1 ]
}

close_panels() {
  local panel
  for panel in spotlight notifications clipboard powermenu; do
    dms_call "$panel" close >/dev/null
  done
  [ "$(dms_call control-center status)" = hidden ] || dms_call control-center hide >/dev/null
  close_keybindings_panel
}

close_windows() {
  no_windows || swaymsg '[all] kill' >/dev/null
  wait_for "no windows left" 8 no_windows
}

end_process() {
  local description="$1"; shift
  wait_for "$description to exit" "$POLITE_EXIT_TIMEOUT" no_process "$@" && return 0
  echo "end_process: $description is still running ${POLITE_EXIT_TIMEOUT}s after its window closed, sending SIGTERM" >&2
  pkill -TERM "$@" || [ $? -eq 1 ]
  wait_for "$description to exit after SIGTERM" "$SIGNAL_EXIT_TIMEOUT" no_process "$@" && return 0
  echo "end_process: $description survived SIGTERM for ${SIGNAL_EXIT_TIMEOUT}s, sending SIGKILL" >&2
  pkill -KILL "$@" || [ $? -eq 1 ]
  wait_for "$description to exit after SIGKILL" "$SIGNAL_EXIT_TIMEOUT" no_process "$@"
}

end_capture_processes() {
  local name survivors=()
  end_process "the capture's firefox (profile $FIREFOX_PROFILE)" -f "$FIREFOX_PROFILE" || survivors+=(firefox)
  for name in "${CAPTURE_PROCESSES[@]}"; do
    end_process "$name" -x "$name" || survivors+=("$name")
  done
  [ "${#survivors[@]}" -eq 0 ] || { echo "end_capture_processes: still running: ${survivors[*]}" >&2; return 1; }
}

show_clean_desktop() {
  swaymsg workspace number 1 >/dev/null
  clean_bar
}

close_all_windows() {
  close_panels
  close_windows
  end_capture_processes
  show_clean_desktop
}

reset_notification_history() {
  systemctl --user stop dms
  rm -f ~/.cache/DankMaterialShell/notification_history.json
  systemctl --user start dms
  wait_for "dms ipc ready" 30 dms_ipc_ready
}

post_notifications() {
  notify-send -a vekrona "vekrona" "Fedora 44 + Sway + DankMaterialShell is ready."
  notify-send -a Ghostty "Update" "Ghostty config reloaded."
  notify-send -a Firefox "Download complete" "vekrona-4k-wallpaper.png"
  dms_call notifications dismissAllPopups >/dev/null
  wait_for_stable_frame "$SCREEN_RIGHT_HALF"
}

clear_clipboard_history() {
  dms clipboard clear >/dev/null
}

fill_clipboard() {
  local entry count=0
  clear_clipboard_history
  wait_for "empty clipboard history" 5 clipboard_entry_count_is 0
  for entry in \
    'vekrona: Fedora 44 + Sway + DankMaterialShell' \
    './install.sh --skip 10-nvidia 70' \
    'vekrona-theme gruvbox-dark' \
    'Hyper+Space opens Spotlight' \
    'github.com/vekrona/vekrona'
  do
    dms clipboard copy "$entry" >/dev/null
    count=$((count + 1))
    wait_for "clipboard entry $count recorded" 5 clipboard_entry_count_is "$count"
  done
}

park_cursor() {
  swaymsg seat seat0 cursor set 1919 1079 >/dev/null
}

grab_screen_png() {
  park_cursor
  timeout "$GRIM_TIMEOUT" grim -
}

recorder_active() {
  systemctl --user is-active --quiet "$RECORDER_UNIT"
}

recorder_failed() {
  systemctl --user is-failed --quiet "$RECORDER_UNIT"
}

recorder_has_opened_output() {
  grep -q 'Output #0' "$RECORDER_LOG"
}

recorder_log_has_dropped_frames() {
  grep -q '^Failed' "$RECORDER_LOG"
}

recorder_recording() {
  recorder_active || { echo "wf-recorder is not running; its log:"; cat "$RECORDER_LOG"; return "$WAIT_FOR_ABORT_STATUS"; }
  recorder_has_opened_output && [ -s "$CLIP_PATH" ]
}

start_recording() {
  recorder_active && { echo "refusing to record: $RECORDER_UNIT is already running" >&2; return 1; }
  ! recorder_failed || systemctl --user reset-failed "$RECORDER_UNIT"
  rm -f "$CLIP_PATH"
  park_cursor
  systemd-run --user --quiet --unit="$RECORDER_UNIT" \
    -p KillSignal=SIGINT -p TimeoutStopSec=15 \
    -p StandardOutput="truncate:$RECORDER_LOG" \
    -E WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    wf-recorder -f "$CLIP_PATH" -g "0,0 1920x1080" -r 30
  wait_for "wf-recorder to start writing $CLIP_PATH" 10 recorder_recording
}

stop_recording() {
  recorder_active || { echo "wf-recorder stopped before the clip ended; its log:" >&2; cat "$RECORDER_LOG" >&2; return 1; }
  systemctl --user stop "$RECORDER_UNIT"
  if recorder_failed || recorder_log_has_dropped_frames; then
    echo "wf-recorder did not finish cleanly; its log:" >&2
    cat "$RECORDER_LOG" >&2
    return 1
  fi
  [ -s "$CLIP_PATH" ] || { echo "wf-recorder left no video at $CLIP_PATH" >&2; return 1; }
}

request_sway_exit() {
  # sway exits before it can answer, so swaymsg reports a failed IPC read; the caller waits for the session to be gone
  swaymsg exit >/dev/null 2>&1 || true
}

stop_recorder() {
  ! recorder_active || systemctl --user stop "$RECORDER_UNIT"
}

restore_theme() {
  theme_is "$DEFAULT_THEME" || restore_default_theme
}

restart_tray() {
  ! systemctl --user is-enabled --quiet "$TRAY_UNIT" || systemctl --user restart "$TRAY_UNIT"
}

release_idle_inhibitor() {
  dms_call inhibit disable >/dev/null
}

restore_step() {
  local description="$1" status; shift
  # errexit is ignored for everything that runs as the condition of ||, && or if, so the step gets a subshell outside any condition
  set +e
  ( set -e; "$@" )
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "restored: $description"
  else
    echo "NOT restored: $description (exit $status)" >&2
    RESTORE_FAILURES+=("$description")
  fi
}

restore_desktop() {
  RESTORE_FAILURES=()
  restore_step "the session is unlocked and the output is on" ensure_desktop_ready
  restore_step "the screen recorder is stopped" stop_recorder
  restore_step "the panels are closed" close_panels
  restore_step "the windows are closed" close_windows
  restore_step "no capture process is left" end_capture_processes
  restore_step "workspace 1 shows a clean bar" show_clean_desktop
  restore_step "the previous avatar is back" restore_avatar
  restore_step "the clipboard history is empty" clear_clipboard_history
  restore_step "the notification history is dropped" reset_notification_history
  restore_step "the theme is $DEFAULT_THEME" restore_theme
  restore_step "$TRAY_UNIT is restarted" restart_tray
  restore_step "the idle inhibitor is released" release_idle_inhibitor
  restore_step "the site server is stopped and port $SITE_PORT is free" stop_site_server
  restore_step "$REMOTE_DIR is removed" rm -rf "$REMOTE_DIR"
  if [ "${#RESTORE_FAILURES[@]}" -gt 0 ]; then
    echo "restore_desktop: could not restore:" >&2
    printf '  - %s\n' "${RESTORE_FAILURES[@]}" >&2
    return 1
  fi
}

leftovers_of_earlier_run_exist() {
  [ -e "$REMOTE_DIR" ] || site_unit_loaded || recorder_active
}

restore_leftovers_of_earlier_run() {
  leftovers_of_earlier_run_exist || return 0
  echo "restore_leftovers_of_earlier_run: an earlier capture run did not finish, restoring the guest first" >&2
  restore_desktop
}

require_terminal_preconditions() {
  [ -f "$VEKRONA_CHECKOUT/$INSTALLER_SCRIPT" ] || { echo "no $VEKRONA_CHECKOUT/$INSTALLER_SCRIPT in the guest: clone the vekrona repo to $VEKRONA_CHECKOUT" >&2; return 1; }
  command -v vekrona-rollback >/dev/null || { echo "vekrona-rollback is not installed in the guest" >&2; return 1; }
  [ -x "$SNAPSHOT_BIN" ] || { echo "$SNAPSHOT_BIN is missing or not executable" >&2; return 1; }
  sudo -n -l "$SNAPSHOT_BIN" >/dev/null 2>&1 || { echo "sudo -n may not run $SNAPSHOT_BIN without a password" >&2; return 1; }
}

snippet_command() {
  local shown="$1" tail_lines="$2" expected_status="$3" expected_prefix="$4"; shift 4
  local output status=0
  output="$("$@" 2>&1 </dev/null)" || status=$?
  if [ "$status" -ne "$expected_status" ] || [[ "$output" != "$expected_prefix"* ]]; then
    echo "terminal snippet: '$shown' ($*) exited with $status (expected $expected_status) and printed:" >&2
    printf '%s\n' "$output" >&2
    [ -z "$expected_prefix" ] || echo "(its output was expected to start with '$expected_prefix')" >&2
    return 1
  fi
  printf '$ %s\n%s\n\n' "$shown" "$(printf '%s\n' "$output" | tail -n "$tail_lines")" >>"$TERMINAL_SNIPPET"
}

open_snippet_terminal() {
  install_terminal -e bash -c "'cat $TERMINAL_SNIPPET; exec bash'"
  wait_for_terminal_window
  wait_for_stable_frame "$SCREEN_BELOW_BAR"
}

build_terminal_snippet() {
  require_terminal_preconditions
  : >"$TERMINAL_SNIPPET"
  snippet_command "vekrona-rollback --help" 20 1 "usage: vekrona-rollback" vekrona-rollback --help
  snippet_command "sudo vekrona-snapshot \"$SNAPSHOT_DESCRIPTION\"" 20 0 "" sudo -n "$SNAPSHOT_BIN" "$SNAPSHOT_DESCRIPTION"
  snippet_command "./$INSTALLER_SCRIPT ${INSTALLER_ARGS[*]}" 22 0 "" "$VEKRONA_CHECKOUT/$INSTALLER_SCRIPT" "${INSTALLER_ARGS[@]}"
}
