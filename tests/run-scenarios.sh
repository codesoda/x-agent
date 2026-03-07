#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${ROOT_DIR}/tests"
LOG_DIR="${TESTS_DIR}/.logs"

usage() {
  cat <<'EOF'
Run x-agent scenario fixtures.

Usage:
  tests/run-scenarios.sh [FILTER]
  tests/run-scenarios.sh --list
  tests/run-scenarios.sh --help

Examples:
  tests/run-scenarios.sh
  tests/run-scenarios.sh cargo-agent
  tests/run-scenarios.sh npm-agent/issues
EOF
}

print_status() {
  local status="$1"
  local message="$2"
  printf "%-6s %s\n" "$status" "$message"
}

scenario_label_from_file() {
  local scenario_file="$1"
  echo "${scenario_file#${ROOT_DIR}/tests/}" | sed 's|/scenario.env$||'
}

list_scenarios() {
  find "$TESTS_DIR" -type f -name scenario.env | sort
}

missing_required_tool() {
  local tools="$1"
  local tool
  for tool in $tools; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "$tool"
      return 0
    fi
  done
  return 1
}

run_one() {
  local scenario_file="$1"
  local scenario_dir
  scenario_dir="$(dirname "$scenario_file")"

  local SCENARIO_NAME=""
  local AGENT_SCRIPT=""
  local RUN_ARGS="all"
  local EXPECT_EXIT="0"
  local REQUIRED_TOOLS=""

  # shellcheck source=/dev/null
  source "$scenario_file"

  local label
  if [[ -n "${SCENARIO_NAME}" ]]; then
    label="$SCENARIO_NAME"
  else
    label="$(scenario_label_from_file "$scenario_file")"
  fi

  if [[ -z "${AGENT_SCRIPT}" ]]; then
    print_status "FAIL" "${label} (AGENT_SCRIPT not set)"
    return 1
  fi

  local script_path="${ROOT_DIR}/${AGENT_SCRIPT}"
  if [[ ! -x "$script_path" ]]; then
    print_status "SKIP" "${label} (missing script: ${AGENT_SCRIPT})"
    return 0
  fi

  local missing_tool=""
  if missing_tool="$(missing_required_tool "${REQUIRED_TOOLS}")"; then
    print_status "SKIP" "${label} (missing tool: ${missing_tool})"
    return 0
  fi

  mkdir -p "$LOG_DIR"
  local safe_name
  safe_name="$(echo "$label" | tr '/ ' '__' | tr -cd '[:alnum:]_.-')"
  local log_file="${LOG_DIR}/${safe_name}.log"

  local -a args=()
  if [[ -n "${RUN_ARGS}" ]]; then
    # shellcheck disable=SC2206
    args=($RUN_ARGS)
  fi

  local exit_code
  pushd "$scenario_dir" >/dev/null
  set +e
  "$script_path" "${args[@]}" >"$log_file" 2>&1
  exit_code=$?
  set -e
  popd >/dev/null

  if [[ "$exit_code" == "$EXPECT_EXIT" ]]; then
    print_status "PASS" "$label"
    return 0
  fi

  print_status "FAIL" "${label} (expected ${EXPECT_EXIT}, got ${exit_code})"
  echo "  Log: $log_file"
  echo "  Output (first 40 lines):"
  sed -n '1,40p' "$log_file" | sed 's/^/    /'
  return 1
}

run_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    print_status "SKIP" "shellcheck (not installed)"
    return 0
  fi

  local scripts=()
  while IFS= read -r -d '' f; do
    scripts+=("$f")
  done < <(find "$ROOT_DIR/skills" -name '*.sh' -print0; find "$ROOT_DIR" -maxdepth 1 -name '*.sh' -print0; printf '%s\0' "$ROOT_DIR/tests/run-scenarios.sh")

  if shellcheck --severity=warning "${scripts[@]}" >/dev/null 2>&1; then
    print_status "PASS" "shellcheck"
    return 0
  fi

  print_status "FAIL" "shellcheck"
  shellcheck --severity=warning "${scripts[@]}" | sed 's/^/    /'
  return 1
}

main() {
  local mode="${1:-run}"
  local filter=""

  case "$mode" in
    -h|--help|help)
      usage
      exit 0
      ;;
    --list)
      while IFS= read -r scenario_file; do
        scenario_label_from_file "$scenario_file"
      done < <(list_scenarios)
      exit 0
      ;;
    *)
      if [[ "$#" -gt 0 ]]; then
        filter="$1"
      fi
      ;;
  esac

  local total=0
  local failed=0

  # Run shellcheck if no filter or filter matches "shellcheck"
  if [[ -z "$filter" || "shellcheck" == *"$filter"* ]]; then
    total=$((total + 1))
    if ! run_shellcheck; then
      failed=$((failed + 1))
    fi
  fi

  while IFS= read -r scenario_file; do
    if [[ -n "$filter" && "$scenario_file" != *"$filter"* ]]; then
      continue
    fi

    total=$((total + 1))
    if ! run_one "$scenario_file"; then
      failed=$((failed + 1))
    fi
  done < <(list_scenarios)

  echo "------"
  echo "Scenarios run: $total"
  echo "Failures: $failed"
  [[ "$failed" -eq 0 ]]
}

main "$@"

