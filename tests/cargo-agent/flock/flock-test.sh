#!/usr/bin/env bash
set -euo pipefail

# Test: cargo-agent workflow-level lock prevents concurrent runs.
#
# 1. Hold the lockfile in a background process.
# 2. Launch cargo-agent (help, so it exits quickly after acquiring the lock).
# 3. Verify cargo-agent prints the "waiting" message.
# 4. Release the lock.
# 5. Verify cargo-agent completes successfully.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/skills/cargo-agent/scripts/cargo-agent.sh"
TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/flock-test.XXXXXX")"

cleanup() {
  # Kill any lingering background jobs.
  kill "$HOLDER_PID" 2>/dev/null || true
  wait "$HOLDER_PID" 2>/dev/null || true
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

LOCKFILE="$TMPDIR_TEST/cargo-agent.lock"
HOLDER_PID=""

# --- Step 1: hold the lock in the background ---
hold_lock() {
  exec 9>"$LOCKFILE"
  if command -v flock >/dev/null 2>&1; then
    flock 9
  else
    perl -e '
      use Fcntl ":flock";
      open(my $fh, ">&=", 9) or die "fdopen: $!";
      flock($fh, LOCK_EX) or die "flock: $!";
    '
  fi
  # Keep the subprocess alive (and lock held) until killed.
  sleep 30
}

hold_lock &
HOLDER_PID=$!

# Give the holder time to acquire the lock.
sleep 0.5

# --- Step 2: launch cargo-agent in the background ---
AGENT_OUTPUT="$TMPDIR_TEST/agent-output.txt"
TMPDIR_ROOT="$TMPDIR_TEST" "$SCRIPT" help >"$AGENT_OUTPUT" 2>&1 &
AGENT_PID=$!

# --- Step 3: wait for the "waiting" message (up to 3s) ---
waited=0
found=0
while [[ "$waited" -lt 6 ]]; do
  if grep -q "waiting for another run to finish" "$AGENT_OUTPUT" 2>/dev/null; then
    found=1
    break
  fi
  sleep 0.5
  waited=$((waited + 1))
done

if [[ "$found" != "1" ]]; then
  echo "FAIL: cargo-agent did not print the 'waiting' message within 3s"
  echo "--- output ---"
  cat "$AGENT_OUTPUT"
  echo "--------------"
  exit 1
fi

# --- Step 4: release the lock ---
kill "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true

# --- Step 5: verify cargo-agent completes ---
if wait "$AGENT_PID"; then
  echo "PASS: cargo-agent waited for lock and completed successfully"
  exit 0
else
  echo "FAIL: cargo-agent exited with non-zero status after acquiring lock"
  echo "--- output ---"
  cat "$AGENT_OUTPUT"
  echo "--------------"
  exit 1
fi
