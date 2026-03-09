---
name: sql-agent
description: |
  Run sql-agent.sh — a lean SQL linter that produces agent-friendly output with sqlfluff.
  Use when: running SQL checks, linting SQL files with sqlfluff, validating SQL style,
  or when the user asks to run sqlfluff, sql lint, sql format, or sql checks.
  Triggers on: sql agent, sqlfluff, sql lint, sql format, sql checks, validate sql.
context: fork
allowed-tools:
  - Bash(scripts/sql-agent.sh*)
  - Bash(RUN_*=* scripts/sql-agent.sh*)
  - Bash(FMT_MODE=* scripts/sql-agent.sh*)
  - Bash(SQLFLUFF_DIALECT=* scripts/sql-agent.sh*)
  - Bash(MAX_LINES=* scripts/sql-agent.sh*)
  - Bash(KEEP_DIR=* scripts/sql-agent.sh*)
  - Bash(FAIL_FAST=* scripts/sql-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/sql-agent.sh*)
  - Bash(TMPDIR_ROOT=* scripts/sql-agent.sh*)
  - Bash(CI=* scripts/sql-agent.sh*)
---

# SQL Agent

Run the `sql-agent.sh` script for lean, structured SQL linting output designed for coding agents.

## Script Location

```
scripts/sql-agent.sh
```

## Usage

### Run Full Suite (lint)
```bash
scripts/sql-agent.sh
```

### Run Individual Steps
```bash
scripts/sql-agent.sh lint          # sqlfluff lint only
scripts/sql-agent.sh fix           # sqlfluff fix (auto-fix)
scripts/sql-agent.sh all           # full suite (default: lint only)
```

### Enable Auto-Fix
```bash
RUN_FIX=1 scripts/sql-agent.sh all
FMT_MODE=fix scripts/sql-agent.sh all
```

### Specify Dialect
```bash
SQLFLUFF_DIALECT=postgres scripts/sql-agent.sh lint
SQLFLUFF_DIALECT=mysql scripts/sql-agent.sh lint
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_LINT` | `1` | Set to `0` to skip lint step |
| `RUN_FIX` | `0` | Set to `1` to enable fix step |
| `FMT_MODE` | `auto` | `auto` = check in CI, respects RUN_FIX locally; `check` or `fix` |
| `SQLFLUFF_DIALECT` | `ansi` | SQL dialect (ansi, postgres, mysql, bigquery, etc.) |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes checks to .sql files only |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: lint`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- Discovers `.sql` files recursively (excludes `.git/`, `node_modules/`, `vendor/`)
- `CHANGED_FILES` scopes checks to only `.sql` files
- Reports SKIP when no `.sql` files are found
- Fix defaults to OFF — enable with `RUN_FIX=1` or `FMT_MODE=fix`
- In CI (`CI=true`), fix is forced to check-only mode
- `--force` flag is used with `sqlfluff fix` to avoid interactive prompts
