#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TRON_DIR="${THREEOX_TRON_DIR:-/mnt/v/!CENTRAL.CMD/_TRON/3OX.Ai}"

export HAWK_LOG_FILE="$TRON_DIR/3ox.log"
export HAWK_STREAM_FILE="$TRON_DIR/Pulse/meta/pulse.jsonl"
export HAWK_GRPC_TARGETS="$BASE_DIR/conf/3ox.grpc.targets"
export HAWK_DAEMON_UNIT="3ox-supervisor.service"

exec "$BASE_DIR/run.sh" "$@"
