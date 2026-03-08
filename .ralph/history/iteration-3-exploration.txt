# Exploration Notes

## Key Files & Roles

- `lib/x-agent-common.sh` — shared boilerplate library sourced by all agents; provides env defaults, step/result/overall formatting, need(), setup_outdir(), setup_lock(), and should_continue(). Side-effect-free on source.
- `AGENTS.md` — repository guardrails for Bash 3.2 compatibility, output contract, and workflow expectations.
- `skills/npm-agent/scripts/npm-agent.sh` — current agent pattern with shared defaults, step timing, cleanup, and `--help` usage.
- `skills/cargo-agent/scripts/cargo-agent.sh` — shows lock+cleanup precedence, nextest integration, and verbose `overall_ok` flow.
- `skills/terra-agent/scripts/terra-agent.sh` — shows optional tool skip behavior and terraform-specific lock/cleanup conventions.
- `skills/*/SKILL.md` — shared metadata schema including `allowed-tools` and trigger language.
- `install.sh` — local vs remote install modes, optional dependency checks, and destination patching.
- `tests/run-scenarios.sh` — authoritative test harness contract for all agents; shellcheck plus scenario fixture execution.
- `tests/*/scenario.env` — scenario metadata (`SCENARIO_NAME`, `AGENT_SCRIPT`, `RUN_ARGS`, `EXPECT_EXIT`, `REQUIRED_TOOLS`).
- `tests/cargo-agent/flock/flock-test.sh` — current lock integration test for waiting on lock acquisition.
- `docs/agents/add-x-agent.md` — how new agents are expected to be structured, including boilerplate expectations and install updates.
- `docs/agents/scenario-tests.md` — fixture conventions and execution format.
- `docs/agents/definition-of-done.md` — acceptance contract for each agent.
- `docs/testing.md` — testing and CI matrix expectations.
- `.github/workflows/ci.yml` — shellcheck job and per-agent scenario execution matrix.
- `README.md` — user-facing discoverability for available agents and quick command references.
- `.ralph/specs/01-shared-library-extract.md` — explicit FR list for spec 01.

## Patterns & Conventions

- Bash headers are standardized: `#!/usr/bin/env bash` + `set -euo pipefail`.
- Output contract is strict and machine-aided: each step prints `Step:`, `Result: PASS|FAIL|SKIP`, optional `Fix:`, and `Time:`; final section prints `Overall:` and `Logs:`.
- `MAX_LINES` is CI-aware; local defaults are concise and CI allows large output (`MAX_LINES=999999`).
- Step failure handling is controlled by an `overall_ok` accumulator and `should_continue` guard.
- Cleanup trap pattern preserves logs on failure and optionally keeps them on success via `KEEP_DIR`.
- Optional tools are converted to skip or degraded behavior instead of hard failures.
- `--help|help|-h` and `--fail-fast` are user-facing entry points for agent control flow.
- Installer supports two modes: local checkout mode (symlink `skills/*`) and remote mode (copied skill directory).

## Database Schema

No database layer exists in this repository.

## Test Infrastructure

- `tests/run-scenarios.sh` drives all behavior checks and is the common validation entrypoint.
- Shellcheck runs first (or as dedicated CI job) using `--severity=warning` across `skills/*/scripts/*.sh`, `install.sh`, and test scripts.
- Scenarios are discovered by finding `tests/*/scenario.env`; each fixture runs via its `AGENT_SCRIPT` in fixture directory.
- Missing dependencies in scenario `REQUIRED_TOOLS` cause a soft `SKIP` instead of hard failure.
- `tests/cargo-agent/flock` extends coverage to lock behavior via a background lock holder helper script.
- CI runs separate jobs per agent and matrix variants for optional tools (e.g., no nextest/tflint vs with tools).

## Architecture & Data Flow

- Entry point: a single agent script executed from project root; it parses CLI flags, sets run-mode globals, and calls step functions in order.
- Shared boilerplate currently resides inside each script; extraction moves it into a central `lib/x-agent-common.sh` while preserving call points.
- Runtime flow is: initialize env defaults → resolve dependencies with `need()` → prepare output directory + lock → run selected command path (`format/check/test/...`) → print per-step output → print overall status.
- Logging flow: each step writes to `$OUTDIR/<step>.log`; failure paths print a bounded snippet and preserve `OUTDIR` path.
- Install flow: `install.sh` copies or symlinks skills and `lib/` directory, then rewrites `SKILL.md` paths depending on install mode. Remote installs fetch `lib/x-agent-common.sh` and copy it to each destination root's `lib/` directory. Local installs symlink the `lib/` directory.
- Test flow: local invocation and CI both rely on the same scenario runner; changes must remain compatible with both.
