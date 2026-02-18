#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$BASE_DIR/shell/init_fake_env.sh"

export HAWK_LOG_FILE="$BASE_DIR/shell/fake_env/runtime.log"
export HAWK_STREAM_FILE="$BASE_DIR/shell/fake_env/stream.events"
export HAWK_GRPC_TARGETS="$BASE_DIR/shell/fake_env/grpc.targets"
export HAWK_GRPC_FAKE_FILE="$BASE_DIR/shell/fake_env/grpc_health.jsonl"

"$BASE_DIR/shell/emit_fake_activity.sh" 8 0.15 >/tmp/hawk_emit_verify.log 2>&1 &
emit_pid=$!
trap 'kill "$emit_pid" >/dev/null 2>&1 || true' EXIT

out1=$(python3 "$BASE_DIR/hawk_tui.py" --check)
sleep 1
out2=$(python3 "$BASE_DIR/hawk_tui.py" --check)

commands=$(printf '%s\n' "$out2" | awk -F': ' '/"commands"/{gsub(/,/,"",$2);print $2}')
grpc_ok=$(printf '%s\n' "$out2" | awk -F': ' '/"grpc_ok"/{gsub(/,/,"",$2);print $2}')
stream_rows=$(printf '%s\n' "$out2" | awk -F': ' '/"stream_rows"/{gsub(/,/,"",$2);print $2}')
log_size=$(printf '%s\n' "$out2" | awk -F': ' '/"log_size"/{gsub(/,/,"",$2);print $2}')

fail=0
[[ "${commands:-0}" -ge 4 ]] || { echo "FAIL: commands=$commands"; fail=1; }
[[ "${grpc_ok:-0}" -ge 1 ]] || { echo "FAIL: grpc_ok=$grpc_ok"; fail=1; }
[[ "${stream_rows:-0}" -ge 1 ]] || { echo "FAIL: stream_rows=$stream_rows"; fail=1; }
[[ "${log_size:-0}" -gt 0 ]] || { echo "FAIL: log_size=$log_size"; fail=1; }

if [[ "$fail" -eq 1 ]]; then
  echo "verify failed"
  echo "--check #1"
  echo "$out1"
  echo "--check #2"
  echo "$out2"
  exit 1
fi

echo "verify passed"
echo "$out2"
