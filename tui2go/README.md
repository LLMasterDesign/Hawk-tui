# TUI2GO

///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂///
▛//▞▞ ⟦⎊⟧ :: TUI2GO // README :: 2GO substrate ▞▞

2GO control surface for Hawk — TRACT and FORGE panels.

## Overview

TUI2GO is the substrate of Hawk-tui: dual control panels for tract (validate+snapshot) and forge (loop+restart) modes, with mobile-layout themes and unified watch pipelines.

- **TRACT CONTROL**: `tui2go-runner.sh`, validate+snapshot watch
- **FORGE CONTROL**: `forge.sh`, loop+restart watch, hawkd + injector

## Layout

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

:: ∎
