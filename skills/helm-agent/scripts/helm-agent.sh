#!/usr/bin/env bash
set -euo pipefail

# helm-agent: lean Helm chart linter and template validator for coding agents
# deps: helm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_LINT="${RUN_LINT:-1}"
RUN_TEMPLATE="${RUN_TEMPLATE:-1}"
CHART_DIR="${CHART_DIR:-}"

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
helm-agent — lean Helm chart linter and template validator for coding agents.

Usage: helm-agent.sh [options] [command]

Commands:
  lint      Run helm lint on chart directories
  template  Run helm template to validate rendering
  all       Run lint + template (default)
  help      Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_LINT=0|1             Toggle lint step (default: 1)
  RUN_TEMPLATE=0|1         Toggle template step (default: 1)
  CHART_DIR=path           Explicit chart directory (skip auto-detection)
  CHANGED_FILES="a.yaml b.tpl"  Scope to charts containing these files
  MAX_LINES=N              Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1             Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1            Stop after first failure (default: 0)
EOF
}

# ---- Chart discovery ------------------------------------------------------

# Finds the nearest parent directory containing Chart.yaml for a given file.
# Prints the chart root or nothing if not found.
find_chart_root() {
  local filepath="$1"
  local dir
  dir="$(dirname "$filepath")"

  while true; do
    if [[ -f "${dir}/Chart.yaml" ]]; then
      echo "$dir"
      return 0
    fi
    # Stop at current working directory or filesystem root
    if [[ "$dir" == "." || "$dir" == "/" ]]; then
      return 1
    fi
    dir="$(dirname "$dir")"
  done
}

# Populates CHART_TARGETS (newline-separated list of chart root directories).
collect_chart_targets() {
  CHART_TARGETS=""

  # Priority 1: explicit CHART_DIR
  if [[ -n "$CHART_DIR" ]]; then
    if [[ -d "$CHART_DIR" ]] && [[ -f "${CHART_DIR}/Chart.yaml" ]]; then
      CHART_TARGETS="$CHART_DIR"
      echo "Using explicit CHART_DIR: ${CHART_DIR}"
      return 0
    fi
    echo "CHART_DIR set but no Chart.yaml found at: ${CHART_DIR}"
    return 0
  fi

  # Priority 2: derive chart roots from CHANGED_FILES
  if [[ -n "${CHANGED_FILES:-}" ]]; then
    local seen=""
    local f root
    for f in $CHANGED_FILES; do
      case "$f" in
        *.yaml|*.yml|*.tpl)
          if [[ -f "$f" ]]; then
            root="$(find_chart_root "$f")" || continue
            # Dedupe
            case " ${seen} " in
              *" ${root} "*) ;;
              *)
                seen="${seen} ${root}"
                if [[ -z "$CHART_TARGETS" ]]; then
                  CHART_TARGETS="$root"
                else
                  CHART_TARGETS="${CHART_TARGETS}
${root}"
                fi
                ;;
            esac
          fi
          ;;
      esac
    done

    if [[ -n "$CHART_TARGETS" ]]; then
      local count
      count="$(printf '%s\n' "$CHART_TARGETS" | wc -l | tr -d ' ')"
      echo "Discovered ${count} chart(s) from CHANGED_FILES"
    else
      echo "CHANGED_FILES set but no chart-related files found"
    fi
    return 0
  fi

  # Priority 3: recursive Chart.yaml search
  local found
  found="$(find . -name Chart.yaml -not -path '*/charts/*' -print 2>/dev/null | sort)" || true
  if [[ -z "$found" ]]; then
    echo "No Chart.yaml found in directory tree"
    return 0
  fi

  local chart_file chart_root
  while IFS= read -r chart_file; do
    chart_root="$(dirname "$chart_file")"
    if [[ -z "$CHART_TARGETS" ]]; then
      CHART_TARGETS="$chart_root"
    else
      CHART_TARGETS="${CHART_TARGETS}
${chart_root}"
    fi
  done <<< "$found"

  local count
  count="$(printf '%s\n' "$CHART_TARGETS" | wc -l | tr -d ' ')"
  echo "Discovered ${count} chart(s) via recursive search"
}

# ---- Steps ----------------------------------------------------------------

run_lint() {
  step "lint"

  if [[ -z "$CHART_TARGETS" ]]; then
    echo
    echo "Result: SKIP (no charts discovered)"
    fmt_elapsed
    return 0
  fi

  local ok=1 idx=0 chart_dir log
  while IFS= read -r chart_dir; do
    idx=$((idx + 1))
    log="${OUTDIR}/lint.${idx}.log"
    echo "Linting: ${chart_dir}"

    if ! helm lint "$chart_dir" >"$log" 2>&1; then
      ok=0
      echo
      echo "Output (first ${MAX_LINES} lines):"
      head -n "$MAX_LINES" "$log"
    fi
  done <<< "$CHART_TARGETS"

  print_result "$ok" "${OUTDIR}/lint.*.log" \
    "resolve the chart errors above, then re-run: /helm-agent lint"

  return $(( 1 - ok ))
}

run_template() {
  step "template"

  if [[ -z "$CHART_TARGETS" ]]; then
    echo
    echo "Result: SKIP (no charts discovered)"
    fmt_elapsed
    return 0
  fi

  local ok=1 idx=0 chart_dir log
  while IFS= read -r chart_dir; do
    idx=$((idx + 1))
    log="${OUTDIR}/template.${idx}.log"
    echo "Rendering: ${chart_dir}"

    if ! helm template "$chart_dir" >"$log" 2>&1; then
      ok=0
      echo
      echo "Output (first ${MAX_LINES} lines):"
      head -n "$MAX_LINES" "$log"
    fi
  done <<< "$CHART_TARGETS"

  print_result "$ok" "${OUTDIR}/template.*.log" \
    "resolve the template errors above, then re-run: /helm-agent template"

  return $(( 1 - ok ))
}

# ---- Main -----------------------------------------------------------------

main() {
  # Parse help before need() checks so --help works without helm installed
  case "${1:-}" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  need helm

  setup_outdir "helm-agent"

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

  collect_chart_targets

  case "$cmd" in
    lint) run_lint || overall_ok=0 ;;
    template) run_template || overall_ok=0 ;;
    all)
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
      if [[ "$RUN_TEMPLATE" == "1" ]] && should_continue; then run_template || overall_ok=0; fi
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
