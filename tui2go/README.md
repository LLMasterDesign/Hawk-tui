# TUI2GO

///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂///
▛//▞▞ ⟦⎊⟧ :: TUI2GO // README :: 2GO substrate ▞▞

GO surface for micro TUIs — deploys under 5MB, stays tiny ("2GO"). May use Hawk source to build; deploys independently. TRACT and FORGE are users of TUI2GO.

## Overview

(Needs proper spec — see TODO below.)

## Layout (example: TRACT and FORGE users)

```
// 2GO ... TRACT CONTROL          // 2GO // FORGE CONTROL
Setup | Status | Action Bar       Setup | Status | Action Bar
```

## Key bindings

| Key | Action    |
|-----|-----------|
| `sp`| refresh   |
| `t` | theme     |
| `u` | up        |
| `r` | restart   |
| `e` | emit      |
| `s` | start     |
| `x` | stop      |
| `d` | down      |
| `q` | quit      |

## Self-contained use

This folder is structured so TUI2GO can be pulled and used independently of Hawk-main:

- **Copy/subtree**: Copy this directory into your environment and wire `repo`, `tract_sh`, `forge_sh`, and env paths to your layout.
- **Branch**: A `feat/tui2go` branch may carry TUI2GO-specific work for substrate development in isolation.

## Photo

> **TODO** — Add your TUI2GO screenshot: save as `tui2go-2go-panels.png` in this directory. The main README embeds it automatically once the file exists.

## TUI2GO spec TODO (repo alignment — no personal info, no breaking others' PCs)

- [ ] Spec TUI2GO: GO surface for micro TUIs, <5MB, 2GO
- [ ] Clarify: may use Hawk source to build; deploys independently
- [ ] Clarify: TRACT and FORGE are users of TUI2GO, not owned by it
- [ ] Remove any remaining hardcoded paths or personal info
- [ ] Ensure layout works on other folks' machines

:: ∎
