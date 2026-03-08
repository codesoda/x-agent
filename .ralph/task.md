# Task: x-agent Backlog — Shared Library + 8 New Agents

## Overview

Extract shared boilerplate from existing agents into a common library, then ship 8 new workflow runner agents. Each agent follows the established pattern: SKILL.md, bash script sourcing the shared lib, scenario tests, and install.sh integration.

## Goals

- Extract duplicated boilerplate into `lib/x-agent-common.sh`
- Refactor existing agents (cargo, npm, terra) to source the shared library
- Ship 8 new agents with full scenario tests and documentation
- Every agent supports fix/auto-format where the underlying tool provides it
- Maintain Bash 3.2 compatibility and structured output contract

## Success Metrics

- All 8 new agents pass their scenario tests (clean + issues fixtures)
- Existing agents pass their scenario tests after shared library refactor
- `shellcheck --severity=warning` passes on all scripts including `lib/x-agent-common.sh`
- Each new agent script is under ~200 lines of domain-specific code
- `tests/run-scenarios.sh` discovers and runs all scenarios successfully

## Specs

- [ ] 01-shared-library-extract.md
- [ ] 02-refactor-existing-agents.md
- [ ] 03-bash-agent.md
- [ ] 04-go-agent.md
- [ ] 05-gha-agent.md
- [ ] 06-helm-agent.md
- [ ] 07-kube-agent.md
- [ ] 08-docker-agent.md
- [ ] 09-ansible-agent.md
- [ ] 10-sql-agent.md

## Overall Acceptance Criteria

- All specs completed with all acceptance criteria met
- `tests/run-scenarios.sh` passes for all agents
- `shellcheck --severity=warning` passes on all scripts
- All agents follow the output contract (Step/Result/Fix/Overall)
- install.sh and README.md updated for all new agents
