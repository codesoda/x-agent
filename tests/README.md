# Scenario Tests

This folder contains fixture projects used to smoke-test each x-agent.

## Quick Start

```bash
tests/run-scenarios.sh --list
tests/run-scenarios.sh
```

## Layout

```text
tests/
  run-scenarios.sh
  cargo-agent/
    clean/
    issues/
  npm-agent/
    clean/
    issues/
  terra-agent/
    clean/
    issues/
```

Each runnable scenario includes a `scenario.env` file.

Scenarios without `scenario.env` are treated as placeholders and skipped by discovery.

