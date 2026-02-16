# Hawk-tui Specification

## 1. Purpose
Hawk-tui is a long-lifecycle operator console for agentic systems.

Primary goal:
- Monitor gRPC health, daemon status, stream lag, and log motion.
- Expose a scriptable awk command palette so AI agents can add/change monitoring behavior without rewriting UI internals.

Non-goal (for now):
- hard-coding 3ox-specific semantics into core TUI.

## 2. Design principles
- Command-first architecture: the TUI renders outputs from `bin/hawk-cmd` commands.
- Script composability: awk scripts are lightweight, auditable, and easy for agents to patch.
- Adapter boundary: external systems are touched in `adapters/` only.
- Shim strategy: ecosystem-specific mapping sits in `shims/`.

## 3. Learned patterns from research (applied)
- K9s model: continuous change watch loop + keyboard-native ops.
  - Source: https://github.com/derailed/k9s
- Bubble Tea model: clean update loop and explicit state transitions.
  - Source: https://github.com/charmbracelet/bubbletea
- Textual model: treat TUI as an app framework with deterministic layout.
  - Source: https://textual.textualize.io/
- Gum model: boot UX and terminal polish without coupling to core runtime.
  - Source: https://github.com/charmbracelet/gum
- Ratatui model: high-performance terminal UI patterns and composable widgets.
  - Source: https://ratatui.rs/

## 4. Layout contract (5-box)
- Box 1: left full-height nav/control legend.
- Box 2: main top page section.
- Box 3: main bottom page section.
- Box 4: right ops section (detail + live log split).
- Box 5: right full-height chat/details panel.

## 5. Command architecture

### 5.1 Registry
`awk/commands/cmd_catalog.awk` is authoritative command catalog.

Output format:
`id|title|runner|description`

### 5.2 Runner
`bin/hawk-cmd` supports:
- `hawk-cmd list`
- `hawk-cmd run <command_id>`

### 5.3 Current command set
- `grpc_health`
- `stream_lag`
- `tail_errors`
- `daemon_status`

### 5.4 Extending command library
1. Add a new awk script or adapter.
2. Register command in `awk/commands/cmd_catalog.awk`.
3. Add dispatch case in `bin/hawk-cmd`.
4. Hawk-tui auto-discovers via `hawk-cmd list`.

## 6. gRPC health model
Source priority:
1. `HAWK_GRPC_FAKE_FILE` (for deterministic test)
2. `grpcurl` + targets file (real probing)
3. fallback `UNKNOWN` per target

Normalized output:
`endpoint<TAB>status<TAB>latency<TAB>source`

## 7. Daemon control model
`adapters/daemon_ctl.sh` provides:
- `start|stop|restart|health|status`
- system scope first, then user scope fallback.

## 8. Test harness
Folder: `shell/`
- `init_fake_env.sh`: creates deterministic fake files.
- `emit_fake_activity.sh`: produces moving logs/streams/grpc health rows.
- `run_fake.sh`: runs Hawk-tui against fake environment.
- `verify.sh`: non-interactive smoke test and assertions.

## 9. Verification checklist
- Command catalog loads >= 4 commands.
- gRPC health shows at least one SERVING endpoint in fake env.
- Stream lag command returns rows.
- Log file grows under fake emitter.
- TUI runs with active motion and live tail updates.

## 10. Known next steps
- Add optional protobuf-native health checks (Python grpc health stubs).
- Add command metadata schema (input args, expected output shape).
- Add plugin signing or checksum policy for command library.
- Add richer parser for JSON stream files in awk commands.
