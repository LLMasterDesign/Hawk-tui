# Deep Dive: Why Hawk-tui Works For Agentic TUI Systems

## Thesis

Most terminal dashboards fail under agent-driven change because they couple UI rendering, data collection, and business logic into one mutable runtime.

Hawk-tui intentionally separates those concerns:
- Data contract: HawkFrame TSV (strict 7-column schema).
- Behavior layer: awk commands and pack threads.
- Integration layer: adapters for external systems.
- Operator surfaces: Python TUI and Rust mirror.

This creates a system where agents can safely extend capability without destabilizing core runtime loops.

## 1. Contract-First Stream Model

A HawkFrame line is always:
- `ts`
- `kind`
- `scope`
- `id`
- `level`
- `msg`
- `kv`

Why this matters:
- Agents can reason about one stable schema.
- Validation is cheap and deterministic.
- Downstream transforms stay composable.

## 2. Command-First Operator Surface

The Python TUI does not hard-code domain-specific logic. It calls:
- `bin/hawk-cmd list`
- `bin/hawk-cmd run <id>`

Result:
- New operator actions are added by extending scripts/registry.
- Agent changes remain localized and auditable.

## 3. Spine/Mirror Separation

`hawkd` (spine) handles fan-in and broadcast over unix sockets.
`hawk` (mirror) focuses on ingest, optional transforms, and TUI state.

This separation supports:
- Multiple producers and consumers.
- Replay/testability via stdin and fake inputs.
- Incremental rollout of new watchers (gRPC/systemd).

## 4. Safe Extensibility With awk Packs

Pack threads formalize script behavior and argument schemas.

Safety properties:
- Unknown args rejected.
- Typed args (`string|int|bool`).
- Thread metadata declarative in `pack.toml`.
- Pack doctor flows can gate unsafe changes.

This gives agents a constrained, inspectable mutation surface.

## 5. Agent Workflow That Scales

Recommended agent loop:
1. Read spec and contract docs.
2. Add or adjust awk/adapters.
3. Update catalog/pack metadata.
4. Run deterministic smoke checks (`shell/verify.sh`, `--check`).
5. Only then modify core runtime paths if still required.

This keeps high-churn work in low-risk layers.

## 6. Anti-Patterns To Avoid

- Embedding environment-specific paths directly in UI code.
- Expanding side effects inside render loops.
- Emitting non-contract output from awk threads.
- Bypassing adapters and calling fragile external tools inline.

## 7. What "Good" Looks Like

A good agent-driven TUI update should:
- Preserve HawkFrame contract compatibility.
- Keep extension logic in command/packs/adapters first.
- Be testable in fake mode.
- Be reversible without invasive refactors.
- Improve operator time-to-triage from keyboard only.

## 8. Practical Evaluation Metrics

Track these during iterations:
- Time to add a new operational check.
- Number of files touched in core UI runtime.
- Smoke pass rate in fake environment.
- Mean time from anomaly to clear operator signal.
- Number of extensions that require no UI code changes.

When these trend in the right direction, the architecture is serving agentic velocity instead of resisting it.
