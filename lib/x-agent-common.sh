#!/usr/bin/env bash
# x-agent-common.sh — shared boilerplate for x-agent workflow runners.
# Source this file from agent scripts; it produces no output or side effects.
# Bash 3.2 compatible.

# ---------------------------------------------------------------------------
# Environment defaults (agent can override after sourcing)
# ---------------------------------------------------------------------------

KEEP_DIR="${KEEP_DIR:-0}"
FAIL_FAST="${FAIL_FAST:-0}"
CHANGED_FILES="${CHANGED_FILES:-}"
TMPDIR_ROOT="${TMPDIR_ROOT:-/tmp}"

# CI-aware MAX_LINES: unlimited in CI, concise locally.
if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
  MAX_LINES="${MAX_LINES:-999999}"
else
  MAX_LINES="${MAX_LINES:-40}"
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Flow control
# ---------------------------------------------------------------------------

# Returns 0 (continue) unless fail-fast is on and a step already failed.
# Caller must declare `overall_ok` before use.
should_continue() { [[ "$FAIL_FAST" != "1" || "$overall_ok" == "1" ]]; }

# ---------------------------------------------------------------------------
# Dependency checking
# ---------------------------------------------------------------------------

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 2; }
}

# ---------------------------------------------------------------------------
# Setup helpers (called explicitly by agents, not auto-executed)
# ---------------------------------------------------------------------------

# Create a temp output directory and install a cleanup trap.
# Usage: setup_outdir <agent-name>
# Sets: OUTDIR
setup_outdir() {
  local agent_name="$1"
  OUTDIR="$(mktemp -d "${TMPDIR_ROOT%/}/${agent_name}.XXXXXX")"

  # Define the cleanup function inside setup_outdir so it captures OUTDIR.
  _xagent_cleanup() {
    local code="$?"
    if [[ "${KEEP_DIR:-0}" == "1" || "$code" != "0" ]]; then
      echo "Logs kept in: $OUTDIR"
    else
      rm -rf "$OUTDIR"
    fi
    exit "$code"
  }

  trap _xagent_cleanup EXIT
}

# Acquire a workflow lock to prevent concurrent agent runs.
# Usage: setup_lock <agent-name>
setup_lock() {
  local agent_name="$1"
  local lockfile="${TMPDIR_ROOT%/}/${agent_name}.lock"

  # Open fd 9 for locking.
  exec 9>"$lockfile"

  if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
      echo "${agent_name}: waiting for another run to finish..."
      flock 9
    fi
  elif command -v perl >/dev/null 2>&1; then
    # macOS: flock not available, use perl as a portable fallback.
    perl -e '
      use Fcntl ":flock";
      open(my $fh, ">&=", 9) or die "fdopen: $!";
      if (!flock($fh, LOCK_EX | LOCK_NB)) {
        print STDERR "'"${agent_name}"': waiting for another run to finish...\n";
        flock($fh, LOCK_EX) or die "flock: $!";
      }
    '
  else
    echo "Warning: neither flock nor perl available; skipping workflow lock" >&2
  fi
}

# ---------------------------------------------------------------------------
# Result formatting
# ---------------------------------------------------------------------------

# Print a step result with optional fix hint.
# Usage: print_result <ok> <log_path> [fix_hint]
#   ok: "1" for pass, "0" for fail
#   log_path: path to the full log file
#   fix_hint: text shown only on failure (optional but expected on FAIL)
print_result() {
  local ok="$1"
  local log_path="$2"
  local fix_hint="${3:-}"

  echo
  if [[ "$ok" == "1" ]]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
    if [[ -n "$fix_hint" ]]; then
      echo "Fix: $fix_hint"
    fi
  fi
  echo "Full log: $log_path"
  fmt_elapsed
}

# Print the final overall summary.
# Usage: print_overall <overall_ok>
#   overall_ok: "1" for pass, "0" for fail
# The caller should exit with the appropriate code after calling this.
print_overall() {
  local overall_ok="$1"
  hr
  if [[ "$overall_ok" == "1" ]]; then
    echo "Overall: PASS"
  else
    echo "Overall: FAIL"
  fi
  echo "Logs: $OUTDIR"
}
