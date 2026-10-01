# shellcheck disable=SC2034
shopt -s inherit_errexit

SITE_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAPTURE_DIR="$SITE_REPO/capture"
OUT_DIR="$CAPTURE_DIR/out"
RAW_DIR="$OUT_DIR/screenshots"
ASSETS_IMG_DIR="$SITE_REPO/assets/img"
ASSETS_VIDEO_DIR="$SITE_REPO/assets/video"
INDEX_HTML="$SITE_REPO/index.html"

ASSET_MODE=644
PALETTE_BG=11131a
PALETTE_FG=e8e8f0
PALETTE_ACCENT=7aa2f7

source "$CAPTURE_DIR/shared.sh"

fail() {
  echo "${0##*/}: $*" >&2
  exit 1
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null || fail "$command_name not found"
  done
}

publish_files() {
  chmod "$ASSET_MODE" "${@:1:$#-1}"
  mv -- "$@"
}
