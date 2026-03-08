---
name: cargo-agent
description: |
  Run cargo-agent.sh — a lean Rust workflow runner that produces agent-friendly output with structured diagnostics.
  Use when: running Rust checks (fmt, clippy, check, test), verifying Rust code before committing,
  or when the user asks to run cargo checks, lint, format, or test a Rust project.
  Triggers on: cargo agent, run cargo checks, rust checks, cargo fmt clippy test, verify rust code.
context: fork
allowed-tools:
  - Bash(scripts/cargo-agent.sh*)
  - Bash(RUN_*=* scripts/cargo-agent.sh*)
  - Bash(MAX_LINES=* scripts/cargo-agent.sh*)
  - Bash(USE_NEXTEST=* scripts/cargo-agent.sh*)
  - Bash(KEEP_DIR=* scripts/cargo-agent.sh*)
  - Bash(FAIL_FAST=* scripts/cargo-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/cargo-agent.sh*)
  - Bash(RUN_INTEGRATION=* scripts/cargo-agent.sh*)
---

# Cargo Agent

Run the `cargo-agent.sh` script for lean, structured Rust workflow output designed for coding agents.

## Script Location

```
scripts/cargo-agent.sh
```

## Usage

### Run Full Suite (fmt + clippy + tests)
```bash
scripts/cargo-agent.sh
```

### Run Individual Steps
```bash
scripts/cargo-agent.sh fmt      # format check only
scripts/cargo-agent.sh check    # cargo check only
scripts/cargo-agent.sh clippy   # clippy only
scripts/cargo-agent.sh test     # tests only
scripts/cargo-agent.sh all      # full suite (default)
```

### Run Specific Tests
Pass extra arguments through to cargo-nextest:
```bash
scripts/cargo-agent.sh test test_login        # tests matching "test_login"
scripts/cargo-agent.sh test -p db             # tests in the db crate
scripts/cargo-agent.sh test -p api test_auth  # "test_auth" in api crate
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_FMT` | `1` | Set to `0` to skip fmt |
| `RUN_CHECK` | `1` | Set to `0` to skip check |
| `RUN_CLIPPY` | `1` | Set to `0` to skip clippy |
| `RUN_TESTS` | `1` | Set to `0` to skip tests |
| `RUN_SQLX` | `1` | Set to `0` to skip sqlx cache verify |
| `RUN_INTEGRATION` | `0` | Set to `1` to enable integration tests |
| `USE_NEXTEST` | `auto` | `auto`/`1`/`0` — controls nextest usage |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes check/clippy/test to affected packages |
| `MAX_LINES` | `40` | Max diagnostic lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: fmt`, `Step: clippy`, etc.)
- Results are `PASS`, `FAIL`, or `SKIP`
- Compiler diagnostics are deduplicated and truncated to `MAX_LINES`
- Full JSON logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- The script must be run from within a Rust project directory
- When clippy is enabled, `check` is automatically skipped (clippy is a superset)
- Requires: `bash`, `jq`, `cargo`. Optional: `cargo-nextest` for tests, `cargo-sqlx` for sqlx cache verify
- On failure, the temp log directory is preserved automatically for inspection
- `CHANGED_FILES` uses `cargo metadata` to resolve files to workspace packages, then scopes check/clippy/test to only those packages
- Short package names are auto-resolved (e.g. `-p api` matches `my-project-api`)
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
