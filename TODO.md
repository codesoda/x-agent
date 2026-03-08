# x-agent TODO

Build and ship new agents one at a time, with one commit per item.
See `docs/agents/definition-of-done.md` for completion criteria.

## Backlog (Priority Order)

- [x] `terra-agent` core: Terraform checks (`fmt-check`, `fmt-fix`, `validate`, optional `tflint`)
- [x] `terra-agent` follow-up: add safe init step (`terraform init -backend=false -input=false`)
- [x] `py-agent`: Python checks (`format`, `lint`, `typecheck`, `test`)
- [ ] `bash-agent`: Bash/shell script checks (`bash -n` syntax validation, `shellcheck` linting)
- [ ] `go-agent`: Go checks (`fmt`, `vet`, optional `staticcheck`, `test`)
- [ ] `gha-agent`: GitHub Actions workflow linting (`actionlint`)
- [ ] `helm-agent`: Helm checks (`lint`, `template` render validation)
- [ ] `kube-agent`: Kubernetes manifest validation (`kubeconform`/`kubeval`)
- [ ] `docker-agent`: Dockerfile linting and optional image build check
- [ ] `ansible-agent`: Ansible lint and syntax validation
- [ ] `sql-agent`: SQL format/lint checks (`sqlfluff`)
