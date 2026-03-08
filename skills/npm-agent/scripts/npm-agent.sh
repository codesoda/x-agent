#!/usr/bin/env bash
set -euo pipefail

# npm-agent: lean Node.js workflow output for coding agents
# deps: bash, mktemp
# optional: biome, eslint, prettier

KEEP_DIR="${KEEP_DIR:-0}"         # set to 1 to keep temp dir even on success
# In CI, show full output; locally, limit to 40 lines to keep things tidy.
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  MAX_LINES="${MAX_LINES:-999999}"
else
  MAX_LINES="${MAX_LINES:-40}"
fi
RUN_LINT="${RUN_LINT:-1}"         # set to 0 to skip lint
RUN_TYPECHECK="${RUN_TYPECHECK:-1}" # set to 0 to skip typecheck
RUN_FORMAT="${RUN_FORMAT:-1}"     # set to 0 to skip format
RUN_TESTS="${RUN_TESTS:-1}"       # set to 0 to skip tests
RUN_BUILD="${RUN_BUILD:-1}"       # set to 0 to skip build
FAIL_FAST="${FAIL_FAST:-0}"      # set to 1 or use --fail-fast to stop after first failure
CHANGED_FILES="${CHANGED_FILES:-}"  # space-separated list of changed files; scopes lint/format

TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"
OUTDIR="$(mktemp -d "${TMPDIR_ROOT%/}/npm-agent.XXXXXX")"

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

# Detect which package manager is in use.
detect_pm() {
  if [[ -f "bun.lock" || -f "bun.lockb" ]]; then echo "bun"
  elif [[ -f "pnpm-lock.yaml" ]]; then echo "pnpm"
  elif [[ -f "yarn.lock" ]]; then echo "yarn"
  else echo "npm"
  fi
}

PM="$(detect_pm)"
echo "Package manager: $PM"

