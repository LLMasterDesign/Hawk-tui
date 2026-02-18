#!/usr/bin/env bash
set -euo pipefail

UNITS_FILE="${1:-}"

if [[ ! -f "$UNITS_FILE" ]]; then
  exit 0
fi

while IFS= read -r unit; do
  [[ -z "$unit" || "$unit" =~ ^# ]] && continue

  if command -v systemctl >/dev/null 2>&1; then
    status=$(systemctl is-active "$unit" 2>/dev/null || true)
    scope="sys"
    if [[ -z "$status" || "$status" == "unknown" ]]; then
      status=$(systemctl --user is-active "$unit" 2>/dev/null || true)
      scope="user"
    fi
    [[ -z "$status" ]] && status="unknown"
  else
    status="unavailable"
    scope="none"
  fi

  printf "%s\t%s\t%s\n" "$unit" "$status" "$scope"
done < "$UNITS_FILE"
