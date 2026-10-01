source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

VEKRONA_REPO="$SITE_REPO/../vekrona"
VM_MAKEFILE_DIR="$VEKRONA_REPO/vm"
VM_NAME="${VM_NAME:-vekrona-test}"
VM_USER="${VM_USER:-vekrona}"
VM_PASSWORD="${VM_PASSWORD:-vekrona}"
VM_HARNESS_KEY="$VM_MAKEFILE_DIR/.ssh/id_ed25519"
LIBVIRT_URI=qemu:///system
SCREEN_SIZE=1920x1080

[ -f "$VM_HARNESS_KEY" ] || fail "no harness SSH key at $VM_HARNESS_KEY (the sibling vekrona checkout with its vm/ harness is required)"
require_commands virsh ssh scp make tar awk cut head sha256sum date mktemp magick ffmpeg ffprobe openssl certutil flock tesseract

mkdir -p "$OUT_DIR" "$RAW_DIR" "$ASSETS_IMG_DIR" "$ASSETS_VIDEO_DIR"

SSH_OPTS=(-F /dev/null -o IdentitiesOnly=yes -o IdentityAgent=none -i "$VM_HARNESS_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

vm_ip() {
  local leases
  leases="$(virsh -c "$LIBVIRT_URI" domifaddr "$VM_NAME" --source lease)" \
    || { echo "lib.sh: virsh could not query domain '$VM_NAME' on $LIBVIRT_URI (wrong VM_NAME, libvirt not running, or no permission)" >&2; return 1; }
  awk '/ipv4/{print $4}' <<<"$leases" | cut -d/ -f1 | head -1
}

VM_IP="$(vm_ip)"
[ -n "$VM_IP" ] || fail "domain '$VM_NAME' on $LIBVIRT_URI has no IPv4 lease (is it running and booted?)"

vm_ssh() {
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_IP" "$@"
}

# shellcheck disable=SC2016
GUEST_SCRIPT_RUNNER='script="$(mktemp)" && cat >"$script" && { status=0; bash "$script" </dev/null || status=$?; rm -f "$script"; exit "$status"; }'

vm_exec() {
  { cat "$CAPTURE_DIR/shared.sh" "$CAPTURE_DIR/remote.sh"; printf '\n'; cat; } | vm_ssh "$GUEST_SCRIPT_RUNNER"
}

guest_query() {
  local status=0
  vm_ssh "$@" || status=$?
  if [ "$status" -gt 1 ]; then
    echo "ssh to $VM_USER@$VM_IP failed (exit $status) while running: $*" >&2
    return "$WAIT_FOR_ABORT_STATUS"
  fi
  return "$status"
}

vm_scp_from() {
  scp "${SSH_OPTS[@]}" "$VM_USER@$VM_IP:$1" "$2" >/dev/null
}

vm_scp_to() {
  scp "${SSH_OPTS[@]}" "$1" "$VM_USER@$VM_IP:$2" >/dev/null
}

vm_make() {
  make --no-print-directory -C "$VM_MAKEFILE_DIR" VM_NAME="$VM_NAME" VM_USER="$VM_USER" "$@"
}

vm_type() {
  if [ "$1" = " " ]; then
    vm_key KEY_SPACE
  else
    vm_make type TEXT="$1" >/dev/null
  fi
}

vm_key() {
  vm_make key KEYS="$1" >/dev/null
}

vm_hyper_key() {
  vm_key "KEY_LEFTCTRL KEY_LEFTALT KEY_LEFTMETA $1"
}

vm_hyper_shift_key() {
  vm_key "KEY_LEFTCTRL KEY_LEFTALT KEY_LEFTMETA KEY_LEFTSHIFT $1"
}

assert_media_size() {
  local path="$1" size
  size="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$path")" \
    || { echo "$path is not a readable image or video" >&2; return 1; }
  [ "$size" = "$SCREEN_SIZE" ] || { echo "$path is $size, expected $SCREEN_SIZE" >&2; return 1; }
}

move_checked_media() {
  local partial="$1" final="$2"
  if ! assert_media_size "$partial"; then
    rm -f "$partial"
    return 1
  fi
  publish_files "$partial" "$final"
}

vm_capture_png() {
  local local_path="$1" partial="$1.partial"
  if ! vm_exec <<<'grab_screen_png' >"$partial"; then
    rm -f "$partial"
    echo "could not grab the guest screen into $local_path" >&2
    return 1
  fi
  move_checked_media "$partial" "$local_path"
}

vm_screenshot_ppm() {
  virsh -c "$LIBVIRT_URI" screenshot "$VM_NAME" "$1" >/dev/null
}

vm_screenshot_ppm_to_png() {
  local local_path="$1" ppm="$HOST_TMP_DIR/screen.ppm"
  vm_screenshot_ppm "$ppm"
  magick "$ppm" "$local_path"
}

vm_record_start() {
  vm_exec <<<'start_recording'
}

vm_record_stop() {
  vm_exec <<<'stop_recording'
  vm_scp_from "$REMOTE_DIR/clip.mp4" "$1" || { echo "could not copy the recording from the guest into $1" >&2; return 1; }
}
