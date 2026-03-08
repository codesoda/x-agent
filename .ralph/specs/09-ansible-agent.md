# Spec 09: ansible-agent

## Objective

Create a new ansible-agent that lints Ansible playbooks/roles and validates syntax.

## Source

- **PRD User Story:** US-008
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-10, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want an ansible-agent that lints and syntax-checks Ansible playbooks/roles so I can catch issues before running them.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_LINT, RUN_SYNTAX)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Required tools (ansible-lint, ansible-playbook) checked with need()
- FR-10: FMT_MODE=check|fix; CI forces check mode (for ansible-lint --fix)
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/ansible-agent/scripts/ansible-agent.sh`
- **Create:** `skills/ansible-agent/SKILL.md`
- **Create:** `tests/ansible-agent/clean/` (scenario.env + valid playbook)
- **Create:** `tests/ansible-agent/issues/` (scenario.env + playbook with lint issues)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `ansible-agent.sh`

**Agent-specific knobs:**
```bash
RUN_LINT="${RUN_LINT:-1}"
RUN_SYNTAX="${RUN_SYNTAX:-1}"
FMT_MODE="${FMT_MODE:-auto}"  # auto = fix locally, check in CI
```

**Required tools:** `need ansible-lint`, `need ansible-playbook`

**Playbook discovery:**
- If CHANGED_FILES set, filter to `.yml`/`.yaml` files
- Otherwise, discover playbooks using common patterns:
  - Files named `playbook*.yml`, `site.yml`, `main.yml`
  - Files in standard Ansible directories (if `roles/` or `playbooks/` exist)
  - For syntax check: files containing `hosts:` key (simple grep filter)
- If no playbooks found: SKIP

**Step: lint**
- Check mode (default, forced in CI): `ansible-lint`
  - ansible-lint auto-discovers from current directory
- Fix mode (FMT_MODE=fix, local only): `ansible-lint --fix`
- Capture output, log to disk
- Fix hint (check mode): `Fix: run /ansible-agent lint with FMT_MODE=fix to auto-fix, then re-run: /ansible-agent lint`
- Fix hint (fix mode, if still fails): `Fix: resolve remaining lint issues above, then re-run: /ansible-agent lint`

**Step: syntax**
- Run `ansible-playbook --syntax-check <playbook>` for each discovered playbook
- Collect results per playbook
- Fix hint: `Fix: resolve syntax errors above, then re-run: /ansible-agent syntax`

**CHANGED_FILES scoping:**
- Filter to `.yml`/`.yaml` files
- For lint: ansible-lint runs project-wide by default (CHANGED_FILES used for skip decision — if no ansible files changed, SKIP)
- For syntax: only check changed playbook files

**Commands:** `lint`, `syntax`, `all` (default)

### Scenario Tests

**clean fixture (`tests/ansible-agent/clean/`):**
- `playbook.yml`: minimal valid Ansible playbook
  ```yaml
  ---
  - name: Test playbook
    hosts: localhost
    gather_facts: false
    tasks:
      - name: Print message
        ansible.builtin.debug:
          msg: "Hello from ansible-agent test"
  ```
- REQUIRED_TOOLS="ansible-lint ansible-playbook"

**issues fixture (`tests/ansible-agent/issues/`):**
- `playbook.yml`: playbook with ansible-lint violations
  ```yaml
  ---
  - hosts: localhost
    tasks:
      - shell: echo hello
      - command: ls -la
  ```
  - Triggers: missing `name` on play/tasks, use of `shell`/`command` without `changed_when`
- REQUIRED_TOOLS="ansible-lint ansible-playbook"

### SKILL.md

Triggers on: ansible agent, ansible lint, ansible checks, validate ansible, ansible syntax check.
Include `FMT_MODE=*` in allowed-tools.

## Test Strategy

- `tests/run-scenarios.sh ansible-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes
- Verify FMT_MODE=fix runs ansible-lint --fix
- Verify CI forces check mode
- Verify SKIP when no ansible files found

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/ansible-agent/scripts/ansible-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] `lint` step runs `ansible-lint` in check mode, `ansible-lint --fix` in fix mode
- [ ] CI forces check mode
- [ ] `syntax` step runs `ansible-playbook --syntax-check` on discovered playbooks
- [ ] Auto-discovers playbooks from common patterns
- [ ] CHANGED_FILES scoping works
- [ ] Reports SKIP when no ansible files found
- [ ] Commands: `lint`, `syntax`, `all`
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
