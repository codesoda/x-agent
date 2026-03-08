# Spec 04: go-agent

## Objective

Create a new go-agent that checks Go formatting, runs vet/lint, and executes tests.

## Source

- **PRD User Story:** US-003
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-10, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want a go-agent that checks formatting, runs vet/lint, and executes tests so I can validate Go code before CI.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_FMT, RUN_VET, RUN_STATICCHECK, RUN_TESTS)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Required tools (go) checked with need(); staticcheck optional (skip with notice)
- FR-10: FMT_MODE=check|fix; CI forces check mode
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/go-agent/scripts/go-agent.sh`
- **Create:** `skills/go-agent/SKILL.md`
- **Create:** `tests/go-agent/clean/` (scenario.env + minimal Go project)
- **Create:** `tests/go-agent/issues/` (scenario.env + Go project with issues)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `go-agent.sh`

**Agent-specific knobs:**
```bash
RUN_FMT="${RUN_FMT:-1}"
RUN_VET="${RUN_VET:-1}"
RUN_STATICCHECK="${RUN_STATICCHECK:-1}"
RUN_TESTS="${RUN_TESTS:-1}"
FMT_MODE="${FMT_MODE:-auto}"  # auto = fix locally, check in CI
```

**Required tools:** `need go`
**Optional tools:** `staticcheck` (skip with notice if not found)

**Step: fmt**
- Check mode: `gofmt -l .` — list files that need formatting. If any listed, FAIL.
- Fix mode: `gofmt -w .` — write changes. Always PASS unless gofmt errors.
- `FMT_MODE=auto`: fix locally, check in CI
- Fix hint: `Fix: run /go-agent fmt with FMT_MODE=fix, then re-run: /go-agent fmt`

**Step: vet**
- Run `go vet ./...`
- Capture stderr (where go vet writes diagnostics)
- Fix hint: `Fix: resolve the vet issues above, then re-run: /go-agent vet`

**Step: staticcheck**
- If `staticcheck` not installed: `Result: SKIP (staticcheck not found — install via go install honnef.co/go/tools/cmd/staticcheck@latest)`
- If installed: run `staticcheck ./...`
- Fix hint: `Fix: resolve the staticcheck issues above, then re-run: /go-agent staticcheck`

**Step: test**
- Run `go test ./...`
- On failure, extract failing test names from output (lines matching `--- FAIL:`)
- Fix hint: `Fix: failing tests: TestFoo, TestBar — resolve and re-run: /go-agent test`

**CHANGED_FILES scoping:**
- Filter `.go` files from CHANGED_FILES
- Extract unique package directories
- Pass as args to `go vet`, `staticcheck`, `go test` instead of `./...`
- `gofmt` always takes file/dir args so pass changed dirs

**Commands:** `fmt`, `vet`, `staticcheck`, `test`, `all` (default)

### Scenario Tests

**clean fixture:**
- `go.mod` with a module name (e.g., `module example.com/clean`)
- `main.go` with a simple valid, formatted Go program
- REQUIRED_TOOLS="go"

**issues fixture:**
- `go.mod` with module name
- `main.go` with formatting issues (tabs vs spaces) OR vet issues (e.g., `fmt.Printf("%d", "string")`)
- REQUIRED_TOOLS="go"

### SKILL.md

Triggers on: go agent, run go checks, golang checks, go fmt vet test, verify go code.
Allowed-tools: include `FMT_MODE=*` pattern.

## Test Strategy

- `tests/run-scenarios.sh go-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes on the script
- Verify FMT_MODE=check catches unformatted code, FMT_MODE=fix reformats it
- Verify staticcheck gracefully skips when not installed

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/go-agent/scripts/go-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `fmt` step uses `gofmt -l` in check mode, `gofmt -w` in fix mode; CI forces check
- [ ] `vet` step runs `go vet ./...`
- [ ] `staticcheck` step skips with notice if not installed
- [ ] `test` step runs `go test ./...`, extracts failing test names in Fix: hint
- [ ] Commands: `fmt`, `vet`, `staticcheck`, `test`, `all`
- [ ] CHANGED_FILES scoping maps .go files to packages
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
