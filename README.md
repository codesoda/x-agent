# x-agent

Every time your coding agent runs a lint or test cycle, it burns thousands of tokens on compilation progress and passing test names. x-agent cuts 90-97% of that noise — your agent gets structured pass/fail, you keep your context window for actual code.

## Why?

Standard build tools produce walls of text. Agents waste context window parsing noise. x-agent scripts give:

- **Structured output** — `Step: lint`, `Result: PASS`, `Overall: FAIL`
- **Truncated diagnostics** — only the first N lines of errors/warnings (configurable)
- **Full logs on disk** — temp dir path printed so the agent can read more if needed
- **Consistent interface** — same env knobs and output format across all runners

## Available Agents

| Agent | Toolchain | Steps |
|-------|-----------|-------|
| `bash-agent` | Bash/Shell | syntax (bash -n), lint (shellcheck) |
| `cargo-agent` | Rust | fmt, check, clippy, test (nextest) |
| `docker-agent` | Docker | lint (hadolint), build-check (BuildKit) |
| `gha-agent` | GitHub Actions | lint (actionlint) |
| `go-agent` | Go | fmt (gofmt), vet, staticcheck, test |
| `helm-agent` | Helm | lint, template |
| `kube-agent` | Kubernetes | validate (kubeconform/kubeval) |
| `npm-agent` | Node.js | format, lint, typecheck, test, build |
| `py-agent` | Python | format (ruff/black), lint (ruff/flake8), typecheck (mypy/pyright), test (pytest) |
| `terra-agent` | Terraform | fmt (check/fix), safe init, plan-safe, validate, lint (tflint) |

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
The installer prompts for each x-agent skill so you can install only what you want.
It also prints a short AGENTS.md/CLAUDE.md policy snippet you can copy/paste.

### Use directly (no install)

```sh
# Rust project
path/to/x-agent/skills/cargo-agent/scripts/cargo-agent.sh

# Node.js project
path/to/x-agent/skills/npm-agent/scripts/npm-agent.sh

# Python project
path/to/x-agent/skills/py-agent/scripts/py-agent.sh

# Docker project
path/to/x-agent/skills/docker-agent/scripts/docker-agent.sh

# GitHub Actions project
path/to/x-agent/skills/gha-agent/scripts/gha-agent.sh

# Go project
path/to/x-agent/skills/go-agent/scripts/go-agent.sh

# Helm project
path/to/x-agent/skills/helm-agent/scripts/helm-agent.sh

# Kubernetes project
path/to/x-agent/skills/kube-agent/scripts/kube-agent.sh

# Terraform project
path/to/x-agent/skills/terra-agent/scripts/terra-agent.sh
```

## Usage

### bash-agent

```sh
bash-agent.sh              # full suite: syntax + lint
bash-agent.sh syntax       # bash -n syntax check only
bash-agent.sh lint         # shellcheck lint only
SHELLCHECK_SEVERITY=error bash-agent.sh lint  # only errors, ignore warnings
```

### cargo-agent

```sh
cargo-agent.sh              # full suite: fmt + clippy + test
cargo-agent.sh fmt          # format only
cargo-agent.sh clippy       # clippy only
cargo-agent.sh test         # tests only
cargo-agent.sh test -p api  # tests in a specific crate
```

### docker-agent

```sh
docker-agent.sh                        # full suite: lint only (build-check off by default)
docker-agent.sh lint                   # hadolint check only
RUN_BUILD_CHECK=1 docker-agent.sh all  # lint + BuildKit check
```

`docker-agent` discovers `Dockerfile`, `Dockerfile.*`, and `*.dockerfile` files recursively. `build-check` uses `docker build --check` (BuildKit lint mode) and defaults to OFF. Reports SKIP when no Dockerfiles are found.

### gha-agent

```sh
gha-agent.sh              # lint all workflow files
gha-agent.sh lint         # actionlint check only
```

`gha-agent` runs `actionlint` on `.github/workflows/*.yml` and `*.yaml` files. Reports SKIP when no workflows directory exists.

### go-agent

```sh
go-agent.sh                 # full suite: fmt + vet + staticcheck + test
go-agent.sh fmt             # gofmt check/fix
go-agent.sh vet             # go vet analysis
go-agent.sh test            # tests only
FMT_MODE=fix go-agent.sh fmt  # auto-fix formatting
```

`go-agent` uses `gofmt` for formatting (auto-fix locally, check-only in CI), `go vet` for analysis, optional `staticcheck` for linting, and `go test` for tests.

### helm-agent

```sh
helm-agent.sh              # full suite: lint + template
helm-agent.sh lint         # helm lint only
helm-agent.sh template     # helm template only
CHART_DIR=charts/myapp helm-agent.sh all  # explicit chart directory
```

`helm-agent` auto-detects chart directories by searching for `Chart.yaml`. Use `CHART_DIR` to override. Reports SKIP when no charts are found.

### kube-agent

```sh
kube-agent.sh              # full suite: validate
kube-agent.sh validate     # validate manifests only
KUBE_SCHEMAS_DIR=path kube-agent.sh all  # custom schema location
```

`kube-agent` auto-detects kubeconform or kubeval and validates all `.yaml`/`.yml` files containing Kubernetes resource definitions (`apiVersion:` + `kind:`). Use `KUBE_SCHEMAS_DIR` for custom schemas. Reports SKIP when no manifests are found.

### npm-agent

```sh
npm-agent.sh                # full suite: format + lint + typecheck + test + build
npm-agent.sh lint           # lint only
npm-agent.sh test           # tests only
npm-agent.sh typecheck      # type checking only
```

npm-agent auto-detects your package manager (bun, pnpm, yarn, npm) and finds formatters/linters from package.json scripts or common tools (biome, eslint, prettier, tsc).

### py-agent

```sh
py-agent.sh                # full suite: format + lint + typecheck + test
py-agent.sh format         # format only (auto-fix locally, check in CI)
py-agent.sh lint           # lint only
py-agent.sh test           # tests only
py-agent.sh test -k login  # tests matching "login"
```

py-agent auto-detects your runner (uv, poetry, or plain python) and finds tools (ruff, black, flake8, mypy, pyright, pytest).

### terra-agent

```sh
terra-agent.sh                              # full suite: fmt(check) + validate + lint
terra-agent.sh fmt-check                    # report formatting drift
terra-agent.sh fmt-fix                      # auto-fix formatting
terra-agent.sh init                         # safe non-mutating init
terra-agent.sh plan-safe                    # safe non-mutating plan
TERRAFORM_CHDIR=infra terra-agent.sh all    # run in infra/
FMT_MODE=fix terra-agent.sh fmt             # fmt using env-selected mode
```

`terra-agent` init is safety-first by default: `-backend=false`, `-input=false`, `-get=false`, `-upgrade=false`, `-lockfile=readonly`, and temp `TF_DATA_DIR` so project files are not mutated.
`terra-agent` plan-safe uses `-refresh=false`, `-lock=false`, and passes on detailed exit code `2` (changes detected).

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

- `/bash-agent` — run shell script checks
- `/cargo-agent` — run Rust checks
- `/docker-agent` — run Dockerfile linting
- `/gha-agent` — run GitHub Actions workflow linting
- `/go-agent` — run Go checks
- `/helm-agent` — run Helm chart checks
- `/kube-agent` — run Kubernetes manifest validation
- `/npm-agent` — run Node.js checks
- `/py-agent` — run Python checks
- `/terra-agent` — run Terraform checks/fixes

## License

MIT
