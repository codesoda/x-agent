---
name: helm-agent
description: |
  Run helm-agent.sh — a lean Helm chart linter and template validator that produces agent-friendly output.
  Use when: running Helm chart checks, linting charts, validating templates, verifying Helm charts before committing,
  or when the user asks to run helm lint, helm template, or Helm chart checks.
  Triggers on: helm agent, helm lint, helm checks, helm template, validate helm chart.
context: fork
allowed-tools:
  - Bash(scripts/helm-agent.sh*)
  - Bash(RUN_*=* scripts/helm-agent.sh*)
  - Bash(CHART_DIR=* scripts/helm-agent.sh*)
  - Bash(MAX_LINES=* scripts/helm-agent.sh*)
  - Bash(KEEP_DIR=* scripts/helm-agent.sh*)
  - Bash(FAIL_FAST=* scripts/helm-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/helm-agent.sh*)
  - Bash(TMPDIR_ROOT=* scripts/helm-agent.sh*)
---

# Helm Agent

Run the `helm-agent.sh` script for lean, structured Helm chart linting and template validation output designed for coding agents.

## Script Location

```
scripts/helm-agent.sh
```

## Usage

### Run Full Suite (lint + template)
```bash
scripts/helm-agent.sh
```

### Run Individual Steps
```bash
scripts/helm-agent.sh lint      # helm lint only
scripts/helm-agent.sh template  # helm template only
scripts/helm-agent.sh all       # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_LINT` | `1` | Set to `0` to skip lint step |
| `RUN_TEMPLATE` | `1` | Set to `0` to skip template step |
| `CHART_DIR` | _(empty)_ | Explicit chart directory (skips auto-detection) |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes to affected charts |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: lint`, `Step: template`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- Auto-detects chart directories by searching for `Chart.yaml`
- `CHART_DIR` overrides auto-detection with a specific chart path
- `CHANGED_FILES` scopes checks to charts containing changed `.yaml`/`.yml`/`.tpl` files
- Reports SKIP when no `Chart.yaml` is found anywhere
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
