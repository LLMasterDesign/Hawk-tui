#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/hawk_tui.py"

if command -v gum >/dev/null 2>&1 && [[ "${NO_GUM_BOOT:-0}" != "1" ]]; then
  gum style --border double --border-foreground 214 --padding "0 2" --foreground 214 --bold "Hawk-tui"
  gum style --foreground 245 "gRPC health + awk command palette"

  if [[ "${NO_GUM_SPIN:-0}" != "1" ]]; then
    gum spin --spinner dot --title "warming command library" -- sleep 0.45
  fi

  gum style --foreground 214 "Launching dashboard"
else
  printf '%s\n' '████████████████████████████████████████'
  printf '%s\n' 'Hawk-tui'
  printf '%s\n' '████████████████████████████████████████'
  echo 'Launching dashboard'
fi

exec python3 "$APP" "$@"
