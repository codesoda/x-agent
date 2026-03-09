#!/usr/bin/env bash
set -euo pipefail

# gha-agent: lean GitHub Actions workflow linter for coding agents
# deps: actionlint

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_LINT="${RUN_LINT:-1}"

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
gha-agent — lean GitHub Actions workflow linter for coding agents.

Usage: gha-agent.sh [options] [command]

Commands:
  lint      Run actionlint on workflow files
  all       Run lint (default)
  help      Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_LINT=0|1             Toggle lint step (default: 1)
  CHANGED_FILES="a.yml b.yml"  Scope to specific files
  MAX_LINES=N              Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1             Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1            Stop after first failure (default: 0)
EOF
}

# ---- Workflow discovery ---------------------------------------------------

# Populates WORKFLOW_FILES (newline-separated list of workflow file paths).
collect_workflow_files() {
  WORKFLOW_FILES=""

  if [[ -n "${CHANGED_FILES:-}" ]]; then
    # Filter CHANGED_FILES to existing .yml/.yaml under .github/workflows/
    local f
    for f in $CHANGED_FILES; do
      case "$f" in
        .github/workflows/*.yml|.github/workflows/*.yaml)
          if [[ -f "$f" ]]; then
            if [[ -z "$WORKFLOW_FILES" ]]; then
              WORKFLOW_FILES="$f"
            else
              WORKFLOW_FILES="${WORKFLOW_FILES}
$f"
            fi
          fi
          ;;
      esac
    done
  else
    if [[ ! -d ".github/workflows" ]]; then
      WORKFLOW_FILES=""
      return 0
    fi
    # Discover all .yml/.yaml files in .github/workflows/
    WORKFLOW_FILES="$(find .github/workflows \
      -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)"
  fi

  local count=0
  if [[ -n "$WORKFLOW_FILES" ]]; then
    count="$(printf '%s\n' "$WORKFLOW_FILES" | wc -l | tr -d ' ')"
  fi
  echo "Discovered ${count} workflow file(s)"
}

# ---- Steps ----------------------------------------------------------------

run_lint() {
  step "lint"

  # No .github/workflows directory at all
  if [[ -z "${CHANGED_FILES:-}" ]] && [[ ! -d ".github/workflows" ]]; then
    echo
    echo "Result: SKIP (no .github/workflows/ directory found)"
    fmt_elapsed
    return 0
  fi

  # CHANGED_FILES set but no workflow files matched
  if [[ -n "${CHANGED_FILES:-}" ]] && [[ -z "$WORKFLOW_FILES" ]]; then
    echo
    echo "Result: SKIP (no workflow files in CHANGED_FILES)"
    fmt_elapsed
    return 0
  fi

  # No workflow files found via discovery
  if [[ -z "$WORKFLOW_FILES" ]]; then
    echo
    echo "Result: SKIP (no .yml/.yaml files in .github/workflows/)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/lint.log"
  local ok=1

  # Build file list array for actionlint invocation
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done <<< "$WORKFLOW_FILES"

  if ! actionlint "${files[@]}" >"$log" 2>&1; then
    ok=0
  fi

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve the workflow errors above, then re-run: /gha-agent lint"

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

  need actionlint

  setup_outdir "gha-agent"

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

  collect_workflow_files

  case "$cmd" in
    lint) run_lint || overall_ok=0 ;;
    all)
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
