#!/usr/bin/env bash
set -euo pipefail

# terra-agent: lean Terraform workflow output for coding agents
# deps: bash, mktemp, terraform
# optional: tflint

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

RUN_FMT="${RUN_FMT:-1}"                # set to 0 to skip fmt
RUN_INIT="${RUN_INIT:-1}"              # set to 0 to skip init
RUN_VALIDATE="${RUN_VALIDATE:-1}"      # set to 0 to skip validate
RUN_LINT="${RUN_LINT:-1}"              # set to 0 to skip lint
RUN_PLAN_SAFE="${RUN_PLAN_SAFE:-0}"    # set to 1 to run plan-safe in all
FMT_MODE="${FMT_MODE:-check}"          # check|fix
FMT_RECURSIVE="${FMT_RECURSIVE:-1}"    # set to 0 to disable recursive fmt
TFLINT_RECURSIVE="${TFLINT_RECURSIVE:-1}" # set to 0 to disable recursive tflint
TERRAFORM_CHDIR="${TERRAFORM_CHDIR:-${TF_CHDIR:-.}}"

setup_outdir "terra-agent"
TF_DATA_DIR_PATH="${TF_DATA_DIR:-$OUTDIR/tf-data}"

normalize_dir() {
  if [[ -z "$TERRAFORM_CHDIR" ]]; then
    TERRAFORM_CHDIR="."
  fi
}

# If CHANGED_FILES is set and TERRAFORM_CHDIR was not explicitly provided,
# auto-detect the terraform root from changed .tf files.
resolve_changed_tf_dir() {
  if [[ -z "$CHANGED_FILES" ]]; then return; fi
  # Only auto-detect when TERRAFORM_CHDIR is the default.
  if [[ "$TERRAFORM_CHDIR" != "." ]]; then return; fi

  local dirs=""
  local f dir
  for f in $CHANGED_FILES; do
    case "$f" in
      *.tf|*.tf.json)
        dir="$(dirname "$f")"
        if ! echo "$dirs" | grep -Fxq "$dir"; then
          dirs="${dirs:+$dirs$'\n'}$dir"
        fi
        ;;
    esac
  done

  if [[ -z "$dirs" ]]; then return; fi
  local count
  count="$(echo "$dirs" | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    TERRAFORM_CHDIR="$dirs"
    echo "Auto-detected TERRAFORM_CHDIR=$TERRAFORM_CHDIR from changed files"
  else
    echo "Note: changed .tf files span multiple directories, running from ."
  fi
}

normalize_fmt_mode() {
  case "$1" in
    check|fix) return 0 ;;
    *)
      echo "Invalid fmt mode: $1 (expected check or fix)" >&2
      exit 2
      ;;
  esac
}

tf() {
  if [[ "$TERRAFORM_CHDIR" == "." ]]; then
    TF_DATA_DIR="$TF_DATA_DIR_PATH" terraform "$@"
  else
    TF_DATA_DIR="$TF_DATA_DIR_PATH" terraform "-chdir=$TERRAFORM_CHDIR" "$@"
  fi
}

ensure_terraform_project() {
  if [[ ! -d "$TERRAFORM_CHDIR" ]]; then
    echo "Error: TERRAFORM_CHDIR does not exist: $TERRAFORM_CHDIR" >&2
    exit 2
  fi

  if ! find "$TERRAFORM_CHDIR" -type f \( -name "*.tf" -o -name "*.tf.json" \) | grep -q .; then
    echo "Error: no Terraform files found in $TERRAFORM_CHDIR" >&2
    exit 2
  fi
}

