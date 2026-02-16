#!/usr/bin/env bash
set -euo pipefail

TARGETS_FILE="${1:-}"
FAKE_FILE="${2:-}"

emit_from_fake() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  awk -F'\t' 'NF>=4 { latest[$1]=$0 } END { for (e in latest) print latest[e] }' "$file"
}

emit_from_grpcurl() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  if ! command -v grpcurl >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r endpoint; do
    [[ -z "$endpoint" || "$endpoint" =~ ^# ]] && continue

    start_ms=$(date +%s%3N)
    out=""
    if out=$(grpcurl -plaintext -max-time 2 "$endpoint" grpc.health.v1.Health/Check 2>&1); then
      status="NOT_SERVING"
      if echo "$out" | grep -q '"status"[[:space:]]*:[[:space:]]*"SERVING"'; then
        status="SERVING"
      fi
    else
      status="UNREACHABLE"
    fi
    end_ms=$(date +%s%3N)
    latency="$((end_ms-start_ms))ms"

    printf "%s\t%s\t%s\tgrpcurl\n" "$endpoint" "$status" "$latency"
  done < "$file"
}

emit_fallback_unknown() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  while IFS= read -r endpoint; do
    [[ -z "$endpoint" || "$endpoint" =~ ^# ]] && continue
    printf "%s\tUNKNOWN\t0ms\tfallback\n" "$endpoint"
  done < "$file"
}

if [[ -n "$FAKE_FILE" ]] && emit_from_fake "$FAKE_FILE"; then
  exit 0
fi

if [[ -n "$TARGETS_FILE" ]] && emit_from_grpcurl "$TARGETS_FILE"; then
  exit 0
fi

emit_fallback_unknown "$TARGETS_FILE"
