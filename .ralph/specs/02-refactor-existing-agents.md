# Spec 02: Refactor Existing Agents to Use Shared Library

## Objective

Refactor cargo-agent, npm-agent, and terra-agent to source `lib/x-agent-common.sh` instead of duplicating boilerplate. Output must be identical before and after.

## Source

- **PRD User Story:** US-001 (completion — refactor portion)
- **Functional Requirements:** FR-1

## User Story Context

> As a contributor, I want common boilerplate extracted into a shared library so that new agents are smaller and consistent.

This spec completes US-001 by refactoring the three existing agents to use the shared lib created in spec 01.

## Functional Requirements

- FR-1: All agents source `lib/x-agent-common.sh` for shared boilerplate

## Components

- **Modify:** `skills/cargo-agent/scripts/cargo-agent.sh`
- **Modify:** `skills/npm-agent/scripts/npm-agent.sh`
- **Modify:** `skills/terra-agent/scripts/terra-agent.sh`

## Implementation Details

For each of the three existing agents:

1. **Add source line** at the top (after `set -euo pipefail`):
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"
```

2. **Remove duplicated code** that now lives in the shared lib:
   - `hr()` function
   - `step()` function and `STEP_START_SECONDS` variable
   - `fmt_elapsed()` function
   - `should_continue()` function
   - `need()` function
   - `KEEP_DIR`, `MAX_LINES`, `FAIL_FAST`, `TMPDIR_ROOT`, `CHANGED_FILES` variable defaults
   - CI-aware `MAX_LINES` detection block
   - Cleanup trap function and `trap cleanup EXIT` line
   - Workflow lock block (flock with Perl fallback)

3. **Replace with calls to shared setup functions:**
   - Call `setup_outdir "<agent-name>"` instead of inline mktemp + cleanup trap
   - Call `setup_lock "<agent-name>"` instead of inline flock block
   - Use `print_overall "$overall_ok"` instead of inline final output block (if applicable)

4. **Keep agent-specific code intact:**
   - Agent-specific `RUN_<STEP>` variables (these override defaults after sourcing)
   - All `run_<step>()` functions
   - The `main()` function and command dispatch
   - The `usage()` function
   - Any agent-specific helpers (e.g., `detect_pm()` in npm-agent)

### Key constraint: Output parity

The refactored agents must produce **byte-identical output** for the same inputs. Run each agent's scenario tests before and after to verify. The only acceptable differences are timing values (`Time: Xs`).

## Test Strategy

- Run `tests/run-scenarios.sh cargo-agent` — all scenarios pass
- Run `tests/run-scenarios.sh npm-agent` — all scenarios pass
- Run `tests/run-scenarios.sh terra-agent` — all scenarios pass
- `shellcheck --severity=warning` passes on all three refactored scripts
- Verify each script is smaller than before (boilerplate removed)

## Dependencies

- Spec 01 (shared library must exist)

## Acceptance Criteria

- [ ] All three agents source `lib/x-agent-common.sh`
- [ ] Duplicated boilerplate removed from all three agents
- [ ] `tests/run-scenarios.sh` passes for cargo-agent, npm-agent, terra-agent
- [ ] `shellcheck --severity=warning` passes on all three scripts
- [ ] Output format is identical before/after (verified by scenario tests)
- [ ] Each agent script is measurably smaller (fewer lines)
