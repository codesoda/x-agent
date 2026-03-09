#!/usr/bin/env bash
set -euo pipefail

# A clean, valid shell script that passes both bash -n and shellcheck.

greet() {
  local name="$1"
  echo "Hello, ${name}!"
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: good.sh <name>" >&2
    return 1
  fi
  greet "$1"
}

main "$@"
