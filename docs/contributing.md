# Contributing to x-agent

Standards and conventions for working in this repository.

## Tech Standards

### Bash 3.2 Compatibility

All shell scripts must work with **Bash 3.2**, which ships as the default
on macOS. This means:

- **No associative arrays** (`local -A` / `declare -A`) — use string variables
  with `grep -Fxq` for dedup, or indexed arrays.
- **No `${!arr[@]}` on associative arrays** — iterate indexed arrays or
  newline-delimited strings instead.
- **No `readarray` / `mapfile`** — use `while read` loops.
- **No `|&`** (pipe stderr) — use `2>&1 |` instead.
- **No `;&` or `;;&`** in `case` fall-through — each pattern must end with `;;`.
- **Empty arrays are unbound under `set -u`** — guard with
  `${arr[@]+"${arr[@]}"}` or check `${#arr[@]}` before expanding.

Use `shellcheck --severity=warning` to catch common issues (it runs in CI
and in the local test suite via `tests/run-scenarios.sh`).

### Script Headers

Every script starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Exit Codes

- `0` — success
- `1` — one or more steps failed
- `2` — bad usage, unknown command, or missing required dependency

### CI Behaviour

Scripts detect CI via `CI=true|1` and adapt:

- `MAX_LINES` defaults to unlimited (full output in build logs).
- Formatting steps run in **check** mode (non-mutating) instead of **fix**.

## Repository Layout

```
skills/<name>-agent/
  SKILL.md                      # Skill metadata + allowed-tools
  scripts/<name>-agent.sh       # Runner script
docs/
  contributing.md               # This file
  agents/
    add-x-agent.md              # Step-by-step guide for creating a new agent
    definition-of-done.md       # Checklist before merging
    scenario-tests.md           # How test fixtures work
tests/
  run-scenarios.sh              # Test runner (also runs shellcheck)
  <name>-agent/
    clean/scenario.env          # Passing fixture
    issues/scenario.env         # Failing fixture
install.sh                      # User-facing installer
```

## Creating a New Agent

Follow `docs/agents/add-x-agent.md` — it covers the full workflow:

1. Skill skeleton (naming, file structure)
2. Script boilerplate (shared helpers, temp dir, cleanup trap)
3. Output contract (`Step`, `Result`, `Fix`, `Overall`, `Logs`)
4. Shared env knobs (`KEEP_DIR`, `MAX_LINES`, `FAIL_FAST`, `RUN_<STEP>`)
5. `--fail-fast` support with `should_continue`
6. `CHANGED_FILES` scoping (scope work to affected files/packages)
7. Exit codes
8. SKILL.md `allowed-tools` patterns
9. Repository metadata updates (`README.md`, `install.sh`)
10. Scenario tests (clean + issues fixtures)
11. Validate against `docs/agents/definition-of-done.md`

## Running Tests

```bash
# All scenarios + shellcheck
tests/run-scenarios.sh

# Filter by agent
tests/run-scenarios.sh cargo-agent

# Just shellcheck
tests/run-scenarios.sh shellcheck

# List all scenarios
tests/run-scenarios.sh --list
```

shellcheck is **required** — the test runner fails if it is not installed.
Install with `brew install shellcheck`.

## Commit Style

- One backlog item per commit.
- Prefix with type: `feat:`, `fix:`, `docs:`, `ci:`, `test:`.
- Keep the first line under 72 characters; add detail in the body.
