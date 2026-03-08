#!/usr/bin/env bash
set -euo pipefail

# kube-agent: lean Kubernetes manifest validator for coding agents
# deps: kubeconform OR kubeval

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../../lib"
# shellcheck source=../../../lib/x-agent-common.sh
source "${LIB_DIR}/x-agent-common.sh"

# ---- Agent-specific knobs ------------------------------------------------

RUN_VALIDATE="${RUN_VALIDATE:-1}"
KUBE_SCHEMAS_DIR="${KUBE_SCHEMAS_DIR:-}"
KUBE_IGNORE_MISSING_SCHEMAS="${KUBE_IGNORE_MISSING_SCHEMAS:-0}"

# ---- Usage ----------------------------------------------------------------

usage() {
  cat <<'EOF'
kube-agent — lean Kubernetes manifest validator for coding agents.

Usage: kube-agent.sh [options] [command]

Commands:
  validate  Validate Kubernetes manifests against schemas
  all       Run validate (default)
  help      Show this help

Options:
  --fail-fast   Stop after first failing step

Environment:
  RUN_VALIDATE=0|1           Toggle validate step (default: 1)
  KUBE_SCHEMAS_DIR=path      Custom schema location for validator
  KUBE_IGNORE_MISSING_SCHEMAS=0|1  Skip resources with missing schemas (default: 0)
  CHANGED_FILES="a.yaml b.yml"  Scope to only these files
  MAX_LINES=N                Max diagnostic lines per step (default: 40)
  KEEP_DIR=0|1               Keep temp log dir on success (default: 0)
  FAIL_FAST=0|1              Stop after first failure (default: 0)
EOF
}

# ---- Tool detection -------------------------------------------------------

KUBE_VALIDATOR=""

resolve_validator() {
  if command -v kubeconform >/dev/null 2>&1; then
    KUBE_VALIDATOR="kubeconform"
  elif command -v kubeval >/dev/null 2>&1; then
    KUBE_VALIDATOR="kubeval"
  else
    echo "Missing required tool: kubeconform or kubeval" >&2
    echo "Install kubeconform: go install github.com/yannh/kubeconform/cmd/kubeconform@latest" >&2
    echo "Or kubeval: https://www.kubeval.com/installation/" >&2
    exit 2
  fi
  echo "Validator: $KUBE_VALIDATOR"
}

# ---- Manifest discovery ---------------------------------------------------

# Populates MANIFEST_FILES (newline-separated list of K8s manifest paths).
MANIFEST_FILES=""

discover_manifests() {
  # Find all .yml/.yaml files, pruning excluded directories
  local candidates
  candidates="$(find . \
    -name .git -prune -o \
    -name .github -prune -o \
    -name node_modules -prune -o \
    -name charts -prune -o \
    \( -name '*.yml' -o -name '*.yaml' \) -print 2>/dev/null | sort)" || true

  if [[ -z "$candidates" ]]; then
    return 0
  fi

  # Apply CHANGED_FILES scoping if set
  if [[ -n "${CHANGED_FILES:-}" ]]; then
    local scoped="" f candidate
    for candidate in $candidates; do
      # Normalize ./path to match CHANGED_FILES entries
      local norm="${candidate#./}"
      for f in $CHANGED_FILES; do
        f="${f#./}"
        if [[ "$norm" == "$f" ]]; then
          if [[ -z "$scoped" ]]; then
            scoped="$candidate"
          else
            scoped="${scoped}
${candidate}"
          fi
          break
        fi
      done
    done
    candidates="$scoped"
    if [[ -z "$candidates" ]]; then
      echo "CHANGED_FILES set but no matching YAML files found"
      return 0
    fi
  fi

  # Filter to Kubernetes manifests: files containing both apiVersion: and kind:
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ -f "$file" ]] || continue
    if grep -q 'apiVersion:' "$file" 2>/dev/null && grep -q 'kind:' "$file" 2>/dev/null; then
      if [[ -z "$MANIFEST_FILES" ]]; then
        MANIFEST_FILES="$file"
      else
        MANIFEST_FILES="${MANIFEST_FILES}
${file}"
      fi
    fi
  done <<< "$candidates"
}

# ---- Steps ----------------------------------------------------------------

