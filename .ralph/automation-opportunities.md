# Automation Opportunities for x-agent

## [2026-03-08T16:59:00Z] output-parity-diff

**Frequency**: Every refactor touching shared helpers in runners, especially spec-02 and similar boilerplate migrations

**Priority**: HIGH

**Current Issue**: Scenario tests enforce command exit codes and shellcheck only; they do not compare full CLI output text. This allows subtle regressions in `Step`, `Result`, `Fix`, and `Overall` formatting to go untested.

**Manual Check**: Capture scenario outputs before/after a refactor and manually diff fixture logs, then visually inspect for non-timing drift.

**Automated Check**: Add a `tests/run-scenarios.sh` diff mode that captures output for `clean`/`issues` fixtures and compares against baseline snapshots with a fixed normalizer that removes `Time: [0-9]+s` lines only.

**Status**: PENDING

## [2026-03-08T17:08:28Z] review-work-plan-checklist

**Frequency**: Caught repeatedly in multi-agent specs where work-plan.txt can be stale

**Priority**: CRITICAL

**Current Issue**: Review phases sometimes proceed without verifying that `.ralph/work-plan.txt` item checkboxes are fully completed, despite explicit acceptance condition in this review protocol.

**Manual Check**: Confirm all checklist entries are checked (`- [x]`) before deciding REWORK/SHIP.

**Automated Check**: Add a validation rule in `ralph validate review` to read `.ralph/work-plan.txt`, fail when any `- [ ]` remains, and include file/line references.

**Status**: PENDING

## [2026-03-08T17:10:01Z] bash-agent-exploration-check

**Frequency**: First occurrence in multi-step feature plans

**Priority**: HIGH

**Current Issue**: New agent planning often forgets to update `find`-exclude list and fixture expectations together, causing either over-scoped script checks or expensive scans.

**Manual Check**: Before implementation, verify all planned new-agent scenarios and discovery paths are documented in `.ralph/exploration.md` and mirrored in plan assumptions.

**Automated Check**: Add a planning validation rule that ensures `x-agent` plans requiring new agents include both script path and fixture path updates in `.ralph/exploration.md` or block `ralph validate plan`.

**Status**: PENDING

## [2026-03-08T17:26:14Z] go-fmt-check-exit-status

**Frequency**: First occurrence

**Priority**: MEDIUM

**Current Issue**: `gofmt -l` output checks can be treated as successful formatting checks even when `gofmt` exits non-zero (for example, parser or filesystem errors), which can create false PASS results in `fmt` check mode.

**Manual Check**: In formatting check steps, verify command exit status is captured separately from diff output checks before printing PASS.

**Automated Check**: Add a shellcheck/lint rule or helper wrapper test in scenario review that flags check-mode implementations that ignore `gofmt -l`/scanner exit status and rely solely on empty stdout.

**Status**: PENDING

## [2026-03-08T17:27:56Z] skip-path-test-coverage

**Frequency**: Each new agent with discoverable path assumptions

**Priority**: MEDIUM

**Current Issue**: Agents with path-dependent discovery (for example workflow discovery, lint target discovery, or scope-only execution) can pass clean/issues fixtures while still missing explicit skip-path assertions.

**Manual Check**: Create and run an explicit no-match fixture by name for each such agent and confirm `Result: SKIP` and exit semantics.

**Automated Check**: Add a review/plan-time validation that inspects `FR` requirements or scenario docs for required skip behavior and fails fast if the implementation plan/work item does not include a dedicated skip fixture.

**Status**: PENDING

## [2026-03-08T00:00:00Z] scoped-edge-scenarios-for-agents

**Frequency**: Repeated across agents with CHANGED_FILES support

**Priority**: HIGH

**Current Issue**: Agents with scoped execution often ship clean/issues fixtures that pass but miss CHANGED_FILES edge cases (no-match and positive-scope branches), so regressions in file scoping logic can slip through.

**Manual Check**: For each scoped agent, add explicit scenarios that verify scoped-match, scoped-no-match, and explicit override behavior.

**Automated Check**: Add a planning/validation rule that parses `.ralph/specs/*-agent.md` for CHANGED_FILES-related requirements and asserts that `tests/<agent>/` contains a dedicated scenario asserting CHANGED_FILES path behavior in addition to clean/issues.

**Status**: PENDING

## [2026-03-08T18:02:17Z] kube-plan-checklist-order

**Frequency**: Every PLAN iteration

**Priority**: HIGH

**Current Issue**: Plan checkers validate checklist shape but not semantic ordering requirements (for example, mandated final two items for exploration updates and final validation gate).

