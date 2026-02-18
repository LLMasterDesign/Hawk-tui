#!/usr/bin/env bash
set -euo pipefail

# ▛▞ 5TRATA Installer TUI :: Layer-by-layer installation with map preview
# 4-pane contract: Setup | Status | Action Bar | Last
# Uses tui2go pattern from hawk

# Ensure UTF-8 encoding
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Check if terminal supports UTF-8, use ASCII fallback if not
USE_ASCII_BOXES=0
if command -v locale >/dev/null 2>&1; then
  if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then
    USE_ASCII_BOXES=1
  fi
else
  # If locale command not available, try to detect
  if [[ -z "${LANG:-}" ]] || [[ "$LANG" != *"UTF-8"* ]] && [[ "$LANG" != *"utf8"* ]]; then
    USE_ASCII_BOXES=1
  fi
fi

# Test if terminal can actually render Unicode box characters
# Even if UTF-8 is reported, the font might not support the characters
if [[ "$USE_ASCII_BOXES" == "0" ]]; then
  # Try to render a test box character and check if it's garbled
  test_output="$(printf '┌' 2>&1)"
  # If output contains replacement character or is empty, use ASCII
  if [[ -z "$test_output" ]] || [[ "$test_output" == *""* ]] || [[ "$test_output" == *"?"* ]]; then
    USE_ASCII_BOXES=1
  fi
  # Also check terminal type - some terminals report UTF-8 but can't render
  if [[ -n "${TERM:-}" ]] && [[ "$TERM" == "dumb" ]] || [[ "$TERM" == *"ansi"* ]]; then
    USE_ASCII_BOXES=1
  fi
fi
export USE_ASCII_BOXES

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SELF_DIR" && pwd)"

X_DRIVE="${X_DRIVE:-/mnt/x}"
SETS_FILE="${SETS_FILE:-$ROOT_DIR/5trata-sets.yml}"

PROFILE="${STRATA_PROFILE:-strata}"
TUI2GO_REFRESH_S="${TUI2GO_REFRESH_S:-2}"
TUI2GO_THEME="${TUI2GO_THEME:-neo}"

SELECTED_SET="cmd"
CURRENT_LAYER=0
INSTALLED_LAYERS=()
LAST_MSG="ready"
LAST_OUTPUT=""
TICK=0

THEME_ORDER=("neo" "amber" "acid" "mono")

ESC=$'\033['
RESET="${ESC}0m"

C_BORDER=""
C_TITLE=""
C_BODY=""
C_ACCENT=""
C_MUTED=""
C_HOT=""
C_SUCCESS=""
C_WARNING=""

apply_theme() {
  case "$TUI2GO_THEME" in
    neo)
      C_BORDER="${ESC}38;5;45m"
      C_TITLE="${ESC}38;5;214;1m"
      C_BODY="${ESC}38;5;252m"
      C_ACCENT="${ESC}38;5;51m"
      C_MUTED="${ESC}38;5;244m"
      C_HOT="${ESC}38;5;196m"
      C_SUCCESS="${ESC}38;5;46m"
      C_WARNING="${ESC}38;5;220m"
      ;;
    amber)
      C_BORDER="${ESC}38;5;214m"
      C_TITLE="${ESC}38;5;220;1m"
      C_BODY="${ESC}38;5;255m"
      C_ACCENT="${ESC}38;5;178m"
      C_MUTED="${ESC}38;5;245m"
      C_HOT="${ESC}38;5;160m"
      C_SUCCESS="${ESC}38;5;46m"
      C_WARNING="${ESC}38;5;220m"
      ;;
    acid)
      C_BORDER="${ESC}38;5;46m"
      C_TITLE="${ESC}38;5;46;1m"
      C_BODY="${ESC}38;5;255m"
      C_ACCENT="${ESC}38;5;255m"
      C_MUTED="${ESC}38;5;245m"
      C_HOT="${ESC}38;5;196m"
      C_SUCCESS="${ESC}38;5;46m"
      C_WARNING="${ESC}38;5;220m"
      ;;
    mono)
      C_BORDER="${ESC}37m"
      C_TITLE="${ESC}97;1m"
C_BODY="${ESC}37m"
      C_ACCENT="${ESC}97m"
C_MUTED="${ESC}90m"
      C_HOT="${ESC}91m"
C_SUCCESS="${ESC}32m"
C_WARNING="${ESC}33m"
      ;;
    *)
      TUI2GO_THEME="neo"
      apply_theme
      return
      ;;
  esac
}

next_theme() {
  local i
  for i in "${!THEME_ORDER[@]}"; do
    if [[ "${THEME_ORDER[$i]}" == "$TUI2GO_THEME" ]]; then
      TUI2GO_THEME="${THEME_ORDER[$(((i + 1) % ${#THEME_ORDER[@]}))]}"
      apply_theme
      LAST_MSG="theme :: $TUI2GO_THEME"
      return
    fi
  done
  TUI2GO_THEME="neo"
  apply_theme
}

