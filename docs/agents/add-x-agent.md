# Add an x-agent

Use this workflow when adding a new `*-agent` skill and runner script.

## 1) Create the skill skeleton

Required files:

```text
skills/<name>-agent/
  SKILL.md
  scripts/<name>-agent.sh
```

Keep naming consistent:

- Skill name: `<name>-agent`
- Script name: `<name>-agent.sh`
- Temp log prefix: `<name>-agent.XXXXXX`

## 2) Script boilerplate

Every agent script must start with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Shared helpers

Copy these helpers into every new agent — they keep output consistent:

```bash
hr() { echo "------------------------------------------------------------"; }

# Returns 0 (continue) unless fail-fast is on and a step already failed.
should_continue() { [[ "$FAIL_FAST" != "1" || "$overall_ok" == "1" ]]; }

STEP_START_SECONDS=0

step() {
  local name="$1"
  STEP_START_SECONDS=$SECONDS
  hr
  echo "Step: $name"
}

fmt_elapsed() {
  local elapsed=$(( SECONDS - STEP_START_SECONDS ))
  echo "Time: ${elapsed}s"
}
```

### Dependency checks

Use a `need()` helper to fail fast (exit 2) when a required tool is missing:

```bash
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 2; }
}
```

### Temp dir and cleanup

Create a temp dir for logs and clean it up on exit:

```bash
TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"
OUTDIR="$(mktemp -d "${TMPDIR_ROOT%/}/<name>-agent.XXXXXX")"

cleanup() {
  local code="$?"
  if [[ "$KEEP_DIR" == "1" || "$code" != "0" ]]; then
    echo "Logs kept in: $OUTDIR"
  else
    rm -rf "$OUTDIR"
  fi
  exit "$code"
}
trap cleanup EXIT
```

On success the temp dir is removed. On failure (or `KEEP_DIR=1`) it is preserved so the caller can inspect full logs.

## 3) Follow the output contract

All agents should emit per step:

- `Step: <name>`
- `Result: PASS|FAIL|SKIP`
- `Time: Xs`
- `Fix:` hint after each `Result: FAIL` (see below)

And at the end:

- `Overall: PASS|FAIL`
- `Logs: <path>` (or `Logs kept in: <path>` from the cleanup trap)

### Fix hints

Every `Result: FAIL` must be followed by a `Fix:` line. The hint should:

1. **Suggest an auto-fix command first**, if one exists. For example, formatting failures should point to the agent's own fix command (`/terra-agent fmt-fix`, or note that `/cargo-agent fmt` auto-fixes locally).
2. **Then tell the caller how to retest** using the same agent (e.g. `then re-run: /cargo-agent clippy`).

Examples:

```
Result: FAIL
Fix: run /terra-agent fmt-fix to auto-format, then re-check: /terra-agent fmt-check

Result: FAIL
Fix: resolve the errors above, then re-run: /cargo-agent clippy
```

### Truncated diagnostics

On failure, print only the first `MAX_LINES` lines of output so the agent gets enough context without being overwhelmed. Always save full logs to disk and print the path:

```
Output (first 40 lines):
<truncated output>

Full log: /tmp/cargo-agent.abc123/clippy.log
```

## 4) Expose shared env knobs

Every agent should include:

- `KEEP_DIR` (default `0`)
- `MAX_LINES` (default `40`, unlimited in CI — see below)
- `FAIL_FAST` (default `0`) — also exposed as `--fail-fast` CLI flag
- `TMPDIR_ROOT` (default `/tmp`)
- `RUN_<STEP>` toggles for each step

### CI-aware `MAX_LINES`

In CI environments, diagnostics should not be truncated so the full output appears in build logs. Use this pattern:

```bash
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  MAX_LINES="${MAX_LINES:-999999}"
else
  MAX_LINES="${MAX_LINES:-40}"
fi
```

The caller can still override with `MAX_LINES=N` in either environment.

### CI-aware step behavior

Some steps should behave differently in CI. For example, formatting steps should **check** in CI (report-only, non-mutating) and **fix** locally (auto-apply changes). Use the `CI` env var to switch modes:

```bash
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  mode="check"
else
  mode="fix"
fi
```

## 5) Support `--fail-fast`

When the `all` command runs multiple steps and `--fail-fast` (or `FAIL_FAST=1`) is set, the script should stop after the first step that fails instead of running all remaining steps.

Use the `should_continue` helper before each step in the `all` path:

```bash
if [[ "$RUN_FMT" == "1" ]] && should_continue; then run_fmt || overall_ok=0; fi
if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
```

Since `overall_ok` starts as `1`, the guard passes for the first step — apply it consistently to all steps for clarity.

If a downstream tool supports its own fail-fast flag (e.g. `cargo nextest --fail-fast`), pass it through.

## 6) Support `CHANGED_FILES` scoping

When a calling agent knows which files it has modified, it can pass them via
`CHANGED_FILES="file1 file2"`. The agent should use this to scope its work
to only the affected parts of the project, falling back to the full project
when the variable is empty.

How each agent implements this varies:

- **cargo-agent**: maps changed files to workspace packages via `cargo metadata`
  and passes `-p <pkg>` to check/clippy/test.
- **npm-agent**: filters changed JS/TS files and passes them to lint/format
  fallback tools (biome, eslint, prettier) instead of `.`.
- **terra-agent**: auto-detects `TERRAFORM_CHDIR` from the directory containing
  changed `.tf` files.

Guidelines:

- `CHANGED_FILES` is always optional — when empty, run the full project.
- If scoping is not meaningful for a step, run it project-wide (e.g. typecheck,
  build, tests in npm-agent).
- Print what the scope resolved to (e.g. `Scoped to packages: -p api -p db`).
- Add `Bash(CHANGED_FILES=* scripts/<name>-agent.sh*)` to SKILL.md `allowed-tools`.

## 7) Exit codes

- `0` — all steps passed
- `1` — one or more steps failed
- `2` — bad usage, unknown command, or missing required dependency

## 8) SKILL.md

The `SKILL.md` front-matter must list `allowed-tools` patterns for every env knob the script supports, so the agent can invoke the script without prompting. Include at minimum:

```yaml
allowed-tools:
  - Bash(scripts/<name>-agent.sh*)
  - Bash(RUN_*=* scripts/<name>-agent.sh*)
  - Bash(MAX_LINES=* scripts/<name>-agent.sh*)
  - Bash(KEEP_DIR=* scripts/<name>-agent.sh*)
  - Bash(FAIL_FAST=* scripts/<name>-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/<name>-agent.sh*)
```

## 9) Update repository metadata

Update:

- `README.md` (agent table + usage examples)
- `install.sh` (`SKILLS` list and optional dependency checks)

## 10) Add scenario tests

Add at least:

- `tests/<name>-agent/clean/` for a passing fixture
- `tests/<name>-agent/issues/` for a failing fixture

Each scenario needs a `scenario.env`. See `docs/agents/scenario-tests.md`.

## 11) Validate against definition of done

Run through `docs/agents/definition-of-done.md` before commit.

