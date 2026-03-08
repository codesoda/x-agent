#!/usr/bin/env bash
set -euo pipefail

# ansible-agent: lean Ansible playbook linter and syntax checker for coding agents
# deps: ansible-lint (required), ansible-playbook (required)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_LINT="${RUN_LINT:-1}"
RUN_SYNTAX="${RUN_SYNTAX:-1}"
FMT_MODE="${FMT_MODE:-auto}"   # auto = fix locally, check in CI

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
ansible-agent — lean Ansible playbook linter and syntax checker for coding agents.

Usage: ansible-agent.sh [options] [command]

Commands:
  lint          Run ansible-lint (check or fix mode)
  syntax        Run ansible-playbook --syntax-check on discovered playbooks
  all           Run enabled steps (default)
  help          Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_LINT=0|1               Toggle lint step (default: 1)
  RUN_SYNTAX=0|1             Toggle syntax step (default: 1)
  FMT_MODE=auto|check|fix    Lint mode (default: auto — fix locally, check in CI)
  CHANGED_FILES="a b"        Scope to specific files
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
        FMT_MODE="fix"
      fi
      ;;
    check|fix)
      # CI forces check mode regardless
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

# ---- Playbook discovery ----------------------------------------------------

# Populates ANSIBLE_FILES (newline-separated list of .yml/.yaml paths relevant to ansible)
# and PLAYBOOKS_FOR_SYNTAX (subset with hosts: key for syntax checking).
discover_playbooks() {
  ANSIBLE_FILES=""
  PLAYBOOKS_FOR_SYNTAX=""

  if [[ -n "${CHANGED_FILES:-}" ]]; then
    # Filter CHANGED_FILES to .yml/.yaml files that exist
    local f
    for f in $CHANGED_FILES; do
      case "$f" in
        *.yml|*.yaml)
          if [[ -f "$f" ]]; then
            if [[ -z "$ANSIBLE_FILES" ]]; then
              ANSIBLE_FILES="$f"
            else
              ANSIBLE_FILES="${ANSIBLE_FILES}
$f"
            fi
          fi
          ;;
      esac
    done
  else
    # Recursive find, excluding common non-project directories
    ANSIBLE_FILES="$(find . \
      -name '.git' -prune -o \
      -name 'node_modules' -prune -o \
      -name 'vendor' -prune -o \
      -name '.venv' -prune -o \
      -name '.cache' -prune -o \
      -name '__pycache__' -prune -o \
      -type f \( -name '*.yml' -o -name '*.yaml' \) \
      -print | sort)" || true
  fi

  # Build syntax target list: only files containing hosts: key
  if [[ -n "$ANSIBLE_FILES" ]]; then
    local f
    while IFS= read -r f; do
      if [[ -f "$f" ]] && grep -q '^[[:space:]]*-\{0,1\}[[:space:]]*hosts:' "$f" 2>/dev/null; then
        if [[ -z "$PLAYBOOKS_FOR_SYNTAX" ]]; then
          PLAYBOOKS_FOR_SYNTAX="$f"
        else
          PLAYBOOKS_FOR_SYNTAX="${PLAYBOOKS_FOR_SYNTAX}
$f"
        fi
      fi
    done <<< "$ANSIBLE_FILES"
  fi

  local yaml_count=0 syntax_count=0
  if [[ -n "$ANSIBLE_FILES" ]]; then
    yaml_count="$(printf '%s\n' "$ANSIBLE_FILES" | wc -l | tr -d ' ')"
  fi
  if [[ -n "$PLAYBOOKS_FOR_SYNTAX" ]]; then
    syntax_count="$(printf '%s\n' "$PLAYBOOKS_FOR_SYNTAX" | wc -l | tr -d ' ')"
  fi
  echo "Discovered ${yaml_count} YAML file(s), ${syntax_count} playbook(s) for syntax check"
}

# ---- Steps ----------------------------------------------------------------

run_lint() {
  step "lint"

  # CHANGED_FILES set but no YAML files matched
  if [[ -n "${CHANGED_FILES:-}" ]] && [[ -z "$ANSIBLE_FILES" ]]; then
    echo
    echo "Result: SKIP (no YAML files in CHANGED_FILES)"
    fmt_elapsed
    return 0
  fi

  # No YAML files found at all
  if [[ -z "$ANSIBLE_FILES" ]]; then
    echo
    echo "Result: SKIP (no YAML files found)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/lint.log"
  local ok=1

  if [[ "$FMT_MODE" == "fix" ]]; then
    echo "Mode: fix (ansible-lint --fix)"
    if ! ansible-lint --fix >"$log" 2>&1; then
      ok=0
    fi
  else
    echo "Mode: check"
    if ! ansible-lint >"$log" 2>&1; then
      ok=0
    fi
  fi

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  local fix_hint
  if [[ "$FMT_MODE" == "fix" ]]; then
    fix_hint="resolve remaining lint issues above, then re-run: /ansible-agent lint"
  else
    fix_hint="run /ansible-agent lint with FMT_MODE=fix to auto-fix, then re-run: /ansible-agent lint"
  fi

  print_result "$ok" "$log" "$fix_hint"

  return $(( 1 - ok ))
}

run_syntax() {
  step "syntax"

  # CHANGED_FILES set but no playbooks matched
  if [[ -n "${CHANGED_FILES:-}" ]] && [[ -z "$PLAYBOOKS_FOR_SYNTAX" ]]; then
    echo
    echo "Result: SKIP (no playbooks in CHANGED_FILES)"
    fmt_elapsed
    return 0
  fi

  # No playbooks found for syntax checking
  if [[ -z "$PLAYBOOKS_FOR_SYNTAX" ]]; then
    echo
    echo "Result: SKIP (no playbooks found for syntax check)"
    fmt_elapsed
    return 0
  fi

  local log="${OUTDIR}/syntax.log"
  local ok=1

  while IFS= read -r playbook; do
    echo "--- $playbook ---" >> "$log"
    if ! ansible-playbook --syntax-check "$playbook" >> "$log" 2>&1; then
      ok=0
    fi
  done <<< "$PLAYBOOKS_FOR_SYNTAX"

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "$log" \
    "resolve syntax errors above, then re-run: /ansible-agent syntax"

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

  need ansible-lint
  need ansible-playbook

  resolve_fmt_mode

  setup_outdir "ansible-agent"

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

  discover_playbooks

  case "$cmd" in
    lint)
      run_lint || overall_ok=0
      ;;
    syntax)
      run_syntax || overall_ok=0
      ;;
    all)
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
      if [[ "$RUN_SYNTAX" == "1" ]] && should_continue; then run_syntax || overall_ok=0; fi
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
