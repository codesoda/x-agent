#!/usr/bin/env bash
set -euo pipefail

# cargo-agent: lean Rust workflow output for coding agents
# deps: bash, mktemp, jq
# optional: cargo-nextest (for tests)

JQ_BIN="${JQ_BIN:-jq}"
KEEP_DIR="${KEEP_DIR:-0}"         # set to 1 to keep temp dir even on success
# In CI, show full output; locally, limit to 40 lines to keep things tidy.
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  MAX_LINES="${MAX_LINES:-999999}"
else
  MAX_LINES="${MAX_LINES:-40}"
fi
RUN_TESTS="${RUN_TESTS:-1}"       # set to 0 to skip tests
RUN_CLIPPY="${RUN_CLIPPY:-1}"     # set to 0 to skip clippy
RUN_FMT="${RUN_FMT:-1}"           # set to 0 to skip fmt
RUN_CHECK="${RUN_CHECK:-1}"       # set to 0 to skip check
RUN_SQLX="${RUN_SQLX:-1}"         # set to 0 to skip sqlx cache verify
USE_NEXTEST="${USE_NEXTEST:-auto}" # auto|1|0
RUN_INTEGRATION="${RUN_INTEGRATION:-0}" # set to 1 to run integration tests
FAIL_FAST="${FAIL_FAST:-0}"      # set to 1 or use --fail-fast to stop after first failure

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

# Returns 0 (continue) unless fail-fast is on and a step already failed.
should_continue() { [[ "$FAIL_FAST" != "1" || "$overall_ok" == "1" ]]; }

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

