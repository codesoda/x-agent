#!/usr/bin/env bash
set -euo pipefail

# sql-agent: lean SQL linter for coding agents
# deps: sqlfluff (required)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_LINT="${RUN_LINT:-1}"
RUN_FIX="${RUN_FIX:-0}"               # opt-in
FMT_MODE="${FMT_MODE:-auto}"           # auto = check in CI, respects RUN_FIX locally
SQLFLUFF_DIALECT="${SQLFLUFF_DIALECT:-ansi}"  # postgres, mysql, bigquery, etc.

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
sql-agent — lean SQL linter for coding agents.

Usage: sql-agent.sh [options] [command]

Commands:
  lint          Run sqlfluff lint on discovered SQL files
  fix           Run sqlfluff fix (auto-fix lint issues)
  all           Run enabled steps (default: lint only; fix before lint when enabled)
  help          Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_LINT=0|1               Toggle lint step (default: 1)
  RUN_FIX=0|1                Toggle fix step (default: 0)
  FMT_MODE=auto|check|fix    Format mode (default: auto — check in CI, respects RUN_FIX locally)
  SQLFLUFF_DIALECT=DIALECT    SQL dialect for sqlfluff (default: ansi)
  CHANGED_FILES="a.sql b.sql" Scope to specific files
  MAX_LINES=N                Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1               Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1              Stop after first failure (default: 0)
EOF
}

# ---- FMT_MODE resolution --------------------------------------------------

resolve_fmt_mode() {
  case "$FMT_MODE" in
    auto)
      if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
        FMT_MODE="check"
      else
        # In auto mode locally, respect RUN_FIX
        if [[ "$RUN_FIX" == "1" ]]; then
          FMT_MODE="fix"
        else
          FMT_MODE="check"
        fi
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

# ---- SQL file discovery ---------------------------------------------------

# Populates SQL_FILES (newline-separated list of .sql file paths).
discover_sql_files() {
  SQL_FILES=""

  if [[ -n "${CHANGED_FILES:-}" ]]; then
    local f
    for f in $CHANGED_FILES; do
      case "$f" in
        *.sql)
          if [[ -f "$f" ]]; then
            if [[ -z "$SQL_FILES" ]]; then
              SQL_FILES="$f"
            else
              SQL_FILES="${SQL_FILES}
$f"
            fi
          fi
          ;;
      esac
    done
  else
    # Recursive find, excluding common non-project directories
    SQL_FILES="$(find . \
      -name '.git' -prune -o \
      -name 'node_modules' -prune -o \
      -name 'vendor' -prune -o \
      -name '.venv' -prune -o \
      -name '__pycache__' -prune -o \
      -type f -name '*.sql' \
      -print | sort)"
  fi

  local count=0
  if [[ -n "$SQL_FILES" ]]; then
    count="$(printf '%s\n' "$SQL_FILES" | wc -l | tr -d ' ')"
  fi
  echo "Discovered ${count} SQL file(s)"
}

# ---- Steps ----------------------------------------------------------------

# Returns 0 (skip) if no SQL files; 1 (continue) otherwise.
check_sql_files() {
  if [[ -n "${CHANGED_FILES:-}" ]] && [[ -z "$SQL_FILES" ]]; then
    echo; echo "Result: SKIP (no .sql files in CHANGED_FILES)"; fmt_elapsed; return 0
  fi
  if [[ -z "$SQL_FILES" ]]; then
    echo; echo "Result: SKIP (no .sql files found)"; fmt_elapsed; return 0
  fi
  return 1
}

run_lint() {
  step "lint"
  check_sql_files && return 0

  local log="${OUTDIR}/lint.log" ok=1
  # shellcheck disable=SC2086
  sqlfluff lint --dialect "$SQLFLUFF_DIALECT" $SQL_FILES >"$log" 2>&1 || ok=0

  if [[ "$ok" == "0" ]]; then
    echo; echo "Output (first ${MAX_LINES} lines):"; head -n "$MAX_LINES" "$log"
  fi
  print_result "$ok" "$log" \
    "run /sql-agent fix or FMT_MODE=fix /sql-agent to auto-fix, then re-run: /sql-agent lint"
  return $(( 1 - ok ))
}

run_fix() {
  step "fix"
  check_sql_files && return 0

  local log="${OUTDIR}/fix.log" ok=1
  # shellcheck disable=SC2086
  sqlfluff fix --dialect "$SQLFLUFF_DIALECT" --force $SQL_FILES >"$log" 2>&1 || ok=0

  if [[ "$ok" == "0" ]]; then
    echo; echo "Output (first ${MAX_LINES} lines):"; head -n "$MAX_LINES" "$log"
  fi
  print_result "$ok" "$log" \
    "some issues cannot be auto-fixed — resolve manually, then re-run: /sql-agent lint"
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

  need sqlfluff

  setup_outdir "sql-agent"

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
  discover_sql_files

  # Determine if fix should run in 'all' mode.
  # Use FMT_MODE (post-resolution) as single source of truth — it already
  # incorporates RUN_FIX for local auto mode and forces check in CI.
  local fix_enabled=0
  if [[ "$FMT_MODE" == "fix" ]]; then
    fix_enabled=1
  fi

  case "$cmd" in
    lint)
      run_lint || overall_ok=0
      ;;
    fix)
      if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
        echo "CI detected — fix is disabled; running lint instead"
        run_lint || overall_ok=0
      else
        run_fix || overall_ok=0
      fi
      ;;
    all)
      # When fix is enabled, run fix BEFORE lint so lint reports post-fix state
      if [[ "$fix_enabled" == "1" ]] && should_continue; then run_fix || overall_ok=0; fi
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
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
