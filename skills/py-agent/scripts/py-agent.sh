#!/usr/bin/env bash
set -euo pipefail

# py-agent: lean Python workflow output for coding agents
# deps: bash, mktemp
# optional: ruff, black, mypy, pyright, pytest

KEEP_DIR="${KEEP_DIR:-0}"         # set to 1 to keep temp dir even on success
# In CI, show full output; locally, limit to 40 lines to keep things tidy.
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  MAX_LINES="${MAX_LINES:-999999}"
else
  MAX_LINES="${MAX_LINES:-40}"
fi
RUN_FORMAT="${RUN_FORMAT:-1}"     # set to 0 to skip format
RUN_LINT="${RUN_LINT:-1}"         # set to 0 to skip lint
RUN_TYPECHECK="${RUN_TYPECHECK:-1}" # set to 0 to skip typecheck
RUN_TESTS="${RUN_TESTS:-1}"       # set to 0 to skip tests
FAIL_FAST="${FAIL_FAST:-0}"      # set to 1 or use --fail-fast to stop after first failure

TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"
OUTDIR="$(mktemp -d "${TMPDIR_ROOT%/}/py-agent.XXXXXX")"

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

# Detect Python runner (uv, poetry, or plain python/pip).
detect_runner() {
  if [[ -f "uv.lock" ]] && command -v uv >/dev/null 2>&1; then echo "uv"
  elif [[ -f "poetry.lock" ]] && command -v poetry >/dev/null 2>&1; then echo "poetry"
  else echo "plain"
  fi
}

# Resolve python binary (prefer python3, fall back to python).
detect_python() {
  if command -v python3 >/dev/null 2>&1; then echo "python3"
  elif command -v python >/dev/null 2>&1; then echo "python"
  else echo "python3"  # let it fail with a clear error
  fi
}

RUNNER="$(detect_runner)"
PYTHON="$(detect_python)"
echo "Runner: $RUNNER"

# Run a command through the detected runner, or plain.
# Replaces bare "python" with the detected python binary.
run_cmd() {
  local cmd="$1"
  shift
  if [[ "$cmd" == "python" ]]; then
    cmd="$PYTHON"
  fi
  case "$RUNNER" in
    uv)     uv run "$cmd" "$@" ;;
    poetry) poetry run "$cmd" "$@" ;;
    *)      "$cmd" "$@" ;;
  esac
}

# Check if a tool is available (directly or via runner).
have_tool() {
  local tool="$1"
  case "$RUNNER" in
    uv)     uv run "$tool" --version >/dev/null 2>&1 ;;
    poetry) poetry run "$tool" --version >/dev/null 2>&1 ;;
    *)      command -v "$tool" >/dev/null 2>&1 ;;
  esac
}

