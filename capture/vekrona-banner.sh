#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
RESET='\033[0m'

printf '%b\n' "${CYAN}${BOLD}"
cat <<'BANNER'
 __   __      _
 \ \ / /___ _| |_ _ _ ___ _ _  __ _
  \ V / -_) ' \ '_| '_/ _ \ ' \/ _` |
   \_/\___|_||_|_| |_| \___/_||_\__,_|
BANNER
printf '%b\n' "${RESET}"

printf '%b%-14s%b %s\n' "$MAGENTA" "OS" "$RESET" "$(. /etc/os-release && echo "$PRETTY_NAME")"
printf '%b%-14s%b %s\n' "$MAGENTA" "Kernel" "$RESET" "$(uname -r)"
printf '%b%-14s%b %s\n' "$MAGENTA" "Desktop" "$RESET" "Sway $(sway --version | awk '{print $3}') + DankMaterialShell"
printf '%b%-14s%b %s\n' "$MAGENTA" "Uptime" "$RESET" "$(uptime -p)"
printf '%b%-14s%b %s\n' "$MAGENTA" "Memory" "$RESET" "$(free -h | awk '/^Mem:/{print $3 " / " $2}')"
printf '%b%-14s%b %s\n' "$MAGENTA" "Disk (/)" "$RESET" "$(df -h / | awk 'NR==2{print $3 " / " $2 " (" $5 " used)"}')"
printf '%b%-14s%b %s\n' "$MAGENTA" "Shell" "$RESET" "$SHELL"
printf '\n'
printf '%b%s%b\n' "$DIM" "github.com/vekrona/vekrona" "$RESET"
