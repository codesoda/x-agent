# Spec 06: helm-agent

## Objective

Create a new helm-agent that lints Helm charts and validates template rendering.

## Source

- **PRD User Story:** US-005
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want a helm-agent that lints Helm charts and validates template rendering so I can catch chart errors before CI.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_LINT, RUN_TEMPLATE)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Required tools (helm) checked with need()
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/helm-agent/scripts/helm-agent.sh`
- **Create:** `skills/helm-agent/SKILL.md`
- **Create:** `tests/helm-agent/clean/` (scenario.env + minimal valid chart)
- **Create:** `tests/helm-agent/issues/` (scenario.env + chart with issues)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `helm-agent.sh`

**Agent-specific knobs:**
```bash
RUN_LINT="${RUN_LINT:-1}"
RUN_TEMPLATE="${RUN_TEMPLATE:-1}"
CHART_DIR="${CHART_DIR:-}"  # auto-detect if empty
```

**Required tools:** `need helm`

**Chart directory detection:**
1. If `CHART_DIR` is explicitly set, use it
2. If `CHANGED_FILES` is set, look for `Chart.yaml` in parent dirs of changed files
3. Otherwise, search current directory tree for `Chart.yaml`
4. If no `Chart.yaml` found anywhere: SKIP all steps with reason

**Step: lint**
- Run `helm lint <chart-dir>`
- helm lint returns non-zero on errors, prints warnings/errors to stdout
- Fix hint: `Fix: resolve the chart errors above, then re-run: /helm-agent lint`

**Step: template**
- Run `helm template <chart-dir>` — renders templates to stdout
- On success: discard rendered output (just checking it renders), print PASS
- On failure: show error output (template rendering errors)
- Fix hint: `Fix: resolve the template errors above, then re-run: /helm-agent template`

**CHANGED_FILES scoping:**
- Filter changed files to chart-related files (*.yaml, *.yml, *.tpl, Chart.yaml, values.yaml)
- Detect which chart(s) are affected by finding Chart.yaml in parent directories
- If multiple charts detected, run for each

**Commands:** `lint`, `template`, `all` (default)

### Scenario Tests

**clean fixture (`tests/helm-agent/clean/`):**
- Minimal valid Helm chart:
  - `Chart.yaml` with name, version, apiVersion
  - `templates/configmap.yaml` with a simple valid template
  - `values.yaml` with default values used by the template
- REQUIRED_TOOLS="helm"

**issues fixture (`tests/helm-agent/issues/`):**
- Chart with issues:
  - `Chart.yaml` with valid metadata
  - `templates/bad.yaml` with a template syntax error (e.g., `{{ .Values.missing | required "msg" }}` without default, or malformed template `{{ .Values.x }`)
- REQUIRED_TOOLS="helm"

### SKILL.md

Triggers on: helm agent, helm lint, helm checks, helm template, validate helm chart.
Include `CHART_DIR=*` in allowed-tools.

## Test Strategy

- `tests/run-scenarios.sh helm-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes
- Verify SKIP when no Chart.yaml found
- Verify CHART_DIR override works
- Verify CHANGED_FILES detects affected chart

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/helm-agent/scripts/helm-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `helm lint` on chart directory
- [ ] `template` step runs `helm template`, discards output on success, shows errors on failure
- [ ] Auto-detects chart directory from Chart.yaml
- [ ] Reports SKIP when no Chart.yaml found
- [ ] CHANGED_FILES scoping detects affected chart(s)
- [ ] Commands: `lint`, `template`, `all`
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
