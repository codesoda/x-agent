# PRD: x-agent Backlog — Shared Library + 8 New Agents

## Introduction

The x-agent project provides lean workflow runner scripts for coding agents. Three agents exist (cargo-agent, npm-agent, terra-agent) but contain significant duplicated boilerplate. This PRD covers extracting shared helpers into a common library, refactoring existing agents, and shipping 8 new agents. Each agent is a separate deliverable with its own PR targeting main.

## Goals

- Extract ~100-150 lines of duplicated boilerplate into `lib/x-agent-common.sh`
- Refactor existing agents (cargo, npm, terra) to source the shared library
- Ship 8 new agents, each with full scenario tests, SKILL.md, and install.sh integration
- Every agent supports fix/auto-format where the underlying tool provides it
- Maintain Bash 3.2 compatibility and structured output contract across all agents

## User Stories

**Definition of Done (applies to all stories):**
- All acceptance criteria met
- `shellcheck --severity=warning` passes on all new/modified scripts
- `tests/run-scenarios.sh` passes for all affected agents
- Bash 3.2 compatible (no associative arrays, no `readarray`, no `|&`)
- Structured output contract followed (Step/Result/Fix/Overall)
- Every `Result: FAIL` includes a `Fix:` hint

---

### US-001: Extract shared library and refactor existing agents
**Description:** As a contributor, I want common boilerplate extracted into a shared library so that new agents are smaller and consistent.

**Acceptance Criteria:**
- [ ] `lib/x-agent-common.sh` created with: `hr()`, `step()`, `fmt_elapsed()`, `should_continue()`, `need()`, cleanup trap setup, workflow lock setup, MAX_LINES/CI detection, standard variable defaults
- [ ] cargo-agent, npm-agent, terra-agent refactored to `source` the shared lib
- [ ] All three existing agents produce identical output before/after refactor
- [ ] `tests/run-scenarios.sh` passes for all existing agents after refactor
- [ ] `shellcheck --severity=warning` passes on `lib/x-agent-common.sh` and all refactored scripts
- [ ] Shared lib is Bash 3.2 compatible

---

### US-002: bash-agent
**Description:** As a developer, I want a bash-agent that validates shell scripts for syntax errors and lint issues so I can catch problems before CI.

**Steps:**
- `syntax` — `bash -n` on each `.sh` file (required)
- `lint` — `shellcheck --severity=warning` (required)

**Required tools:** bash, shellcheck
**Fix mode:** None (neither tool supports auto-fix). `Fix:` hints reference shellcheck wiki URLs.

**Knobs:** `RUN_SYNTAX=1`, `RUN_LINT=1`, `SHELLCHECK_SEVERITY=warning` (configurable), `CHANGED_FILES` scoping

**Acceptance Criteria:**
- [ ] `skills/bash-agent/scripts/bash-agent.sh` sources `lib/x-agent-common.sh`
- [ ] `syntax` step runs `bash -n` on all `.sh` files (or scoped via `CHANGED_FILES`)
- [ ] `lint` step runs `shellcheck` on all `.sh` files (or scoped)
- [ ] Failed shellcheck results include wiki link in `Fix:` hint (e.g. `See https://www.shellcheck.net/wiki/SC2086`)
- [ ] Commands: `syntax`, `lint`, `all` (default runs both)
- [ ] `SKILL.md` with trigger language and allowed-tools patterns
- [ ] `install.sh` updated with `bash-agent` in SKILLS list and dep checks
- [ ] `tests/bash-agent/clean/` and `tests/bash-agent/issues/` scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-003: go-agent
**Description:** As a developer, I want a go-agent that checks formatting, runs vet/lint, and executes tests so I can validate Go code before CI.

**Steps:**
- `fmt` — `gofmt -l` to check, `gofmt -w` to fix (required)
- `vet` — `go vet ./...` (required)
- `staticcheck` — `staticcheck ./...` (optional, skip with notice if not installed)
- `test` — `go test ./...` (required)

**Required tools:** go
**Optional tools:** staticcheck
**Fix mode:** `gofmt -w` when `FMT_MODE=fix`

**Knobs:** `RUN_FMT=1`, `RUN_VET=1`, `RUN_STATICCHECK=1`, `RUN_TESTS=1`, `FMT_MODE=check|fix` (check in CI, fix locally)

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `fmt` step uses `gofmt -l` in check mode, `gofmt -w` in fix mode; CI forces check mode
- [ ] `vet` step runs `go vet ./...`, reports diagnostics on failure
- [ ] `staticcheck` step skips with notice if not installed, runs if available
- [ ] `test` step runs `go test ./...`, extracts failing test names in `Fix:` hint
- [ ] Commands: `fmt`, `vet`, `staticcheck`, `test`, `all` (default)
- [ ] `CHANGED_FILES` scoping: maps changed `.go` files to packages
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-004: gha-agent
**Description:** As a developer, I want a gha-agent that lints GitHub Actions workflow files so I can catch workflow errors before pushing.

