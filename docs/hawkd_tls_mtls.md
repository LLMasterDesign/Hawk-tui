# ▛▞// hawkd TLS + mTLS runbook :: docs.hawkd.tls
# @ctx ⫸ [grpc.watch.rotation]

## TLS only
```bash
cargo run -p hawkd -- \
  --socket-path /tmp/hawk.sock \
  --source none \
  --watch service:8443,,proto.alpha \
  --grpc-tls-mode tls \
  --grpc-ca /etc/3ox/certs/ca.pem \
  --grpc-domain service
```

## mTLS
```bash
cargo run -p hawkd -- \
  --socket-path /tmp/hawk.sock \
  --source none \
  --watch service:8443,,proto.alpha \
  --grpc-tls-mode mtls \
  --grpc-ca /etc/3ox/certs/ca.pem \
  --grpc-cert /etc/3ox/certs/client.pem \
  --grpc-key /etc/3ox/certs/client.key \
  --grpc-domain service
```

## Connect Hawk UI
```bash
cargo run -p hawk -- --source unix --socket-path /tmp/hawk.sock
```

## TLS truths
- `--grpc-domain` must match cert SAN/CN expectations.
- If you connect by IP, cert must include IP SAN or use DNS.
- `--grpc-ca` is required for private PKI/self-signed chains.
- Watch stream is event-driven; reconnect only on failure.

## Rotation every 90 days
1. Rotate cert/key files in place.
2. Restart `hawkd` via systemd as a controlled lifecycle event.

# :: ∎
