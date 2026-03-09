---
name: ansible-agent
description: |
  Run ansible-agent.sh — a lean Ansible playbook linter and syntax checker that produces agent-friendly output.
  Use when: running Ansible checks, linting playbooks with ansible-lint, syntax-checking playbooks,
  or when the user asks to validate ansible, run ansible lint, or check ansible syntax.
  Triggers on: ansible agent, ansible lint, ansible checks, validate ansible, ansible syntax check.
context: fork
allowed-tools:
  - Bash(scripts/ansible-agent.sh*)
  - Bash(RUN_*=* scripts/ansible-agent.sh*)
  - Bash(FMT_MODE=* scripts/ansible-agent.sh*)
  - Bash(MAX_LINES=* scripts/ansible-agent.sh*)
  - Bash(KEEP_DIR=* scripts/ansible-agent.sh*)
  - Bash(FAIL_FAST=* scripts/ansible-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/ansible-agent.sh*)
  - Bash(TMPDIR_ROOT=* scripts/ansible-agent.sh*)
---

# Ansible Agent

Run the `ansible-agent.sh` script for lean, structured Ansible playbook linting and syntax checking output designed for coding agents.

## Script Location

```
scripts/ansible-agent.sh
```

## Usage

### Run Full Suite (lint + syntax)
```bash
scripts/ansible-agent.sh
```

### Run Individual Steps
```bash
scripts/ansible-agent.sh lint          # ansible-lint check only
scripts/ansible-agent.sh syntax        # ansible-playbook --syntax-check only
scripts/ansible-agent.sh all           # full suite (default)
```

### Auto-Fix Lint Issues
```bash
FMT_MODE=fix scripts/ansible-agent.sh lint
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_LINT` | `1` | Set to `0` to skip lint step |
| `RUN_SYNTAX` | `1` | Set to `0` to skip syntax step |
| `FMT_MODE` | `auto` | `auto` = fix locally / check in CI; `check` = always check; `fix` = always fix |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes checks to YAML files only |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: lint`, `Step: syntax`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- Discovers `.yml` and `.yaml` files recursively
- `ansible-lint` runs project-wide (not scoped to individual files)
- `syntax` step only checks files containing a `hosts:` key
- `CHANGED_FILES` controls skip decisions: if no YAML files are changed, steps are skipped
- In CI (`CI=true`), `FMT_MODE` is forced to `check` regardless of setting
- Reports SKIP when no YAML files or playbooks are found
