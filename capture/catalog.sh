# shellcheck disable=SC2034
SCREENSHOT_NAMES=(
  hero spotlight control-center notifications clipboard keybindings
  theme-tokyo-night theme-catppuccin-mocha theme-gruvbox-dark
  lock terminal-ops greeter
)
CLIP_NAMES=(
  hero spotlight control-center notifications clipboard keybindings
  theme-cycle terminal lock
)

validate_names() {
  local kind="$1" valid="$2" name; shift 2
  for name in "$@"; do
    [[ " $valid " == *" $name "* ]] || {
      echo "${0##*/}: unknown $kind '$name'; valid: $valid" >&2
      return 1
    }
  done
}

validate_screenshot_names() {
  validate_names scene "${SCREENSHOT_NAMES[*]}" "$@"
}

validate_clip_names() {
  validate_names clip "${CLIP_NAMES[*]}" "$@"
}

selection_has() {
  local wanted="$1"; shift
  [[ " $* " == *" $wanted "* ]]
}
