#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$BASE_DIR/shell/init_fake_env.sh"

export HAWK_LOG_FILE="$BASE_DIR/shell/fake_env/runtime.log"
export HAWK_STREAM_FILE="$BASE_DIR/shell/fake_env/stream.events"
export HAWK_GRPC_TARGETS="$BASE_DIR/shell/fake_env/grpc.targets"
export HAWK_GRPC_FAKE_FILE="$BASE_DIR/shell/fake_env/grpc_health.jsonl"

"$BASE_DIR/shell/emit_fake_activity.sh" 0 0.4 >/tmp/hawk_emit.log 2>&1 &
emit_pid=$!
trap 'kill "$emit_pid" >/dev/null 2>&1 || true' EXIT

exec "$BASE_DIR/run.sh"
