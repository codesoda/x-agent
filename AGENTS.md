# x-agent Contributor Guide

This repository contains lean workflow runners for coding agents.
Read this file first, then open only the linked docs you need.

## Quick Rules

- Keep output concise and structured (`Step`, `Result`, `Overall`, log path).
- Keep full logs on disk and print where they are saved.
- Support shared knobs (`RUN_<STEP>`, `MAX_LINES`, `KEEP_DIR`).
- Add scenario fixtures under `tests/<agent>/` for both `clean` and `issues`.
- Ship one backlog item per commit.

## Progressive Disclosure

- Add a new agent: `docs/agents/add-x-agent.md`
- Definition of done: `docs/agents/definition-of-done.md`
- Scenario tests and fixtures: `docs/agents/scenario-tests.md`

