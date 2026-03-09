---
name: kube-agent
description: |
  Run kube-agent.sh — a lean Kubernetes manifest validator that produces agent-friendly output.
  Use when: running Kubernetes manifest validation, kubeconform checks, kubeval checks, verifying K8s manifests before applying,
  or when the user asks to validate Kubernetes YAML, run k8s checks, or check manifests.
  Triggers on: kube agent, kubernetes validate, kubeconform, kubeval, k8s checks, validate manifests.
context: fork
allowed-tools:
  - Bash(scripts/kube-agent.sh*)
  - Bash(RUN_*=* scripts/kube-agent.sh*)
  - Bash(KUBE_SCHEMAS_DIR=* scripts/kube-agent.sh*)
  - Bash(KUBE_IGNORE_MISSING_SCHEMAS=* scripts/kube-agent.sh*)
  - Bash(MAX_LINES=* scripts/kube-agent.sh*)
  - Bash(KEEP_DIR=* scripts/kube-agent.sh*)
  - Bash(FAIL_FAST=* scripts/kube-agent.sh*)
  - Bash(CHANGED_FILES=* scripts/kube-agent.sh*)
  - Bash(TMPDIR_ROOT=* scripts/kube-agent.sh*)
---

# Kube Agent

Run the `kube-agent.sh` script for lean, structured Kubernetes manifest validation output designed for coding agents.

## Script Location

```
scripts/kube-agent.sh
```

## Usage

### Run Full Suite (validate)
```bash
scripts/kube-agent.sh
```

### Run Individual Steps
```bash
scripts/kube-agent.sh validate  # validate manifests only
scripts/kube-agent.sh all       # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_VALIDATE` | `1` | Set to `0` to skip validate step |
| `KUBE_SCHEMAS_DIR` | _(empty)_ | Custom schema location for validator |
| `KUBE_IGNORE_MISSING_SCHEMAS` | `0` | Set to `1` to skip resources with missing schemas (useful for CRDs, offline) |
| `FAIL_FAST` | `0` | Set to `1` to stop after first failure (or use `--fail-fast`) |
| `CHANGED_FILES` | _(empty)_ | Space-separated changed file paths; scopes to matching manifests |
| `MAX_LINES` | `40` | Max output lines printed per step (unlimited in CI) |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: validate`)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- Prefers `kubeconform` over `kubeval`; exits with code 2 if neither is installed
- Discovers `.yml`/`.yaml` files containing both `apiVersion:` and `kind:`
- Excludes `.git/`, `.github/`, `node_modules/`, and `charts/` directories
- `CHANGED_FILES` scopes validation to only the specified files
- Reports SKIP when no Kubernetes manifests are found
- In CI (`CI=true`), `MAX_LINES` defaults to unlimited; locally it defaults to 40
