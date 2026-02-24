# x-agent

Agent-friendly workflow runners for common dev toolchains. Designed to be called by AI coding agents (Claude Code, Codex, etc.) — super lightweight output on stdout, full logs in temp files when the model needs them.

## Why?

Standard build tools produce walls of text. Agents waste context window parsing noise. x-agent scripts give:

- **Structured output** — `Step: lint`, `Result: PASS`, `Overall: FAIL`
- **Truncated diagnostics** — only the first N lines of errors/warnings (configurable)
- **Full logs on disk** — temp dir path printed so the agent can read more if needed
- **Consistent interface** — same env knobs and output format across all runners

## Available Agents

| Agent | Toolchain | Steps |
|-------|-----------|-------|
| `cargo-agent` | Rust | fmt, check, clippy, test (nextest) |
| `npm-agent` | Node.js | format, lint, typecheck, test, build |

## Quick Start

### Install via curl

```sh
curl -sSf https://raw.githubusercontent.com/codesoda/x-agent/main/install.sh | sh
```

### Install from local clone

```sh
git clone git@github.com:codesoda/x-agent.git
cd x-agent
sh install.sh
```

Local installs use symlinks so edits to the repo are immediately reflected.

### Use directly (no install)

```sh
# Rust project
path/to/x-agent/skills/cargo-agent/scripts/cargo-agent.sh

# Node.js project
path/to/x-agent/skills/npm-agent/scripts/npm-agent.sh
```

## Usage

### cargo-agent

```sh
cargo-agent.sh              # full suite: fmt + clippy + test
cargo-agent.sh fmt          # format only
cargo-agent.sh clippy       # clippy only
cargo-agent.sh test         # tests only
cargo-agent.sh test -p api  # tests in a specific crate
```

### npm-agent

```sh
npm-agent.sh                # full suite: format + lint + typecheck + test + build
npm-agent.sh lint           # lint only
npm-agent.sh test           # tests only
npm-agent.sh typecheck      # type checking only
```

npm-agent auto-detects your package manager (bun, pnpm, yarn, npm) and finds formatters/linters from package.json scripts or common tools (biome, eslint, prettier, tsc).

## Environment Knobs

All agents share the same pattern:

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_<STEP>` | `1` | Set to `0` to skip a step |
| `MAX_LINES` | `40` | Max diagnostic lines printed per step |
| `KEEP_DIR` | `0` | Set to `1` to keep temp log dir on success |

```sh
# Skip tests, keep logs
RUN_TESTS=0 KEEP_DIR=1 cargo-agent.sh

# Only run lint and typecheck
RUN_FORMAT=0 RUN_TESTS=0 RUN_BUILD=0 npm-agent.sh
```

## Output Format

```
------------------------------------------------------------
Step: clippy
Errors: 0
Warnings: 3

Diagnostics (first 40 lines):
warning: unused variable `x`
warning: unused import `std::io`
warning: function `old_handler` is never used

Result: PASS
Full JSON: /tmp/cargo-agent.abc123/clippy.json
Lean diags: /tmp/cargo-agent.abc123/clippy.diags.txt
Time: 4s
------------------------------------------------------------
Overall: PASS
Logs: /tmp/cargo-agent.abc123
```

On **PASS**, temp logs are cleaned up automatically. On **FAIL** (or `KEEP_DIR=1`), logs are preserved and the path is printed so the agent can inspect them.

## Claude Code Skills

The `skills/` directory contains Claude Code skill definitions. After installing, agents like Claude Code can invoke these as skills:

- `/cargo-agent` — run Rust checks
- `/npm-agent` — run Node.js checks

## License

MIT