# Resolve short package names (e.g. "api" → "ai-barometer-api").
# Populates _RESOLVED_ARGS with the (possibly modified) argument list.
_RESOLVED_ARGS=()
_WS_PACKAGES=""
resolve_package_args() {
  _RESOLVED_ARGS=()

  # Lazy-load workspace package names once.
  if [[ -z "$_WS_PACKAGES" ]]; then
    _WS_PACKAGES="$(cargo metadata --no-deps --format-version=1 2>/dev/null \
      | "$JQ_BIN" -r '.packages[].name' || true)"
  fi
  if [[ -z "$_WS_PACKAGES" ]]; then
    _RESOLVED_ARGS=("$@")
    return
  fi

  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-p" || "$1" == "--package" ]] && [[ $# -ge 2 ]]; then
      local flag="$1" pkg="$2"
      shift 2
      if echo "$_WS_PACKAGES" | grep -Fxq "$pkg"; then
        _RESOLVED_ARGS+=("$flag" "$pkg")
      else
        local matches
        matches="$(echo "$_WS_PACKAGES" | grep -E "(^|-)${pkg}$" || true)"
        local count
        count="$(echo "$matches" | grep -c . 2>/dev/null || echo 0)"
        if [[ "$count" == "1" ]]; then
          echo "Note: package '${pkg}' not found, using '${matches}'" >&2
          _RESOLVED_ARGS+=("$flag" "$matches")
        else
          _RESOLVED_ARGS+=("$flag" "$pkg")
        fi
      fi
    else
      _RESOLVED_ARGS+=("$1")
      shift
    fi
  done
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
    echo "Fix: resolve the issues above, then re-run: /cargo-agent fmt"
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
  [[ "$ok" == "0" ]] && echo "Fix: resolve the errors above, then re-run: /cargo-agent check"
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
  [[ "$ok" == "0" ]] && echo "Fix: resolve the errors above, then re-run: /cargo-agent clippy"
  echo "Full JSON: $json"
  echo "Lean diags: $diags"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_sqlx_verify() {
  step "sqlx-cache"

  # Skip if the project doesn't use sqlx.
  if ! cargo metadata --no-deps --format-version=1 2>/dev/null \
       | "$JQ_BIN" -e '.packages[].dependencies[] | select(.name=="sqlx")' >/dev/null 2>&1; then
    echo "Result: SKIP (no sqlx dependency found)"
    fmt_elapsed
    return 0
  fi

  # sqlx dep found — cargo-sqlx is required to verify the cache.
  if ! command -v cargo-sqlx >/dev/null 2>&1; then
    echo "Result: FAIL"
    echo "Fix: install sqlx-cli ('cargo install sqlx-cli'), then re-run: /cargo-agent sqlx"
    fmt_elapsed
    return 1
  fi

  local log="$OUTDIR/sqlx.log"
  local status_before="$OUTDIR/sqlx.status.before"
  local status_after="$OUTDIR/sqlx.status.after"
  local ok=1

  git status --porcelain -- .sqlx >"$status_before"

  if ! cargo sqlx prepare --workspace -- --tests >"$log" 2>&1; then
    ok=0
    echo "sqlx prepare failed."
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  git status --porcelain -- .sqlx >"$status_after"
  if ! cmp -s "$status_before" "$status_after"; then
    ok=0
    echo
    echo ".sqlx changed after running prepare (first ${MAX_LINES} entries):"
    head -n "$MAX_LINES" "$status_after"
    echo "Run: cargo sqlx prepare --workspace -- --tests"
    echo "Then commit updated .sqlx files."
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: run 'cargo sqlx prepare --workspace -- --tests' and commit .sqlx files"
  echo "Full log: $log"
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

  # Resolve short package names (e.g. -p api → -p ai-barometer-api).
  resolve_package_args "$@"
  # Bash 3.2 + `set -u` treats "${arr[@]}" on an empty array as unbound.
  if [[ ${#_RESOLVED_ARGS[@]} -gt 0 ]]; then
    set -- "${_RESOLVED_ARGS[@]}"
  else
    set --
  fi

  local -a nextest_args=(--status-level fail --final-status-level fail)
  [[ "$FAIL_FAST" == "1" ]] && nextest_args+=(--fail-fast)
  if [[ "$RUN_INTEGRATION" == "1" ]]; then
    nextest_args+=(--features integration)
  fi

  # Extra args (filters, -p package, etc.) are passed through to nextest.
  if cargo nextest run \
      "${nextest_args[@]}" \
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
  [[ "$ok" == "0" ]] && echo "Fix: resolve the failing tests, then re-run: /cargo-agent test"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

usage() {
  cat <<'EOF'
cargo-agent: lean Rust workflow output for coding agents

Usage:
  cargo-agent [--fail-fast]            # runs fmt, clippy, sqlx, nextest (if installed)
  cargo-agent [--fail-fast] fmt|check|clippy|sqlx|all
  cargo-agent [--fail-fast] test [NEXTEST_ARGS]

Flags:
  --fail-fast            stop after first failing step; also passed to nextest

Env knobs:
  MAX_LINES=40           # printed lines per step (unlimited in CI)
  KEEP_DIR=0|1           # keep temp log dir even on success
  FAIL_FAST=0|1          # same as --fail-fast flag
  RUN_FMT=0|1
  CI=true|1             # fmt runs in check mode on CI, fix mode locally
  RUN_CHECK=0|1
  RUN_CLIPPY=0|1
  RUN_SQLX=0|1
  RUN_TESTS=0|1
  RUN_INTEGRATION=0|1  # enable integration tests (requires DB/network)
  USE_NEXTEST=auto|1|0

Examples:
  cargo-agent                          # full suite
  cargo-agent --fail-fast              # full suite, stop on first failure
  cargo-agent sqlx                     # sqlx cache verify only
  cargo-agent test test_login          # tests matching "test_login"
  cargo-agent test -p db               # tests in the db crate
  cargo-agent test -p api test_auth    # "test_auth" in api crate
  RUN_TESTS=0 cargo-agent              # skip tests
EOF
}

main() {
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --fail-fast) FAIL_FAST=1; shift ;;
      *) break ;;
    esac
  done

  local cmd="${1:-all}"
  shift 2>/dev/null || true
  local overall_ok=1

  case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    fmt)   run_fmt   || overall_ok=0 ;;
    check) run_check || overall_ok=0 ;;
    clippy) run_clippy || overall_ok=0 ;;
    sqlx) run_sqlx_verify || overall_ok=0 ;;
    test)  run_tests "$@" || overall_ok=0 ;;
    all)
      if [[ "$RUN_FMT" == "1" ]]; then run_fmt || overall_ok=0; fi
      if [[ "$RUN_SQLX" == "1" ]] && should_continue; then run_sqlx_verify || overall_ok=0; fi
      # Skip check when clippy is enabled — clippy is a superset of check.
      if [[ "$RUN_CHECK" == "1" && "$RUN_CLIPPY" != "1" ]] && should_continue; then run_check || overall_ok=0; fi
      if [[ "$RUN_CLIPPY" == "1" ]] && should_continue; then run_clippy || overall_ok=0; fi
      if [[ "$RUN_TESTS" == "1" ]] && should_continue; then run_tests || overall_ok=0; fi
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
