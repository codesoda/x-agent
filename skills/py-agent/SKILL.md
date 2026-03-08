---
name: py-agent
description: |
  Run py-agent.sh — a lean Python workflow runner that produces agent-friendly output.
  Use when: running Python checks (format, lint, typecheck, test), verifying Python code before committing,
  or when the user asks to run Python checks, lint, format, or test a Python project.
  Triggers on: py agent, run python checks, python checks, ruff mypy pytest, verify python code, run py checks.
context: fork
allowed-tools:
  - Bash(scripts/py-agent.sh*)
  - Bash(RUN_*=* scripts/py-agent.sh*)
  - Bash(MAX_LINES=* scripts/py-agent.sh*)
  - Bash(KEEP_DIR=* scripts/py-agent.sh*)
  - Bash(FAIL_FAST=* scripts/py-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/py-agent.sh*)
---

# Py Agent

Run the `py-agent.sh` script for lean, structured Python workflow output designed for coding agents.

## Script Location

```
scripts/py-agent.sh
```

## Usage

### Run Full Suite (format + lint + typecheck + test)
```bash
scripts/py-agent.sh
```

### Run Individual Steps
```bash
scripts/py-agent.sh format      # format (auto-fix locally, check in CI)
scripts/py-agent.sh lint         # lint only
scripts/py-agent.sh typecheck    # typecheck only
scripts/py-agent.sh test         # tests only
scripts/py-agent.sh all          # full suite (default)
```

### Pass Args to Tests
```bash
scripts/py-agent.sh test -k test_login       # filter by name
scripts/py-agent.sh test tests/unit/          # specific directory
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_FORMAT` | `1` | Set to `0` to skip format |
| `RUN_LINT` | `1` | Set to `0` to skip lint |
| `RUN_TYPECHECK` | `1` | Set to `0` to skip typecheck |
| `RUN_TESTS` | `1` | Set to `0` to skip tests |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |
| `FAIL_FAST` | `0` | Stop after first failing step; passes `-x` to pytest |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes format/lint to affected `.py` files |

## Auto-Detection

- **Runner**: detects uv, poetry, or plain python from lock files
- **Format**: tries ruff format, then black
- **Lint**: tries ruff check, then flake8
- **Typecheck**: tries mypy, then pyright
- **Tests**: tries pytest, then python -m unittest discover
- **CI mode**: format runs `--check` in CI, auto-fixes locally

## Output Format

- Each step prints a header (`Step: format`, `Step: lint`, etc.)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES` with full logs on disk
- `Fix:` hint after each failure (suggests auto-fix commands where available)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- The script must be run from within a Python project directory (requires pyproject.toml, setup.py, setup.cfg, or requirements.txt)
- Steps are skipped gracefully if no matching tool is found
- On failure, the temp log directory is preserved automatically for inspection
