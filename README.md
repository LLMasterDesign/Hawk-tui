# Hawk-tui

Hawk-tui is a command-first operator console for long-lived, agentic systems.

It combines:
- A Python operator dashboard (`hawk_tui.py`) for rapid terminal operations.
- A Rust event spine and mirror (`hawkd`, `hawk`, `hawk_core`) for structured stream ingest, broadcast, and transform.
- An awk command/packs layer so agents can add operational logic without rewriting the UI core.

## What It Does

- Monitors gRPC health, daemon status, stream lag, and log motion.
- Runs an awk-powered command palette through `bin/hawk-cmd`.
- Supports fake deterministic test data for safe development loops.
- Supports real adapters for systemd and gRPC health checks.
- Provides a Rust HawkFrame pipeline with optional awk transforms and pack validation.

## Architecture At A Glance

```text
publishers/stdin/unix ingest
            |
            v
         hawkd (Rust spine)
   - optional gRPC watchers
   - optional systemd watchers
   - unix socket broadcast
            |
            v
      hawk (Rust mirror TUI)  OR  hawk_tui.py (Python operator TUI)
            |
            v
      awk threads/packs for filtering, mapping, aggregation
```

Core contract: HawkFrame TSV is always 7 tab-separated columns:
`ts kind scope id level msg kv`

## Repo Map

- `hawk_tui.py`: Python 5-box operator TUI.
- `bin/hawk-cmd`: command registry + dispatch (`list`, `run <id>`).
- `awk/commands`: command catalog and awk transforms.
- `adapters`: boundary scripts for gRPC and systemd integration.
- `packs/hawk.core`: pack/thread model for awk transforms.
- `crates/hawk_core`: HawkFrame parser/serializer + severity model.
- `crates/hawkd`: unix socket spine, ingest, watcher fan-in.
- `crates/hawk`: mirror TUI and pack tooling (`pack list/show/doctor`).
- `shell`: fake environment + smoke verification scripts.

## Quick Start (Fake Environment)

Requirements:
- `bash`, `python3`, `awk`
- optional: `gum` for richer boot UX

Run:

```bash
cd /mnt/v/!CENTRAL.CMD/!LAUNCHPAD/Hawk-tui
./shell/run_fake.sh
```

Smoke verify:

```bash
cd /mnt/v/!CENTRAL.CMD/!LAUNCHPAD/Hawk-tui
./shell/verify.sh
```

JSON health snapshot:

```bash
python3 hawk_tui.py --check
```

## Run Against Real Targets

1. Configure gRPC targets and units.
2. Export environment overrides if needed.
3. Start the dashboard.

```bash
export HAWK_GRPC_TARGETS="$(pwd)/conf/3ox.grpc.targets"
export HAWK_UNITS_FILE="$(pwd)/conf/systemd_units.txt"
./run.sh
```

## Rust Workspace Usage

List pack threads:

```bash
cargo run -p hawk -- pack list
```

Show thread schema:

```bash
cargo run -p hawk -- pack show fail_only
```

Run mirror from stdin:

```bash
cargo run -p hawk -- --source stdin
```

Run mirror from unix socket:

```bash
cargo run -p hawk -- --source unix --socket-path /tmp/hawk.sock
```

Run `hawkd` with gRPC watch + mTLS:

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

## Command Palette

Current command IDs:
- `grpc_health`
- `stream_lag`
- `tail_errors`
- `daemon_status`

Add a command:
1. Create awk script or adapter in `awk/commands` or `adapters`.
2. Register it in `awk/commands/cmd_catalog.awk`.
3. Add dispatch in `bin/hawk-cmd`.
4. It auto-appears in the TUI command list.

## Python TUI Keybindings

- `1..4`: switch pages
- `j/k` or arrows: navigate pages
- `[` and `]`: cycle command catalog
- `Enter`: run selected command
- `a/z/e`: daemon start/stop/restart
- `h/u`: daemon health/status
- `m`: append note
- `r`: refresh all polls
- `q`: quit

## Documentation Index

- Docs index: `docs/INDEX.md`
- Onboarding: `docs/ONBOARDING.md`
- Deep dive (agentic TUI patterns): `docs/AGENTIC_TUI_DEEP_DIVE.md`
- Specs overview: `docs/SPECS.md`
- Full project spec: `HAWK-TUI.SPEC.md`
- AWK book: `docs/HAWK.AWK.BOOK.md`
- AWK command cookbook: `docs/awk_command_book.md`
- `hawkd` TLS + mTLS: `docs/hawkd_tls_mtls.md`
- `hawkd` service unit: `docs/hawkd.service`

## Why This Works For Agentic Systems

Hawk-tui keeps the right boundaries:
- Stable data contract (HawkFrame TSV).
- Replaceable behavior layer (awk threads and packs).
- Clear adapter boundary for external systems.
- Keyboard-native operator surface for fast recovery and triage.

Agents can safely add capability by editing scripts/manifests first, instead of mutating core UI runtime paths.
