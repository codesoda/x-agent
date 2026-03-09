#!/bin/sh
set -eu

# x-agent installer: installs agent-friendly workflow scripts and Claude/Codex skills.
# Works via: curl -sSf <raw-url>/install.sh | sh
# Or locally: sh install.sh

PROJECT_NAME="x-agent"
REPO_OWNER="${X_AGENT_REPO_OWNER:-codesoda}"
REPO_NAME="${X_AGENT_REPO_NAME:-x-agent}"
REPO_REF="${X_AGENT_REPO_REF:-main}"
RAW_BASE="${X_AGENT_RAW_BASE:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}}"

CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

AUTO_YES=0
SKIP_DEPS=0
INSTALL_CODEX=1
INSTALL_CLAUDE=1

TMP_DIR=""
SOURCE_DIR=""
SOURCE_MODE="remote"

# Available skills to install (each has its own scripts/ subdirectory)
SKILLS="ansible-agent bash-agent cargo-agent docker-agent gha-agent go-agent helm-agent kube-agent npm-agent py-agent sql-agent terra-agent"
SELECTED_SKILLS=""

info() {
  printf "[%s] %s\n" "$PROJECT_NAME" "$*"
}

warn() {
  printf "[%s] WARNING: %s\n" "$PROJECT_NAME" "$*" >&2
}

die() {
  printf "[%s] ERROR: %s\n" "$PROJECT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Install x-agent skills and scripts into local agent skill directories.

Usage:
  sh install.sh [options]
  curl -sSf https://raw.githubusercontent.com/codesoda/x-agent/main/install.sh | sh

Options:
  --yes          Non-interactive mode; accept default install prompts.
  --skip-deps    Skip dependency checks.
  --codex-only   Only install to ~/.codex/skills.
  --claude-only  Only install to ~/.claude/skills.
  --help         Show this help text.

Notes:
  Interactive mode prompts per x-agent skill and install destination.
  At the end, the installer prints a copy/paste snippet for AGENTS.md/CLAUDE.md.

Environment variables:
  CODEX_SKILLS_DIR   Override Codex skills root (default: ~/.codex/skills)
  CLAUDE_SKILLS_DIR  Override Claude skills root (default: ~/.claude/skills)
  X_AGENT_REPO_OWNER Override repo owner for remote fetches.
  X_AGENT_REPO_NAME  Override repo name for remote fetches.
  X_AGENT_REPO_REF   Override repo ref/branch for remote fetches.
  X_AGENT_RAW_BASE   Override full raw base URL for remote fetches.
EOF
}

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT INT TERM

prompt_yes_no() {
  question="$1"
  default="${2:-yes}"

  if [ "$AUTO_YES" -eq 1 ]; then
    return 0
  fi

  if [ "$default" = "yes" ]; then
    prompt="[Y/n]"
    fallback="yes"
  else
    prompt="[y/N]"
    fallback="no"
  fi

  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    while :; do
      printf "%s %s " "$question" "$prompt" > /dev/tty
      if ! IFS= read -r answer < /dev/tty; then
        break
      fi
      case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        [Nn]|[Nn][Oo]) return 1 ;;
        "")
          if [ "$fallback" = "yes" ]; then
            return 0
          fi
          return 1
          ;;
        *) printf "Please answer yes or no.\n" > /dev/tty ;;
      esac
    done
  fi

  [ "$fallback" = "yes" ]
}

skill_selected() {
  skill="$1"
  case " ${SELECTED_SKILLS} " in
    *" ${skill} "*) return 0 ;;
    *) return 1 ;;
  esac
}

add_selected_skill() {
  skill="$1"
  if [ -z "$SELECTED_SKILLS" ]; then
    SELECTED_SKILLS="$skill"
  else
    SELECTED_SKILLS="${SELECTED_SKILLS} ${skill}"
  fi
}

select_skills() {
  if [ "$AUTO_YES" -eq 1 ]; then
    SELECTED_SKILLS="$SKILLS"
    return 0
  fi

  info "Select x-agent skills to install:"
  for skill in $SKILLS; do
    if prompt_yes_no "Install ${skill}?" yes; then
      add_selected_skill "$skill"
    fi
  done
}

