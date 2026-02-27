#!/usr/bin/env bash
set -euo pipefail

# terra-agent: lean Terraform workflow output for coding agents
# deps: bash, mktemp, terraform
# optional: tflint

KEEP_DIR="${KEEP_DIR:-0}"              # set to 1 to keep temp dir even on success
MAX_LINES="${MAX_LINES:-40}"           # limit printed output lines per step
RUN_FMT="${RUN_FMT:-1}"                # set to 0 to skip fmt
RUN_INIT="${RUN_INIT:-1}"              # set to 0 to skip init
RUN_VALIDATE="${RUN_VALIDATE:-1}"      # set to 0 to skip validate
RUN_LINT="${RUN_LINT:-1}"              # set to 0 to skip lint
FMT_MODE="${FMT_MODE:-check}"          # check|fix
FMT_RECURSIVE="${FMT_RECURSIVE:-1}"    # set to 0 to disable recursive fmt
TFLINT_RECURSIVE="${TFLINT_RECURSIVE:-1}" # set to 0 to disable recursive tflint
TERRAFORM_CHDIR="${TERRAFORM_CHDIR:-${TF_CHDIR:-.}}"

TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"
OUTDIR="$(mktemp -d "${TMPDIR_ROOT%/}/terra-agent.XXXXXX")"
TF_DATA_DIR_PATH="${TF_DATA_DIR:-$OUTDIR/tf-data}"

cleanup() {
  local code="$?"
  if [[ "$KEEP_DIR" == "1" || "$code" != "0" ]]; then
    echo "Logs kept in: $OUTDIR"
  else
    rm -rf "$OUTDIR"
  fi
  exit "$code"
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 2; }
}

hr() { echo "------------------------------------------------------------"; }

STEP_START_SECONDS=0

step() {
  local name="$1"
  STEP_START_SECONDS=$SECONDS
  hr
  echo "Step: $name"
}

fmt_elapsed() {
  local elapsed=$(( SECONDS - STEP_START_SECONDS ))
  echo "Time: ${elapsed}s"
}

normalize_dir() {
  if [[ -z "$TERRAFORM_CHDIR" ]]; then
    TERRAFORM_CHDIR="."
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
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

usage() {
  cat <<'EOF'
terra-agent: lean Terraform workflow output for coding agents

Usage:
  terra-agent                               # runs fmt(check), init(safe), validate, lint
  terra-agent fmt                           # fmt in FMT_MODE
  terra-agent fmt-check                     # report-only format check
  terra-agent fmt-fix                       # auto-fix formatting
  terra-agent init                          # safe non-mutating init
  terra-agent validate                      # terraform validate
  terra-agent lint                          # tflint (if installed)
  terra-agent all                           # full suite (default)

Env knobs:
  MAX_LINES=40                   # printed lines per step
  KEEP_DIR=0|1                   # keep temp log dir even on success
  TERRAFORM_CHDIR=.              # terraform root directory
  TF_CHDIR=.                     # alias for TERRAFORM_CHDIR
  RUN_FMT=0|1
  RUN_INIT=0|1
  RUN_VALIDATE=0|1
  RUN_LINT=0|1
  FMT_MODE=check|fix             # default: check
  FMT_RECURSIVE=0|1              # default: 1
  TFLINT_RECURSIVE=0|1           # default: 1

Examples:
  terra-agent
  TERRAFORM_CHDIR=infra terra-agent fmt-check
  TERRAFORM_CHDIR=infra terra-agent fmt-fix
  TERRAFORM_CHDIR=infra terra-agent init
  FMT_MODE=fix TERRAFORM_CHDIR=infra terra-agent fmt
  RUN_LINT=0 TERRAFORM_CHDIR=infra terra-agent all
EOF
}

main() {
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
  ensure_terraform_project

  case "$cmd" in
    fmt)       run_fmt "$FMT_MODE" || overall_ok=0 ;;
    fmt-check) run_fmt "check" || overall_ok=0 ;;
    fmt-fix)   run_fmt "fix" || overall_ok=0 ;;
    init)      run_init || overall_ok=0 ;;
    validate)  run_validate || overall_ok=0 ;;
    lint)      run_lint || overall_ok=0 ;;
    all)
      if [[ "$RUN_FMT" == "1" ]]; then run_fmt "$FMT_MODE" || overall_ok=0; fi
      if [[ "$RUN_INIT" == "1" ]]; then run_init || overall_ok=0; fi
      if [[ "$RUN_VALIDATE" == "1" ]]; then run_validate || overall_ok=0; fi
      if [[ "$RUN_LINT" == "1" ]]; then run_lint || overall_ok=0; fi
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 2
      ;;
  esac

  hr
  echo "Overall: $([[ "$overall_ok" == "1" ]] && echo PASS || echo FAIL)"
  echo "Logs: $OUTDIR"
  [[ "$overall_ok" == "1" ]]
}

main "$@"
