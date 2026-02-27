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

## 2) Follow the output contract

All agents should emit:

- `Step: <name>`
- `Result: PASS|FAIL|SKIP` for each step
- `Overall: PASS|FAIL` at the end
- `Logs: <path>` (or `Logs kept in: <path>` on cleanup)

On failures, print only the first `MAX_LINES` lines and keep full logs on disk.

## 3) Expose shared env knobs

Every agent should include:

- `KEEP_DIR` (default `0`)
- `MAX_LINES` (default `40`)
- `RUN_<STEP>` toggles for each step

## 4) Update repository metadata

Update:

- `README.md` (agent table + usage examples)
- `install.sh` (`SKILLS` list and optional dependency checks)

## 5) Add scenario tests

Add at least:

- `tests/<name>-agent/clean/` for a passing fixture
- `tests/<name>-agent/issues/` for a failing fixture

Each scenario needs a `scenario.env`. See `docs/agents/scenario-tests.md`.

## 6) Validate against definition of done

Run through `docs/agents/definition-of-done.md` before commit.

