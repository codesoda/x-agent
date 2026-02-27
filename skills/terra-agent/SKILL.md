---
name: terra-agent
description: |
  Run terra-agent.sh — a lean Terraform workflow runner that reports formatting/validation status
  and can also auto-fix Terraform formatting.
  Use when: running Terraform fmt checks, auto-fixing fmt, safe init, safe plan, validate, or optional tflint checks.
  Triggers on: terra agent, terraform fmt check, terraform fmt fix, terraform init, terraform plan, terraform validate, run terraform checks.
context: fork
allowed-tools:
  - Bash(scripts/terra-agent.sh*)
  - Bash(RUN_*=* scripts/terra-agent.sh*)
  - Bash(MAX_LINES=* scripts/terra-agent.sh*)
  - Bash(KEEP_DIR=* scripts/terra-agent.sh*)
  - Bash(FMT_MODE=* scripts/terra-agent.sh*)
  - Bash(TERRAFORM_CHDIR=* scripts/terra-agent.sh*)
  - Bash(TF_CHDIR=* scripts/terra-agent.sh*)
---

# Terra Agent

Run the `terra-agent.sh` script for lean, structured Terraform workflow output designed for coding agents.

## Script Location

```bash
scripts/terra-agent.sh
```

## Usage

### Run Full Suite (fmt + init + validate + lint)
```bash
scripts/terra-agent.sh
```

### Run Individual Steps
```bash
scripts/terra-agent.sh fmt         # fmt in FMT_MODE (default: check)
scripts/terra-agent.sh fmt-check   # report files needing formatting
scripts/terra-agent.sh fmt-fix     # auto-fix formatting
scripts/terra-agent.sh init        # safe non-mutating init
scripts/terra-agent.sh plan-safe   # safe non-mutating plan
scripts/terra-agent.sh validate    # terraform validate
scripts/terra-agent.sh lint        # tflint (if installed)
scripts/terra-agent.sh all         # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_FMT` | `1` | Set to `0` to skip fmt |
| `RUN_INIT` | `1` | Set to `0` to skip init |
| `RUN_VALIDATE` | `1` | Set to `0` to skip validate |
| `RUN_LINT` | `1` | Set to `0` to skip lint |
| `RUN_PLAN_SAFE` | `0` | Set to `1` to include `plan-safe` in `all` |
| `FMT_MODE` | `check` | `check` (report-only) or `fix` (rewrite files) |
| `FMT_RECURSIVE` | `1` | Set to `0` to disable recursive fmt |
| `TFLINT_RECURSIVE` | `1` | Set to `0` to disable recursive tflint |
| `TERRAFORM_CHDIR` | `.` | Terraform root directory to run in |
| `TF_CHDIR` | `.` | Alias for `TERRAFORM_CHDIR` |
| `MAX_LINES` | `40` | Max diagnostic lines printed per step |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Output Format

- Each step prints a header (`Step: fmt`, `Step: validate`, etc.)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- Run from the Terraform root, or set `TERRAFORM_CHDIR=infra` (for example)
- `fmt-check` is non-mutating and fails when formatting drift exists
- `fmt-fix` rewrites files to canonical Terraform formatting
- `init` runs in safe mode: `-backend=false`, `-input=false`, `-get=false`, `-upgrade=false`, `-lockfile=readonly`
- `init` uses a temp `TF_DATA_DIR`, so it does not create `.terraform/` in the project directory
- `plan-safe` runs with `-refresh=false`, `-lock=false`, `-input=false`, and `-detailed-exitcode`
- `plan-safe` treats exit code `2` (changes present) as `PASS`; only errors fail the step
- `lint` is skipped gracefully when `tflint` is not installed
