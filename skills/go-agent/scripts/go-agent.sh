#!/usr/bin/env bash
set -euo pipefail

# go-agent: lean Go workflow runner for coding agents
# deps: go (required), staticcheck (optional)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_FMT="${RUN_FMT:-1}"
RUN_VET="${RUN_VET:-1}"
RUN_STATICCHECK="${RUN_STATICCHECK:-1}"
RUN_TESTS="${RUN_TESTS:-1}"
FMT_MODE="${FMT_MODE:-auto}"

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
go-agent — lean Go workflow runner for coding agents.

Usage: go-agent.sh [options] [command]

Commands:
  fmt           Run gofmt formatting check/fix
  vet           Run go vet analysis
  staticcheck   Run staticcheck linter (skipped if not installed)
  test          Run go test
  all           Run fmt + vet + staticcheck + test (default)
  help          Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_FMT=0|1             Toggle fmt step (default: 1)
  RUN_VET=0|1             Toggle vet step (default: 1)
  RUN_STATICCHECK=0|1     Toggle staticcheck step (default: 1)
  RUN_TESTS=0|1           Toggle test step (default: 1)
  FMT_MODE=auto|check|fix Format mode (default: auto — fix locally, check in CI)
  CHANGED_FILES="a.go b.go"  Scope to specific files/packages
  MAX_LINES=N             Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1            Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1           Stop after first failure (default: 0)
EOF
}

# ---- Scope resolution -----------------------------------------------------

# Resolve CHANGED_FILES to unique Go package directories.
# Sets SCOPED_DIRS (space-separated) and SCOPED_PKGS (./dir/... format).
resolve_scope() {
  SCOPED_DIRS=""
  SCOPED_PKGS=""

  if [[ -z "${CHANGED_FILES:-}" ]]; then
    return 0
  fi

  local dirs=""
  local f d
  for f in $CHANGED_FILES; do
    if [[ "$f" == *.go ]] && [[ -f "$f" ]]; then
      d="$(dirname "$f")"
      # Deduplicate
      case " $dirs " in
        *" $d "*) ;;
        *) dirs="${dirs:+$dirs }$d" ;;
      esac
    fi
  done

  if [[ -z "$dirs" ]]; then
    return 0
  fi

  SCOPED_DIRS="$dirs"
  # Build ./dir format for go tool commands
  local pkgs=""
  for d in $dirs; do
    local pkg
    if [[ "$d" == "." ]]; then
      pkg="./..."
    else
      pkg="./${d#./}"
    fi
    pkgs="${pkgs:+$pkgs }$pkg"
  done
  SCOPED_PKGS="$pkgs"

  echo "Scoped to changed packages: ${SCOPED_PKGS}"
}

# Returns the fmt targets: scoped dirs or "." for full project.
fmt_targets() {
  if [[ -n "$SCOPED_DIRS" ]]; then
    echo "$SCOPED_DIRS"
  else
    echo "."
  fi
}

# Returns the package targets: scoped packages or "./..." for full project.
pkg_targets() {
  if [[ -n "$SCOPED_PKGS" ]]; then
    echo "$SCOPED_PKGS"
  else
    echo "./..."
  fi
}

# ---- FMT_MODE resolution --------------------------------------------------

resolve_fmt_mode() {
  case "$FMT_MODE" in
    auto)
      if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
        FMT_MODE="check"
      else
        FMT_MODE="fix"
      fi
      ;;
    check|fix)
      # CI forces check regardless of user setting
      if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
        FMT_MODE="check"
      fi
      ;;
    *)
      echo "Invalid FMT_MODE: ${FMT_MODE} (expected: auto, check, fix)" >&2
      exit 2
      ;;
  esac
}

# ---- Steps ----------------------------------------------------------------

