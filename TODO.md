# Repo health TODO

- [ ] Add TUI2GO screenshot: `tui2go/tui2go-2go-panels.png`
- [ ] Spec TUI2GO: GO surface for micro TUIs, <5MB, 2GO; TRACT/FORGE as users
- [x] Audit for remaining hardcoded paths
- [ ] Audit for personal info or machine-specific references
- [ ] Ensure examples/scripts run on other folks' PCs
- [ ] Lint / CI if not present
- [ ] Quote style audit: most `""` in shell are required for variable expansion; only a few pure `echo` literals could use `''` (cosmetic only; AWK/Rust use `""` by language rule)

:: ∎
