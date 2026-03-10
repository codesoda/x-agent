#!/usr/bin/env bash
set -euo pipefail

# cargo-agent: lean Rust workflow output for coding agents
# deps: bash, mktemp, jq
# optional: cargo-nextest (for tests)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

JQ_BIN="${JQ_BIN:-jq}"
RUN_TESTS="${RUN_TESTS:-1}"       # set to 0 to skip tests
RUN_CLIPPY="${RUN_CLIPPY:-1}"     # set to 0 to skip clippy
RUN_FMT="${RUN_FMT:-1}"           # set to 0 to skip fmt
RUN_CHECK="${RUN_CHECK:-1}"       # set to 0 to skip check
RUN_SQLX="${RUN_SQLX:-1}"         # set to 0 to skip sqlx cache verify
USE_NEXTEST="${USE_NEXTEST:-auto}" # auto|1|0
RUN_INTEGRATION="${RUN_INTEGRATION:-0}" # set to 1 to run integration tests

# Default to SQLx offline mode, but allow explicit overrides (e.g. CI sets false).
export SQLX_OFFLINE="${SQLX_OFFLINE:-true}"

setup_outdir "cargo-agent"
setup_lock "cargo-agent"

need "$JQ_BIN"
need cargo

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

# Resolve CHANGED_FILES to affected workspace packages.
# Populates _AFFECTED_PKG_ARGS with "-p pkg1 -p pkg2 ..." or empty if all.
_AFFECTED_PKG_ARGS=()
resolve_affected_packages() {
  _AFFECTED_PKG_ARGS=()
  if [[ -z "$CHANGED_FILES" ]]; then return; fi

  local metadata
  metadata="$(cargo metadata --no-deps --format-version=1 2>/dev/null || true)"
  if [[ -z "$metadata" ]]; then return; fi

  local ws_root
  ws_root="$(echo "$metadata" | "$JQ_BIN" -r '.workspace_root')"

  # Build "name<TAB>relative-dir" pairs from manifest paths.
  local pkg_dirs
  pkg_dirs="$(echo "$metadata" | "$JQ_BIN" -r \
    --arg root "$ws_root" \
    '.packages[] | "\(.name)\t\(.manifest_path | split("/")[:-1] | join("/") | ltrimstr($root + "/"))"')"

  local seen=""
  local file rel_dir name
  for file in $CHANGED_FILES; do
    while IFS=$'\t' read -r name rel_dir; do
      if [[ "$file" == "$rel_dir"/* || "$file" == "$rel_dir" ]]; then
        if ! echo "$seen" | grep -Fxq "$name"; then
          seen="${seen:+$seen$'\n'}$name"
          _AFFECTED_PKG_ARGS+=(-p "$name")
        fi
      fi
    done <<< "$pkg_dirs"
  done

  if [[ ${#_AFFECTED_PKG_ARGS[@]} -gt 0 ]]; then
    echo "Scoped to packages: ${_AFFECTED_PKG_ARGS[*]}"
  fi
}

# Build -p package args from changed files in git (tracked + untracked).
# Populates _CHANGED_PACKAGE_ARGS and _CHANGED_FORCE_FULL.
_CHANGED_PACKAGE_ARGS=()
_CHANGED_FORCE_FULL=0
collect_changed_package_args() {
  _CHANGED_PACKAGE_ARGS=()
  _CHANGED_FORCE_FULL=0

  local diff_paths untracked_paths combined_paths changed_crates
  diff_paths="$(git diff --name-only HEAD 2>/dev/null || true)"
  untracked_paths="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
  combined_paths="$(printf '%s\n%s\n' "$diff_paths" "$untracked_paths" | sed '/^$/d' | sort -u)"

  if [[ -z "$combined_paths" ]]; then
    return 1
  fi

  # Workspace-level cargo config/manifest changes can impact all crates.
  if echo "$combined_paths" | grep -Eq '^(Cargo\.toml|Cargo\.lock|\.cargo/)'; then
    _CHANGED_FORCE_FULL=1
    return 0
  fi

  changed_crates="$(echo "$combined_paths" | awk -F/ '$1=="crates" && $2!="" {print $2}' | sort -u)"
  if [[ -z "$changed_crates" ]]; then
    return 1
  fi

  local crate_name
  while IFS= read -r crate_name; do
    [[ -n "$crate_name" ]] && _CHANGED_PACKAGE_ARGS+=("-p" "$crate_name")
  done <<< "$changed_crates"

  return 0
}

# Extract failing test names from a nextest/libtest log file.
extract_failing_tests() {
  local log="$1"
  [[ -s "$log" ]] || return 0

  {
    # nextest human output, e.g. "FAIL [ 0.001s] crate::module::test_name"
    sed -nE 's/^.*FAIL[[:space:]]+\[[^]]+\][[:space:]]+([^[:space:]]+).*$/\1/p' "$log"
    # libtest-style output, e.g. "test crate::module::test_name ... FAILED"
    sed -nE 's/^test[[:space:]]+([^[:space:]]+)[[:space:]]+\.\.\.[[:space:]]+FAILED$/\1/p' "$log"
    # Failure summaries under "failures:" sections.
    awk '
      /^failures:$/ { in_failures = 1; next }
      in_failures && /^[[:space:]]*$/ { in_failures = 0; next }
      in_failures {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        if (line ~ /::/) print line
      }
    ' "$log"
  } | sort -u
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
  if [[ "$mode" == "fix" ]]; then
    # In fix mode, first detect which files need formatting, then apply.
    local needs_fmt
    needs_fmt="$(cargo fmt --all -- --check 2>&1 || true)"
    if ! cargo "${fmt_args[@]}" >"$log" 2>&1; then
      ok=0
      echo "Result: FAIL"
      echo "Fix: resolve the issues above, then re-run: /cargo-agent fmt"
      echo "First ${MAX_LINES} lines:"
      head -n "$MAX_LINES" "$log"
    elif [[ -n "$needs_fmt" ]]; then
      local changed_files
      changed_files="$(echo "$needs_fmt" | grep '^Diff in' | sed 's/^Diff in //' | sed 's/:[0-9]*:$//' | sort -u)"
      if [[ -n "$changed_files" ]]; then
        echo "Result: PASS (files reformatted)"
        echo "Files fixed:"
        echo "$changed_files" | while read -r f; do echo "  $f"; done
      else
        echo "Result: PASS"
      fi
    else
      echo "Result: PASS"
    fi
  else
    # Check mode (CI).
    if cargo "${fmt_args[@]}" >"$log" 2>&1; then
      echo "Result: PASS"
    else
      ok=0
      echo "Result: FAIL"
      echo "Fix: resolve the issues above, then re-run: /cargo-agent fmt"
      echo "First ${MAX_LINES} lines:"
      head -n "$MAX_LINES" "$log"
    fi
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

  local -a scope=(--workspace)
  if [[ ${#_AFFECTED_PKG_ARGS[@]} -gt 0 ]]; then scope=("${_AFFECTED_PKG_ARGS[@]}"); fi

  if cargo check "${scope[@]}" --all-targets --message-format=json >"$json" 2>"$OUTDIR/check.stderr.log"; then
    :
  else
    ok=0
  fi

  local errors warnings
  errors="$(count_compiler_level "$json" "error" 2>/dev/null || echo 0)"
  warnings="$(count_compiler_level "$json" "warning" 2>/dev/null || echo 0)"

  echo "Errors: $errors"
  echo "Warnings: $warnings"

  extract_compiler_diags "$json" 1 2>/dev/null | awk '!seen[$0]++' >"$diags" || true

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

  local -a scope=(--workspace)
  if [[ ${#_AFFECTED_PKG_ARGS[@]} -gt 0 ]]; then scope=("${_AFFECTED_PKG_ARGS[@]}"); fi

  if cargo clippy "${scope[@]}" --all-targets --message-format=json >"$json" 2>"$OUTDIR/clippy.stderr.log"; then
    :
  else
    ok=0
  fi

  local errors warnings
  errors="$(count_compiler_level "$json" "error" 2>/dev/null || echo 0)"
  warnings="$(count_compiler_level "$json" "warning" 2>/dev/null || echo 0)"

  echo "Errors: $errors"
  echo "Warnings: $warnings"

  extract_compiler_diags "$json" 1 2>/dev/null | awk '!seen[$0]++' >"$diags" || true
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
  local changed_only=0
  local -a test_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --changed) changed_only=1 ;;
      --all) changed_only=0 ;;
      *) test_args+=("$1") ;;
    esac
    shift
  done

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

  if [[ "$changed_only" == "1" ]]; then
    if collect_changed_package_args; then
      if [[ "$_CHANGED_FORCE_FULL" == "1" ]]; then
        echo "Changed workspace-level Cargo files detected; running full suite."
      elif [[ ${#_CHANGED_PACKAGE_ARGS[@]} -gt 0 ]]; then
        echo "Changed crates:"
        local i
        for ((i = 1; i < ${#_CHANGED_PACKAGE_ARGS[@]}; i += 2)); do
          echo "  ${_CHANGED_PACKAGE_ARGS[$i]}"
        done
        if [[ ${#test_args[@]} -gt 0 ]]; then
          test_args=("${_CHANGED_PACKAGE_ARGS[@]}" "${test_args[@]}")
        else
          test_args=("${_CHANGED_PACKAGE_ARGS[@]}")
        fi
      else
        echo "Result: SKIP"
        echo "No changed crates detected under crates/."
        fmt_elapsed
        return 0
      fi
    else
      echo "Result: SKIP"
      echo "No changed files detected in git diff/untracked files."
      fmt_elapsed
      return 0
    fi
  fi

  local log="$OUTDIR/nextest.log"

  # Resolve short package names (e.g. -p api → -p ai-barometer-api).
  if [[ ${#test_args[@]} -gt 0 ]]; then
    resolve_package_args "${test_args[@]}"
  else
    resolve_package_args
  fi
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
  # Scope to affected packages when CHANGED_FILES is set and no explicit -p flag.
  if [[ ${#_AFFECTED_PKG_ARGS[@]} -gt 0 && "$*" != *"-p"* ]]; then
    nextest_args+=("${_AFFECTED_PKG_ARGS[@]}")
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

    local failed_tests
    failed_tests="$(extract_failing_tests "$log")"
    if [[ -n "$failed_tests" ]]; then
      echo
      echo "Failing tests:"
      echo "$failed_tests" | while read -r test_name; do
        [[ -n "$test_name" ]] && echo "  $test_name"
      done
      echo
      echo "Re-run failing tests with:"
      echo "$failed_tests" | while read -r test_name; do
        [[ -n "$test_name" ]] && echo "  /cargo-agent test $test_name"
      done
    fi
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
  cargo-agent [--fail-fast] test [--changed|--all] [NEXTEST_ARGS]

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
  CHANGED_FILES="f1 f2"   # scope check/clippy/test to affected packages

Examples:
  cargo-agent                          # full suite
  cargo-agent --fail-fast              # full suite, stop on first failure
  cargo-agent sqlx                     # sqlx cache verify only
  cargo-agent test test_login          # tests matching "test_login"
  cargo-agent test --changed           # tests for crates with changed files
  cargo-agent test --changed test_auth # changed-crate tests filtered by "test_auth"
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

  resolve_affected_packages

  case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    fmt)   run_fmt   || overall_ok=0 ;;
    check) run_check || overall_ok=0 ;;
    clippy) run_clippy || overall_ok=0 ;;
    sqlx) run_sqlx_verify || overall_ok=0 ;;
    test)  run_tests "$@" || overall_ok=0 ;;
    all)
      # sqlx runs early: it verifies the cache before compilation steps, and
      # a stale cache causes confusing downstream errors in check/clippy.
      if [[ "$RUN_FMT" == "1" ]] && should_continue; then run_fmt || overall_ok=0; fi
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

  print_overall "$overall_ok"
  [[ "$overall_ok" == "1" ]]
}

main "$@"
