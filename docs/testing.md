# Testing

All testing — local and CI — runs through `tests/run-scenarios.sh`.

## Local Testing

```bash
# Everything (shellcheck + all scenario fixtures)
tests/run-scenarios.sh

# Filter to one agent
tests/run-scenarios.sh cargo-agent

# Just shellcheck
tests/run-scenarios.sh shellcheck

# List available scenarios
tests/run-scenarios.sh --list
```

**Prerequisites**: `shellcheck` is required (`brew install shellcheck`).
Each scenario declares its own tool requirements in `REQUIRED_TOOLS` — if a
tool is missing, that scenario is skipped.

## Shellcheck

All shell scripts are linted with `shellcheck --severity=warning`. This runs:

- Locally as the first check in `tests/run-scenarios.sh` (fails if shellcheck
  is not installed).
- In CI as a dedicated job.

## Scenario Fixtures

Each agent has fixture projects under `tests/<agent>/` that exercise known
pass and fail paths. See `docs/agents/scenario-tests.md` for the full
`scenario.env` contract and directory layout.

At minimum every agent needs:

- `tests/<name>-agent/clean/` — expects exit `0` (everything passes)
- `tests/<name>-agent/issues/` — expects exit `1` (intentional failures)

## CI Workflow

GitHub Actions runs on every push to `main` and on all pull requests
(`.github/workflows/ci.yml`).

### Jobs

| Job | What it does |
|-----|-------------|
| **shellcheck** | Lints all scripts with `--severity=warning` |
| **cargo-agent (baseline)** | Rust toolchain only, `USE_NEXTEST=0` |
| **cargo-agent (with-nextest)** | Adds `cargo-nextest`, `USE_NEXTEST=auto` |
| **npm-agent** | Node 22 |
| **terra-agent (baseline)** | Terraform only |
| **terra-agent (with-tflint)** | Adds tflint |

All matrix jobs use `fail-fast: false` so every combination runs regardless
of individual failures.

### Design Principles

- **Test with and without optional tools** — matrix variants install optional
  dependencies (nextest, tflint) so we verify both the happy path and the
  graceful-skip path.
- **Same runner locally and in CI** — CI calls the same
  `tests/run-scenarios.sh` that developers run locally. No separate test
  harness.
- **CI-aware behaviour** — agents detect `CI=true` and adapt (unlimited
  `MAX_LINES`, check-only formatting). The workflow sets this env var
  explicitly.

### Adding CI Coverage for a New Agent

1. Add `clean` and `issues` scenario fixtures (see above).
2. Add a new job block to `.github/workflows/ci.yml`.
3. If the agent has optional tools, use a matrix to test with and without them.
4. The job should install required tools and call
   `tests/run-scenarios.sh <agent-name>`.
