# Spec 10: sql-agent

## Objective

Create a new sql-agent that lints SQL files with `sqlfluff` and optionally auto-fixes them.

## Source

- **PRD User Story:** US-009
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-10, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want an sql-agent that lints and optionally auto-fixes SQL files so I can maintain consistent SQL style.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_LINT, RUN_FIX)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Required tools (sqlfluff) checked with need()
- FR-10: FMT_MODE=check|fix; CI forces check mode
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/sql-agent/scripts/sql-agent.sh`
- **Create:** `skills/sql-agent/SKILL.md`
- **Create:** `tests/sql-agent/clean/` (scenario.env + valid SQL files)
- **Create:** `tests/sql-agent/issues/` (scenario.env + SQL files with lint issues)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `sql-agent.sh`

**Agent-specific knobs:**
```bash
RUN_LINT="${RUN_LINT:-1}"
RUN_FIX="${RUN_FIX:-0}"          # opt-in
FMT_MODE="${FMT_MODE:-auto}"      # auto = check in CI, respects RUN_FIX locally
SQLFLUFF_DIALECT="${SQLFLUFF_DIALECT:-ansi}"  # postgres, mysql, bigquery, etc.
```

**Required tools:** `need sqlfluff`

**File discovery:**
- If CHANGED_FILES set, filter to `.sql` files
- Otherwise, find all `.sql` files recursively (excluding `.git/`, `node_modules/`, `vendor/`)
- If no `.sql` files found: SKIP all steps

**Step: lint**
- Run `sqlfluff lint --dialect $SQLFLUFF_DIALECT <files>`
- sqlfluff outputs violations with line numbers and rule codes
- Capture output, log to disk
- Fix hint: `Fix: run /sql-agent fix or FMT_MODE=fix /sql-agent to auto-fix, then re-run: /sql-agent lint`

**Step: fix (opt-in)**
- Enabled when `RUN_FIX=1` or `FMT_MODE=fix`
- CI forces lint-only regardless (FMT_MODE=auto → check in CI)
- Run `sqlfluff fix --dialect $SQLFLUFF_DIALECT --force <files>` (--force to avoid interactive prompts)
- Fix hint (if fix itself fails): `Fix: some issues cannot be auto-fixed — resolve manually, then re-run: /sql-agent lint`

**Commands:** `lint`, `fix`, `all` (default — runs lint; also runs fix if RUN_FIX=1 or FMT_MODE=fix)

**Note on `all` command order:** When fix is enabled, run fix BEFORE lint so lint reports the post-fix state.

### Scenario Tests

**clean fixture (`tests/sql-agent/clean/`):**
- `queries/select.sql`: valid, well-formatted SQL
  ```sql
  SELECT
      id,
      name,
      email
  FROM
      users
  WHERE
      active = 1
  ORDER BY
      name;
  ```
- REQUIRED_TOOLS="sqlfluff"

**issues fixture (`tests/sql-agent/issues/`):**
- `queries/bad.sql`: SQL with lint violations
  ```sql
  SELECT id,name,email FROM users WHERE active=1 ORDER BY name
  ```
  - Triggers common sqlfluff rules: spacing, capitalization, trailing newline
- REQUIRED_TOOLS="sqlfluff"

### SKILL.md

Triggers on: sql agent, sqlfluff, sql lint, sql format, sql checks, validate sql.
Include `SQLFLUFF_DIALECT=*`, `RUN_FIX=*`, `FMT_MODE=*` in allowed-tools.

## Test Strategy

- `tests/run-scenarios.sh sql-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes
- Verify SKIP when no .sql files found
- Verify SQLFLUFF_DIALECT passes through correctly
- Verify RUN_FIX=1 runs sqlfluff fix
- Verify CI forces lint-only

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/sql-agent/scripts/sql-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `sqlfluff lint` on all `.sql` files (or scoped)
- [ ] `fix` step defaults OFF, runs `sqlfluff fix` when enabled
- [ ] CI forces lint-only regardless of FMT_MODE
- [ ] SQLFLUFF_DIALECT passed through to --dialect flag (default: ansi)
- [ ] Auto-discovers .sql files recursively
- [ ] CHANGED_FILES scoping works
- [ ] Reports SKIP when no .sql files found
- [ ] Commands: `lint`, `fix`, `all`
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
