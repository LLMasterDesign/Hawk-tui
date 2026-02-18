#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_DIR="$BASE_DIR/shell/fake_env"

log="$FAKE_DIR/runtime.log"
stream="$FAKE_DIR/stream.events"
grpc_fake="$FAKE_DIR/grpc_health.jsonl"

count="${1:-0}"       # 0 = infinite
sleep_s="${2:-0.5}"
i=0

while :; do
  i=$((i+1))
  ts=$(date +%s)

  sev="INFO"
  if (( i % 9 == 0 )); then
    sev="ERROR"
  elif (( i % 4 == 0 )); then
    sev="WARN"
  fi

  echo "$ts $sev pulse heartbeat seq=$i" >> "$log"

  stream_name="orders"
  case $((i % 3)) in
    0) stream_name="orders" ;;
    1) stream_name="health" ;;
    2) stream_name="agent" ;;
  esac
  echo "$ts|$stream_name|event_$i" >> "$stream"

  endpoint="127.0.0.1:50051"
  case $((i % 3)) in
    0) endpoint="127.0.0.1:50051" ;;
    1) endpoint="127.0.0.1:50052" ;;
    2) endpoint="127.0.0.1:50053" ;;
  esac

  status="SERVING"
  if (( i % 7 == 0 )); then
    status="NOT_SERVING"
  fi
  latency="$((8 + (i % 40)))ms"
  printf "%s\t%s\t%s\tfake\n" "$endpoint" "$status" "$latency" >> "$grpc_fake"

  if (( count > 0 && i >= count )); then
    break
  fi
  sleep "$sleep_s"
done
