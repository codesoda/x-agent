---
name: bash-agent
description: |
  Run bash-agent.sh — a lean shell script validation runner that produces agent-friendly output.
  Use when: running shell/bash script checks (syntax, lint), verifying shell scripts before committing,
  or when the user asks to run shellcheck, bash checks, or validate shell scripts.
  Triggers on: bash agent, shell agent, shellcheck, bash lint, shell checks, verify shell scripts.
context: fork
allowed-tools:
  - Bash(scripts/bash-agent.sh*)
  - Bash(RUN_*=* scripts/bash-agent.sh*)
  - Bash(SHELLCHECK_SEVERITY=* scripts/bash-agent.sh*)
  - Bash(MAX_LINES=* scripts/bash-agent.sh*)
  - Bash(KEEP_DIR=* scripts/bash-agent.sh*)
  - Bash(FAIL_FAST=* scripts/bash-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/bash-agent.sh*)
---

# Bash Agent

Run the `bash-agent.sh` script for lean, structured shell script validation output designed for coding agents.

## Script Location

```
scripts/bash-agent.sh
```

## Usage

### Run Full Suite (syntax + lint)
```bash
scripts/bash-agent.sh
```

### Run Individual Steps
```bash
scripts/bash-agent.sh syntax    # bash -n syntax check only
scripts/bash-agent.sh lint      # shellcheck lint only
scripts/bash-agent.sh all       # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_SYNTAX` | `1` | Set to `0` to skip syntax check |
| `RUN_LINT` | `1` | Set to `0` to skip shellcheck lint |
| `SHELLCHECK_SEVERITY` | `warning` | shellcheck `--severity` level (`error`, `warning`, `info`, `style`) |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes checks to those `.sh` files |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: syntax`, `Step: lint`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Failed shellcheck results include wiki links for each error code
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- The script discovers all `.sh` files recursively, excluding `.git`, `node_modules`, and `vendor`
- `CHANGED_FILES` scopes checks to only the listed `.sh` files that exist
- `SHELLCHECK_SEVERITY` controls the minimum severity level for shellcheck warnings
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
