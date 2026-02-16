BEGIN {
  print "grpc_health|gRPC Health|adapter+awk|Probe endpoints and normalize SERVING status"
  print "stream_lag|Stream Lag|awk|Summarize per-stream lag from timestamped events"
  print "tail_errors|Tail Errors|awk|Count ERROR/WARN/INFO in recent log lines"
  print "daemon_status|Daemon Status|adapter|Inspect systemd active state for unit list"
}
