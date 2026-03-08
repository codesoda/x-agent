#!/usr/bin/env bash
set -euo pipefail

# docker-agent: lean Dockerfile linter for coding agents
# deps: hadolint (required), docker (optional, for build-check)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_LINT="${RUN_LINT:-1}"
RUN_BUILD_CHECK="${RUN_BUILD_CHECK:-0}"  # opt-in, expensive

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
docker-agent — lean Dockerfile linter for coding agents.

Usage: docker-agent.sh [options] [command]

Commands:
  lint          Run hadolint on discovered Dockerfiles
  build-check   Run docker build --check (BuildKit lint mode, opt-in)
  all           Run enabled steps (default: lint only)
  help          Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_LINT=0|1               Toggle lint step (default: 1)
  RUN_BUILD_CHECK=0|1        Toggle build-check step (default: 0)
  CHANGED_FILES="a b"        Scope to specific files
  MAX_LINES=N                Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1               Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1              Stop after first failure (default: 0)
EOF
}

# ---- Dockerfile discovery -------------------------------------------------

# Populates DOCKERFILES (newline-separated list of Dockerfile paths).
discover_dockerfiles() {
  DOCKERFILES=""

  if [[ -n "${CHANGED_FILES:-}" ]]; then
    local f
    for f in $CHANGED_FILES; do
      local base
      base="$(basename "$f")"
      case "$base" in
        Dockerfile|Dockerfile.*|*.dockerfile)
          if [[ -f "$f" ]]; then
            if [[ -z "$DOCKERFILES" ]]; then
              DOCKERFILES="$f"
            else
              DOCKERFILES="${DOCKERFILES}
$f"
            fi
          fi
          ;;
      esac
    done
  else
    # Recursive find, excluding common non-project directories
    DOCKERFILES="$(find . \
      -name '.git' -prune -o \
      -name 'node_modules' -prune -o \
      -name 'vendor' -prune -o \
      -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.dockerfile' \) \
      -print | sort)"
  fi

  local count=0
  if [[ -n "$DOCKERFILES" ]]; then
    count="$(printf '%s\n' "$DOCKERFILES" | wc -l | tr -d ' ')"
  fi
  echo "Discovered ${count} Dockerfile(s)"
}

# ---- Steps ----------------------------------------------------------------

run_lint() {
  step "lint"

  if [[ -n "${CHANGED_FILES:-}" ]] && [[ -z "$DOCKERFILES" ]]; then
    echo
    echo "Result: SKIP (no Dockerfiles in CHANGED_FILES)"
    fmt_elapsed
    return 0
  fi

  if [[ -z "$DOCKERFILES" ]]; then
    echo
    echo "Result: SKIP (no Dockerfiles found)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/lint.log"
  local ok=1

  while IFS= read -r dockerfile; do
    echo "--- $dockerfile ---" >> "$log"
    if ! hadolint "$dockerfile" >> "$log" 2>&1; then
      ok=0
    fi
  done <<< "$DOCKERFILES"

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve hadolint issues above, then re-run: /docker-agent lint"

  return $(( 1 - ok ))
}

run_build_check() {
  step "build-check"

  if ! command -v docker >/dev/null 2>&1; then
    echo
    echo "Result: SKIP (docker not found)"
    fmt_elapsed
    return 0
  fi

  if [[ -n "${CHANGED_FILES:-}" ]] && [[ -z "$DOCKERFILES" ]]; then
    echo
    echo "Result: SKIP (no Dockerfiles in CHANGED_FILES)"
    fmt_elapsed
    return 0
  fi

  if [[ -z "$DOCKERFILES" ]]; then
    echo
    echo "Result: SKIP (no Dockerfiles found)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/build-check.log"
  local ok=1

  while IFS= read -r dockerfile; do
    echo "--- $dockerfile ---" >> "$log"
    if ! docker build --check -f "$dockerfile" . >> "$log" 2>&1; then
      ok=0
    fi
  done <<< "$DOCKERFILES"

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve build check errors above, then re-run: /docker-agent build-check"

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

  need hadolint

  setup_outdir "docker-agent"

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

  discover_dockerfiles

  case "$cmd" in
    lint)
      run_lint || overall_ok=0
      ;;
    build-check)
      run_build_check || overall_ok=0
      ;;
    all)
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
      if [[ "$RUN_BUILD_CHECK" == "1" ]] && should_continue; then run_build_check || overall_ok=0; fi
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
