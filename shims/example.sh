#!/usr/bin/env bash
# ▛▞// shim :: example
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${HAWK_DATA_DIR:-/var/lib/hawk}"

export HAWK_LOG_FILE="${HAWK_LOG_FILE:-$DATA_DIR/runtime.log}"
export HAWK_STREAM_FILE="${HAWK_STREAM_FILE:-$DATA_DIR/stream.events}"
export HAWK_GRPC_TARGETS="${HAWK_GRPC_TARGETS:-$BASE_DIR/conf/grpc.targets.example}"
export HAWK_DAEMON_UNIT="${HAWK_DAEMON_UNIT:-hawkd.service}"

exec "$BASE_DIR/run.sh" "$@"
