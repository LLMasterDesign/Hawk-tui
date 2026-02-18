#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_DIR="$BASE_DIR/shell/fake_env"
mkdir -p "$FAKE_DIR"

log="$FAKE_DIR/runtime.log"
stream="$FAKE_DIR/stream.events"
targets="$FAKE_DIR/grpc.targets"
grpc_fake="$FAKE_DIR/grpc_health.jsonl"
chat="$BASE_DIR/agent_chat.log"

: > "$log"
: > "$stream"
: > "$grpc_fake"
: > "$chat"

cat > "$targets" <<EOF
127.0.0.1:50051
127.0.0.1:50052
127.0.0.1:50053
EOF

now=$(date +%s)
cat >> "$log" <<EOF
$now INFO hawk boot complete
$now INFO awk library loaded
$now WARN grpc target 127.0.0.1:50052 cold-start
EOF

cat >> "$stream" <<EOF
$now|orders|boot
$now|health|boot
$now|agent|boot
EOF

cat >> "$grpc_fake" <<EOF
127.0.0.1:50051	SERVING	12ms	fake
127.0.0.1:50052	NOT_SERVING	31ms	fake
127.0.0.1:50053	SERVING	9ms	fake
EOF

echo "fake env ready: $FAKE_DIR"
