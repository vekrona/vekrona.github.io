source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$CAPTURE_DIR/fonts.sh"

CAPTURE_LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/vekrona-capture-$VM_NAME.lock"

acquire_capture_lock() {
  exec {CAPTURE_LOCK_FD}>>"$CAPTURE_LOCK_FILE"
  flock --nonblock "$CAPTURE_LOCK_FD" \
    || fail "another capture run holds the lock for VM $VM_NAME (started as: $(cat "$CAPTURE_LOCK_FILE")); this run changed nothing"
  printf '%s %s\n' "$$" "$*" >"$CAPTURE_LOCK_FILE"
}

acquire_capture_lock "${0##*/}" "$@"

CURRENT_STEP=""
GUEST_TOUCHED=false
HOST_TMP_DIR="$(mktemp -d)"
VM_SCREEN_HASH_FILE="$HOST_TMP_DIR/screen-hash"
THEME_TOAST_SEEN=false
THEME_CYCLE_ATTEMPTS=5
EXIT_STATUS_SIGINT=130
EXIT_STATUS_SIGTERM=143
TERMINAL_CLIP_LEAD_DWELL=0.5
TERMINAL_CLIP_SUBMIT_DWELL=0.4
TERMINAL_CLIP_END_DWELL=2.5
TYPING_INTERVAL=0.12
BAR_CENTER_CROP=400x32+760+8
BAR_CENTER_OCR_SCALE=400%
WEATHER_READING_PATTERN='[0-9]+[^[:space:]]?C[[:space:]]*$'
WEATHER_TIMEOUT=90
LOCK_LEAD_DWELL=1.0
LOCK_READ_DWELL=1.4
LOCK_TYPING_INTERVAL=0.2
LOCK_SUBMIT_DWELL=0.4
LOCK_END_DWELL=1.8
LOCK_BLACK_MAX_LUMA=24
KEYBINDINGS_DWELL=5.0

capture_teardown() {
  echo "capture teardown:"
  vm_exec <<<'restore_desktop'
}

report_exit() {
  local status="$1"
  case "$status" in
    0) ;;
    "$EXIT_STATUS_SIGINT") echo "${0##*/}: ${CURRENT_STEP:-no step} was interrupted by SIGINT" >&2 ;;
    "$EXIT_STATUS_SIGTERM") echo "${0##*/}: ${CURRENT_STEP:-no step} was interrupted by SIGTERM" >&2 ;;
    *) [ -z "$CURRENT_STEP" ] || echo "${0##*/}: $CURRENT_STEP failed (exit $status)" >&2 ;;
  esac
}

finish_capture() {
  local status=$?
  trap - EXIT INT TERM
  report_exit "$status"
  rm -f "$OUT_DIR"/*.partial.mp4 "$RAW_DIR"/*.png.partial
  if [ "$GUEST_TOUCHED" = true ] && ! capture_teardown; then
    echo "${0##*/}: restoring the guest session failed, check it by hand" >&2
    [ "$status" -ne 0 ] || status=1
  fi
  rm -rf "$HOST_TMP_DIR"
  exit "$status"
}
trap finish_capture EXIT
trap 'exit $EXIT_STATUS_SIGINT' INT
trap 'exit $EXIT_STATUS_SIGTERM' TERM

run_step() {
  CURRENT_STEP="$1"; shift
  "$@"
  CURRENT_STEP=""
}

scene_function() {
  echo "scene_${1//-/_}"
}

record_function() {
  echo "record_${1//-/_}"
}

require_defined_functions() {
  local function_name
  for function_name in "$@"; do
    declare -F "$function_name" >/dev/null || fail "$function_name is not defined in scenes.sh, but catalog.sh lists it"
  done
}

require_scene_functions() {
  local name
  for name in "$@"; do
    require_defined_functions "$(scene_function "$name")"
  done
}

require_clip_functions() {
  local name
  for name in "$@"; do
    require_defined_functions "$(record_function "$name")"
  done
}

