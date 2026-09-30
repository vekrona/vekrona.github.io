#!/usr/bin/env bash
set -euo pipefail

VEKRONA_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../vekrona" && pwd)"
SITE_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_MAKEFILE_DIR="$VEKRONA_REPO/vm"
VM_NAME="${VM_NAME:-vekrona-test}"
VM_USER="${VM_USER:-vekrona}"
VM_HARNESS_KEY="$VM_MAKEFILE_DIR/.ssh/id_ed25519"

CAPTURE_DIR="$SITE_REPO/capture"
OUT_DIR="$CAPTURE_DIR/out"
ASSETS_IMG_DIR="$SITE_REPO/assets/img"
ASSETS_VIDEO_DIR="$SITE_REPO/assets/video"

mkdir -p "$OUT_DIR" "$ASSETS_IMG_DIR" "$ASSETS_VIDEO_DIR"

SSH_OPTS=(-F /dev/null -o IdentitiesOnly=yes -o IdentityAgent=none -i "$VM_HARNESS_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

vm_ip() {
  virsh -c qemu:///system domifaddr "$VM_NAME" --source lease 2>/dev/null \
    | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1
}

VM_IP="$(vm_ip)"
[[ -n "$VM_IP" ]] || { echo "capture/lib.sh: could not determine $VM_NAME's IPv4 address" >&2; exit 1; }

REMOTE_PREAMBLE='
set -euo pipefail
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export SWAYSOCK="$(ls -t /run/user/1000/sway-ipc.*.sock 2>/dev/null | head -1)"
[ -n "$SWAYSOCK" ] || { echo "no sway-ipc socket under /run/user/1000 (no graphical session logged in?)" >&2; exit 1; }

wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0 max=$((timeout * 5))
  until "$@" >/dev/null 2>&1; do
    waited=$((waited + 1))
    [ "$waited" -lt "$max" ] || { echo "timed out after ${timeout}s waiting for: $desc" >&2; return 1; }
    sleep 0.2
  done
}

tree_has() {
  swaymsg -t get_tree -r | jq -e "$1" >/dev/null 2>&1
}

window_count() {
  swaymsg -t get_tree -r | jq "[.. | objects | select(.app_id? or .window_properties?.class?)] | length"
}

lock_status_field() {
  dms ipc call lock status 2>/dev/null | jq -r ".$1" 2>/dev/null
}

settle() {
  sleep "${1:-0.4}"
}

export -f wait_for tree_has window_count lock_status_field settle

ensure_unlocked() {
  [ "$(lock_status_field sessionLockLocked)" = "true" ] || return 0
  dms ipc call lock unlock >/dev/null
  wait_for "session unlock" 10 bash -c "[ \"\$(dms ipc call lock status | jq -r .sessionLockLocked)\" = false ]"
}
ensure_unlocked
'

vm_exec() {
  { printf '%s\n' "$REMOTE_PREAMBLE"; cat; } | ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_IP" bash -s
}

vm_scp_from() {
  local remote_path="$1" local_path="$2"
  scp "${SSH_OPTS[@]}" "$VM_USER@$VM_IP:$remote_path" "$local_path" >/dev/null
}

vm_scp_to() {
  local local_path="$1" remote_path="$2"
  scp "${SSH_OPTS[@]}" "$local_path" "$VM_USER@$VM_IP:$remote_path" >/dev/null
}

vm_capture_png() {
  local local_path="$1"
  local remote_tmp
  remote_tmp="/tmp/vekrona-capture-$$-$RANDOM.png"
  vm_exec <<EOF
grim "$remote_tmp"
EOF
  vm_scp_from "$remote_tmp" "$local_path"
  vm_exec <<EOF
rm -f "$remote_tmp"
EOF
}

vm_make() {
  make -C "$VM_MAKEFILE_DIR" VM_NAME="$VM_NAME" VM_USER="$VM_USER" "$@"
}

vm_type() {
  vm_make type TEXT="$1"
}

vm_key() {
  vm_make key KEYS="$1"
}

vm_hyper_key() {
  vm_key "KEY_LEFTCTRL KEY_LEFTALT KEY_LEFTMETA $1"
}

settle() {
  sleep "${1:-0.4}"
}

vm_record_start() {
  local remote_path="$1"
  vm_exec <<EOF
rm -f "$remote_path" /tmp/vekrona-record.pid
setsid wf-recorder -f "$remote_path" -g "0,0 1920x1080" -r 30 >/tmp/vekrona-record.log 2>&1 < /dev/null &
disown
echo \$! > /tmp/vekrona-record.pid
wait_for "recording file to appear" 5 test -e /tmp/vekrona-record.pid
EOF
}

vm_record_stop() {
  vm_exec <<'EOF'
pid="$(cat /tmp/vekrona-record.pid)"
kill -INT "$pid"
wait_for "recorder to exit" 10 bash -c "! kill -0 $pid 2>/dev/null"
EOF
}

vm_screenshot_ppm_to_png() {
  local local_path="$1"
  local tmp
  tmp="$(mktemp --suffix=.ppm)"
  virsh -c qemu:///system screenshot "$VM_NAME" "$tmp" >/dev/null
  magick "$tmp" "$local_path"
  rm -f "$tmp"
}