# Filter CHANGED_FILES to JS/TS source files for scoping lint/format.
_CHANGED_SRC_FILES=()
if [[ -n "$CHANGED_FILES" ]]; then
  for f in $CHANGED_FILES; do
    case "$f" in
      *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.mts|*.cts|*.json|*.css|*.scss|*.less|*.html|*.vue|*.svelte)
        [[ -f "$f" ]] && _CHANGED_SRC_FILES+=("$f")
        ;;
    esac
  done
  if [[ ${#_CHANGED_SRC_FILES[@]} -gt 0 ]]; then
    echo "Scoped to ${#_CHANGED_SRC_FILES[@]} changed file(s)"
  fi
fi

# Run a package.json script if it exists, capturing output.
# Returns 0 if the script ran successfully, 1 if it failed, 2 if script not found.
run_script() {
  local script_name="$1"
  local log="$2"

  # Check if the script exists in package.json
  if ! node -e "
    const pkg = require('./package.json');
    if (!pkg.scripts || !pkg.scripts['$script_name']) process.exit(1);
  " 2>/dev/null; then
    return 2
  fi

  if $PM run "$script_name" >"$log" 2>&1; then
    return 0
  else
    return 1
  fi
}

run_format() {
  step "format"
  local log="$OUTDIR/format.log"
  local ok=1
  local found=0

  # Try package.json scripts first
  for script in format fmt "format:fix" "fmt:fix" "format:check" "fmt:check"; do
    run_script "$script" "$log"
    local rc=$?
    if [[ "$rc" == "0" ]]; then found=1; break; fi
    if [[ "$rc" == "1" ]]; then found=1; ok=0; break; fi
  done

  # Fallback: try common formatters directly
  if [[ "$found" == "0" ]]; then
    # Use changed files when available, otherwise check entire project.
    local -a targets=(.)
    if [[ ${#_CHANGED_SRC_FILES[@]} -gt 0 ]]; then targets=("${_CHANGED_SRC_FILES[@]}"); fi

    if command -v biome >/dev/null 2>&1; then
      echo "Using: biome format"
      if biome format "${targets[@]}" >"$log" 2>&1; then found=1; else found=1; ok=0; fi
    elif npx prettier --version >/dev/null 2>&1; then
      echo "Using: prettier"
      if npx prettier --check "${targets[@]}" >"$log" 2>&1; then found=1; else found=1; ok=0; fi
    fi
  fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no formatter found)"
    fmt_elapsed
    return 0
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the formatting issues, then re-run: /npm-agent format"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_lint() {
  step "lint"
  local log="$OUTDIR/lint.log"
  local ok=1
  local found=0

  # Try package.json scripts first
  for script in lint "lint:fix" "lint:check"; do
    run_script "$script" "$log"
    local rc=$?
    if [[ "$rc" == "0" ]]; then found=1; break; fi
    if [[ "$rc" == "1" ]]; then found=1; ok=0; break; fi
  done

  # Fallback: try common linters directly
  if [[ "$found" == "0" ]]; then
    # Use changed files when available, otherwise check entire project.
    local -a targets=(.)
    if [[ ${#_CHANGED_SRC_FILES[@]} -gt 0 ]]; then targets=("${_CHANGED_SRC_FILES[@]}"); fi

    if command -v biome >/dev/null 2>&1; then
      echo "Using: biome lint"
      if biome lint "${targets[@]}" >"$log" 2>&1; then found=1; else found=1; ok=0; fi
    elif npx eslint --version >/dev/null 2>&1; then
      echo "Using: eslint"
      if npx eslint "${targets[@]}" >"$log" 2>&1; then found=1; else found=1; ok=0; fi
    fi
  fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no linter found)"
    fmt_elapsed
    return 0
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the lint errors above, then re-run: /npm-agent lint"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_typecheck() {
  step "typecheck"
  local log="$OUTDIR/typecheck.log"
  local ok=1
  local found=0

  # Try package.json scripts first
  for script in typecheck "type-check" "types:check" tsc; do
    run_script "$script" "$log"
    local rc=$?
    if [[ "$rc" == "0" ]]; then found=1; break; fi
    if [[ "$rc" == "1" ]]; then found=1; ok=0; break; fi
  done

  # Fallback: try tsc directly if tsconfig exists
  if [[ "$found" == "0" && -f "tsconfig.json" ]]; then
    echo "Using: tsc --noEmit"
    if npx tsc --noEmit >"$log" 2>&1; then found=1; else found=1; ok=0; fi
  fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no TypeScript config found)"
    fmt_elapsed
    return 0
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the type errors above, then re-run: /npm-agent typecheck"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_tests() {
  step "test"
  local log="$OUTDIR/test.log"
  local ok=1
  local found=0

  # Try package.json "test" script
  run_script "test" "$log"
  local rc=$?
  if [[ "$rc" == "0" ]]; then found=1; fi
  if [[ "$rc" == "1" ]]; then found=1; ok=0; fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no test script found)"
    fmt_elapsed
    return 0
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the failing tests, then re-run: /npm-agent test"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_build() {
  step "build"
  local log="$OUTDIR/build.log"
  local ok=1
  local found=0

  run_script "build" "$log"
  local rc=$?
  if [[ "$rc" == "0" ]]; then found=1; fi
  if [[ "$rc" == "1" ]]; then found=1; ok=0; fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no build script found)"
    fmt_elapsed
    return 0
  fi

  if [[ "$ok" == "0" && -s "$log" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  echo
  echo "Result: $([[ "$ok" == "1" ]] && echo PASS || echo FAIL)"
  [[ "$ok" == "0" ]] && echo "Fix: resolve the build errors above, then re-run: /npm-agent build"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

usage() {
  cat <<'EOF'
npm-agent: lean Node.js workflow output for coding agents

Usage:
  npm-agent [--fail-fast]              # runs format, lint, typecheck, test, build
  npm-agent [--fail-fast] format|lint|typecheck|test|build|all

Flags:
  --fail-fast            stop after first failing step

Env knobs:
  MAX_LINES=40           # printed lines per step (unlimited in CI)
  KEEP_DIR=0|1           # keep temp log dir even on success
  FAIL_FAST=0|1          # same as --fail-fast flag
  RUN_FORMAT=0|1
  RUN_LINT=0|1
  RUN_TYPECHECK=0|1
  RUN_TESTS=0|1
  RUN_BUILD=0|1
  CHANGED_FILES="f1 f2"   # scope lint/format to changed files (fallback tools only)

Auto-detection:
  - Package manager: detects bun, pnpm, yarn, or npm from lock files
  - Format: tries package.json scripts (format, fmt), then biome, then prettier
  - Lint: tries package.json scripts (lint), then biome, then eslint
  - Typecheck: tries package.json scripts (typecheck, tsc), then tsc --noEmit
  - Tests: runs package.json "test" script
  - Build: runs package.json "build" script

Examples:
  npm-agent                            # full suite
  npm-agent --fail-fast                # full suite, stop on first failure
  npm-agent lint                       # lint only
  npm-agent test                       # tests only
  RUN_BUILD=0 npm-agent                # skip build
  RUN_TESTS=0 RUN_BUILD=0 npm-agent    # lint + typecheck only
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

  # Verify we're in a Node.js project
  if [[ ! -f "package.json" ]]; then
    echo "Error: no package.json found in current directory" >&2
    exit 2
  fi

  case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    format)    run_format    || overall_ok=0 ;;
    lint)      run_lint      || overall_ok=0 ;;
    typecheck) run_typecheck || overall_ok=0 ;;
    test)      run_tests     || overall_ok=0 ;;
    build)     run_build     || overall_ok=0 ;;
    all)
      if [[ "$RUN_FORMAT" == "1" ]] && should_continue; then run_format || overall_ok=0; fi
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
      if [[ "$RUN_TYPECHECK" == "1" ]] && should_continue; then run_typecheck || overall_ok=0; fi
      if [[ "$RUN_TESTS" == "1" ]] && should_continue; then run_tests || overall_ok=0; fi
      if [[ "$RUN_BUILD" == "1" ]] && should_continue; then run_build || overall_ok=0; fi
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
