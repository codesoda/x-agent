#!/usr/bin/env bash
set -euo pipefail

# Wrapper that hides kubeconform from PATH so kube-agent falls back to kubeval.
# Used by kubeval-* test fixtures to exercise the fallback branch (FR-6).
#
# Instead of removing entire PATH directories (which drops co-located tools
# like kubeval), this creates shadow directories with symlinks to everything
# EXCEPT kubeconform.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_SCRIPT="${SCRIPT_DIR}/../../skills/kube-agent/scripts/kube-agent.sh"

SHADOW_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$SHADOW_ROOT"; }
trap cleanup EXIT

NEW_PATH=""
IFS=':'
for dir in $PATH; do
  if [[ -x "${dir}/kubeconform" ]]; then
    # Create a shadow directory with symlinks to all binaries except kubeconform
    safe_name="$(echo "$dir" | tr '/' '_')"
    shadow="${SHADOW_ROOT}/${safe_name}"
    mkdir -p "$shadow"
    for bin in "$dir"/*; do
      [[ -e "$bin" ]] || continue
      bn="$(basename "$bin")"
      [[ "$bn" == "kubeconform" ]] && continue
      ln -sf "$bin" "$shadow/$bn" 2>/dev/null || true
    done
    dir="$shadow"
  fi
  if [[ -z "$NEW_PATH" ]]; then
    NEW_PATH="$dir"
  else
    NEW_PATH="${NEW_PATH}:${dir}"
  fi
done
unset IFS

export PATH="$NEW_PATH"

exec "$AGENT_SCRIPT" "$@"
