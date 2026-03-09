#!/usr/bin/env bash
set -euo pipefail

# bash-agent: lean shell script validation for coding agents
# deps: bash, shellcheck

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_SYNTAX="${RUN_SYNTAX:-1}"
RUN_LINT="${RUN_LINT:-1}"
SHELLCHECK_SEVERITY="${SHELLCHECK_SEVERITY:-warning}"

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
bash-agent — lean shell script validation for coding agents.

Usage: bash-agent.sh [options] [command]

Commands:
  syntax    Run bash -n syntax check on all .sh files
  lint      Run shellcheck on all .sh files
  all       Run syntax + lint (default)
  help      Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_SYNTAX=0|1           Toggle syntax step (default: 1)
  RUN_LINT=0|1             Toggle lint step (default: 1)
  SHELLCHECK_SEVERITY=...  shellcheck --severity level (default: warning)
  CHANGED_FILES="a.sh b.sh"  Scope to specific files
  MAX_LINES=N              Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1             Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1            Stop after first failure (default: 0)
EOF
}

# ---- File discovery -------------------------------------------------------

# Populates the SH_FILES variable (newline-separated list of .sh file paths).
collect_sh_files() {
  SH_FILES=""

  if [[ -n "${CHANGED_FILES:-}" ]]; then
    # Filter CHANGED_FILES to existing .sh files
    local f
    for f in $CHANGED_FILES; do
      if [[ "$f" == *.sh ]] && [[ -f "$f" ]]; then
        if [[ -z "$SH_FILES" ]]; then
          SH_FILES="$f"
        else
          SH_FILES="${SH_FILES}
$f"
        fi
      fi
    done
  else
    # Recursive scan excluding common non-project dirs
    SH_FILES="$(find . \
      -name .git -prune -o \
      -name node_modules -prune -o \
      -name vendor -prune -o \
      -name '*.sh' -type f -print | sort)"
  fi

  local count=0
  if [[ -n "$SH_FILES" ]]; then
    count="$(printf '%s\n' "$SH_FILES" | wc -l | tr -d ' ')"
  fi
  echo "Discovered ${count} .sh file(s)"
}

# ---- Steps ----------------------------------------------------------------

run_syntax() {
  step "syntax"

  if [[ -z "$SH_FILES" ]]; then
    echo
    echo "Result: SKIP (no matching .sh files)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/syntax.log"
  local ok=1

  while IFS= read -r f; do
    if ! bash -n "$f" >>"$log" 2>&1; then
      ok=0
    fi
  done <<< "$SH_FILES"

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve syntax errors above, then re-run: /bash-agent syntax"

  return $(( 1 - ok ))
}

run_lint() {
  step "lint"

  if [[ -z "$SH_FILES" ]]; then
    echo
    echo "Result: SKIP (no matching .sh files)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/lint.log"
  local ok=1

  # Build file list array for shellcheck invocation
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done <<< "$SH_FILES"

  if ! shellcheck --severity="$SHELLCHECK_SEVERITY" "${files[@]}" >"$log" 2>&1; then
    ok=0
  fi

  local fix_hint=""
  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"

    # Extract unique SC codes and build wiki links
    local codes
    codes="$(grep -oE 'SC[0-9]+' "$log" | sort -u | head -n 5)"
    if [[ -n "$codes" ]]; then
      local links=""
      while IFS= read -r code; do
        if [[ -n "$links" ]]; then
          links="${links} , https://www.shellcheck.net/wiki/${code}"
        else
          links="https://www.shellcheck.net/wiki/${code}"
        fi
      done <<< "$codes"
      fix_hint="see ${links} — resolve issues, then re-run: /bash-agent lint"
    else
      fix_hint="resolve shellcheck issues above, then re-run: /bash-agent lint"
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

  need bash
  need shellcheck

  setup_outdir "bash-agent"

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

  collect_sh_files

  case "$cmd" in
    syntax) run_syntax || overall_ok=0 ;;
    lint)   run_lint   || overall_ok=0 ;;
    all)
      if [[ "$RUN_SYNTAX" == "1" ]] && should_continue; then run_syntax || overall_ok=0; fi
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
