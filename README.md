# Hawk-tui

Built for AI operators: an AWK-powered terminal UI with live gRPC health, daemon controls, adapter boundaries, and Rust-backed event streaming.

Part of the [ZENS3N Systems substrate hub](https://github.com/LLMasterDesign/ZENS3N).

## ▛▞ 00. What This Repo Is

Hawk-tui is an operator surface for AI-first operations.

It splits responsibility on purpose:
- Python TUI for control and visibility (`hawk_tui.py`)
- AWK command layer for fast behavior changes (`awk/commands`, `bin/hawk-cmd`)
- Rust event spine/mirror for durable stream handling (`hawkd`, `hawk`, `hawk_core`)
- Shell adapters for external systems (`adapters`)

HawkFrame stream contract is always 7 TSV columns:
`ts kind scope id level msg kv`

:: ∎

## ▛▞ 01. Quick Links

Use these first when onboarding or extending.

- 📚 Docs Index: [docs/INDEX.md](docs/INDEX.md)
- 👋 Onboarding: [docs/ONBOARDING.md](docs/ONBOARDING.md)
- 📐 Specs: [docs/SPECS.md](docs/SPECS.md)
- 🧵 Hawk AWK Book: [docs/HAWK.AWK.BOOK.md](docs/HAWK.AWK.BOOK.md)
- 🔧 Hawk AWK Command Book: [docs/awk_command_book.md](docs/awk_command_book.md)
- 📖 GNU awk Manual: [gawk manual](https://www.gnu.org/software/gawk/manual/)
- 🔒 gRPC TLS/mTLS reference: [docs/hawkd_tls_mtls.md](docs/hawkd_tls_mtls.md)

:: ∎

## ▛▞ Architecture

This diagram shows how ingestion, spine, UI, and command logic are separated.

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
      awk commands / packs / adapters
```

:: ∎

## ▛▞ Fast Answers

Is this designed for AI operators first?
- Yes.

Can OpenClaw use this?
- Yes. Hawk-tui is intended for agent frameworks like OpenClaw that need to build and run terminal interfaces for users.

:: ∎

## ▛▞ 02. Quick Start (Bun Host First)

If your host stack is Bun (recommended for your setup), start here.

This block clones the repo and installs Bun wrapper dependencies.

```bash
git clone https://github.com/LLMasterDesign/Hawk-tui.git
cd Hawk-tui/bun
bun install
```

This block starts the Rust spine (`hawkd`) from Bun.

```bash
HAWKD_BIN=hawkd \
HAWK_SOCKET_PATH=/tmp/hawk.sock \
HAWKD_SOURCE=none \
HAWK_WATCHES="127.0.0.1:50051,,local.grpc" \
bun run spine
```

This block starts the UI client (`hawk`) from Bun in a second terminal.

```bash
cd Hawk-tui/bun
HAWK_BIN=hawk \
HAWK_SOCKET_PATH=/tmp/hawk.sock \
bun run ui
```

If you are not using Bun, this block runs the direct CLI path.

```bash
cd Hawk-tui
./bin/hawk-cmd list
python3 hawk_tui.py --check
./run.sh
```

Notes:
- If `grpcurl` is not installed, gRPC status falls back to `UNKNOWN` instead of crashing.
- `HAWK_DAEMON_UNIT` controls which daemon `a/z/e/h/u` actions target.

:: ∎

## ▛▞ 03. Fake Mode (Secondary Path for Safe Demos)

This block is for deterministic demo/testing when real services are unavailable.
Use this second, not as your primary production path.

```bash
./shell/run_fake.sh
```

This block runs non-interactive smoke checks and prints a JSON summary.

```bash
./shell/verify.sh
python3 hawk_tui.py --check
```

:: ∎

## ▛▞ 04. Daemon Control: Exactly Which Service Gets Called

These keys call `adapters/daemon_ctl.sh` with the unit set by `HAWK_DAEMON_UNIT`.
Default unit is `hawk-agent.service` if you do not override it.

- `a` -> `start`
- `z` -> `stop`
- `e` -> `restart`
- `h` -> `health` (`systemctl status`)
- `u` -> `status` (`systemctl status`)

This block shows direct shell calls equivalent to TUI keypresses.

```bash
export HAWK_DAEMON_UNIT="hawk-agent.service"
./adapters/daemon_ctl.sh health "$HAWK_DAEMON_UNIT"
./adapters/daemon_ctl.sh restart "$HAWK_DAEMON_UNIT"
```

This block shows status checks for a unit list used by `daemon_status` command.

```bash
./adapters/systemd_status.sh conf/systemd_units.txt
```

:: ∎

## ▛▞ 05. Command Surface (What Actually Runs)

Each command is discoverable and executable through `bin/hawk-cmd`.
The examples below show real command shapes and outputs.

This block lists the command registry.

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

This block runs gRPC health using explicit target and fake files.

```bash
HAWK_GRPC_TARGETS="$(pwd)/shell/fake_env/grpc.targets" \
HAWK_GRPC_FAKE_FILE="$(pwd)/shell/fake_env/grpc_health.jsonl" \
./bin/hawk-cmd run grpc_health
```

This block runs stream lag summary.

```bash
HAWK_STREAM_FILE="$(pwd)/shell/fake_env/stream.events" \
./bin/hawk-cmd run stream_lag
```

This block runs log severity tail summary.

```bash
HAWK_LOG_FILE="$(pwd)/shell/fake_env/runtime.log" \
./bin/hawk-cmd run tail_errors
```

:: ∎

## ▛▞ 06. Nav Model (Current + Extendable Path)

Current implementation has 4 top-level pages mapped to numeric keys `1..4`.
To extend beyond this, update the nav definitions and page dispatcher.

Files you edit for nav extension:
- `hawk_tui.py` -> `NAV_ITEMS`
- `hawk_tui.py` -> `draw_left_nav` (`nav_cards`)
- `hawk_tui.py` -> `draw_main` page switch branches

This block shows the current conceptual nav tree.

```text
overview
grpc
streams
commands
```

This block shows a recommended nested model for future extension.

```text
overview
  runtime
  incidents
grpc
  health
  endpoints
streams
  lag
  throughput
commands
  catalog
  output
```

Important: nested nav is a design target; current code ships with flat 4-page nav.

:: ∎

## ▛▞ 07. Rust Spine + Mirror Examples

These commands show the Rust path for ingest, broadcast, and transform.

This block lists available pack threads.

```bash
cargo run -p hawk -- pack list
```

This block inspects one thread schema.

```bash
cargo run -p hawk -- pack show fail_only
```

This block validates packs and AWK safety checks.

```bash
cargo run -p hawk -- pack-doctor --smoke true --security strict
```

This block runs `hawkd` as socket spine reading stdin.

```bash
cargo run -p hawkd -- --socket-path /tmp/hawk.sock --source stdin
```

This block runs `hawk` mirror consuming the socket stream.

```bash
cargo run -p hawk -- --source unix --socket-path /tmp/hawk.sock
```

This block injects one frame into the pipeline.

```bash
printf '2026-02-16T12:00:00Z\tHEALTH\tsystemd\thawk-agent.service\tok\talive\tstate=active\n' \
  | cargo run -p hawkd -- --socket-path /tmp/hawk.sock --source stdin
```

:: ∎

## ▛▞ 08. Add a New AWK Command (Full Walkthrough)

This section shows the minimum edits required to add a new command end-to-end.

This block creates the AWK file.

```bash
cat > awk/commands/warn_only.awk <<'AWK'
BEGIN { FS="\t"; OFS="\t" }
/\tWARN\t|\twarn\t/ { print }
AWK
```

This block adds command metadata to catalog.

```awk
print "warn_only|Warn Only|awk|Show warn-level lines only"
```

This block adds dispatch logic to `bin/hawk-cmd`.

```bash
warn_only)
  if [[ -f "$LOG_FILE" ]]; then
    tail -n "${HAWK_TAIL_LINES:-300}" "$LOG_FILE" | awk -f "$CMD_DIR/warn_only.awk"
  else
    echo ""
  fi
  ;;
```

This block validates your new command.

```bash
./bin/hawk-cmd list | rg warn_only
./bin/hawk-cmd run warn_only
./shell/verify.sh
```

:: ∎

## ▛▞ 09. Visual Capture (When You Can Run It)

Use this after launch to produce proof images and clips for docs/releases.

This block captures a static screenshot from your terminal app.

```text
1) Launch: ./run.sh
2) Drive to the view you want (gRPC, Streams, Commands)
3) Take terminal screenshot and save as docs/assets/hawk-tui-main.png
```

This block records a short terminal session (if `asciinema` is installed).

```bash
asciinema rec docs/assets/hawk-tui-demo.cast
```

Then render a shareable GIF/MP4 with your preferred renderer.

If you want, once you run it, I can help you script a repeatable capture pipeline.

:: ∎

## ▛▞ 10. Troubleshooting

This block helps diagnose common startup/operation issues quickly.

- No commands visible:
  - `./bin/hawk-cmd list`
  - check `awk/commands/cmd_catalog.awk` syntax
- Daemon controls do nothing:
  - verify `HAWK_DAEMON_UNIT`
  - run `./adapters/daemon_ctl.sh health <unit>` manually
- gRPC all unknown:
  - validate `HAWK_GRPC_TARGETS`
  - install/configure `grpcurl` if using live probes
- Rust toolchain errors:
  - `rustup show active-toolchain`
  - `rustup default stable`

:: ∎

## ▛▞ 11. Bun Service Wrapper

Use this when your host project is Bun-based and you want `hawkd`/`hawk` managed as service processes.

This block runs the Bun wrapper for `hawkd` (spine mode).

```bash
cd bun
bun install
HAWKD_BIN=hawkd HAWK_SOCKET_PATH=/tmp/hawk.sock HAWKD_SOURCE=none bun run spine
```

This block runs the Bun wrapper for `hawk` (UI mode).

```bash
cd bun
HAWK_BIN=hawk HAWK_SOCKET_PATH=/tmp/hawk.sock bun run ui
```

For env-driven project shim defaults, use:
- `shims/project.sh`
- `conf/project.grpc.targets`

:: ∎

## ▛▞ 12. License

MIT. See [LICENSE](LICENSE).

:: ∎