record_clip() {
  local name="$1" partial="$OUT_DIR/$1.partial.mp4"
  rm -f "$partial"
  "$(record_function "$name")" "$partial"
  move_checked_media "$partial" "$OUT_DIR/$name.mp4"
}

settle() {
  sleep "$1"
}

type_slowly() {
  local text="$1" interval="$2" i
  for ((i = 0; i < ${#text}; i++)); do
    vm_type "${text:i:1}"
    settle "$interval"
  done
}

vm_screen_hash() {
  virsh -c "$LIBVIRT_URI" screenshot "$VM_NAME" "$HOST_TMP_DIR/poll.ppm" >/dev/null \
    && sha256sum <"$HOST_TMP_DIR/poll.ppm"
}

vm_screen_stable_since_last_poll() {
  local baseline="${1:-}" current previous=""
  current="$(vm_screen_hash)" || return "$WAIT_FOR_ABORT_STATUS"
  if [ -f "$VM_SCREEN_HASH_FILE" ]; then
    previous="$(cat "$VM_SCREEN_HASH_FILE")"
  fi
  printf '%s\n' "$current" >"$VM_SCREEN_HASH_FILE"
  [ "$current" != "$baseline" ] && [ "$current" = "$previous" ]
}

wait_for_stable_vm_screen() {
  rm -f "$VM_SCREEN_HASH_FILE"
  wait_for "a stable guest screen" 20 vm_screen_stable_since_last_poll "${1:-}"
}

GREETER_PASSWORD_LABEL_CROP=90x14+332+400

greeter_password_prompt_drawn() {
  local ink
  virsh -c "$LIBVIRT_URI" screenshot "$VM_NAME" "$HOST_TMP_DIR/greeter.ppm" >/dev/null || return "$WAIT_FOR_ABORT_STATUS"
  ink="$(magick "$HOST_TMP_DIR/greeter.ppm" -crop "$GREETER_PASSWORD_LABEL_CROP" +repage -format '%[fx:mean]' info:)" || return "$WAIT_FOR_ABORT_STATUS"
  awk -v ink="$ink" 'BEGIN { exit !(ink > 0.01) }'
}

guest_session_up() {
  guest_query "runtime_dir=/run/user/\$(id -u); [ -S \$runtime_dir/wayland-1 ] && compgen -G \"\$runtime_dir/sway-ipc.*.sock\""
}

guest_session_gone() {
  local status=0
  guest_session_up >/dev/null || status=$?
  case "$status" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$status" ;;
  esac
}

guest_session_unlocked() {
  local locked
  locked="$(vm_exec <<<'lock_status_field sessionLockLocked')" || return "$WAIT_FOR_ABORT_STATUS"
  [ "$locked" = false ]
}

greeter_running() {
  guest_query pgrep -x tuigreet
}

greeter_remembers_user() {
  guest_query sudo -n test -s /var/lib/greetd/tuigreet-lastuser
}

upload_capture_avatar() {
  local avatar="$HOST_TMP_DIR/avatar.png"
  magick -size 256x256 xc:none -fill "#$PALETTE_ACCENT" -draw 'circle 128,128 128,2' \
    -font "$FONT_BOLD" -pointsize 150 -fill "#$PALETTE_BG" -gravity center -annotate +0+5 V "$avatar"
  vm_scp_to "$avatar" "$REMOTE_DIR/avatar.png"
  vm_exec <<<'install_capture_avatar'
}

sync_site() {
  tar -C "$SITE_REPO" -czf - index.html favicon.svg favicon.ico apple-touch-icon.png site.webmanifest assets \
    | vm_ssh "tar -C '$SITE_ROOT' -xzf -"
}

upload_site_tls() {
  local dir="$HOST_TMP_DIR/tls" key_options=(-newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes)
  mkdir "$dir"
  openssl req -x509 "${key_options[@]}" -days 2 -subj "/CN=vekrona capture CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign" \
    -keyout "$dir/ca.key" -out "$dir/ca.pem"
  openssl req "${key_options[@]}" -subj "/CN=$SITE_HOST" -keyout "$dir/server.key" -out "$dir/server.csr"
  openssl x509 -req -in "$dir/server.csr" -CA "$dir/ca.pem" -CAkey "$dir/ca.key" -CAcreateserial -days 2 \
    -extfile <(printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' "$SITE_HOST") \
    -out "$dir/server.pem"
  mkdir "$dir/nss"
  certutil -N -d "sql:$dir/nss" --empty-password
  certutil -A -d "sql:$dir/nss" -n "vekrona capture CA" -t "C,," -i "$dir/ca.pem"
  tar -C "$dir" -czf - ca.pem server.pem server.key nss | vm_ssh "tar -C '$SITE_TLS_DIR' -xzf -"
}

capture_init() {
  GUEST_TOUCHED=true
  vm_exec <<'EOF'
require_guest_commands
restore_leftovers_of_earlier_run
ensure_desktop_ready
rm -rf "$REMOTE_DIR"
mkdir -p "$SITE_ROOT" "$SITE_TLS_DIR"
EOF
  vm_scp_to "$CAPTURE_DIR/vekrona-banner.sh" "$REMOTE_DIR/vekrona-banner.sh"
  vm_scp_to "$CAPTURE_DIR/firefox-user.js" "$REMOTE_DIR/firefox-user.js"
  vm_scp_to "$CAPTURE_DIR/site-server.py" "$REMOTE_DIR/site-server.py"
  upload_site_tls
  sync_site
  vm_exec <<<'start_site_server'
  upload_capture_avatar
  vm_exec <<<'prepare_session'
}

bar_center_reading() {
  local ppm="$HOST_TMP_DIR/bar.ppm" png="$HOST_TMP_DIR/bar-center.png"
  vm_screenshot_ppm "$ppm" || return "$WAIT_FOR_ABORT_STATUS"
  magick "$ppm" -crop "$BAR_CENTER_CROP" +repage -resize "$BAR_CENTER_OCR_SCALE" -colorspace Gray -negate "$png" || return "$WAIT_FOR_ABORT_STATUS"
  tesseract "$png" stdout --psm 7 2>/dev/null | tr -s ' \n' ' ' || return "$WAIT_FOR_ABORT_STATUS"
}

weather_temperature_drawn() {
  local reading
  reading="$(bar_center_reading)" || return "$WAIT_FOR_ABORT_STATUS"
  echo "the middle of the bar reads: ${reading:-nothing}"
  [[ "$reading" =~ $WEATHER_READING_PATTERN ]]
}

wait_for_weather() {
  wait_for "the bar's weather widget to show a temperature (does the guest have working internet and DNS?)" "$WEATHER_TIMEOUT" weather_temperature_drawn
}

begin_scene() {
  vm_exec <<<'ensure_desktop_ready; close_all_windows'
  wait_for_weather
}

empty_notification_history() {
  vm_exec <<<'reset_notification_history'
  wait_for_weather
}

open_background_windows() {
  vm_exec <<<'open_window_pair open_firefox_site'
}

open_theme_windows() {
  vm_exec <<<'open_window_pair open_banner_terminal'
}

scene_hero() {
  begin_scene
  open_background_windows
  vm_capture_png "$1"
}

capture_panel() {
  local panel="$1" out="$2"
  vm_exec <<<"open_dms_panel $panel"
  vm_capture_png "$out"
  vm_exec <<<'close_panels'
}

scene_spotlight() {
  begin_scene
  open_background_windows
  capture_panel spotlight "$1"
}

scene_control_center() {
  begin_scene
  open_background_windows
  capture_panel control-center "$1"
}

scene_notifications() {
  begin_scene
  empty_notification_history
  open_background_windows
  vm_exec <<<'post_notifications'
  capture_panel notifications "$1"
}

scene_clipboard() {
  begin_scene
  open_background_windows
  vm_exec <<<'fill_clipboard'
  capture_panel clipboard "$1"
}

scene_keybindings() {
  begin_scene
  open_background_windows
  vm_exec <<<'open_keybindings_panel'
  vm_capture_png "$1"
  vm_exec <<<'close_keybindings_panel'
}

capture_theme() {
  local theme_name="$1" out="$2"
  begin_scene
  vm_exec <<<"set_theme $theme_name"
  open_theme_windows
  vm_exec <<<'clean_bar; wait_for_focus_chip'
  vm_capture_png "$out"
  vm_exec <<<'restore_default_theme'
}

scene_theme_tokyo_night() {
  capture_theme tokyo-night "$1"
}

scene_theme_catppuccin_mocha() {
  capture_theme catppuccin-mocha "$1"
}

scene_theme_gruvbox_dark() {
  capture_theme gruvbox-dark "$1"
}

scene_lock() {
  local unlocked_screen
  begin_scene
  unlocked_screen="$(vm_screen_hash)"
  vm_exec <<'EOF'
dms_call lock lock >/dev/null
wait_for "session locked" 8 session_locked
EOF
  wait_for_stable_vm_screen "$unlocked_screen"
  vm_screenshot_ppm_to_png "$1"
  vm_exec <<'EOF'
dms_call lock unlock >/dev/null
wait_for "session unlocked" 8 session_unlocked
EOF
}

wait_for_greeter() {
  wait_for "the sway session to exit" 30 guest_session_gone
  wait_for "tuigreet to run" 30 greeter_running
  wait_for "the greeter's password prompt" 30 greeter_password_prompt_drawn
  wait_for_stable_vm_screen
}

vm_relogin() {
  vm_type "$VM_PASSWORD"
  vm_key KEY_ENTER
  wait_for "the graphical session to start" 60 guest_session_up
  vm_exec <<'EOF'
wait_for "dms ipc ready" 30 dms_ipc_ready
wait_for "session unlocked" 10 session_unlocked
wait_for "a 1920x1080 output mode" 15 output_mode_is_1920x1080
prepare_session
EOF
}

require_remembered_greeter_user() {
  local remembered=0
  greeter_remembers_user || remembered=$?
  [ "$remembered" -eq 0 ] || fail "tuigreet has no remembered user (/var/lib/greetd/tuigreet-lastuser is missing or empty); log in once through the greeter first"
}

scene_greeter() {
  local out="$1"
  require_remembered_greeter_user
  vm_exec <<<'request_sway_exit'
  wait_for_greeter
  vm_screenshot_ppm_to_png "$out"
  vm_relogin
}

record_panel_clip() {
  local key="$1" out="$2"
  vm_record_start
  settle 0.5
  vm_hyper_key "$key"
  vm_exec <<<'wait_for_overlay_focus'
  settle 2.0
  vm_hyper_key "$key"
  settle 0.6
  vm_record_stop "$out"
}

record_hero() {
  begin_scene
  open_background_windows
  vm_record_start
  settle 1.2
  vm_hyper_key KEY_2
  settle 1.0
  vm_hyper_key KEY_1
  settle 1.6
  vm_record_stop "$1"
}

record_spotlight() {
  begin_scene
  open_background_windows
  vm_record_start
  settle 0.5
  vm_hyper_key KEY_SPACE
  vm_exec <<<'wait_for_overlay_focus'
  type_slowly ghostty "$TYPING_INTERVAL"
  settle 1.8
  vm_hyper_key KEY_SPACE
  settle 0.6
  vm_record_stop "$1"
}

record_control_center() {
  begin_scene
  open_background_windows
  record_panel_clip KEY_COMMA "$1"
}

record_notifications() {
  begin_scene
  empty_notification_history
  open_background_windows
  vm_exec <<<'post_notifications'
  record_panel_clip KEY_N "$1"
}

record_clipboard() {
  begin_scene
  open_background_windows
  vm_exec <<<'fill_clipboard'
  record_panel_clip KEY_V "$1"
}

record_keybindings() {
  begin_scene
  open_background_windows
  vm_exec <<<'open_keybindings_panel'
  vm_record_start
  settle "$KEYBINDINGS_DWELL"
  vm_key KEY_ESC
  settle 0.6
  vm_record_stop "$1"
}

cycle_theme() {
  local before toast
  before="$(vm_exec <<<'current_theme')"
  [ -n "$before" ] || { echo "the guest reported no current theme before the switch" >&2; return 1; }
  vm_hyper_shift_key KEY_T
  toast="$(vm_exec <<EOF
wait_for "theme switch away from $before" 15 theme_differs_from "$before"
toast_state
clean_bar
wait_for_focus_chip
EOF
)"
  case "$toast" in
    hidden) ;;
    visible:*) THEME_TOAST_SEEN=true ;;
    *) echo "unexpected DMS toast state '$toast' after the theme switch" >&2; return 1 ;;
  esac
}

