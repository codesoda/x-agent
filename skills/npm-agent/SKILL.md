---
name: npm-agent
description: |
  Run npm-agent.sh — a lean Node.js workflow runner that produces agent-friendly output.
  Use when: running JS/TS checks (format, lint, typecheck, test, build), verifying Node code before committing,
  or when the user asks to run npm/yarn/pnpm/bun checks, lint, format, or test a Node.js project.
  Triggers on: npm agent, run npm checks, node checks, lint and test, verify node code, run js checks.
context: fork
allowed-tools:
  - Bash(scripts/npm-agent.sh*)
  - Bash(RUN_*=* scripts/npm-agent.sh*)
  - Bash(MAX_LINES=* scripts/npm-agent.sh*)
  - Bash(KEEP_DIR=* scripts/npm-agent.sh*)
---

# NPM Agent

Run the `npm-agent.sh` script for lean, structured Node.js workflow output designed for coding agents.

## Script Location

```
scripts/npm-agent.sh
```

## Usage

### Run Full Suite (format + lint + typecheck + test + build)
```bash
scripts/npm-agent.sh
```

### Run Individual Steps
```bash
scripts/npm-agent.sh format      # format check only
scripts/npm-agent.sh lint         # lint only
scripts/npm-agent.sh typecheck    # typecheck only
scripts/npm-agent.sh test         # tests only
scripts/npm-agent.sh build        # build only
scripts/npm-agent.sh all          # full suite (default)
```

## Environment Knobs

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_FORMAT` | `1` | Set to `0` to skip format |
| `RUN_LINT` | `1` | Set to `0` to skip lint |
| `RUN_TYPECHECK` | `1` | Set to `0` to skip typecheck |
| `RUN_TESTS` | `1` | Set to `0` to skip tests |
| `RUN_BUILD` | `1` | Set to `0` to skip build |
| `MAX_LINES` | `40` | Max output lines printed per step |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

## Auto-Detection

- **Package manager**: detects bun, pnpm, yarn, or npm from lock files
- **Format**: tries package.json scripts (`format`, `fmt`), then biome, then prettier
- **Lint**: tries package.json scripts (`lint`), then biome, then eslint
- **Typecheck**: tries package.json scripts (`typecheck`, `tsc`), then `tsc --noEmit`
- **Tests**: runs package.json `test` script
- **Build**: runs package.json `build` script

## Output Format

- Each step prints a header (`Step: format`, `Step: lint`, etc.)
- Results are `PASS`, `FAIL`, or `SKIP`
- On failure, output is truncated to `MAX_LINES`
- Full logs are saved to a temp directory (path printed in output)
- Overall result is printed at the end: `Overall: PASS` or `Overall: FAIL`

## Important Notes

- The script must be run from within a Node.js project directory (requires `package.json`)
- Steps are skipped gracefully if no matching tool/script is found
- On failure, the temp log directory is preserved automatically for inspection