**Manual Check**: Inspect checklist items near the end of `.ralph/work-plan.txt` before starting implementation handoff.

**Automated Check**:
  - Extend `ralph validate plan` to assert that the final item is the final-gate requirement and the penultimate item is the exploration-update requirement.
  - Report explicit, actionable line references when ordering is incorrect.

**Status**: PENDING

## [2026-03-08T18:45:00Z] kube-scope-skip-fixture-coverage

**Frequency**: Each new scoped agent where clean/issues fixtures do not hit no-match or skip branches

**Priority**: HIGH

**Current Issue**: discovery-based agents with `CHANGED_FILES` can regress in scoped and no-manifest branches while still passing clean/issues fixtures because `run-scenarios` only checks exit codes by default.

**Manual Check**: Add dedicated fixtures with only `CHANGED_FILES` non-matches (expect SKIP) and no-manifest directories (expect SKIP) before implementing additional validator logic.

**Automated Check**: Add a plan-time validation rule that parses agent specs for `CHANGED_FILES` and verifies corresponding `tests/<agent>/` includes skip/scoped scenarios beyond base `clean` and `issues`.

**Status**: PENDING


## [2026-03-08T17:56:51Z] review-kube-changed-files-assumption

**Frequency**: Repeated assumption in early implementations

**Priority**: MEDIUM

**Current Issue**: Scoped-path behavior is sometimes treated as untestable despite `tests/run-scenarios.sh` supporting `CHANGED_FILES` through `scenario.env`, which leaves FR-3 behavior under-covered.

**Manual Check**: Confirm whether scoped behavior assertions are covered in dedicated fixtures before approving implementations that rely on `CHANGED_FILES` scoping.

**Automated Check**: Add a review-time rule that checks for at least one fixture in `tests/<agent>/` that sets `CHANGED_FILES` when the agent spec includes scoped execution requirements.

**Status**: PENDING

## [2026-03-09T12:00:00Z] scenario-env-export-check

**Frequency**: First occurrence (kube-agent scoped scenarios)
**Priority**: HIGH
**Current Issue**: scenario.env sets env vars that agent scripts need, but without `export` they don't reach the subprocess. Tests silently pass with wrong behavior.
**Manual Check**: Review scenario.env files for variables the agent reads (CHANGED_FILES, etc.) and ensure they are exported.
**Automated Check**:
  - Pre-test validation: grep for known agent-consumed env vars (CHANGED_FILES, KUBE_SCHEMAS_DIR, etc.) in scenario.env files
  - If found without `export` prefix, warn: "Variable X in scenario.env won't reach agent subprocess. Add 'export' prefix."
**Status**: PENDING

## [2026-03-08T18:08:07Z] review-kube-agent-kubeval-coverage

**Frequency**: Repeated in validator-pluggable agents without branch-specific fixtures
**Priority**: HIGH
**Current Issue**: fallback validator branches (e.g., kubeval) are often untested because suites default to primary tool (`kubeconform`/`actionlint` equivalent) and lack explicit availability toggles.
**Manual Check**: Add fixture(s) that exclude the primary validator and set `REQUIRED_TOOLS` to secondary tool.
**Automated Check**: In review, verify when a spec includes fallback tooling that the corresponding test matrix includes at least one fixture forcing the fallback branch.
**Status**: PENDING

## [2026-03-08T18:15:31Z] enforce-scoped-fixture-coverage

**Frequency**: First occurrence
**Priority**: HIGH
**Current Issue**: Agents using `CHANGED_FILES` can pass clean/issues fixtures while skipping wrong scope changes.
**Manual Check**: Require at least one positive-match and one no-match `CHANGED_FILES` fixture per such agent.
**Automated Check**: Add scenario fixture lint rule in `tests/run-scenarios.sh`/review validation to assert presence of a scoped-match and scoped-no-match fixture when agent script references `CHANGED_FILES`.
**Status**: PENDING

## [2026-03-08T18:22:40Z] scenario-env-exports

**Frequency**: Repeated across scope-aware agents in scenario-based harness
**Priority**: MEDIUM
**Current Issue**: Agent fixtures can set variables like CHANGED_FILES or schema knobs without `export`, so subprocess-invoked agents never read them, weakening scoped/optional behavior assertions.
**Manual Check**: Inspect each agent fixture `scenario.env` for variables read by the agent and verify they are exported when required by harness subprocess execution.
**Automated Check**: Add a lint/preflight that parses `scenario.env` files for known agent env vars (for example CHANGED_FILES, KUBE_SCHEMAS_DIR, KUBE_IGNORE_MISSING_SCHEMAS) and warns when set without `export`.
**Status**: PENDING
