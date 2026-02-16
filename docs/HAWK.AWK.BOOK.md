<!-- ▛▞// hawk awk book :: docs.hawk.awk.book -->
<!-- @ctx ⫸ [awk.book.essential] -->
<!-- @ctx ⫸ [hawkframe.tsv.contract] -->
<!-- @ctx ⫸ [pack.thread.schema] -->
# HAWK.AWK.BOOK

Status: ACTIVE
Audience: humans and agents
Goal: write awk threads that are correct, composable, and community-safe.

## 00. Prime Directive
Hawk is a mirror. `hawkd` is a spine. `awk` threads are lenses.
Only one job matters: transform HawkFrame TSV without breaking the stream.

## 01. HawkFrame TSV Contract
A HawkFrame is exactly 7 tab-separated columns:
1. `ts` RFC3339 or empty
2. `kind` token, example `HEALTH`
3. `scope` token, example `systemd`, `grpc`, `awk`
4. `id` stable entity id
5. `level` `ok|info|warn|fail|unknown`
6. `msg` one-line text
7. `kv` semicolon bag: `k=v;k=v;flag`

Rules:
- Use literal TAB as field separator.
- Always emit 7 columns.
- No newlines in `msg` or `kv`.
- `#` comment lines and blank lines are ignored by parser.

## 02. Thread Types
- `filter`: pass subset only, no synthetic frames.
- `map`: one output line per input line, still 7 columns.
- `aggregate`: emit synthetic frames, still 7 columns.

Hard rules:
- Never print debug to stdout.
- Print debug only to stderr.

## 03. Vars and Schema
Hawk injects vars with `awk -v key=value -f thread.awk`.
Every script var must be declared in `pack.toml`:
- `name`
- `type` (`string|int|bool`)
- `default`
- `help`

Validation:
- unknown vars rejected
- `int` must parse
- `bool` must be `true|false|1|0`

## 04. Thread Template
```awk
BEGIN { FS = "\t"; OFS = "\t"; }
{
  # 1 ts, 2 kind, 3 scope, 4 id, 5 level, 6 msg, 7 kv
  print $0;
}
```

## 05. Manifest Template
```toml
[[thread]]
id = "my_thread"
title = "My Thread"
kind = "filter"
file = "my_thread.awk"
description = "One sentence."

[[thread.arg]]
name = "scope"
type = "string"
default = ""
help = "Optional scope filter on $3."
```

## 06. Canon Snippets
```awk
# fail or warn only
tolower($5)=="fail" || tolower($5)=="warn" { print $0 }

# systemd only
$3=="systemd" { print $0 }

# id prefix
index($4, "spine.")==1 { print $0 }
```

## 07. Community Checklist
A thread is acceptable only if:
- `pack.toml` parses
- thread id is unique in loaded index
- script file exists
- emitted lines are valid 7-column HawkFrame TSV
- referenced vars are declared
- no debug on stdout
- no secrets in `msg` or `kv`

## 08. Safety at Scale
Keep three non-negotiables:
1. hard TSV contract
2. hard templates
3. hard validator (`hawk pack doctor`, next batch)

# :: ∎
