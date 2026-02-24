#!/usr/bin/env bash
set -euo pipefail

# cargo-agent: lean Rust workflow output for coding agents
# deps: bash, mktemp, jq
# optional: cargo-nextest (for tests)

JQ_BIN="${JQ_BIN:-jq}"
KEEP_DIR="${KEEP_DIR:-0}"         # set to 1 to keep temp dir even on success
MAX_LINES="${MAX_LINES:-40}"      # limit printed diagnostics lines per step
RUN_TESTS="${RUN_TESTS:-1}"       # set to 0 to skip tests
RUN_CLIPPY="${RUN_CLIPPY:-1}"     # set to 0 to skip clippy
RUN_FMT="${RUN_FMT:-1}"           # set to 0 to skip fmt
RUN_CHECK="${RUN_CHECK:-1}"       # set to 0 to skip check
USE_NEXTEST="${USE_NEXTEST:-auto}" # auto|1|0

TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"
OUTDIR="$(mktemp -d "${TMPDIR_ROOT%/}/cargo-agent.XXXXXX")"

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

need "$JQ_BIN"
need cargo

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

# Extract compiler diagnostics (errors/warnings) from cargo JSON stream.
# Outputs: lines like "error: message" and optionally a location line.
extract_compiler_diags() {
  local json_file="$1"
  local include_location="${2:-0}"

  if [[ "$include_location" == "1" ]]; then
    "$JQ_BIN" -r '
      select(.reason=="compiler-message") |
      select(.message.level=="error" or .message.level=="warning") |
      .message as $m |
      ($m.spans[0] // {}) as $s |
      "\($m.level): \($m.message)\n  --> \($s.file_name // "?"):\($s.line_start // 0)"
    ' "$json_file"
  else
    "$JQ_BIN" -r '
      select(.reason=="compiler-message") |
      select(.message.level=="error" or .message.level=="warning") |
      "\(.message.level): \(.message.message)"
    ' "$json_file"
  fi
}

count_compiler_level() {
  local json_file="$1"
  local level="$2"
  "$JQ_BIN" --slurp -r --arg lvl "$level" '
    [.[] | select(.reason=="compiler-message" and .message.level==$lvl)] | length
  ' "$json_file"
}

run_fmt() {
  step "fmt"
  local log="$OUTDIR/fmt.log"
  local ok=1

  local fmt_args=(fmt --all)
  local mode="fix"
  if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
    fmt_args+=(-- --check)
    mode="check"
  fi

  echo "Mode: $mode"
  if cargo "${fmt_args[@]}" >"$log" 2>&1; then
    echo "Result: PASS"
  else
    ok=0
    echo "Result: FAIL"
    echo "First ${MAX_LINES} lines:"
    head -n "$MAX_LINES" "$log"
  fi

  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_check() {
  step "check"
  local json="$OUTDIR/check.json"
  local diags="$OUTDIR/check.diags.txt"
  local ok=1

  if cargo check --workspace --all-targets --message-format=json >"$json" 2>"$OUTDIR/check.stderr.log"; then
    :
  else
    ok=0
  fi

  local errors warnings
  errors="$(count_compiler_level "$json" "error" 2>/dev/null || echo 0)"
  warnings="$(count_compiler_level "$json" "warning" 2>/dev/null || echo 0)"

  echo "Errors: $errors"
  echo "Warnings: $warnings"

  extract_compiler_diags "$json" 0 2>/dev/null | awk '!seen[$0]++' >"$diags" || true

  if [[ "$errors" != "0" ]]; then ok=0; fi

  if [[ -s "$diags" ]]; then
    echo
    echo "Diagnostics (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$diags"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  echo "Full JSON: $json"
  echo "Lean diags: $diags"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_clippy() {
  step "clippy"
  local json="$OUTDIR/clippy.json"
  local diags="$OUTDIR/clippy.diags.txt"
  local ok=1

  if cargo clippy --workspace --all-targets --message-format=json >"$json" 2>"$OUTDIR/clippy.stderr.log"; then
    :
  else
    ok=0
  fi

  local errors warnings
  errors="$(count_compiler_level "$json" "error" 2>/dev/null || echo 0)"
  warnings="$(count_compiler_level "$json" "warning" 2>/dev/null || echo 0)"

  echo "Errors: $errors"
  echo "Warnings: $warnings"

  extract_compiler_diags "$json" 0 2>/dev/null | awk '!seen[$0]++' >"$diags" || true
  if [[ "$errors" != "0" ]]; then ok=0; fi

  if [[ -s "$diags" ]]; then
    echo
    echo "Diagnostics (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$diags"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  echo "Full JSON: $json"
  echo "Lean diags: $diags"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

have_nextest() {
  command -v cargo-nextest >/dev/null 2>&1 || cargo nextest --version >/dev/null 2>&1
}

run_tests() {
  step "test"
  local ok=1

  if [[ "$USE_NEXTEST" == "0" ]]; then
    echo "Result: SKIP (USE_NEXTEST=0, no runner configured)"
    return 0
  fi

  if [[ "$USE_NEXTEST" == "auto" ]]; then
    if ! cargo nextest --version >/dev/null 2>&1; then
      echo "Result: SKIP"
      echo "cargo-nextest not found. Install it, or set RUN_TESTS=0."
      return 0
    fi
  fi

  local log="$OUTDIR/nextest.log"

  # Extra args (filters, -p package, etc.) are passed through to nextest.
  if cargo nextest run \
      --status-level fail \
      --final-status-level fail \
      "$@" \
      >"$log" 2>&1; then
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

usage() {
  cat <<'EOF'
cargo-agent: lean Rust workflow output for coding agents

Usage:
  cargo-agent                        # runs fmt, clippy, nextest (if installed)
  cargo-agent fmt|check|clippy|all
  cargo-agent test [NEXTEST_ARGS]    # pass-through to cargo nextest run

Env knobs:
  MAX_LINES=40           # printed lines per step
  KEEP_DIR=0|1           # keep temp log dir even on success
  RUN_FMT=0|1
  CI=true|1             # fmt runs in check mode on CI, fix mode locally
  RUN_CHECK=0|1
  RUN_CLIPPY=0|1
  RUN_TESTS=0|1
  USE_NEXTEST=auto|1|0

Examples:
  cargo-agent                          # full suite
  cargo-agent test test_login          # tests matching "test_login"
  cargo-agent test -p db               # tests in the db crate
  cargo-agent test -p api test_auth    # "test_auth" in api crate
  RUN_TESTS=0 cargo-agent              # skip tests
EOF
}

main() {
  local cmd="${1:-all}"
  shift 2>/dev/null || true
  local overall_ok=1

  case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    fmt)   run_fmt   || overall_ok=0 ;;
    check) run_check || overall_ok=0 ;;
    clippy) run_clippy || overall_ok=0 ;;
    test)  run_tests "$@" || overall_ok=0 ;;
    all)
      if [[ "$RUN_FMT" == "1" ]]; then run_fmt || overall_ok=0; fi
      # Skip check when clippy is enabled — clippy is a superset of check.
      if [[ "$RUN_CHECK" == "1" && "$RUN_CLIPPY" != "1" ]]; then run_check || overall_ok=0; fi
      if [[ "$RUN_CLIPPY" == "1" ]]; then run_clippy || overall_ok=0; fi
      if [[ "$RUN_TESTS" == "1" ]]; then run_tests || overall_ok=0; fi
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