run_fmt() {
  local mode="$1"
  normalize_fmt_mode "$mode"

  step "fmt"
  local log="$OUTDIR/fmt.${mode}.log"
  local ok=1
  local -a args=(fmt)

  if [[ "$mode" == "check" ]]; then
    args+=("-check")
  fi
  if [[ "$FMT_RECURSIVE" == "1" ]]; then
    args+=("-recursive")
  fi

  echo "Mode: $mode"
  if tf "${args[@]}" >"$log" 2>&1; then
    :
  else
    ok=0
  fi

  if [[ "$mode" == "check" && "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Files needing formatting (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  if [[ "$mode" == "fix" && -s "$log" ]]; then
    echo
    echo "Files formatted (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  if [[ "$ok" == "0" && "$mode" == "check" ]]; then
    echo "Fix: run /terra-agent fmt-fix to auto-format, then re-check: /terra-agent fmt-check"
  elif [[ "$ok" == "0" ]]; then
    echo "Fix: resolve the errors above, then re-run: /terra-agent fmt-fix"
  fi
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_validate() {
  step "validate"
  local log="$OUTDIR/validate.log"
  local ok=1

  if tf validate -no-color >"$log" 2>&1; then
    :
  else
    ok=0
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the validation errors above, then re-run: /terra-agent validate"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_init() {
  step "init"
  local log="$OUTDIR/init.log"
  local ok=1
  local -a args=(
    init
    -backend=false
    -input=false
    -lockfile=readonly
    -get=false
    -upgrade=false
    -no-color
  )

  # Safety guarantees:
  # - no backend init
  # - no prompts
  # - no module downloads/upgrades
  # - lockfile must stay unchanged
  # - TF_DATA_DIR points at temp output dir, not the project
  if tf "${args[@]}" >"$log" 2>&1; then
    :
  else
    ok=0
  fi

  echo "Mode: safe (non-mutating)"
  echo "TF_DATA_DIR: $TF_DATA_DIR_PATH"

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the init errors above, then re-run: /terra-agent init"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_plan_safe() {
  step "plan-safe"
  local init_log="$OUTDIR/plan-safe.init.log"
  local log="$OUTDIR/plan-safe.log"
  local ok=1
  local changed=0
  local rc=0
  local -a init_args=(
    init
    -backend=false
    -input=false
    -lockfile=readonly
    -get=false
    -upgrade=false
    -no-color
  )
  local -a plan_args=(
    plan
    -refresh=false
    -lock=false
    -input=false
    -detailed-exitcode
    -no-color
  )

  # Run safe init first so plan-safe works from a clean temp TF_DATA_DIR.
  if tf "${init_args[@]}" >"$init_log" 2>&1; then
    :
  else
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    set +e
    tf "${plan_args[@]}" >"$log" 2>&1
    rc=$?
    set -e

    case "$rc" in
      0)
        changed=0
        ;;
      2)
        changed=1
        ;;
      *)
        ok=0
        ;;
    esac
  fi

  echo "Mode: safe (non-mutating)"
  echo "TF_DATA_DIR: $TF_DATA_DIR_PATH"
  if [[ "$ok" == "1" ]]; then
    echo "Changes detected: $([[ "$changed" == "1" ]] && echo yes || echo no)"
  fi

  if [[ "$ok" == "0" ]]; then
    if [[ -s "$init_log" ]]; then
      echo
      echo "Init output (first ${MAX_LINES} lines):"
      head -n "$MAX_LINES" "$init_log"
    fi
    if [[ -s "$log" ]]; then
      echo
      echo "Plan output (first ${MAX_LINES} lines):"
      head -n "$MAX_LINES" "$log"
    fi
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the errors above, then re-run: /terra-agent plan-safe"
  echo "Init log: $init_log"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_lint() {
  step "lint"
  local log="$OUTDIR/lint.log"
  local ok=1
  local -a args=()

  if ! command -v tflint >/dev/null 2>&1; then
    echo "Result: SKIP (tflint not found)"
    fmt_elapsed
    return 0
  fi

  if [[ "$TFLINT_RECURSIVE" == "1" ]]; then
    args+=("--recursive")
  fi

  if [[ "$TERRAFORM_CHDIR" == "." ]]; then
    if tflint "${args[@]}" >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  else
    if (cd "$TERRAFORM_CHDIR" && tflint "${args[@]}") >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the lint issues above, then re-run: /terra-agent lint"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

usage() {
  cat <<'EOF'
terra-agent: lean Terraform workflow output for coding agents

Usage:
  terra-agent [--fail-fast]                   # runs fmt(check), init(safe), validate, lint
  terra-agent [--fail-fast] fmt               # fmt in FMT_MODE
  terra-agent fmt-check                       # report-only format check
  terra-agent fmt-fix                         # auto-fix formatting
  terra-agent init                            # safe non-mutating init
  terra-agent plan-safe                       # safe non-mutating plan (passes on exit 0 or 2)
  terra-agent validate                        # terraform validate
  terra-agent lint                            # tflint (if installed)
  terra-agent [--fail-fast] all               # full suite (default)

Flags:
  --fail-fast              stop after first failing step

Env knobs:
  MAX_LINES=40                   # printed lines per step (unlimited in CI)
  KEEP_DIR=0|1                   # keep temp log dir even on success
  FAIL_FAST=0|1                  # same as --fail-fast flag
  TERRAFORM_CHDIR=.              # terraform root directory
  TF_CHDIR=.                     # alias for TERRAFORM_CHDIR
  RUN_FMT=0|1
  RUN_INIT=0|1
  RUN_VALIDATE=0|1
  RUN_LINT=0|1
  RUN_PLAN_SAFE=0|1            # set to 1 to include in "all"
  FMT_MODE=check|fix             # default: check
  FMT_RECURSIVE=0|1              # default: 1
  TFLINT_RECURSIVE=0|1           # default: 1
  CHANGED_FILES="f1 f2"          # auto-set TERRAFORM_CHDIR from changed .tf files

Examples:
  terra-agent
  terra-agent --fail-fast                         # full suite, stop on first failure
  TERRAFORM_CHDIR=infra terra-agent fmt-check
  TERRAFORM_CHDIR=infra terra-agent fmt-fix
  TERRAFORM_CHDIR=infra terra-agent init
  TERRAFORM_CHDIR=infra terra-agent plan-safe
  FMT_MODE=fix TERRAFORM_CHDIR=infra terra-agent fmt
  RUN_PLAN_SAFE=1 TERRAFORM_CHDIR=infra terra-agent all
  RUN_LINT=0 TERRAFORM_CHDIR=infra terra-agent all
EOF
}

main() {
  while [[ "${1:-}" == --* ]]; do
    # shellcheck disable=SC2034 # FAIL_FAST used by should_continue() in x-agent-common.sh
    case "$1" in
      --fail-fast) FAIL_FAST=1; shift ;;
      *) break ;;
    esac
  done

  local cmd="${1:-all}"
  shift 2>/dev/null || true
  local overall_ok=1

  case "$cmd" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  need terraform
  normalize_dir
  resolve_changed_tf_dir
  ensure_terraform_project

  case "$cmd" in
    fmt)       run_fmt "$FMT_MODE" || overall_ok=0 ;;
    fmt-check) run_fmt "check" || overall_ok=0 ;;
    fmt-fix)   run_fmt "fix" || overall_ok=0 ;;
    init)      run_init || overall_ok=0 ;;
    plan-safe) run_plan_safe || overall_ok=0 ;;
    validate)  run_validate || overall_ok=0 ;;
    lint)      run_lint || overall_ok=0 ;;
    all)
      if [[ "$RUN_FMT" == "1" ]] && should_continue; then run_fmt "$FMT_MODE" || overall_ok=0; fi
      if [[ "$RUN_INIT" == "1" ]] && should_continue; then run_init || overall_ok=0; fi
      if [[ "$RUN_VALIDATE" == "1" ]] && should_continue; then run_validate || overall_ok=0; fi
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
      if [[ "$RUN_PLAN_SAFE" == "1" ]] && should_continue; then run_plan_safe || overall_ok=0; fi
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