run_validate() {
  step "validate"

  if [[ -z "$MANIFEST_FILES" ]]; then
    echo
    echo "Result: SKIP (no Kubernetes manifests found)"
    fmt_elapsed
    return 0
  fi

  local count
  count="$(printf '%s\n' "$MANIFEST_FILES" | wc -l | tr -d ' ')"
  echo "Found ${count} Kubernetes manifest(s)"

  local log="${OUTDIR}/validate.log"
  local ok=1

  # Build file list as array
  local files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done <<< "$MANIFEST_FILES"

  if [[ "$KUBE_VALIDATOR" == "kubeconform" ]]; then
    local args=(-summary -output json)
    if [[ -n "$KUBE_SCHEMAS_DIR" ]]; then
      args+=(-schema-location "$KUBE_SCHEMAS_DIR")
    fi
    if [[ "$KUBE_IGNORE_MISSING_SCHEMAS" == "1" ]]; then
      args+=(-ignore-missing-schemas)
    fi
    if ! kubeconform "${args[@]}" "${files[@]}" >"$log" 2>&1; then
      ok=0
    fi
    # Parse JSON summary for resource counts
    parse_kubeconform_summary "$log"
  else
    local args=(--strict)
    if [[ -n "$KUBE_SCHEMAS_DIR" ]]; then
      args+=(--schema-location "$KUBE_SCHEMAS_DIR")
    fi
    if [[ "$KUBE_IGNORE_MISSING_SCHEMAS" == "1" ]]; then
      args+=(--ignore-missing-schemas)
    fi
    if ! kubeval "${args[@]}" "${files[@]}" >"$log" 2>&1; then
      ok=0
    fi
    # Parse kubeval output for resource counts
    parse_kubeval_output "$log"
  fi

  if [[ "$ok" == "0" ]]; then
    echo
    echo "Output (first ${MAX_LINES} lines):"
    head -n "$MAX_LINES" "$log"
  fi

  print_result "$ok" "${OUTDIR}/validate.log" \
    "resolve schema validation errors above, then re-run: /kube-agent validate"

  return $(( 1 - ok ))
}

parse_kubeconform_summary() {
  local log="$1"
  # kubeconform -output json -summary produces pretty-printed JSON with
  # a "summary" object containing "valid", "invalid", "errors", "skipped".
  # Extract counts with grep+sed — no jq dependency needed.
  local valid=0 invalid=0 errors=0
  if [[ -f "$log" ]]; then
    local val
    val="$(grep '"valid"' "$log" | tail -1 | sed 's/[^0-9]//g')" || true
    [[ -n "$val" ]] && valid="$val"
    val="$(grep '"invalid"' "$log" | tail -1 | sed 's/[^0-9]//g')" || true
    [[ -n "$val" ]] && invalid="$val"
    val="$(grep '"errors"' "$log" | tail -1 | sed 's/[^0-9]//g')" || true
    [[ -n "$val" ]] && errors="$val"
    echo "Resources: ${valid} valid, ${invalid} invalid, ${errors} errors"
  fi
}

parse_kubeval_output() {
  local log="$1"
  if [[ ! -f "$log" ]]; then
    return 0
  fi
  # kubeval outputs lines like:
  #   PASS - file.yaml contains a valid Deployment (apps/v1)
  #   ERR  - file.yaml contains an invalid Deployment (apps/v1) - ...
  #   WARN - ...
  local valid=0 invalid=0 errors=0
  local line
  while IFS= read -r line; do
    case "$line" in
      PASS\ -*)  valid=$((valid + 1)) ;;
      ERR\ -*)   invalid=$((invalid + 1)) ;;
      WARN\ -*)  errors=$((errors + 1)) ;;
    esac
  done < "$log"
  echo "Resources: ${valid} valid, ${invalid} invalid, ${errors} warnings"
}

# ---- Main -----------------------------------------------------------------

main() {
  # Parse help before dependency checks so --help works without validators
  case "${1:-}" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  resolve_validator

  setup_outdir "kube-agent"

  # Parse flags
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --fail-fast)
        # shellcheck disable=SC2034
        FAIL_FAST=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  local cmd="${1:-all}"
  shift 2>/dev/null || true
  local overall_ok=1

  discover_manifests

  case "$cmd" in
    validate) run_validate || overall_ok=0 ;;
    all)
      if [[ "$RUN_VALIDATE" == "1" ]] && should_continue; then run_validate || overall_ok=0; fi
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