fetch_to_file() {
  url="$1"
  out="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return 0
  fi

  return 1
}

# Detect if we're running from a local checkout or need to fetch from remote.
resolve_source_dir() {
  # Check if running from inside the repo
  if [ -d "./skills" ]; then
    SOURCE_DIR="$(pwd)"
    SOURCE_MODE="local"
    info "Using local source at ${SOURCE_DIR}."
    return 0
  fi

  # Check relative to the script location
  case "$0" in
    */*)
      script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
      if [ -n "$script_dir" ] && [ -d "$script_dir/skills" ]; then
        SOURCE_DIR="$script_dir"
        SOURCE_MODE="local"
        info "Using source next to install.sh at ${SOURCE_DIR}."
        return 0
      fi
      ;;
  esac

  # Remote fetch
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_NAME}.XXXXXX")"
  SOURCE_DIR="${TMP_DIR}"
  SOURCE_MODE="remote"

  # Fetch shared library
  mkdir -p "${SOURCE_DIR}/lib"
  src_url="${RAW_BASE}/lib/x-agent-common.sh"
  dest="${SOURCE_DIR}/lib/x-agent-common.sh"
  info "Fetching lib/x-agent-common.sh..."
  if ! fetch_to_file "$src_url" "$dest"; then
    die "Unable to download ${src_url}"
  fi

  # Fetch each selected skill's SKILL.md and scripts
  for skill in $SELECTED_SKILLS; do
    mkdir -p "${SOURCE_DIR}/skills/${skill}/scripts"

    # Fetch SKILL.md
    src_url="${RAW_BASE}/skills/${skill}/SKILL.md"
    dest="${SOURCE_DIR}/skills/${skill}/SKILL.md"
    info "Fetching skills/${skill}/SKILL.md..."
    if ! fetch_to_file "$src_url" "$dest"; then
      die "Unable to download ${src_url}"
    fi

    # Fetch the skill's script
    script_name="${skill}.sh"
    src_url="${RAW_BASE}/skills/${skill}/scripts/${script_name}"
    dest="${SOURCE_DIR}/skills/${skill}/scripts/${script_name}"
    info "Fetching skills/${skill}/scripts/${script_name}..."
    if ! fetch_to_file "$src_url" "$dest"; then
      die "Unable to download ${src_url}"
    fi
    chmod +x "$dest"
  done
}

# Install a single skill to a skills root, with scripts alongside it.
install_skill_to_root() {
  root="$1"
  skill="$2"
  target="${root}/${skill}"

  mkdir -p "$root"
  rm -rf "$target"

  if [ "$SOURCE_MODE" = "local" ]; then
    ln -s "${SOURCE_DIR}/skills/${skill}" "$target"
    info "Symlinked ${skill} to ${target} -> ${SOURCE_DIR}/skills/${skill}"
  else
    mkdir -p "$target"
    cp -R "${SOURCE_DIR}/skills/${skill}/." "$target/"
    chmod +x "${target}/scripts/"*.sh 2>/dev/null || true
    info "Installed ${skill} to ${target}"
  fi
}

# Install the shared library to a skills root so agent scripts can source it.
# For local installs, symlink the lib/ directory.
# For remote installs, copy the fetched lib/ directory.
install_lib_to_root() {
  root="$1"
  target="${root}/lib"

  mkdir -p "$root"
  rm -rf "$target"

  if [ "$SOURCE_MODE" = "local" ]; then
    ln -s "${SOURCE_DIR}/lib" "$target"
    info "Symlinked lib to ${target} -> ${SOURCE_DIR}/lib"
  else
    mkdir -p "$target"
    cp -R "${SOURCE_DIR}/lib/." "$target/"
    info "Installed lib to ${target}"
  fi
}

# Rewrite SKILL.md paths to point at the actual installed script location.
patch_skill_paths() {
  root="$1"
  skill="$2"
  skill_md="${root}/${skill}/SKILL.md"

  if [ ! -f "$skill_md" ]; then return; fi

  # For local (symlink) installs, paths already point to the right place via the repo.
  # For remote installs, update paths to point at the skill's bundled scripts dir.
  if [ "$SOURCE_MODE" = "remote" ]; then
    scripts_dir="${root}/${skill}/scripts"
    # Replace relative scripts/ paths with the actual installed path
    if command -v sed >/dev/null 2>&1; then
      sed -i.bak "s|scripts/${skill}.sh|${scripts_dir}/${skill}.sh|g" "$skill_md"
      rm -f "${skill_md}.bak"
    fi
  fi
}

check_optional_deps() {
  info "Checking optional dependencies..."
  all_ok=1

  if skill_selected "ansible-agent"; then
    if command -v ansible-lint >/dev/null 2>&1; then
      info "  Found: ansible-lint"
    else
      warn "  Missing: ansible-lint (needed by ansible-agent)"
      all_ok=0
    fi

    if command -v ansible-playbook >/dev/null 2>&1; then
      info "  Found: ansible-playbook"
    else
      warn "  Missing: ansible-playbook (needed by ansible-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "bash-agent"; then
    if command -v shellcheck >/dev/null 2>&1; then
      info "  Found: shellcheck"
    else
      warn "  Missing: shellcheck (needed by bash-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "docker-agent"; then
    if command -v hadolint >/dev/null 2>&1; then
      info "  Found: hadolint"
    else
      warn "  Missing: hadolint (needed by docker-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "gha-agent"; then
    if command -v actionlint >/dev/null 2>&1; then
      info "  Found: actionlint"
    else
      warn "  Missing: actionlint (needed by gha-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "helm-agent"; then
    if command -v helm >/dev/null 2>&1; then
      info "  Found: helm"
    else
      warn "  Missing: helm (needed by helm-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "kube-agent"; then
    if command -v kubeconform >/dev/null 2>&1; then
      info "  Found: kubeconform"
    elif command -v kubeval >/dev/null 2>&1; then
      info "  Found: kubeval"
    else
      warn "  Missing: kubeconform or kubeval (needed by kube-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "go-agent"; then
    if command -v go >/dev/null 2>&1; then
      info "  Found: go"
    else
      warn "  Missing: go (needed by go-agent)"
      all_ok=0
    fi

    if command -v staticcheck >/dev/null 2>&1; then
      info "  Found: staticcheck"
    else
      warn "  Missing: staticcheck (optional for go-agent staticcheck step)"
    fi
  fi

  if skill_selected "cargo-agent"; then
    if command -v jq >/dev/null 2>&1; then
      info "  Found: jq"
    else
      warn "  Missing: jq (needed by cargo-agent)"
      all_ok=0
    fi

    if command -v cargo >/dev/null 2>&1; then
      info "  Found: cargo"
    else
      warn "  Missing: cargo (needed by cargo-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "npm-agent"; then
    if command -v node >/dev/null 2>&1; then
      info "  Found: node"
    else
      warn "  Missing: node (needed by npm-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "py-agent"; then
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
      info "  Found: python"
    else
      warn "  Missing: python3 (needed by py-agent)"
      all_ok=0
    fi

    for dep in ruff black; do
      if command -v "$dep" >/dev/null 2>&1; then
        info "  Found: ${dep}"
        break
      fi
    done
  fi

  if skill_selected "sql-agent"; then
    if command -v sqlfluff >/dev/null 2>&1; then
      info "  Found: sqlfluff"
    else
      warn "  Missing: sqlfluff (needed by sql-agent)"
      all_ok=0
    fi
  fi

  if skill_selected "terra-agent"; then
    if command -v terraform >/dev/null 2>&1; then
      info "  Found: terraform"
    else
      warn "  Missing: terraform (needed by terra-agent)"
      all_ok=0
    fi

    if command -v tflint >/dev/null 2>&1; then
      info "  Found: tflint"
    else
      warn "  Missing: tflint (optional for terra-agent lint step)"
    fi
  fi

  if [ "$all_ok" -eq 0 ]; then
    warn "Some optional dependencies are missing. Skills will skip steps that need them."
  fi
}

print_agents_md_snippet() {
  if [ -z "$SELECTED_SKILLS" ]; then
    return 0
  fi

  echo ""
  echo "----- BEGIN AGENTS/CLAUDE SNIPPET -----"
  echo "## x-agent checks"
  echo ""
  echo "Before completing work, run the relevant x-agent checks in dedicated sub-agents for the stacks you changed:"

  for skill in $SELECTED_SKILLS; do
    case "$skill" in
      ansible-agent)
        echo "- Ansible: use \`/ansible-agent\` (lint/syntax)."
        ;;
      bash-agent)
        echo "- Bash/Shell: use \`/bash-agent\` (syntax/lint)."
        ;;
      docker-agent)
        echo "- Docker: use \`/docker-agent\` (lint Dockerfiles)."
        ;;
      gha-agent)
        echo "- GitHub Actions: use \`/gha-agent\` (lint)."
        ;;
      helm-agent)
        echo "- Helm: use \`/helm-agent\` (lint/template)."
        ;;
      kube-agent)
        echo "- Kubernetes: use \`/kube-agent\` (validate manifests)."
        ;;
      go-agent)
        echo "- Go: use \`/go-agent\` (fmt/vet/staticcheck/test)."
        ;;
      cargo-agent)
        echo "- Rust: use \`/cargo-agent\` (fmt/check/clippy/test)."
        ;;
      npm-agent)
        echo "- Node.js: use \`/npm-agent\` (format/lint/typecheck/test/build)."
        ;;
      py-agent)
        echo "- Python: use \`/py-agent\` (format/lint/typecheck/test)."
        ;;
      sql-agent)
        echo "- SQL: use \`/sql-agent\` (lint/fix)."
        ;;
      terra-agent)
        echo "- Terraform: use \`/terra-agent\` (fmt-check/fmt-fix/init/plan-safe/validate/lint)."
        ;;
    esac
  done

  echo "- Launch stack-specific sub-agents to run these checks; do not skip them in the main agent."
  echo "- If a change touches multiple stacks, run all matching skills."
  if skill_selected "terra-agent"; then
    echo "- For Terraform formatting drift, run \`/terra-agent fmt-check\`; if it fails, run \`/terra-agent fmt-fix\` and then re-run checks."
    echo "- For safe planning, run \`/terra-agent plan-safe\` (exit code 2 = changes detected, not failure)."
  fi
  echo "- Resolve all FAIL results before completing the task."
  echo "----- END AGENTS/CLAUDE SNIPPET -----"
}

# --- Main ---

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)
      AUTO_YES=1
      ;;
    --skip-deps)
      SKIP_DEPS=1
      ;;
    --codex-only)
      INSTALL_CODEX=1
      INSTALL_CLAUDE=0
      ;;
    --claude-only)
      INSTALL_CODEX=0
      INSTALL_CLAUDE=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
  shift
done

info "x-agent installer"
info "=================="

select_skills
if [ -z "$SELECTED_SKILLS" ]; then
  info "No skills selected. Nothing to install."
  info "Done."
  exit 0
fi

resolve_source_dir

if [ "$SKIP_DEPS" -eq 0 ]; then
  check_optional_deps
else
  info "Skipping dependency checks (--skip-deps)."
fi

if [ "$INSTALL_CLAUDE" -eq 1 ]; then
  if prompt_yes_no "Install skills to ${CLAUDE_SKILLS_DIR}?" yes; then
    install_lib_to_root "$CLAUDE_SKILLS_DIR"
    for skill in $SELECTED_SKILLS; do
      install_skill_to_root "$CLAUDE_SKILLS_DIR" "$skill"
      patch_skill_paths "$CLAUDE_SKILLS_DIR" "$skill"
    done
  else
    info "Skipped Claude install."
  fi
fi

if [ "$INSTALL_CODEX" -eq 1 ]; then
  if prompt_yes_no "Install skills to ${CODEX_SKILLS_DIR}?" yes; then
    install_lib_to_root "$CODEX_SKILLS_DIR"
    for skill in $SELECTED_SKILLS; do
      install_skill_to_root "$CODEX_SKILLS_DIR" "$skill"
      patch_skill_paths "$CODEX_SKILLS_DIR" "$skill"
    done
  else
    info "Skipped Codex install."
  fi
fi

info ""
info "Installed skills: ${SELECTED_SKILLS}"
info ""
print_agents_md_snippet
info ""
info "Done."
