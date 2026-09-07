# Pull Request

<!--
Pull request template for viavitae-infra, inherited from viavitae-template.

Complete every box. A box that genuinely does not apply is annotated "n/a" with a
reason — it is not left blank. Blank boxes are treated as "not done" and the review
is returned.

Before opening this pull request, read CONTRIBUTING.md for the small-PR doctrine
(under 400 changed lines), the [infra] evidence table and the rollback requirement,
and QODER.md if you used AI assistance.

A change to `terraform/envs/prod/**`, `k8s/policies/**`, `backup/**` or any firewall
rule needs a security review in addition to the platform review. Request both up
front; CODEOWNERS will not ask for the second one automatically on every path.
-->

## Summary

<!-- One or two sentences: what changes, and why. Link the design or ADR if there is one. -->

## Linked issue

<!-- Closes #123 — use the keyword so the issue closes automatically. Write "n/a" with a reason if there is no issue. -->

Closes #

## Type of change

<!-- Keep one, delete the rest. -->

- [ ] `feat` — a new feature
- [ ] `fix` — a bug fix
- [ ] `perf` — a performance improvement
- [ ] `refactor` — restructuring, no behaviour change
- [ ] `docs` — documentation only
- [ ] `test` — tests only, no production change
- [ ] `build` / `ci` — build system, dependencies or CI configuration
- [ ] `chore` — maintenance, touches neither source nor tests
- [ ] `revert` — reverting a previous commit
- [ ] **Breaking change** — append `!` to the commit type and describe the migration below.
      In this repository that includes: a plan with `destroy` or `replace` on a `prod`
      resource, a state backend or state key change, a VMID renumbering, a VLAN or firewall
      re-segmentation, a retention reduction, or an admission policy moved to `Enforce`.

## Checklist

### Change quality

- [ ] **Conventional Commit title** — `<type>(<scope>): <imperative summary>`, under 72 characters, per CONTRIBUTING.md
- [ ] **Linked issue** — `Closes #nnn` above, or "n/a" with a reason
- [ ] **Linters and validators pass locally** — `./tools/preflight.sh` run to completion, output pasted in Verification below
- [ ] **No secrets in diff** — Gitleaks run locally over the full history, no credential, token, key, kubeconfig, `*.tfvars` or connection string anywhere in the change
- [ ] **No new deps without justification** — every added provider, collection, chart or binary is named below with the reason, the licence, and why an existing dependency could not do the job

### Infrastructure impact

- [ ] **`terraform plan` output attached** — posted by the `plan` job in `deploy.yml` for every touched environment, or "n/a — no Terraform change". A plan is attached per environment; one plan does not stand in for three.
- [ ] **No unintended destroy or replace** — the plan shows no `destroy` and no force-new replacement, or each one is explained in prose below with its reason and its window
- [ ] **IaC scanners clean** — `trivy config` reports no `CRITICAL` or `HIGH`, and `checkov` reports no finding on the gating checks; both run in `compliance-check.yml`. An accepted finding carries a suppression comment naming the approver and the review date.
- [ ] **Ansible check mode run** — `ansible-playbook --check --diff` output attached for the target inventory, or a statement of why check mode is not safe for these tasks
- [ ] **Manifests render** — `kubectl apply --dry-run=client -R -f k8s/` and the `helm template` render both succeed, or "n/a — no Kubernetes change"
- [ ] **Admission policy rollout staged** — a new or changed Kyverno policy lands in `Audit` first with the `Enforce` date stated below, or "n/a — no policy change"
- [ ] **DR impact assessed** — does this change alter an RPO, an RTO, a backup schedule, a retention period or the restore path? If yes, `docs/capacity-plan.md` and the affected runbook are updated in this change; otherwise "n/a — no recovery impact"
- [ ] **Rollback path stated** — fill in the Rollback section below. "None" is an acceptable answer only when the change is genuinely irreversible and a window and a go/no-go point are given.
- [ ] **Maintenance window** — required for any `prod` change with an availability impact: date, expected duration, who is on call, and how the change is aborted
- [ ] **Ownership boundary respected** — the change does not give Terraform and Ansible, or Terraform and Argo CD, ownership of the same object (README.md boundary table)

