#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
unit="${2:-hawk-agent.service}"

if [[ -z "$action" ]]; then
  echo "missing action"
  exit 2
fi

if [[ "$action" == "health" || "$action" == "status" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status "$unit" --no-pager 2>/dev/null || systemctl --user status "$unit" --no-pager 2>/dev/null || true
    exit 0
  fi
  echo "systemctl not found"
  exit 0
fi

if command -v systemctl >/dev/null 2>&1; then
  if systemctl "$action" "$unit" 2>/dev/null; then
    echo "system scope ok"
    exit 0
  fi
  if systemctl --user "$action" "$unit" 2>/dev/null; then
    echo "user scope ok"
    exit 0
  fi
fi

echo "unable to $action $unit"
exit 1