repeat_char() {
  local n="$1"
  local ch="$2"
  if (( n <= 0 )); then
    return
  fi
  printf "%*s" "$n" "" | tr ' ' "$ch"
}

# Box drawing characters with ASCII fallback
if [[ "${USE_ASCII_BOXES:-0}" == "1" ]]; then
  BOX_TL="+"
  BOX_TR="+"
  BOX_BL="+"
  BOX_BR="+"
  BOX_H="-"
  BOX_V="|"
  BOX_TJ="+"
else
  BOX_TL="┌"
  BOX_TR="┐"
  BOX_BL="└"
  BOX_BR="┘"
  BOX_H="─"
  BOX_V="│"
  BOX_TJ="├"
fi

terminal_cols() {
  local cols
  cols="$(tput cols 2>/dev/null || true)"
  if [[ -z "$cols" ]] || ! [[ "$cols" =~ ^[0-9]+$ ]]; then
    cols=120
  fi
  if (( cols < 84 )); then
    cols=84
  fi
  printf '%s' "$cols"
}

spinner_frame() {
  local frames=("[/]" "[|]" "[\\]" "[-]" "[\\]" "[|]")
  printf '%s' "${frames[$((TICK % ${#frames[@]}))]}"
}

blank_block_line() {
  local width="$1"
  printf "%${width}s" ""
}

render_block() {
  local title="$1"
  local content="$2"
  local width="$3"
  local inner=$((width - 2))
  local bodyw=$((inner - 1))
  local rule
  rule="$(repeat_char "$inner" "$BOX_H")"

  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_TL" "$rule" "$BOX_TR" "$RESET"
  printf '%b%s%b%-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_TITLE" "$inner" " $title" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_TJ" "$rule" "$BOX_TJ" "$RESET"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      printf '%b%s%b%-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_BODY" "$inner" "" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
      continue
    fi
    while IFS= read -r wrapped || [[ -n "$wrapped" ]]; do
      printf '%b%s%b %-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_BODY" "$bodyw" "$wrapped" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
    done < <(printf '%s\n' "$line" | fold -s -w "$bodyw")
  done <<< "$content"

  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_BL" "$rule" "$BOX_BR" "$RESET"
}

