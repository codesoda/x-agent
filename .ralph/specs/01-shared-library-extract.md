# Spec 01: Extract Shared Library

## Objective

Create `lib/x-agent-common.sh` containing all boilerplate functions duplicated across existing agents. This is a new additive file — no existing agents are modified in this spec.

## Source

- **PRD User Story:** US-001 (partial — extraction only, refactor in spec 02)
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-10

## User Story Context

> As a contributor, I want common boilerplate extracted into a shared library so that new agents are smaller and consistent.

This spec covers only the creation of the shared library. The refactoring of existing agents to use it is in spec 02.

## Functional Requirements

- FR-1: All agents source `lib/x-agent-common.sh` for shared boilerplate
- FR-2: All agents support universal knobs: `KEEP_DIR`, `MAX_LINES`, `FAIL_FAST`, `TMPDIR_ROOT`, `CHANGED_FILES`
- FR-4: All agents produce structured output
- FR-5: All agents support `--fail-fast` CLI flag and `--help`/`help`/`-h` usage output
- FR-6: Required tools checked with `need()` (exit 2 if missing)
- FR-7: Cleanup trap preserves logs on failure or `KEEP_DIR=1`
- FR-8: Workflow lock (flock with Perl fallback) prevents concurrent runs per agent
- FR-9: `MAX_LINES` defaults to 40 locally, 999999 when `CI=true|1`

## Components

- **Create:** `lib/x-agent-common.sh`

## Implementation Details

Extract the following functions and patterns from existing agents (use `skills/npm-agent/scripts/npm-agent.sh` as the primary reference):

### Variables to initialize (agent can override after sourcing):
```
KEEP_DIR="${KEEP_DIR:-0}"
FAIL_FAST="${FAIL_FAST:-0}"
CHANGED_FILES="${CHANGED_FILES:-}"
TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"
```

### CI-aware MAX_LINES:
```bash
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  MAX_LINES="${MAX_LINES:-999999}"
else
  MAX_LINES="${MAX_LINES:-40}"
fi
```

### Helper functions to extract:
1. `hr()` — print separator line
2. `step()` — print step header, record start time
3. `fmt_elapsed()` — print elapsed time for current step
4. `should_continue()` — fail-fast guard
5. `need()` — check for required tool, exit 2 if missing

### Setup functions (called by agent, not auto-executed on source):
6. `setup_outdir <agent-name>` — create temp dir, set OUTDIR, install cleanup trap
7. `setup_lock <agent-name>` — acquire workflow lock (flock with Perl fallback)
8. `print_overall <overall_ok>` — print final Overall: PASS|FAIL + Logs: path

### Step result helper:
9. `print_result <ok> <log_path> <fix_hint>` — print Result: PASS|FAIL, optional Fix:, Full log:, and Time:

### Important constraints:
- The file must be **sourceable without side effects** — no auto-execution of setup functions
- Must be Bash 3.2 compatible (no associative arrays, no readarray, no `|&`)
- Must pass `shellcheck --severity=warning`
- Use `#!/usr/bin/env bash` shebang even though it's sourced (for shellcheck)

### Install.sh considerations:
- The `install.sh` must be updated to also install `lib/x-agent-common.sh` alongside skills
- For local (symlink) installs, the relative path from `skills/<name>/scripts/` to `lib/` is `../../../lib/`
- For remote installs, the lib must be copied into a location accessible from the installed skill
- Add a `resolve_lib_dir()` function or use a relative path resolution pattern in the shared lib itself

### How agents will source it:
```bash
# Resolve lib dir relative to script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"
```

## Test Strategy

- `shellcheck --severity=warning lib/x-agent-common.sh` passes
- Source the lib in a test script and verify all functions are available
- Verify `setup_outdir` creates temp dir and cleanup trap works
- Verify `need` exits with code 2 for missing tools
- Existing agent tests still pass (agents are NOT modified in this spec)

## Dependencies

None — this is the first spec.

## Acceptance Criteria

- [ ] `lib/x-agent-common.sh` exists with all shared functions listed above
- [ ] File is Bash 3.2 compatible
- [ ] `shellcheck --severity=warning lib/x-agent-common.sh` passes
- [ ] Sourcing the file does not produce output or side effects
- [ ] `setup_outdir`, `setup_lock`, and `print_overall` are callable functions, not auto-executed
- [ ] `install.sh` updated to handle `lib/` directory for both local and remote installs
- [ ] All existing agent scenario tests still pass (agents are unchanged)
