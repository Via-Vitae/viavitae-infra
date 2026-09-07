# QODER.md — AI Pair-Programming Guardrails

Behavioural guidelines for AI-assisted coding with Qoder in PyCharm on ViaVitae
repositories. These exist to reduce the recurring failure modes of large language models
in production codebases: invented files, plausible-looking stubs, silent scope creep and
compliance violations that get worked around instead of surfaced.

This file is a **binding instruction set** for the assistant, not advice. Where it
conflicts with a default behaviour, this file wins. Where it conflicts with an explicit
instruction from a human reviewer, the human wins and the divergence is recorded.

Merge these rules with project-specific instructions in the repository's own
documentation. Project rules extend these; they do not weaken them.

---

## Rule 1 — Never invent files beyond the requested scope

Create only the files that were asked for. Do not add a helper module, a configuration
file, a sample script, a `README` for a subdirectory, a test fixture directory, or a
"while I was here" utility unless it was requested.

Specifically prohibited without an explicit request:

- adding a companion config file that a third-party action or tool happens to support;
- adding `main.py`, `index.js`, `example/`, `demo/` or any sample entrypoint;
- adding `.gitkeep`, `.editorconfig` or lint configuration to a directory that was not
  part of the request;
- splitting one requested file into several, or merging several requested files into one.

If a requested file genuinely cannot work without a companion file, **stop and say so**
before writing either. A reference to a file that does not exist is a silent failure that
only surfaces on a hosted runner or in production.

## Rule 2 — Complete implementations only

No `// TODO`, no `# FIXME`, no `pass` bodies, no `raise NotImplementedError`, no stub
functions, no mocked behaviour shipped as finished work, no truncated files ending in
`...`, no "rest unchanged" elisions.

Every file you produce must be complete, syntactically valid, and runnable in the state
you leave it. If part of an implementation depends on information you do not have, you
must either:

1. ask for the information before writing; or
2. write the complete surrounding implementation and state precisely which decision is
   outstanding, rather than emitting a placeholder that looks finished.

Never invent a value that you cannot verify — not a commit SHA, not a package version, not
an API endpoint, not a legal entity name, not a cryptographic fingerprint, not a price.
Fabricated identifiers are worse than absent ones: they parse, they look authoritative, and
they fail at runtime or, in the case of supply-chain identifiers, they resolve to someone
else's code.

## Rule 3 — Ask before structural or architectural changes

Stop and ask before any change that alters the shape of the system rather than its
contents:

- adding, removing, renaming or moving a module, package, directory or public file;
- changing a public API, function signature, return type, event schema or database column;
- introducing a new dependency, framework, runtime, service or data store;
- changing an authentication, authorisation, tenancy or data-retention mechanism;
- changing CI structure: job graph, required checks, permissions model, deployment target;
- any refactor that touches more than one module boundary.

Propose the change, state the trade-off, and wait. A correct question is cheaper than an
unwanted migration.

## Rule 4 — No network calls, no telemetry, deterministic output

Do not perform network calls during generation: no package downloads, no registry lookups,
no fetching documentation, no calling external APIs, no telemetry, no analytics beacons.
Do not add code that phones home.

Output must be deterministic: the same input produces the same output. No random ordering,
no timestamps generated at write time unless explicitly requested, no environment-dependent
branches that change the produced artefacts, no "latest" version specifiers.

Pin what can be pinned. Where an external identifier is required and cannot be resolved
offline, declare it as an outstanding input instead of guessing it.

## Rule 5 — Respect existing conventions detected in the codebase

Before writing, read enough of the surrounding code to learn its conventions, then follow
them. Match the existing:

- naming style, indentation, line length and quoting, as codified in `.editorconfig`;
- module and directory layout;
- error-handling and logging patterns;
- comment density and documentation style;
- test framework, fixture conventions and assertion style;
- dependency management approach and lockfile policy;
- commit message format, per `CONTRIBUTING.md`.

Do not introduce a second way of doing something that already has one way. Do not
"modernise" a codebase's style as a side effect of an unrelated change. Where a convention
is not documented, infer it from the majority of existing code, not from your training
default.

## Rule 6 — Minimal diffs, refactor only when asked

Change what was asked and nothing else. A pull request should be reviewable in one pass;
the house limit is 400 changed lines.

Prohibited as unrequested side effects:

- reformatting files you did not otherwise need to edit;
- renaming variables, functions or files for readability;
- restructuring imports or reordering declarations;
- "cleaning up" adjacent code, comments or documentation;
- upgrading dependencies unrelated to the change;
- adding tests for code you did not touch.

If you notice something worth improving nearby, **mention it in your response** and let a
human decide. Do not include it in the diff.

## Rule 7 — Compliance stop-conditions

These conditions **halt work immediately**. Report the conflict, do not proceed, and never
silently work around them.

### GDPR

- Any new processing of personal data without a completed Data Protection Impact
  Assessment in `docs/DPIA-template.md`.
- Any transfer, storage or backup of personal data outside the European Economic Area.
- Any new third-party processor or subprocessor without a Data Processing Agreement and an
  ADR recording the decision.
- Any request to collect data beyond what the stated purpose requires, to extend a
  retention period, or to weaken a lawful basis under Article 6.
- Any use of special category data under Article 9 — including data revealing religious
  belief, which is directly relevant to a church vertical — without an explicit Article 9
  condition and DPO sign-off.
- Any change that would prevent a data subject exercising access, rectification, erasure,
  restriction, portability or objection.

### WCAG 2.2 AA

- Any user interface change that removes or bypasses an accessibility control.
- Any new component without a keyboard-accessible path, a visible focus state, a programmatic
  name, and sufficient colour contrast.
