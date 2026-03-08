# Spec 05: gha-agent

## Objective

Create a new gha-agent that lints GitHub Actions workflow files using `actionlint`.

## Source

- **PRD User Story:** US-004
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want a gha-agent that lints GitHub Actions workflow files so I can catch workflow errors before pushing.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_LINT)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Required tools (actionlint) checked with need()
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/gha-agent/scripts/gha-agent.sh`
- **Create:** `skills/gha-agent/SKILL.md`
- **Create:** `tests/gha-agent/clean/` (scenario.env + valid workflow fixture)
- **Create:** `tests/gha-agent/issues/` (scenario.env + invalid workflow fixture)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `gha-agent.sh`

**Agent-specific knobs:**
```bash
RUN_LINT="${RUN_LINT:-1}"
```

**Required tools:** `need actionlint`

**Step: lint**
- If no `.github/workflows/` directory exists: `Result: SKIP (no .github/workflows/ directory found)`
- Run `actionlint` (it auto-discovers `.github/workflows/*.yml` and `*.yaml`)
- If CHANGED_FILES is set, filter to only `.yml`/`.yaml` files under `.github/workflows/` and pass them as args
- If CHANGED_FILES is set but none match workflow path, SKIP
- Capture output, log to disk
- Fix hint: `Fix: resolve the workflow errors above, then re-run: /gha-agent lint`

**Commands:** `lint`, `all` (default)

This is a simple single-step agent. The main function is straightforward.

### Scenario Tests

**clean fixture (`tests/gha-agent/clean/`):**
- `.github/workflows/ci.yml`: a minimal valid GitHub Actions workflow
  ```yaml
  name: CI
  on: [push]
  jobs:
    test:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - run: echo "hello"
  ```
- REQUIRED_TOOLS="actionlint"

**issues fixture (`tests/gha-agent/issues/`):**
- `.github/workflows/bad.yml`: a workflow with actionlint-detectable issues
  - e.g., invalid `runs-on` value, missing `uses` version, or bad expression syntax like `${{ github.events.push }}`
- REQUIRED_TOOLS="actionlint"

### SKILL.md

Triggers on: gha agent, github actions lint, actionlint, workflow lint, github actions checks.
Single step so allowed-tools is minimal.

## Test Strategy

- `tests/run-scenarios.sh gha-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes
- Verify SKIP when no `.github/workflows/` exists
- Verify CHANGED_FILES scoping filters to workflow files only

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/gha-agent/scripts/gha-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `actionlint` on workflow files
- [ ] Reports SKIP when no `.github/workflows/` directory exists
- [ ] CHANGED_FILES scoping filters to `.yml`/`.yaml` under `.github/workflows/`
- [ ] Commands: `lint`, `all`
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