record_theme_cycle_attempt() {
  begin_scene
  vm_exec <<<'restore_default_theme'
  open_theme_windows
  vm_record_start
  THEME_TOAST_SEEN=false
  settle 0.8
  cycle_theme
  settle 1.4
  cycle_theme
  settle 1.4
  cycle_theme
  settle 1.4
  vm_record_stop "$1"
  vm_exec <<<'restore_default_theme'
}

record_theme_cycle() {
  local attempt
  for ((attempt = 1; attempt <= THEME_CYCLE_ATTEMPTS; attempt++)); do
    record_theme_cycle_attempt "$1"
    if [ "$THEME_TOAST_SEEN" = false ]; then
      return 0
    fi
    echo "${0##*/}: DMS showed an error toast during the theme cycle (attempt $attempt of $THEME_CYCLE_ATTEMPTS), recording again" >&2
  done
  echo "${0##*/}: all $THEME_CYCLE_ATTEMPTS theme cycle recordings showed a DMS error toast" >&2
  return 1
}

record_terminal() {
  vm_exec <<<'require_terminal_preconditions'
  begin_scene
  vm_exec <<<'open_install_terminal'
  vm_record_start
  settle "$TERMINAL_CLIP_LEAD_DWELL"
  type_slowly "./$INSTALLER_SCRIPT ${INSTALLER_ARGS[*]}" "$TYPING_INTERVAL"
  settle "$TERMINAL_CLIP_SUBMIT_DWELL"
  vm_key KEY_ENTER
  vm_exec <<'EOF'
wait_for "the installer to start" 10 installer_running
wait_for "the installer to finish" 120 installer_finished
EOF
  settle "$TERMINAL_CLIP_END_DWELL"
  vm_record_stop "$1"
}

