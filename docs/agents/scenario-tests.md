# Scenario Tests

Scenario tests provide fixture projects that run each agent in known states.

## Directory Layout

```text
tests/
  run-scenarios.sh
  <agent-name>/
    clean/
      scenario.env
      ...fixture files...
    issues/
      scenario.env
      ...fixture files...
```

## scenario.env contract

Required keys:

- `SCENARIO_NAME`: Human-readable scenario label.
- `AGENT_SCRIPT`: Script path relative to repo root.
- `EXPECT_EXIT`: Expected exit code (`0` pass, `1` fail).

Optional keys:

- `RUN_ARGS`: Runner arguments (default: `all`).
- `REQUIRED_TOOLS`: Space-separated executables needed for this scenario.

Example:

```bash
SCENARIO_NAME="cargo-agent clean"
AGENT_SCRIPT="skills/cargo-agent/scripts/cargo-agent.sh"
RUN_ARGS="all"
EXPECT_EXIT="0"
REQUIRED_TOOLS="cargo jq"
```

## Running

List scenarios:

```bash
tests/run-scenarios.sh --list
```

Run all scenarios:

```bash
tests/run-scenarios.sh
```

Filter by path fragment:

```bash
tests/run-scenarios.sh cargo-agent
```

