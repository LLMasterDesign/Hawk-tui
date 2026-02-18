# Hawk-tui

Built for AI operators: an AWK-powered terminal UI with live gRPC health, daemon controls, adapter boundaries, and Rust-backed event streaming.

> If your incident workflow is 14 tabs, 3 half-broken scripts, and one cursed `tail -f`, Hawk-tui is the cleanup crew.

Part of the [ZENS3N Systems](https://github.com/LLMasterDesign/ZENS3N) substrate hub.

## Quick Links

- 📚 Docs Index: [docs/INDEX.md](docs/INDEX.md)
- 👋 Onboarding: [docs/ONBOARDING.md](docs/ONBOARDING.md)
- 📐 Specs: [docs/SPECS.md](docs/SPECS.md)
- 🧵 AWK Book: [docs/HAWK.AWK.BOOK.md](docs/HAWK.AWK.BOOK.md)
- 🔧 AWK Command Book: [docs/awk_command_book.md](docs/awk_command_book.md)
- 🔒 gRPC TLS/mTLS: [docs/hawkd_tls_mtls.md](docs/hawkd_tls_mtls.md)

## Why Hawk-tui

Most operator dashboards degrade when agent-driven changes happen fast.
Hawk-tui avoids that by keeping hard boundaries:

- UI is a mirror, not the source of truth.
- Command logic lives in AWK scripts and adapters.
- Event plumbing lives in Rust (`hawkd`, `hawk_core`, `hawk`).
- New behavior lands in small files, not full UI rewrites.

## What You Get

- Python operator dashboard (`hawk_tui.py`) with keyboard-first control.
- Command palette driven by `bin/hawk-cmd` and `awk/commands`.
- Live gRPC health normalization and daemon controls.
- Deterministic fake environment for safe iteration.
- Rust spine (`hawkd`) and mirror (`hawk`) for ingest/broadcast.
- Pack/thread model for reusable AWK transforms.

## Architecture

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
      hawk (Rust mirror TUI)  OR  hawk_tui.py (Python operator TUI)  OR  TUI2GO (2GO micro-TUI surface)
            |
            v
      awk commands / packs / adapters
```

Core stream contract is HawkFrame TSV with exactly 7 columns:
`ts kind scope id level msg kv`

## TUI2GO — substrate of Hawk

TUI2GO is a GO surface for building micro TUIs. Deploys under 5MB, stays tiny ("2GO"). May use Hawk source to build; deploys independently. **TRACT** and **FORGE** are users of it.

![TUI2GO 2GO control panels — TRACT and FORGE](tui2go/tui2go-2go-panels.png)

→ Full docs: [tui2go/README.md](tui2go/README.md)

## Quick Start

Requirements:
- `bash`
- `python3`
- `awk`

Recommended:
- `cargo`, `rustc`, `rustup`
- `tmux`

Optional:
- `grpcurl` for real gRPC probes
- `gum` for startup polish

Run fake environment:

```bash
cd /path/to/Hawk-tui
./shell/run_fake.sh
```

Verify:

```bash
./shell/verify.sh
```

One-shot JSON health check:

```bash
python3 hawk_tui.py --check
```

Expected shape:

```json
{
  "app": "hawk-tui",
  "commands": 4,
  "grpc_ok": 3,
  "grpc_bad": 0,
  "stream_rows": 3,
  "log_size": 12345,
  "log_delta": 321
}
```

## Command Surface Examples

List command catalog:

```bash
./bin/hawk-cmd list
```

Example output:

```text
grpc_health|gRPC Health|adapter+awk|Probe endpoints and normalize SERVING status
stream_lag|Stream Lag|awk|Summarize per-stream lag from timestamped events
tail_errors|Tail Errors|awk|Count ERROR/WARN/INFO in recent log lines
daemon_status|Daemon Status|adapter|Inspect systemd active state for unit list
```

Run gRPC health against fixtures:

```bash
HAWK_GRPC_FAKE_FILE="$(pwd)/shell/fake_env/grpc_health.jsonl" \
HAWK_GRPC_TARGETS="$(pwd)/shell/fake_env/grpc.targets" \
./bin/hawk-cmd run grpc_health
```

Example output:

```text
127.0.0.1:50051	SERVING	36ms	fake
127.0.0.1:50052	SERVING	34ms	fake
127.0.0.1:50053	SERVING	35ms	fake
```

Run stream lag:

```bash
HAWK_STREAM_FILE="$(pwd)/shell/fake_env/stream.events" \
./bin/hawk-cmd run stream_lag
```

Example output:

```text
orders	lag=0s	events=5822	last_epoch=1771260977
health	lag=1s	events=5822	last_epoch=1771260976
agent	lag=0s	events=5822	last_epoch=1771260977
```

Run log severity summary:

```bash
HAWK_LOG_FILE="$(pwd)/shell/fake_env/runtime.log" \
./bin/hawk-cmd run tail_errors
```

Example output:

```text
ERROR	34
WARN	66
INFO	200
```

## Python TUI Controls

- `1..4`: switch pages
- `j/k` or arrows: navigate
- `[` and `]`: select command
- `Enter`: run selected command
- `a`: daemon start
- `z`: daemon stop
- `e`: daemon restart
- `h`: daemon health
- `u`: daemon status
- `m`: append note
- `r`: refresh now
- `q`: quit

## Run Against Real Systems

```bash
export HAWK_GRPC_TARGETS="$(pwd)/conf/grpc.targets.example"
export HAWK_UNITS_FILE="$(pwd)/conf/systemd_units.txt"
./run.sh
```

Common overrides:

```bash
export HAWK_LOG_FILE="/var/log/hawk/runtime.log"
export HAWK_STREAM_FILE="/var/lib/hawk/stream.events"
export HAWK_DAEMON_UNIT="hawk-agent.service"
```

## Rust Track: Spine + Mirror

List pack threads:

```bash
cargo run -p hawk -- pack list
```

Show thread schema:

```bash
cargo run -p hawk -- pack show fail_only
```

Run pack doctor:

```bash
cargo run -p hawk -- pack-doctor --smoke true --security strict
```

Run mirror from stdin:

```bash
cargo run -p hawk -- --source stdin
```

Feed one frame manually:

```bash
printf '2026-02-16T12:00:00Z\tHEALTH\tgrpc\tproto.alpha\tok\talive\tstatus=SERVING;latency_ms=12\n' \
  | cargo run -p hawk -- --source stdin
```

Run mirror from unix socket:

```bash
cargo run -p hawk -- --source unix --socket-path /tmp/hawk.sock
```

Run spine (`hawkd`) and broadcast:

```bash
cargo run -p hawkd -- --socket-path /tmp/hawk.sock --source stdin
```

Pipe events into spine:

```bash
printf '2026-02-16T12:00:01Z\tHEALTH\tsystemd\thawk-agent.service\twarn\tdegraded\tstate=activating\n' \
  | cargo run -p hawkd -- --socket-path /tmp/hawk.sock --source stdin
```

## Transform Examples (AWK Threads)

Use built-in thread transform:

```bash
printf '2026-02-16T12:00:02Z\tHEALTH\tgrpc\talpha\tfail\tdown\treason=timeout\n' \
  | cargo run -p hawk -- --source stdin --transform thread:fail_only
```

Pass thread vars:

```bash
printf '2026-02-16T12:00:03Z\tHEALTH\tsystemd\thawk-agent.service\twarn\tslow\tlatency_ms=950\n' \
  | cargo run -p hawk -- --source stdin --transform thread:fail_only --tvar scope=systemd
```

Use a direct AWK file transform:

```bash
printf '2026-02-16T12:00:04Z\tHEALTH\tsystemd\thawk-agent.service\tfail\tdown\tstate=inactive\n' \
  | cargo run -p hawk -- --source stdin --transform file:./packs/hawk.core/fail_only.awk
```

## gRPC mTLS Example (`hawkd`)

```bash
cargo run -p hawkd -- \
  --socket-path /tmp/hawk.sock \
  --source none \
  --watch service.example.internal:8443,,proto.alpha \
  --grpc-tls-mode mtls \
  --grpc-ca /etc/hawk/certs/ca.pem \
  --grpc-cert /etc/hawk/certs/client.pem \
  --grpc-key /etc/hawk/certs/client.key \
  --grpc-domain service.example.internal
```

Reference: [docs/hawkd_tls_mtls.md](docs/hawkd_tls_mtls.md)

## Add a New Command (End-to-End)

### 1. Create the AWK command

```bash
cat > awk/commands/warn_only.awk <<'AWK'
BEGIN { FS="\t"; OFS="\t" }
/\tWARN\t|\twarn\t/ { print }
AWK
```

### 2. Register it in the catalog

Edit `awk/commands/cmd_catalog.awk` and add:

```awk
print "warn_only|Warn Only|awk|Show warn-level lines only"
```

### 3. Wire dispatch in `bin/hawk-cmd`

Add a new case:

```bash
warn_only)
  if [[ -f "$LOG_FILE" ]]; then
    tail -n "${HAWK_TAIL_LINES:-300}" "$LOG_FILE" | awk -f "$CMD_DIR/warn_only.awk"
  else
    echo ""
  fi
  ;;
