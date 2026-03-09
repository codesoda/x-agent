---
name: docker-agent
description: |
  Run docker-agent.sh — a lean Dockerfile linter that produces agent-friendly output.
  Use when: running Dockerfile checks, linting Dockerfiles with hadolint, verifying Dockerfiles before committing,
  or when the user asks to run hadolint, dockerfile lint, or docker checks.
  Triggers on: docker agent, dockerfile lint, hadolint, docker checks, validate dockerfile.
context: fork
allowed-tools:
  - Bash(scripts/docker-agent.sh*)
  - Bash(RUN_*=* scripts/docker-agent.sh*)
  - Bash(MAX_LINES=* scripts/docker-agent.sh*)
  - Bash(KEEP_DIR=* scripts/docker-agent.sh*)
  - Bash(FAIL_FAST=* scripts/docker-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/docker-agent.sh*)
  - Bash(TMPDIR_ROOT=* scripts/docker-agent.sh*)
---

# Docker Agent

Run the `docker-agent.sh` script for lean, structured Dockerfile linting output designed for coding agents.

## Script Location

```
scripts/docker-agent.sh
```

## Usage

### Run Full Suite (lint)
```bash
scripts/docker-agent.sh
```

### Run Individual Steps
```bash
scripts/docker-agent.sh lint          # hadolint check only
scripts/docker-agent.sh build-check   # BuildKit lint mode (requires docker)
scripts/docker-agent.sh all           # full suite (default: lint only)
```

### Enable Build Check
```bash
RUN_BUILD_CHECK=1 scripts/docker-agent.sh all
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_LINT` | `1` | Set to `0` to skip lint step |
| `RUN_BUILD_CHECK` | `0` | Set to `1` to enable build-check step (requires docker) |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes checks to Dockerfiles only |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: lint`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- Discovers `Dockerfile`, `Dockerfile.*`, and `*.dockerfile` files recursively
- `CHANGED_FILES` scopes checks to only Dockerfile-like files
- Reports SKIP when no Dockerfiles are found
- `build-check` defaults to OFF — it requires a Docker daemon and is expensive
- `build-check` skips with notice if `docker` is not installed
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
