# Spec 07: kube-agent

## Objective

Create a new kube-agent that validates Kubernetes manifests using `kubeconform` (preferred) or `kubeval`.

## Source

- **PRD User Story:** US-006
- **Functional Requirements:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-11, FR-12, FR-13

## User Story Context

> As a developer, I want a kube-agent that validates Kubernetes manifests so I can catch schema errors before applying to a cluster.

## Functional Requirements

- FR-1: Sources `lib/x-agent-common.sh`
- FR-2: Supports universal knobs
- FR-3: Per-step toggles (RUN_VALIDATE)
- FR-4: Structured output
- FR-5: --fail-fast and --help
- FR-6: Requires kubeconform OR kubeval (exit 2 if neither found)
- FR-11, FR-12, FR-13: SKILL.md, install.sh, scenario tests

## Components

- **Create:** `skills/kube-agent/scripts/kube-agent.sh`
- **Create:** `skills/kube-agent/SKILL.md`
- **Create:** `tests/kube-agent/clean/` (scenario.env + valid K8s manifests)
- **Create:** `tests/kube-agent/issues/` (scenario.env + invalid manifests)
- **Modify:** `install.sh`
- **Modify:** `README.md`

## Implementation Details

### Script: `kube-agent.sh`

**Agent-specific knobs:**
```bash
RUN_VALIDATE="${RUN_VALIDATE:-1}"
KUBE_SCHEMAS_DIR="${KUBE_SCHEMAS_DIR:-}"  # optional custom schema location
```

**Tool detection:**
```bash
KUBE_VALIDATOR=""
if command -v kubeconform >/dev/null 2>&1; then
  KUBE_VALIDATOR="kubeconform"
elif command -v kubeval >/dev/null 2>&1; then
  KUBE_VALIDATOR="kubeval"
else
  echo "Missing required tool: kubeconform or kubeval" >&2
  echo "Install kubeconform: go install github.com/yannh/kubeconform/cmd/kubeconform@latest" >&2
  echo "Or kubeval: https://www.kubeval.com/installation/" >&2
  exit 2
fi
echo "Validator: $KUBE_VALIDATOR"
```

**File discovery:**
- Find all `.yml`/`.yaml` files recursively (excluding `.github/`, `node_modules/`, `.git/`, `charts/` (Helm territory))
- Filter to Kubernetes manifests: files that contain both `apiVersion:` and `kind:` (use grep)
- If CHANGED_FILES set, filter to only those files
- If no K8s manifests found: SKIP

**Step: validate**
- kubeconform: `kubeconform -summary -output json <files>`
  - If KUBE_SCHEMAS_DIR set: `-schema-location $KUBE_SCHEMAS_DIR`
- kubeval: `kubeval --strict <files>`
  - If KUBE_SCHEMAS_DIR set: `--schema-location $KUBE_SCHEMAS_DIR`
- Report count of valid/invalid resources
- Fix hint: `Fix: resolve schema validation errors above, then re-run: /kube-agent validate`

**Commands:** `validate`, `all` (default)

### Scenario Tests

**clean fixture (`tests/kube-agent/clean/`):**
- `deployment.yaml`: valid Kubernetes Deployment manifest
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: test-app
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: test
    template:
      metadata:
        labels:
          app: test
      spec:
        containers:
          - name: app
            image: nginx:latest
  ```
- REQUIRED_TOOLS="kubeconform" (primary, test will skip if not installed)

**issues fixture (`tests/kube-agent/issues/`):**
- `bad-deployment.yaml`: invalid manifest (e.g., wrong apiVersion, missing required fields, or invalid field names)
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: test
  spec:
    replicas: "not-a-number"
  ```
- REQUIRED_TOOLS="kubeconform"

### SKILL.md

Triggers on: kube agent, kubernetes validate, kubeconform, kubeval, k8s checks, validate manifests.
Include `KUBE_SCHEMAS_DIR=*` in allowed-tools.

## Test Strategy

- `tests/run-scenarios.sh kube-agent` — clean passes, issues fails
- `shellcheck --severity=warning` passes
- Verify SKIP when no K8s manifests found
- Verify non-K8s YAML files are skipped
- Verify KUBE_SCHEMAS_DIR passthrough

## Dependencies

- Spec 01 (shared library)

## Acceptance Criteria

- [ ] `skills/kube-agent/scripts/kube-agent.sh` exists and is executable
- [ ] Sources `lib/x-agent-common.sh`
- [ ] Prefers kubeconform, falls back to kubeval
- [ ] Exits 2 with message naming both options if neither installed
- [ ] Validates only YAML files containing apiVersion/kind
- [ ] KUBE_SCHEMAS_DIR passes through to validator
- [ ] CHANGED_FILES scoping works
- [ ] Reports SKIP when no K8s manifests found
- [ ] Commands: `validate`, `all`
- [ ] SKILL.md, install.sh, README.md updated
- [ ] clean/issues scenario tests pass
- [ ] shellcheck passes
