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
