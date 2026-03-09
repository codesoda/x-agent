---
name: go-agent
description: |
  Run go-agent.sh — a lean Go workflow runner that produces agent-friendly output.
  Use when: running Go checks (fmt, vet, staticcheck, test), verifying Go code before committing,
  or when the user asks to run go checks, lint, format, or test a Go project.
  Triggers on: go agent, run go checks, golang checks, go fmt vet test, verify go code.
context: fork
allowed-tools:
  - Bash(scripts/go-agent.sh*)
  - Bash(RUN_*=* scripts/go-agent.sh*)
  - Bash(FMT_MODE=* scripts/go-agent.sh*)
  - Bash(MAX_LINES=* scripts/go-agent.sh*)
  - Bash(KEEP_DIR=* scripts/go-agent.sh*)
  - Bash(FAIL_FAST=* scripts/go-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/go-agent.sh*)
---

# Go Agent

Run the `go-agent.sh` script for lean, structured Go validation output designed for coding agents.

## Script Location

```
scripts/go-agent.sh
```

## Usage

### Run Full Suite (fmt + vet + staticcheck + test)
```bash
scripts/go-agent.sh
```

### Run Individual Steps
```bash
scripts/go-agent.sh fmt           # gofmt formatting check/fix
scripts/go-agent.sh vet           # go vet analysis
scripts/go-agent.sh staticcheck   # staticcheck linter
scripts/go-agent.sh test          # go test
scripts/go-agent.sh all           # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_FMT` | `1` | Set to `0` to skip fmt step |
| `RUN_VET` | `1` | Set to `0` to skip vet step |
| `RUN_STATICCHECK` | `1` | Set to `0` to skip staticcheck step |
| `RUN_TESTS` | `1` | Set to `0` to skip test step |
| `FMT_MODE` | `auto` | `auto` = fix locally, check in CI; `check` = list only; `fix` = rewrite |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes checks to those `.go` packages |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: fmt`, `Step: vet`, etc.)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Failed test results include extracted failing test names
- `staticcheck` is skipped with a notice if not installed
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- `FMT_MODE=auto` fixes formatting locally but only checks in CI (`CI=true`)
- `staticcheck` is optional; if not installed, the step is skipped (not failed)
- `CHANGED_FILES` scopes checks to only the listed `.go` file packages
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