```

### 4. Validate and run

```bash
./bin/hawk-cmd list | rg warn_only
./bin/hawk-cmd run warn_only
./shell/verify.sh
```

The command will appear in the TUI palette automatically.

## AWK Toolkit Links

- Hawk AWK rules and templates: [docs/HAWK.AWK.BOOK.md](docs/HAWK.AWK.BOOK.md)
- Hawk command patterns: [docs/awk_command_book.md](docs/awk_command_book.md)
- GNU awk reference: [gawk manual](https://www.gnu.org/software/gawk/manual/)

## Troubleshooting

No commands in UI:
- Check `./bin/hawk-cmd list`
- Validate `awk/commands/cmd_catalog.awk`
- Ensure `bin/hawk-cmd` is executable

gRPC is unknown everywhere:
- Verify `HAWK_GRPC_TARGETS`
- Validate `grpcurl` and cert paths in real mode
- Re-test using fixture mode to isolate transport issues

No log movement:
- Validate `HAWK_LOG_FILE`
- Ensure logs are being written
- Run `./shell/run_fake.sh` to confirm baseline behavior

Rust toolchain errors (`rustup`/`cargo`):
- Check `rustup show active-toolchain`
- Set a default: `rustup default stable`

## Repo Layout

- `hawk_tui.py`: Python 5-box operator UI
- `bin/hawk-cmd`: command registry/runner
- `awk/commands`: AWK command scripts
- `adapters`: system integration scripts
- `packs/hawk.core`: packaged AWK threads + schema
- `crates/hawk_core`: HawkFrame model/parsing
- `crates/hawkd`: socket spine + watchers
- `crates/hawk`: mirror TUI + transforms + doctor
- `shell`: fake env + smoke tests
- `docs`: onboarding, specs, AWK docs, deep dive

## FAQ

Do I need Elixir/BEAM to run Hawk-tui?
- No. Core runtime here is Python + AWK + Rust + shell adapters.

Can I run only the Python track?
- Yes. Use `./run.sh` or `./shell/run_fake.sh`.

Can I run only the Rust track?
- Yes. Use `hawkd` and `hawk` cargo commands directly.

Is this designed for AI operators first?
- Yes.

## License

MIT. See [LICENSE](LICENSE).
