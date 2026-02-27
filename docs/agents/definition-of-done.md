# Definition of Done for a New x-agent

An agent is done only when all items below are complete.

## Skill and Script

- `skills/<name>-agent/SKILL.md` exists with accurate trigger language.
- `skills/<name>-agent/scripts/<name>-agent.sh` exists and is executable.
- Script has `--help`/`help` usage output.
- Script uses lean step-based output and final overall status.

## Behavior

- Supports `KEEP_DIR`, `MAX_LINES`, and `RUN_<STEP>` toggles.
- Missing optional tools are handled as `SKIP` with a clear reason.
- Failures preserve logs and print truncated diagnostics.
- Pass path exits `0`; failing path exits non-zero.

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

