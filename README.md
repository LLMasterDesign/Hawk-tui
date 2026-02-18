# Hawk-tui

AWK-powered terminal UI for AI operators: live gRPC health, daemon controls, Rust-backed event streaming.

> 14 tabs, 3 half-broken scripts, one cursed `tail -f` → Hawk-tui is the cleanup crew.

## Proof it works

```bash
./shell/verify.sh
```

Expected: `verify passed` + JSON. Or: `python3 hawk_tui.py --check`

## Quick Start

**Requirements:** `bash`, `python3`, `awk`. Optional: `cargo`, `tmux`.

```bash
./shell/run_fake.sh    # fake env + TUI
./shell/verify.sh      # smoke test
```

**Real systems:** `export HAWK_GRPC_TARGETS=conf/grpc.targets.example` then `./run.sh`

## Design layout

```text
publishers / stdin / unix
       ↓
   hawkd (Rust spine) —— gRPC/systemd watchers
       ↓
hawk | hawk_tui.py | TUI2GO
       ↓
awk commands / packs / adapters
```

**HawkFrame TSV:** 7 cols `ts kind scope id level msg kv`

**Repo:** `hawk_tui.py` · `bin/hawk-cmd` · `awk/commands` · `packs/hawk.core` · `crates/{hawk,hawkd,hawk_core}` · `shell/` · `docs/`

## Docs

[Onboarding](docs/ONBOARDING.md) · [Specs](docs/SPECS.md) · [AWK Book](docs/HAWK.AWK.BOOK.md) · [Index](docs/INDEX.md) · [TUI2GO](tui2go/README.md)

MIT · [ZENS3N Systems](https://github.com/LLMasterDesign/ZENS3N)
