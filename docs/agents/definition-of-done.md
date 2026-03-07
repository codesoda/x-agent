# Definition of Done for a New x-agent

An agent is done only when all items below are complete.

## Skill and Script

- `skills/<name>-agent/SKILL.md` exists with accurate trigger language.
- `skills/<name>-agent/SKILL.md` `allowed-tools` includes patterns for all env knobs (`RUN_*`, `MAX_LINES`, `KEEP_DIR`, `FAIL_FAST`, plus any agent-specific knobs).
- `skills/<name>-agent/scripts/<name>-agent.sh` exists and is executable.
- Script starts with `set -euo pipefail`.
- Script has `--help`/`help`/`-h` usage output.

## Output Contract

- Each step emits `Step:`, `Result: PASS|FAIL|SKIP`, and `Time: Xs`.
- Each `Result: FAIL` is followed by a `Fix:` line — suggests an auto-fix command first (if one exists), then tells how to retest via the agent.
- On failure, prints truncated diagnostics (first `MAX_LINES` lines) and saves full logs to disk with path printed.
- Final output is `Overall: PASS|FAIL` and `Logs: <path>`.

## Behavior

- Supports `KEEP_DIR`, `MAX_LINES`, `FAIL_FAST`, `TMPDIR_ROOT`, and `RUN_<STEP>` toggles.
- `MAX_LINES` defaults to `40` locally, `999999` in CI (`CI=true|1`).
- CI-sensitive steps adapt behavior (e.g. format: check in CI, fix locally).
- Accepts `--fail-fast` CLI flag; when set, `all` stops after first failing step.
- If a downstream tool has native fail-fast support, it is passed through.
- Required deps checked with `need()` — exits `2` if missing.
- Missing optional tools are handled as `SKIP` with a clear reason.
- Cleanup trap preserves logs on failure or `KEEP_DIR=1`; removes temp dir on success.
- Exit codes: `0` pass, `1` fail, `2` bad usage or missing required dep.

## Documentation and Install

- `README.md` includes the new agent in "Available Agents".
- `README.md` includes basic usage examples for the new script.
- `install.sh` installs the new skill (update `SKILLS`).
- `install.sh` dependency checks include relevant optional requirements.

## Scenario Testing

- `tests/<name>-agent/clean/scenario.env` exists and expects success.
- `tests/<name>-agent/issues/scenario.env` exists and expects failure.
- Fixtures are minimal but representative.
- `tests/run-scenarios.sh` can discover and run both scenarios.

