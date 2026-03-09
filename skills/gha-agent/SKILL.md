---
name: gha-agent
description: |
  Run gha-agent.sh — a lean GitHub Actions workflow linter that produces agent-friendly output.
  Use when: running GitHub Actions workflow checks, linting workflow files, verifying workflows before committing,
  or when the user asks to run actionlint, workflow lint, or GitHub Actions checks.
  Triggers on: gha agent, github actions lint, actionlint, workflow lint, github actions checks.
context: fork
allowed-tools:
  - Bash(scripts/gha-agent.sh*)
  - Bash(RUN_*=* scripts/gha-agent.sh*)
  - Bash(MAX_LINES=* scripts/gha-agent.sh*)
  - Bash(KEEP_DIR=* scripts/gha-agent.sh*)
  - Bash(FAIL_FAST=* scripts/gha-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/gha-agent.sh*)
---

# GHA Agent

Run the `gha-agent.sh` script for lean, structured GitHub Actions workflow linting output designed for coding agents.

## Script Location

```
scripts/gha-agent.sh
```

## Usage

### Run Full Suite (lint)
```bash
scripts/gha-agent.sh
```

### Run Individual Steps
```bash
scripts/gha-agent.sh lint      # actionlint check only
scripts/gha-agent.sh all       # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_LINT` | `1` | Set to `0` to skip lint step |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes checks to workflow files only |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: lint`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- The script discovers `.yml` and `.yaml` files in `.github/workflows/`
- `CHANGED_FILES` scopes checks to only workflow files (`.yml`/`.yaml` under `.github/workflows/`)
- Reports SKIP when no `.github/workflows/` directory exists
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
