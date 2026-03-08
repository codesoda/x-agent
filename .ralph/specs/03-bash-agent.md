# Spec 03: bash-agent

## Objective

Create a new bash-agent that validates shell scripts with `bash -n` (syntax checking) and `shellcheck` (linting).

## Source

- **PRD User Story:** US-002
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want a bash-agent that validates shell scripts for syntax errors and lint issues so I can catch problems before CI.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs (KEEP_DIR, MAX_LINES, FAIL_FAST, TMPDIR_ROOT, CHANGED_FILES)
- FR-3: Per-step toggles (RUN_SYNTAX, RUN_LINT)
- FR-4: Structured output (Step/Result/Fix/Overall)
- FR-5: --fail-fast and --help support
- FR-6: Required tools checked with need()
- FR-11: SKILL.md with trigger language
- FR-12: install.sh updated
- FR-13: Scenario test fixtures

## Components

- **Create:** `skills/bash-agent/scripts/bash-agent.sh`
- **Create:** `skills/bash-agent/SKILL.md`
- **Create:** `tests/bash-agent/clean/scenario.env` + fixture files
- **Create:** `tests/bash-agent/issues/scenario.env` + fixture files
- **Modify:** `install.sh` (add bash-agent to SKILLS list + dep checks)
- **Modify:** `README.md` (add bash-agent to Available Agents table + usage)

## Implementation Details

### Script: `bash-agent.sh`

**Header:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# bash-agent: lean shell script validation for coding agents
# deps: bash, shellcheck

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"
```

**Agent-specific knobs:**
```bash
RUN_SYNTAX="${RUN_SYNTAX:-1}"
RUN_LINT="${RUN_LINT:-1}"
SHELLCHECK_SEVERITY="${SHELLCHECK_SEVERITY:-warning}"
```

**Required tools:** `need bash`, `need shellcheck`

**File discovery:**
- If `CHANGED_FILES` is set, filter to `.sh` files that exist
- Otherwise, find all `.sh` files recursively (excluding common dirs like `node_modules`, `.git`, `vendor`)
- Print count of discovered files

**Step: syntax**
- Run `bash -n` on each discovered `.sh` file
- Collect failures, log full output
- On failure: `Fix: resolve syntax errors above, then re-run: /bash-agent syntax`

**Step: lint**
- Run `shellcheck --severity=$SHELLCHECK_SEVERITY` on all discovered `.sh` files
- On failure: extract shellcheck error codes and include wiki links in Fix: hint
  - e.g. `Fix: see https://www.shellcheck.net/wiki/SC2086 — resolve issues, then re-run: /bash-agent lint`
- Log full output to disk

**Commands:** `syntax`, `lint`, `all` (default runs both)

### SKILL.md

Follow the npm-agent SKILL.md pattern. Key trigger language:
```
Use when: running shell/bash script checks (syntax, lint), verifying shell scripts before committing,
or when the user asks to run shellcheck, bash checks, or validate shell scripts.
Triggers on: bash agent, shell agent, shellcheck, bash lint, shell checks, verify shell scripts.
```

Allowed-tools must include patterns for `SHELLCHECK_SEVERITY=*`.

### Scenario Tests

**clean fixture (`tests/bash-agent/clean/`):**
- `scenario.env`: EXPECT_EXIT=0, REQUIRED_TOOLS="bash shellcheck"
- `scripts/good.sh`: a valid, clean shell script that passes both bash -n and shellcheck

**issues fixture (`tests/bash-agent/issues/`):**
- `scenario.env`: EXPECT_EXIT=1, REQUIRED_TOOLS="bash shellcheck"
- `scripts/bad.sh`: a shell script with syntax errors or shellcheck violations
  - e.g., unquoted variable `$foo` used in a context that triggers SC2086

### install.sh

- Add `bash-agent` to `SKILLS` variable
- Add dep check for `shellcheck` under bash-agent selection
- Add snippet line for bash-agent in `print_agents_md_snippet`

### README.md

- Add row to Available Agents table: `bash-agent | Bash/Shell | syntax (bash -n), lint (shellcheck)`
- Add usage section with examples

## Test Strategy

- `tests/run-scenarios.sh bash-agent` — clean passes (exit 0), issues fails (exit 1)
- `shellcheck --severity=warning skills/bash-agent/scripts/bash-agent.sh` passes
- Manual test: run in a directory with mixed good/bad .sh files
- Verify `CHANGED_FILES` scoping works (only checks listed files)
- Verify `SHELLCHECK_SEVERITY` knob works (e.g., set to `error` to ignore warnings)

## Dependencies

- Spec 01 (shared library)
- Spec 02 (refactored agents — ensures shared lib integration pattern is proven)

## Acceptance Criteria

- [ ] `skills/bash-agent/scripts/bash-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `syntax` step runs `bash -n` on all `.sh` files (or scoped via CHANGED_FILES)
- [ ] `lint` step runs `shellcheck` on all `.sh` files (or scoped)
- [ ] Failed shellcheck results include wiki link in Fix: hint
- [ ] Commands: `syntax`, `lint`, `all` (default runs both)
- [ ] `--help` prints usage
- [ ] `SKILL.md` exists with trigger language and allowed-tools patterns
- [ ] `install.sh` updated with bash-agent
- [ ] `README.md` updated with bash-agent
- [ ] `tests/bash-agent/clean/` scenario passes (exit 0)
- [ ] `tests/bash-agent/issues/` scenario fails (exit 1)
- [ ] `shellcheck --severity=warning` passes on the script
