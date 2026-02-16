# Hawk-tui Onboarding

This guide gets a new operator or contributor productive quickly.

## 1. What You Are Running

Hawk-tui has two tracks:
- Python operator TUI (`hawk_tui.py`) for fast dashboard operations.
- Rust spine/mirror (`hawkd`, `hawk`, `hawk_core`) for structured event ingest and transform.

## 2. Prerequisites

Required:
- `bash`
- `python3`
- `awk`

Recommended:
- `cargo`, `rustc`, `rustup`
- `tmux`
- `asdf` with Erlang/Elixir plugins if you are using broader BEAM workflows

Optional:
- `gum` for polished startup output
- `grpcurl` for real gRPC health probing

## 3. First Run (Deterministic Fake Environment)

```bash
cd /mnt/v/!CENTRAL.CMD/!LAUNCHPAD/Hawk-tui
./shell/run_fake.sh
```

What this does:
- Creates fake logs, streams, and gRPC health files.
- Starts an emitter that keeps motion alive.
- Launches the operator TUI against predictable local data.

## 4. Validate Installation

```bash
./shell/verify.sh
```

Expected result: `verify passed`

You can also run:

```bash
python3 hawk_tui.py --check
```

Expected JSON keys include:
- `commands`
- `grpc_ok`
- `stream_rows`
- `log_size`

## 5. Understand The Command Surface

List catalog entries:

```bash
./bin/hawk-cmd list
```

Run one command directly:

```bash
./bin/hawk-cmd run grpc_health
```

This is the core extensibility path used by the Python TUI.

## 6. Use The Rust Mirror/Spine

List available pack threads:

```bash
cargo run -p hawk -- pack list
```

Inspect one thread schema:

```bash
cargo run -p hawk -- pack show fail_only
```

Run mirror from stdin:

```bash
cargo run -p hawk -- --source stdin
```

Run spine:

```bash
cargo run -p hawkd -- --socket-path /tmp/hawk.sock --source stdin
```

## 7. First Extension (Add Capability Safely)

1. Add or modify an awk script in `awk/commands`.
2. Register metadata in `awk/commands/cmd_catalog.awk`.
3. Wire command dispatch in `bin/hawk-cmd`.
4. Re-run `./shell/verify.sh`.
5. Validate behavior in TUI.

Use `docs/HAWK.AWK.BOOK.md` as your strict contract reference.

## 8. Operating Checklist

Before marking an environment ready:
- [ ] `./shell/verify.sh` passes
- [ ] `hawk-cmd list` returns expected command catalog
- [ ] gRPC page shows expected endpoint states
- [ ] stream lag command returns rows
- [ ] log tail updates while emitter or real workload runs
- [ ] command execution and daemon controls work from keyboard

## 9. Common Issues

- Command list empty:
  - Verify `awk/commands/cmd_catalog.awk` parses and `bin/hawk-cmd` is executable.
- gRPC health unknown:
  - Check targets file and adapter dependencies (`grpcurl`, certificates, connectivity).
- No log motion:
  - Confirm `HAWK_LOG_FILE` path and write activity.
- Rust commands fail with rustup shim errors:
  - Set a rustup default toolchain (`rustup default stable` or configured system toolchain).
