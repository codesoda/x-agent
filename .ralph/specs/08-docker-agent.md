# Spec 08: docker-agent

## Objective

Create a new docker-agent that lints Dockerfiles with `hadolint` and optionally runs BuildKit `--check` mode.

## Source

- **PRD User Story:** US-007
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want a docker-agent that lints Dockerfiles and optionally runs BuildKit checks so I can catch issues before CI builds.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_LINT, RUN_BUILD_CHECK)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Required tools (hadolint); optional (docker for build-check)
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/docker-agent/scripts/docker-agent.sh`
- **Create:** `skills/docker-agent/SKILL.md`
- **Create:** `tests/docker-agent/clean/` (scenario.env + valid Dockerfile)
- **Create:** `tests/docker-agent/issues/` (scenario.env + bad Dockerfile)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `docker-agent.sh`

**Agent-specific knobs:**
```bash
RUN_LINT="${RUN_LINT:-1}"
RUN_BUILD_CHECK="${RUN_BUILD_CHECK:-0}"  # opt-in, expensive
```

**Required tools:** `need hadolint`
**Optional tools:** docker (for build-check, skip with notice)

**Dockerfile discovery:**
- If CHANGED_FILES set, filter to Dockerfile-like files
- Otherwise, find files matching: `Dockerfile`, `Dockerfile.*`, `*.dockerfile` (recursive, excluding `.git/`, `node_modules/`)
- If no Dockerfiles found: SKIP all steps

**Step: lint**
- Run `hadolint <dockerfile>` for each discovered Dockerfile
- hadolint outputs one issue per line with severity
- Collect all results, log to disk
- Fix hint: `Fix: resolve hadolint issues above, then re-run: /docker-agent lint`

**Step: build-check (opt-in)**
- Defaults to OFF (`RUN_BUILD_CHECK=0`)
- If enabled and docker not installed: `Result: SKIP (docker not found)`
- If enabled: run `docker build --check -f <dockerfile> .` for each Dockerfile
  - `--check` is BuildKit's lint mode — no image is built
- Fix hint: `Fix: resolve build check errors above, then re-run: /docker-agent build-check`

**Commands:** `lint`, `build-check`, `all` (default — lint only unless build-check enabled)

### Scenario Tests

**clean fixture (`tests/docker-agent/clean/`):**
- `Dockerfile`: valid, clean Dockerfile
  ```dockerfile
  FROM alpine:3.19
  RUN apk add --no-cache curl
  COPY . /app
  CMD ["/app/start.sh"]
  ```
- REQUIRED_TOOLS="hadolint"
- Note: RUN_BUILD_CHECK=0 in scenario (build-check requires docker daemon)

**issues fixture (`tests/docker-agent/issues/`):**
- `Dockerfile`: Dockerfile with hadolint violations
  ```dockerfile
  FROM ubuntu:latest
  RUN apt-get update && apt-get install -y curl
  ADD . /app
  ```
  - Triggers: DL3007 (using latest), DL3009 (delete apt cache), DL3020 (use COPY instead of ADD)
- REQUIRED_TOOLS="hadolint"

### SKILL.md

Triggers on: docker agent, dockerfile lint, hadolint, docker checks, validate dockerfile.
Include `RUN_BUILD_CHECK=*` in allowed-tools.

## Test Strategy

- `tests/run-scenarios.sh docker-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes
- Verify SKIP when no Dockerfiles found
- Verify build-check defaults to OFF
- Verify build-check skips with notice when docker not found

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/docker-agent/scripts/docker-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `hadolint` on discovered Dockerfiles
- [ ] Discovers Dockerfiles automatically (Dockerfile, Dockerfile.*, *.dockerfile)
- [ ] `build-check` defaults OFF, runs `docker build --check` when enabled
- [ ] `build-check` skips with notice if docker not installed
- [ ] CHANGED_FILES scoping works
- [ ] Reports SKIP when no Dockerfiles found
- [ ] Commands: `lint`, `build-check`, `all`
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
