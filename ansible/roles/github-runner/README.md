# roles/github-runner

Installs the pinned `actions/runner` binary and registers it with the **Via-Vitae
organisation** as a self-hosted runner carrying `[self-hosted, linux, x64, eu-infra]`.
This is the role that makes the four `security.yml` gates and the four `deploy.yml`
Plan/Apply jobs runnable: they select on that label set, and with zero registered
runners every one of them queues forever (ADR-000 "Runner"; verified `total_count=0`).

Registering with the org rather than a repository is deliberate — one pool serves all
twenty repositories that select the label, and the residency rule is about *where the
job runs*, not which repo queued it.

## Why a self-hosted runner at all

`security.yml` Gate 8 writes the live `AGE_SECRET_KEY_CI` private key to the runner and
performs SOPS decrypt round-trips. A GitHub-hosted runner would place that key, and any
decrypted material, on compute outside the EEA — a QODER.md Rule 7 residency
stop-condition. So the fix is an EU runner, **not** relabelling the jobs to
`ubuntu-latest`. ADR-008 is the authority; this role is its implementation.

## Invariants

| Invariant | Reason |
| --- | --- |
| Version and SHA-256 pinned in `group_vars/ci_runner.yml`, no role default | "Latest" on the machine that will hold the age private key is a version nobody chose and nobody reviewed. The digest is verified before the binary is installed — the same supply-chain stance as `roles/k3s` |
| Runs as the unprivileged `runner` user | A workflow step is arbitrary code from a pull request. DPIA R5 rates runner compromise **High**; the `mgmt`-VLAN placement plus rule X11 plus a non-root user are what keep a compromised runner from being a compromised estate |
| Labels read from `/etc/viavitae/runner-labels` | Terraform (module `prod_runner`) is the single source. The workflow selects on `vars.RUNNER_LABELS`; `tools/preflight.sh` compares the two. A third copy in this role would be the copy that silently wins |
| `config.sh` runs only when `.runner` is absent (or `github_runner_force_register=true`) | Each registration consumes one use of an ephemeral token and `--replace` re-registers a runner that may be mid-job. A no-op converge must not bounce a live job |
| Service installed via the runner's own `svc.sh`, managed via `systemctl` | The runner expects to own its unit and to repair it on upgrade; a templated unit here would fight it |

## Inputs

| Variable | Source | Notes |
| --- | --- | --- |
| `github_runner_version` | `group_vars/ci_runner.yml` | Required. e.g. `2.325.0` |
| `github_runner_checksum` | `group_vars/ci_runner.yml` | Required. 64-hex SHA-256 published for that release |
| `github_runner_registration_token` | `group_vars/vault.sops.yml` | SOPS/age encrypted. Ephemeral (≈1 h, limited uses) — mint a fresh one per registration run |
| `github_runner_url` | role default | `https://github.com/Via-Vitae` |
| labels | `/etc/viavitae/runner-labels` | Written by Terraform at first boot |

## Running it

    ansible-playbook -i inventories/prod/hosts.yml --limit ci_runner playbooks/runner.yml

Always `--check --diff` first. A `--check` run that reports no change on a host whose
runner is visibly absent means the role has stopped describing reality — usually that
`svc.sh install` is being skipped because a stale `.runner` exists.

## Prerequisite: a fresh registration token

GitHub registration tokens expire about an hour after creation. Before a run, mint one
at the target and re-encrypt it into `vault.sops.yml`:

    TOKEN=$(gh api --method POST orgs/Via-Vitae/actions/runners/registration-token --jq .token)

Then update `github_runner_registration_token` with `sops` on the environment's
recipients (prod has no CI recipient — see `.sops.yaml`). The token authorises
*registration only*; it is not a credential the running job holds.

## Not managed here

Network egress (the allow-list to GitHub, the Terraform registry, the Helm repos and
the state bucket is enforced on the `mgmt` VLAN router per DPIA M8 / rule E5, not on the
guest), OS hardening (`roles/hardening`), and the per-job toolchains the workflows fetch
themselves.
