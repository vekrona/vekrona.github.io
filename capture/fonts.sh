# shellcheck disable=SC2034
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

find_jetbrains_mono_nerd_font() {
  local weight="$1" candidate
  for candidate in \
    "/usr/share/fonts/omedora-nerd-fonts/JetBrainsMonoNerdFont-$weight.ttf" \
    "$HOME/.local/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-$weight.ttf" \
    "/usr/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-$weight.ttf"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  fail "no JetBrainsMono Nerd Font $weight.ttf found in known locations"
}

FONT_REGULAR="$(find_jetbrains_mono_nerd_font Regular)"
FONT_BOLD="$(find_jetbrains_mono_nerd_font Bold)"