**Steps:**
- `lint` — `actionlint` on `.github/workflows/*.yml` (required)

**Required tools:** actionlint
**Fix mode:** None (actionlint is check-only)

**Knobs:** `RUN_LINT=1`, `CHANGED_FILES` scoping (filters to `.github/workflows/*.yml`)

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `actionlint` on workflow files
- [ ] If no `.github/workflows/` directory exists, reports SKIP with reason
- [ ] `CHANGED_FILES` scoping filters to only `.yml`/`.yaml` files under `.github/workflows/`
- [ ] Commands: `lint`, `all` (default)
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-005: helm-agent
**Description:** As a developer, I want a helm-agent that lints Helm charts and validates template rendering so I can catch chart errors before CI.

**Steps:**
- `lint` — `helm lint <chart-dir>` (required)
- `template` — `helm template <chart-dir>` to verify templates render without error (required)

**Required tools:** helm
**Fix mode:** None (both commands are validation-only)

**Knobs:** `RUN_LINT=1`, `RUN_TEMPLATE=1`, `CHART_DIR=.` (auto-detect from `Chart.yaml` or `CHANGED_FILES`)

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `helm lint` on the chart directory
- [ ] `template` step runs `helm template` and checks for render errors (output discarded on success, shown on failure)
- [ ] Auto-detects chart directory from `Chart.yaml` if `CHART_DIR` not set
- [ ] If no `Chart.yaml` found, reports SKIP with reason
- [ ] `CHANGED_FILES` scoping: detects chart dir from changed files under a chart path
- [ ] Commands: `lint`, `template`, `all` (default)
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-006: kube-agent
**Description:** As a developer, I want a kube-agent that validates Kubernetes manifests so I can catch schema errors before applying to a cluster.

**Steps:**
- `validate` — `kubeconform` (preferred) or `kubeval` on YAML manifests (required — at least one must be installed)

**Required tools:** kubeconform OR kubeval (prefers kubeconform if both installed)
**Fix mode:** None (validation-only)

**Knobs:** `RUN_VALIDATE=1`, `KUBE_SCHEMAS_DIR` (optional, for offline/custom schemas), `CHANGED_FILES` scoping (filters to `.yml`/`.yaml`)

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] Detects which validator is installed: prefers `kubeconform`, falls back to `kubeval`
- [ ] If neither installed, exits with code 2 and message naming both options
- [ ] `validate` step runs the detected validator on all YAML files (or scoped via `CHANGED_FILES`)
- [ ] Skips known non-Kubernetes YAML (e.g. files without `apiVersion`/`kind` fields) to avoid false positives
- [ ] `KUBE_SCHEMAS_DIR` passes through to the validator's schema location flag
- [ ] Commands: `validate`, `all` (default)
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-007: docker-agent
**Description:** As a developer, I want a docker-agent that lints Dockerfiles and optionally runs BuildKit checks so I can catch issues before CI builds.

**Steps:**
- `lint` — `hadolint` on Dockerfiles (required)
- `build-check` — `docker build --check` BuildKit lint mode (optional, opt-in)

**Required tools:** hadolint
**Optional tools:** docker (for build-check step)
**Fix mode:** None (both tools are check-only)

**Knobs:** `RUN_LINT=1`, `RUN_BUILD_CHECK=0` (opt-in), `DOCKERFILE=Dockerfile` (path, auto-detects from `CHANGED_FILES`)

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `hadolint` on the target Dockerfile(s)
- [ ] Discovers Dockerfiles automatically (`Dockerfile`, `Dockerfile.*`, `*.dockerfile`) or scopes via `CHANGED_FILES`
- [ ] `build-check` step defaults to off (`RUN_BUILD_CHECK=0`), runs `docker build --check` when enabled
- [ ] `build-check` skips with notice if docker is not installed
- [ ] Commands: `lint`, `build-check`, `all` (default)
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-008: ansible-agent
**Description:** As a developer, I want an ansible-agent that lints and syntax-checks Ansible playbooks/roles so I can catch issues before running them.

**Steps:**
- `lint` — `ansible-lint` with optional `--fix` mode (required)
- `syntax` — `ansible-playbook --syntax-check` on playbooks (required)

**Required tools:** ansible-lint, ansible-playbook
**Fix mode:** `ansible-lint --fix` when `FMT_MODE=fix`