render_two_pane() {
  local left_title="$1"
  local left_content="$2"
  local right_title="$3"
  local right_content="$4"
  local cols pane_width
  cols="$(terminal_cols)"
  pane_width=$(((cols - 2) / 2 - 1))
  if (( pane_width < 38 )); then
    pane_width=38
  fi

  local left_tmp right_tmp
  left_tmp="$(mktemp)"
  right_tmp="$(mktemp)"
  render_block "$left_title" "$left_content" "$pane_width" > "$left_tmp"
  render_block "$right_title" "$right_content" "$pane_width" > "$right_tmp"

  local left_lines right_lines max i l r
  mapfile -t left_lines < "$left_tmp"
  mapfile -t right_lines < "$right_tmp"
  rm -f "$left_tmp" "$right_tmp"

  max=${#left_lines[@]}
  if (( ${#right_lines[@]} > max )); then
    max=${#right_lines[@]}
  fi

  for ((i = 0; i < max; i++)); do
    l="${left_lines[$i]:-$(blank_block_line "$pane_width") }"
    r="${right_lines[$i]:-$(blank_block_line "$pane_width") }"
    printf '%s  %s\n' "$l" "$r"
  done
}

draw_action_bar() {
  local cols inner rule
  cols="$(terminal_cols)"
  inner=$((cols - 2))
  rule="$(repeat_char "$inner" "$BOX_H")"

  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_TL" "$rule" "$BOX_TR" "$RESET"
  printf '%b%s%b%-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_TITLE" "$inner" " Action Bar" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_TJ" "$rule" "$BOX_TJ" "$RESET"
  printf '%b%s%b %-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_ACCENT" $((inner - 1)) "[1-3] set  [i] install  [v] validate  [t] theme  [m] map  [q] quit" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_BL" "$rule" "$BOX_BR" "$RESET"
}

draw_last_panel() {
  local cols inner rule
  cols="$(terminal_cols)"
  inner=$((cols - 2))
  rule="$(repeat_char "$inner" "$BOX_H")"

  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_TL" "$rule" "$BOX_TR" "$RESET"
  printf '%b%s%b%-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_TITLE" "$inner" " Last" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_TJ" "$rule" "$BOX_TJ" "$RESET"
  printf '%b%s%b %-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_MUTED" $((inner - 1)) "$LAST_MSG" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"

  if [[ -n "$LAST_OUTPUT" ]]; then
    while IFS= read -r line; do
      printf '%b%s%b %-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_BODY" $((inner - 1)) "$line" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
    done < <(printf '%s\n' "$LAST_OUTPUT" | tail -n 6 | fold -s -w $((inner - 1)))
  else
    printf '%b%s%b %-*s%b%s%b\n' "$C_BORDER" "$BOX_V" "$C_BODY" $((inner - 1)) "no action output yet" "$RESET" "$C_BORDER" "$BOX_V" "$RESET"
  fi

  printf '%b%s%s%s%b\n' "$C_BORDER" "$BOX_BL" "$rule" "$BOX_BR" "$RESET"
}

setup_snapshot() {
  cat <<SETUP
x_drive    $X_DRIVE
sets_file  $SETS_FILE
profile    $PROFILE
theme      $TUI2GO_THEME
selected   $SELECTED_SET
layer      $CURRENT_LAYER
installed  ${INSTALLED_LAYERS[*]:-none}
SETUP
}

status_snapshot() {
  local status=""
  if [[ ${#INSTALLED_LAYERS[@]} -eq 0 ]]; then
    status="not started"
  elif [[ ${#INSTALLED_LAYERS[@]} -eq 6 ]]; then
    status="${C_SUCCESS}complete${RESET}"
  else
    status="in progress (${#INSTALLED_LAYERS[@]}/6)"
  fi
  
  cat <<STATUS
status     $status
layers     0:CMD 1:Bases 2:Stations
           3:Services 4:Agents 5:systemd
SETS       CMD (default)
           Minimal
           Custom
STATUS
}

run_action() {
  local action="$1"
  shift
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    LAST_MSG="ok :: $action"
  else
    LAST_MSG="fail($rc) :: $action"
  fi
  LAST_OUTPUT="$out"
}

draw_screen() {
  local setup status
  setup="$(setup_snapshot)"
  status="$(status_snapshot)"

  printf '\033[H\033[2J'
  printf '%b%s ▛▞ // 2GO // %s%b\n' "$C_TITLE" "$(spinner_frame)" "5TRATA INSTALLER" "$RESET"
  printf '%btheme=%s  4-pane layout%b\n\n' "$C_MUTED" "$TUI2GO_THEME" "$RESET"
  render_two_pane "Setup" "$setup" "Status" "$status"
  printf '\n'
  draw_action_bar
  draw_last_panel
}

cmd_run() {
  if ! [[ -t 0 && -t 1 ]]; then
    echo "tui2go requires an interactive terminal (TTY)." >&2
    exit 2
  fi

  apply_theme
  while true; do
    draw_screen
    if IFS= read -rsn1 -t "$TUI2GO_REFRESH_S" key; then
      case "$key" in
        "1")
          SELECTED_SET="cmd"
          LAST_MSG="set :: CMD (default)"
          ;;
        "2")
          SELECTED_SET="minimal"
          LAST_MSG="set :: Minimal"
          ;;
        "3")
          SELECTED_SET="custom"
          LAST_MSG="set :: Custom"
          ;;
        "i"|"I")
          if [[ $CURRENT_LAYER -lt 6 ]]; then
            local layers=("CMD" "Bases" "Stations" "Services" "Agents" "systemd")
            local layer_name="${layers[$CURRENT_LAYER]}"
            local install_script="$ROOT_DIR/install-layer${CURRENT_LAYER}.sh"
            if [[ -f "$install_script" ]]; then
              run_action "install-layer-$CURRENT_LAYER" bash "$install_script" "$X_DRIVE"
              if [[ $? -eq 0 ]]; then
                INSTALLED_LAYERS+=("$CURRENT_LAYER")
                CURRENT_LAYER=$((CURRENT_LAYER + 1))
              fi
            else
              LAST_MSG="fail :: script missing"
              LAST_OUTPUT="install-layer${CURRENT_LAYER}.sh not found"
            fi
          else
            LAST_MSG="info :: all layers installed"
          fi
          ;;
        "v"|"V")
          if [[ ${#INSTALLED_LAYERS[@]} -gt 0 ]]; then
            local last_layer="${INSTALLED_LAYERS[-1]}"
            local validate_script="$ROOT_DIR/validate-5trata.sh"
            if [[ -f "$validate_script" ]]; then
              run_action "validate-layer-$last_layer" bash "$validate_script" "$last_layer" "$X_DRIVE"
            else
              LAST_MSG="warn :: validation script missing"
            fi
          else
            LAST_MSG="info :: install a layer first"
          fi
          ;;
        "t"|"T")
          next_theme
          ;;
        "m"|"M")
          LAST_MSG="map :: installation preview"
          LAST_OUTPUT="Layer 0: CMD (!CENTRAL.CMD/_TRON/3OX.Ai/)
Layer 1: Bases (CITADEL.BASE, OBSIDIAN.BASE)
Layer 2: Stations (service providers)
Layer 3: Services ((4)Toolkit/)
Layer 4: Agents (skills.md, sparkfile.md)
Layer 5: systemd (.vec3/, _meta/, _TRON/)"
          ;;
        "q"|"Q")
          break
          ;;
        *)
          LAST_MSG="key ignored :: $key"
          ;;
      esac
    fi
    TICK=$((TICK + 1))
  done
}

case "${1:-run}" in
  run|2go|tui)
    cmd_run "$@"
    ;;
  *)
    echo "Usage: $0 [run|2go|tui]"
    exit 1
    ;;
esac

# :: ∎
