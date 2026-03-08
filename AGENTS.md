# x-agent Contributor Guide

This repository contains lean workflow runners for coding agents.
Read this file first, then open only the linked docs you need.

## Quick Rules

- **Bash 3.2 compatible** — no associative arrays, no `readarray`, no `|&`. Optimized for stock macOS.
- Keep output concise and structured (`Step`, `Result`, `Fix`, `Overall`, log path).
- Keep full logs on disk and print where they are saved.
- Support shared knobs (`RUN_<STEP>`, `MAX_LINES`, `KEEP_DIR`, `FAIL_FAST`, `CHANGED_FILES`).
- Every `Result: FAIL` must include a `Fix:` hint.
- Add scenario fixtures under `tests/<agent>/` for both `clean` and `issues`.
- `shellcheck --severity=warning` must pass on all scripts.
- Ship one backlog item per commit.

## Docs

- Contributing standards and tech requirements: `docs/contributing.md`
- Add a new agent: `docs/agents/add-x-agent.md`
- Definition of done: `docs/agents/definition-of-done.md`
- Scenario tests and fixtures: `docs/agents/scenario-tests.md`

