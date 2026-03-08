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