- Any request to disable an automated accessibility gate, to mark an `axe` violation as
  acceptable without a documented reason, or to ship a known AA failure.
- Any decorative or informational image without `alt` text handling, any form control
  without an associated label, any media without captions or a transcript.

### EU data residency

- Any service, CDN, analytics provider, error tracker, font host, LLM endpoint, object
  store or CI runner that would place personal data outside the EEA.
- Any "just for debugging" export of production or production-like personal data to a
  local machine, a third-party sandbox, or an AI service.
- Any change that moves self-hosted infrastructure to an external provider without an ADR
  and a residency assessment.

### Secrets

- Any credential, token, key or connection string appearing in source, configuration, CI
  files, test fixtures, documentation, logs or commit history.
- Any request to disable, bypass or loosen secret scanning, or to add a finding to an
  ignore list without a documented justification and security approval.

### How to stop

When a stop-condition triggers: state which condition, quote the relevant requirement,
explain the concrete consequence of proceeding, and propose the compliant alternative.
Then wait for a decision. Do not implement the non-compliant version "so you can see it",
and do not add a partial workaround.

---

## Rule 8 — Infrastructure stop-conditions (viavitae-infra)

This repository controls production compute, network segmentation, tenant databases and
backups. The failure mode here is not a bug in a release; it is an outage, a data loss or
an exposure that is discovered by a customer. These conditions halt work in the same way
as Rule 7, and they are merged into this file as required by the repository baseline.

### Irreversibility

- Any change whose plan contains `destroy`, `replace` or a force-new attribute on a
  `prod` resource, without the reason stated in prose and a rollback path in the pull
  request description.
- Any VMID reuse, storage-layout change, schema migration or certificate reissue presented
  as reversible when it is not.
- Any `terraform apply` executed locally against `staging` or `prod`. Apply runs only from
  `deploy.yml` after a human approval on the target environment, so that the reviewed plan
  and the applied plan are the same plan.

### Ownership boundaries

- Any change that lets two tools own one thing: Terraform and Ansible both configuring the
  same in-guest service, or Terraform and the Argo CD `clients` ApplicationSet both
  creating the same Kubernetes object. The boundary table in `README.md` is binding;
  crossing it needs an ADR.
- Any change that introduces a second source of truth for a version, an endpoint or a
  tenant list. One value, one file, everything else reads it.

### Quorum, capacity and single points of failure

- Any design that claims high availability on fewer fault domains than the quorum requires.
  Three etcd members on two Proxmox nodes is not HA; it is a guaranteed quorum loss on the
  first node failure. Do not write it, do not approve it, and do not soften the wording to
  make it look acceptable.
- Any resource ceiling, quota or retention period reduced without stating the new blast
  radius.

### Secrets, state and credentials

- Any credential, token, private key, kubeconfig or connection string written into
  Terraform configuration, Terraform **state**, an Ansible variable file, a Kubernetes
  manifest, a CI file, a log line or a pull request comment. Terraform state is plaintext
  to anyone who can read the bucket; a password passed as a resource argument lands there.
- Any change that un-ignores `*.tfstate*`, `*.tfvars` or `.env`, or that ignores
  `.terraform.lock.hcl`. The lock file is a supply-chain control, not a build artefact.
- Any weakening of a network policy, firewall rule, Kyverno policy, Pod Security Standard
  label, RBAC binding or admission policy — including switching a policy from `Enforce` to
  `Audit`, or adding an exclusion namespace — without security approval and an ADR.
- Any egress path opened from the `dmz` or `prod` VLAN to the `mgmt` VLAN. Management
  access is one-directional by design.

### Backups and recovery

- Any change to a backup schedule, retention period or encryption setting that is validated
  by a successful **backup** rather than a successful **restore**.
- Any drill script that writes to a production target, or that can run without an explicit
  confirmation flag.

### Verification is not optional here

For every infrastructure change, state which commands you ran and paste the relevant
output: `terraform validate`, `terraform plan`, `tflint`, `checkov`, `trivy config`,
`ansible-lint`, `kyverno apply`, `shellcheck`. A change you did not validate is a change
you did not make — report it as outstanding rather than as done.

---

## Working agreement

| Situation | Required behaviour |
| --- | --- |
| Instruction is ambiguous | Ask. Do not pick the interpretation that is easiest to implement. |
| Instruction conflicts with a rule above | Surface the conflict, propose the compliant path, wait. |
| Instruction conflicts with `SECURITY.md`, `LICENSE` or law | Refuse, explain, escalate to `security@viavitae.com` or `legal@viavitae.com`. |
| You cannot verify a fact | Say so explicitly. Never present an assumption as a verified result. |
| You changed more than intended | Report the extra changes; do not hide them in the diff. |
| Work is incomplete | Say what remains. Never report partial work as finished. |
| A test or gate fails | Fix the cause. Never delete, skip, relax or stub the test to make it pass. |

## Before you report completion

Confirm every one of the following. If any answer is no, the work is not complete.

1. Does the file tree match the requested tree exactly — nothing added, nothing missing?
   If a companion file was unavoidable (a linter config a gate depends on, a `main.tf` that
   makes four orphaned root files coherent), it is listed explicitly in the response with
   the reason, never slipped in silently.
2. Does every file parse and run in the state you left it?
3. Did you actually execute the verification, and read its output, rather than assuming it?
4. Are there zero placeholders, TODOs, stubs and invented identifiers?
5. Is the diff minimal — no reformatting, no drive-by refactors?
6. Did any Rule 7 or Rule 8 stop-condition trigger that you have not reported?
7. Did you state what you did **not** do, as clearly as what you did?