run_fmt() {
  step "fmt"

  local log="${OUTDIR}/fmt.log"
  local ok=1
  local targets
  # shellcheck disable=SC2046
  targets=$(fmt_targets)

  if [[ "$FMT_MODE" == "check" ]]; then
    # List files needing formatting
    local unformatted
    # gofmt -l exits 0 even if files need formatting; check output
    # shellcheck disable=SC2086
    unformatted="$(gofmt -l $targets 2>"$log")" || true
    if [[ -n "$unformatted" ]]; then
      ok=0
      echo "$unformatted" >> "$log"
      echo
      echo "Files needing formatting:"
      echo "$unformatted" | head -n "$MAX_LINES"
    fi
  else
    # Fix mode: rewrite files
    # shellcheck disable=SC2086
    if ! gofmt -w $targets >"$log" 2>&1; then
      ok=0
    fi
  fi

  local fix_hint=""
  if [[ "$ok" == "0" ]]; then
    fix_hint="run /go-agent fmt with FMT_MODE=fix, then re-run: /go-agent fmt"
  fi

  print_result "$ok" "$log" "$fix_hint"
  return $(( 1 - ok ))
}

run_vet() {
  step "vet"

  local log="${OUTDIR}/vet.log"
  local ok=1
  local targets
  targets=$(pkg_targets)

  # go vet writes diagnostics to stderr
  # shellcheck disable=SC2086
  if ! go vet $targets >"$log" 2>&1; then
    ok=0
  fi

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve the vet issues above, then re-run: /go-agent vet"
  return $(( 1 - ok ))
}

run_staticcheck() {
  step "staticcheck"

  if ! command -v staticcheck >/dev/null 2>&1; then
    echo
    echo "Result: SKIP (staticcheck not found — install via go install honnef.co/go/tools/cmd/staticcheck@latest)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/staticcheck.log"
  local ok=1
  local targets
  targets=$(pkg_targets)

  # shellcheck disable=SC2086
  if ! staticcheck $targets >"$log" 2>&1; then
    ok=0
  fi

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve the staticcheck issues above, then re-run: /go-agent staticcheck"
  return $(( 1 - ok ))
}

run_test() {
  step "test"

  local log="${OUTDIR}/test.log"
  local ok=1
  local targets
  targets=$(pkg_targets)

  # shellcheck disable=SC2086
  if ! go test $targets >"$log" 2>&1; then
    ok=0
  fi

  local fix_hint=""
  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"

    # Extract failing test names from --- FAIL: lines
    local failing_tests
    failing_tests="$(grep '^--- FAIL:' "$log" | sed 's/^--- FAIL: \([^ ]*\).*/\1/' | sort -u | paste -sd ', ' -)" || true
    if [[ -n "$failing_tests" ]]; then
      fix_hint="failing tests: ${failing_tests} — resolve and re-run: /go-agent test"
    else
      fix_hint="resolve the test failures above, then re-run: /go-agent test"
    fi
  fi

  print_result "$ok" "$log" "$fix_hint"
  return $(( 1 - ok ))
}

# ---- Main -----------------------------------------------------------------

main() {
  # Parse help before need() checks so --help works without tools installed
  case "${1:-}" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  need go

  setup_outdir "go-agent"

  # Parse flags
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --fail-fast)
        # shellcheck disable=SC2034
        FAIL_FAST=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  local cmd="${1:-all}"
  shift 2>/dev/null || true
  local overall_ok=1

  resolve_fmt_mode
  resolve_scope

  case "$cmd" in
    fmt)         run_fmt         || overall_ok=0 ;;
    vet)         run_vet         || overall_ok=0 ;;
    staticcheck) run_staticcheck || overall_ok=0 ;;
    test)        run_test        || overall_ok=0 ;;
    all)
      if [[ "$RUN_FMT" == "1" ]] && should_continue; then run_fmt || overall_ok=0; fi
      if [[ "$RUN_VET" == "1" ]] && should_continue; then run_vet || overall_ok=0; fi
      if [[ "$RUN_STATICCHECK" == "1" ]] && should_continue; then run_staticcheck || overall_ok=0; fi
      if [[ "$RUN_TESTS" == "1" ]] && should_continue; then run_test || overall_ok=0; fi
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 2
      ;;
  esac

  print_overall "$overall_ok"
  [[ "$overall_ok" == "1" ]]
}

main "$@"
