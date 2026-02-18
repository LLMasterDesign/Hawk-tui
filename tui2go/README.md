# TUI2GO

///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂///
▛//▞▞ ⟦⎊⟧ :: TUI2GO // README :: 2GO substrate ▞▞

GO surface for micro TUIs — deploys under 5MB, stays tiny ("2GO"). May use Hawk source to build; deploys independently. TRACT and FORGE are users of TUI2GO.

## Overview

GO surface for micro TUIs. Deploys under 5MB, stays tiny ("2GO"). May use Hawk source to build; deploys independently. TRACT and FORGE are users.

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

Place your TUI2GO screenshot at `tui2go-2go-panels.png` in this directory. The main README embeds it automatically.

:: ∎