**Knobs:** `RUN_LINT=1`, `RUN_SYNTAX=1`, `FMT_MODE=check|fix` (check in CI, fix locally)

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `ansible-lint` in check mode by default, `ansible-lint --fix` when `FMT_MODE=fix`
- [ ] CI forces check mode regardless of `FMT_MODE`
- [ ] `syntax` step runs `ansible-playbook --syntax-check` on discovered playbooks
- [ ] Auto-discovers playbooks (files matching common patterns: `playbook*.yml`, `site.yml`, or files containing `hosts:` key)
- [ ] `CHANGED_FILES` scoping filters to `.yml`/`.yaml` files
- [ ] Commands: `lint`, `syntax`, `all` (default)
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

### US-009: sql-agent
**Description:** As a developer, I want an sql-agent that lints and optionally auto-fixes SQL files so I can maintain consistent SQL style.

**Steps:**
- `lint` — `sqlfluff lint` (required)
- `fix` — `sqlfluff fix` (optional, opt-in)

**Required tools:** sqlfluff
**Fix mode:** `sqlfluff fix` when `FMT_MODE=fix` or `RUN_FIX=1`

**Knobs:** `RUN_LINT=1`, `RUN_FIX=0` (opt-in), `FMT_MODE=check|fix` (check in CI), `SQLFLUFF_DIALECT=ansi` (configurable), `CHANGED_FILES` scoping

**Acceptance Criteria:**
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `sqlfluff lint` on all `.sql` files (or scoped via `CHANGED_FILES`)
- [ ] `fix` step defaults to off, runs `sqlfluff fix` when enabled
- [ ] CI forces check/lint-only regardless of `FMT_MODE`
- [ ] `SQLFLUFF_DIALECT` passed through to `--dialect` flag (defaults to `ansi`)
- [ ] Auto-discovers `.sql` files recursively from project root
- [ ] Commands: `lint`, `fix`, `all` (default runs lint only unless fix enabled)
- [ ] `SKILL.md`, `install.sh` updated, clean/issues scenarios pass
- [ ] Script passes `shellcheck --severity=warning`

---

## Functional Requirements

- FR-1: All agents source `lib/x-agent-common.sh` for shared boilerplate
- FR-2: All agents support universal knobs: `KEEP_DIR`, `MAX_LINES`, `FAIL_FAST`, `TMPDIR_ROOT`, `CHANGED_FILES`
- FR-3: All agents support per-step toggles via `RUN_<STEP>=0|1`
- FR-4: All agents produce structured output: `Step:`, `Result: PASS|FAIL|SKIP`, `Fix:` (on fail), `Full log:`, `Time:`, `Overall: PASS|FAIL`, `Logs:`
- FR-5: All agents support `--fail-fast` CLI flag and `--help`/`help`/`-h` usage output
- FR-6: Required tools checked with `need()` (exit 2 if missing); optional tools skip with notice
- FR-7: Cleanup trap preserves logs on failure or `KEEP_DIR=1`
- FR-8: Workflow lock (flock with Perl fallback) prevents concurrent runs per agent
- FR-9: `MAX_LINES` defaults to 40 locally, 999999 when `CI=true|1`
- FR-10: Agents with fix mode use `FMT_MODE=check|fix`; CI forces check mode
- FR-11: Each agent includes `SKILL.md` with trigger language and `allowed-tools` patterns
- FR-12: `install.sh` updated per agent with SKILLS list entry and dependency checks
- FR-13: Each agent has `tests/<name>-agent/clean/` and `tests/<name>-agent/issues/` scenario fixtures

## Non-Goals

- No cross-agent orchestration (running multiple agents in sequence)
- No daemon/watch mode for any agent
- No remote/cloud tool integration (e.g., no Terraform Cloud, no GitHub API calls)
- No full Docker image builds (only BuildKit `--check` lint mode)
- No custom rule authoring for any linter — agents use tool defaults or simple knobs
- No package manager integration (agents don't install missing tools, just report them)

## Technical Considerations

- All scripts must be Bash 3.2 compatible (stock macOS)
- `lib/x-agent-common.sh` must be sourceable without side effects beyond function definitions and variable defaults
- Existing agents (cargo, npm, terra) must not change behavior after refactor — only internal structure
- Scenario test fixtures should use minimal synthetic projects (not real codebases)
- `install.sh` symlinks skills into `~/.claude/skills/` and `~/.codex/skills/`; the shared lib must be accessible from the installed location

## Success Metrics

- All 8 new agents pass their scenario tests (clean + issues fixtures)
- Existing agents pass their scenario tests after shared library refactor
- `shellcheck --severity=warning` passes on all scripts including `lib/x-agent-common.sh`
- Each new agent script is under ~200 lines of domain-specific code (shared boilerplate in lib)
- `tests/run-scenarios.sh` discovers and runs all scenarios successfully

## Open Questions

None — all resolved during clarifying questions.
