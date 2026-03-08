# x-agent Contributor Guide

This repository contains lean workflow runners for coding agents.
Read this file first, then open only the linked docs you need.

## Quick Rules

- **Bash 3.2 compatible** — no associative arrays, no `readarray`, no `|&`. Optimized for stock macOS.
- Keep output concise and structured (`Step`, `Result`, `Fix`, `Overall`, log path).
- Support shared knobs (`RUN_<STEP>`, `MAX_LINES`, `KEEP_DIR`, `FAIL_FAST`, `CHANGED_FILES`).
- Every `Result: FAIL` must include a `Fix:` hint.
- The `help`/`--help`/`-h` command must work without project context — resolve it before any project-existence checks.
- `shellcheck --severity=warning` must pass on all scripts.
- Ship one backlog item per commit.

## Testing

Run `tests/run-scenarios.sh` — it runs shellcheck then all scenario fixtures.
Each agent needs `clean` (pass) and `issues` (fail) fixtures. CI runs the
same script across tool-combination matrices (e.g. with/without nextest).

See `docs/testing.md` for full details.

## Docs

- Contributing standards and tech requirements: `docs/contributing.md`
- Testing (local + CI): `docs/testing.md`
- Add a new agent: `docs/agents/add-x-agent.md`
- Definition of done: `docs/agents/definition-of-done.md`
- Scenario fixtures contract: `docs/agents/scenario-tests.md`

