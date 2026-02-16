# Hawk-tui Specs and Contracts

This file maps the practical, implementation-level contracts contributors and agents must preserve.

## 1. System Purpose

Hawk-tui is an operator console and event mirror for long-lifecycle, agentic workloads.

Primary outcomes:
- Observe health and motion.
- Run scripted operational commands.
- Extend behavior without rewriting core UI runtime.

Reference: `HAWK-TUI.SPEC.md`

## 2. Runtime Components

- Python operator surface: `hawk_tui.py`
- Command dispatcher: `bin/hawk-cmd`
- awk command scripts: `awk/commands/*.awk`
- External adapters: `adapters/*.sh`
- Rust frame model: `crates/hawk_core`
- Rust mirror app: `crates/hawk`
- Rust spine daemon: `crates/hawkd`

## 3. HawkFrame Contract (Normative)

All stream transforms must preserve 7 tab-separated columns:
1. `ts`
2. `kind`
3. `scope`
4. `id`
5. `level`
6. `msg`
7. `kv`

Rules:
- TAB-separated fields only.
- Exactly 7 columns on emitted lines.
- `msg` and `kv` must be one-line values.
- `#` comments and blank lines are ignorable input lines.

References:
- `crates/hawk_core/src/hawkframe.rs`
- `docs/HAWK.AWK.BOOK.md`

## 4. Command Catalog Contract

Catalog authority:
- `awk/commands/cmd_catalog.awk`

Record format:
- `id|title|runner|description`

Dispatcher contract:
- `bin/hawk-cmd list`
- `bin/hawk-cmd run <id>`

Any new command must update both catalog and dispatcher.

## 5. Adapter Boundary Contract

External system calls belong in `adapters/`.

Current boundaries:
- gRPC health probing: `adapters/grpc_health.sh`
- daemon control and status: `adapters/daemon_ctl.sh`, `adapters/systemd_status.sh`

UI and core runtime should consume normalized adapter output, not raw side effects.

## 6. Pack/Thread Contract

Pack metadata source:
- `packs/*/pack.toml`

Each thread defines:
- `id`, `title`, `kind`, `file`, `description`
- optional typed args (`string|int|bool`) with defaults and help text

Validation behavior is exposed through `hawk pack` and doctor flows.

## 7. Operational Validation Contract

Required checks before merge/release:
- `./shell/verify.sh` passes
- `python3 hawk_tui.py --check` returns expected telemetry keys
- command catalog loads and commands execute
- no contract-breaking output from awk scripts

## 8. Security and Stability Guidelines

- Avoid debug output on stdout from awk scripts.
- Keep secrets out of frame `msg` and `kv` fields.
- Prefer deterministic fake test fixtures before real adapter rollout.
- Treat adapter changes as high-risk boundaries and test separately.

## 9. Compatibility Guidance

Preserve backward compatibility for:
- HawkFrame TSV 7-column schema
- `hawk-cmd list/run` command interface
- Existing command IDs used by operator workflows

Breaking any of these requires explicit versioning and migration notes.