### Compliance

- [ ] **GDPR impact assessed** — if personal data is touched (logs, monitoring labels, IAM identities, backup contents), a DPIA reference is given below; if not, this box is annotated "n/a — no personal data"
- [ ] **Data residency confirmed** — every new storage location, processor, runner and egress destination is inside the EEA, or an ADR and a transfer impact assessment are linked
- [ ] **Accessibility checked (WCAG 2.2 AA)** — "n/a — no UI" unless a Grafana dashboard is added, in which case: colour-blind-safe palette, no colour-only encoding, and readable at 200 % zoom
- [ ] **i18n parity LT/EN/RU** — "n/a — no user-facing strings" unless a Grafana dashboard or a status page is added

### Documentation

- [ ] **CHANGELOG entry** — follows from the commit type, or the change is `test`/`chore` and is not released
- [ ] **Docs updated** — README, ADR, runbook, `docs/network-topology.md` or `docs/capacity-plan.md` reflect the change, or no operational behaviour changed
- [ ] **Module or role README updated** — inputs/outputs table for a Terraform module, ownership statement for an Ansible role, or "n/a — no module or role changed"

## Plan output

<!--
Paste the summary line of every attached plan, per environment, so a reviewer can see
the shape of the change without opening the CI log. The full output is posted by the
`plan` job; this is the index to it.
-->

| Environment | Add | Change | Destroy | Replace | Link to plan |
| --- | --- | --- | --- | --- | --- |
| global | | | | | |
| dev | | | | | |
| staging | | | | | |
| prod | | | | | |

## Rollback

<!-- Required. Pick one and state the evidence that it works. -->

- [ ] `terraform apply` of the previous commit — the plan above contains no destroy and no force-new
- [ ] Argo CD revert to the previous Git commit — applies to Kubernetes objects only
- [ ] Restore from `vzdump` snapshot — snapshot ID and accepted RTO stated below
- [ ] Restore from WAL-G point-in-time — target time and accepted RTO stated below
- [ ] **None — irreversible.** Window, go/no-go point and the reason irreversibility is accepted:

Rollback detail:

## Maintenance window

| Field | Value |
| --- | --- |
| Required | no / yes |
| Environment | n/a / dev / staging / prod |
| Window (date, time, TZ) | |
| Expected duration | |
| On call | |
| Abort criteria | |

## New dependencies

<!-- One row per added provider, collection, chart, binary or action. Delete the table if none. -->

| Package | Version | Licence | Why an existing dependency could not do this |
| --- | --- | --- | --- |
| | | | |

## GDPR and DPIA

<!--
Required if this change touches personal data. Under rule R5, processing may not
start before the DPIA is complete. Infrastructure processing is recorded as
INFRA-001 in docs/DPIA-template.md.
-->

| Field | Value |
| --- | --- |
| Personal data affected | none / identify which (logs, metrics labels, identities, backups) |
| Special category data (Art. 9), including religious belief | no / yes — condition relied on |
| DPIA reference | n/a / INFRA-001 section / DPIA-nnn |
| New processor or subprocessor | no / name, DPA in place, EEA residency confirmed |
| Data residency | EEA-only confirmed / exception requested — link the ADR |
| New egress destination | none / host, purpose, VLAN, firewall rule reference |
| Retention period changed | no / old and new period, and which backup or log store |

## Breaking changes and migration

<!-- Required if "Breaking change" is selected above. Otherwise write "none". -->

## AI assistance

<!--
Required disclosure, per QODER.md. State which parts were AI-assisted and confirm
you have read and can defend every line.
-->

- [ ] No AI assistance was used
- [ ] AI assistance was used — I have reviewed every line, confirmed no invented files, no stubs and no placeholders, and I take responsibility for the result

## Verification

<!--
How did you prove this works? Paste the commands you ran and the relevant output.
"Tested locally" without evidence is not verification.
-->

## Size

- [ ] Under 400 changed lines, excluding generated files and lockfiles — or the reason is stated in the summary and review was requested early