lock_session() {
  vm_hyper_key KEY_ESC
  vm_exec <<<'wait_for "session locked" 8 session_locked'
}

submit_lock_password() {
  vm_key KEY_ENTER
  wait_for "the session to unlock after typing the password" 10 guest_session_unlocked
}

drop_black_frames() {
  local clip="$1" filtered="$HOST_TMP_DIR/lock-filtered.mp4"
  ffmpeg -v error -y -i "$clip" \
    -vf "signalstats,metadata=select:key=lavfi.signalstats.YAVG:value=$LOCK_BLACK_MAX_LUMA:function=greater,fps=30,format=yuv420p" \
    -c:v libx264 -crf 16 "$filtered"
  mv "$filtered" "$clip"
}

record_lock() {
  begin_scene
  open_background_windows
  vm_record_start
  settle "$LOCK_LEAD_DWELL"
  lock_session
  settle "$LOCK_READ_DWELL"
  type_slowly "$VM_PASSWORD" "$LOCK_TYPING_INTERVAL"
  settle "$LOCK_SUBMIT_DWELL"
  submit_lock_password
  settle "$LOCK_END_DWELL"
  vm_record_stop "$1"
  drop_black_frames "$1"
}

scene_terminal_ops() {
  vm_exec <<<'build_terminal_snippet'
  begin_scene
  vm_exec <<<'open_snippet_terminal'
  vm_capture_png "$1"
}