run_format() {
  step "format"
  local log="$OUTDIR/format.log"
  local ok=1
  local found=0
  local mode="fix"
  if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
    mode="check"
  fi

  echo "Mode: $mode"

  # Try ruff format first, then black
  if have_tool ruff; then
    found=1
    echo "Using: ruff format"
    local -a args=(ruff format)
    if [[ "$mode" == "check" ]]; then
      args+=(--check --diff)
    fi
    if run_cmd "${args[@]}" >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  elif have_tool black; then
    found=1
    echo "Using: black"
    local -a args=(black .)
    if [[ "$mode" == "check" ]]; then
      args=(black --check --diff .)
    fi
    if run_cmd "${args[@]}" >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no formatter found — install ruff or black)"
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
  if [[ "$ok" == "0" ]]; then
    if [[ "$mode" == "check" ]]; then
      echo "Fix: run /py-agent format (auto-fixes locally), then re-check"
    else
      echo "Fix: resolve the formatting issues, then re-run: /py-agent format"
    fi
  fi
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_lint() {
  step "lint"
  local log="$OUTDIR/lint.log"
  local ok=1
  local found=0

  # Try ruff check first, then flake8
  if have_tool ruff; then
    found=1
    echo "Using: ruff check"
    if run_cmd ruff check >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  elif have_tool flake8; then
    found=1
    echo "Using: flake8"
    if run_cmd flake8 >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no linter found — install ruff or flake8)"
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
  if [[ "$ok" == "0" ]]; then
    if have_tool ruff; then
      echo "Fix: try 'ruff check --fix' for auto-fixable issues, then re-run: /py-agent lint"
    else
      echo "Fix: resolve the lint errors above, then re-run: /py-agent lint"
    fi
  fi
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_typecheck() {
  step "typecheck"
  local log="$OUTDIR/typecheck.log"
  local ok=1
  local found=0

  # Try mypy first, then pyright
  if have_tool mypy; then
    found=1
    echo "Using: mypy"
    if run_cmd mypy . >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  elif have_tool pyright; then
    found=1
    echo "Using: pyright"
    if run_cmd pyright >"$log" 2>&1; then
      :
    else
      ok=0
    fi
  fi

  if [[ "$found" == "0" ]]; then
    echo "Result: SKIP (no type checker found — install mypy or pyright)"
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
  [[ "$ok" == "0" ]] && echo "Fix: resolve the type errors above, then re-run: /py-agent typecheck"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

run_tests() {
  step "test"
  local log="$OUTDIR/test.log"
  local ok=1
  local found=0

  local -a test_args=()
  [[ "$FAIL_FAST" == "1" ]] && test_args+=(-x)

  # Pass through extra args (e.g. test file paths, -k filters).
  # Bash 3.2 + `set -u` treats "${arr[@]}" on an empty array as unbound.
  if [[ $# -gt 0 ]]; then
    test_args+=("$@")
  fi

  if have_tool pytest; then
    found=1
    echo "Using: pytest"
    if [[ ${#test_args[@]} -gt 0 ]]; then
      run_cmd pytest "${test_args[@]}" >"$log" 2>&1 || ok=0
    else
      run_cmd pytest >"$log" 2>&1 || ok=0
    fi
  else
    # Fallback: python -m unittest
    found=1
    echo "Using: python -m unittest"
    local rc=0
    if [[ ${#test_args[@]} -gt 0 ]]; then
      run_cmd python -m unittest discover "${test_args[@]}" >"$log" 2>&1 || rc=$?
    else
      run_cmd python -m unittest discover >"$log" 2>&1 || rc=$?
    fi
    if [[ "$rc" != "0" ]]; then
      # If discover fails with no tests, treat as skip
      if grep -q "Ran 0 tests" "$log" 2>/dev/null; then
        echo "Result: SKIP (no tests found)"
        fmt_elapsed
        return 0
      fi
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
  [[ "$ok" == "0" ]] && echo "Fix: resolve the failing tests, then re-run: /py-agent test"
  echo "Full log: $log"
  fmt_elapsed
  [[ "$ok" == "1" ]]
}

usage() {
  cat <<'EOF'
py-agent: lean Python workflow output for coding agents

Usage:
  py-agent [--fail-fast]              # runs format, lint, typecheck, test
  py-agent [--fail-fast] format|lint|typecheck|test|all
  py-agent [--fail-fast] test [PYTEST_ARGS]

Flags:
  --fail-fast            stop after first failing step; also passes -x to pytest

Env knobs:
  MAX_LINES=40           # printed lines per step (unlimited in CI)
  KEEP_DIR=0|1           # keep temp log dir even on success
  FAIL_FAST=0|1          # same as --fail-fast flag
  RUN_FORMAT=0|1
  RUN_LINT=0|1
  RUN_TYPECHECK=0|1
  RUN_TESTS=0|1

Auto-detection:
  - Runner: detects uv, poetry, or plain python from lock files
  - Format: tries ruff format, then black
  - Lint: tries ruff check, then flake8
  - Typecheck: tries mypy, then pyright
  - Tests: tries pytest, then python -m unittest discover
  - CI mode: format runs --check in CI, auto-fixes locally

Examples:
  py-agent                             # full suite
  py-agent --fail-fast                 # full suite, stop on first failure
  py-agent lint                        # lint only
  py-agent test                        # tests only
  py-agent test -k test_login          # tests matching "test_login"
  py-agent test tests/unit/            # tests in a specific directory
  RUN_TESTS=0 py-agent                 # skip tests
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

  # Verify we're in a Python project
  if [[ ! -f "pyproject.toml" && ! -f "setup.py" && ! -f "setup.cfg" && ! -f "requirements.txt" ]]; then
    echo "Error: no Python project found (expected pyproject.toml, setup.py, setup.cfg, or requirements.txt)" >&2
    exit 2
  fi

  case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    format)    run_format    || overall_ok=0 ;;
    lint)      run_lint      || overall_ok=0 ;;
    typecheck) run_typecheck || overall_ok=0 ;;
    test)      run_tests "$@" || overall_ok=0 ;;
    all)
      if [[ "$RUN_FORMAT" == "1" ]]; then run_format || overall_ok=0; fi
      if [[ "$RUN_LINT" == "1" ]] && should_continue; then run_lint || overall_ok=0; fi
      if [[ "$RUN_TYPECHECK" == "1" ]] && should_continue; then run_typecheck || overall_ok=0; fi
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
