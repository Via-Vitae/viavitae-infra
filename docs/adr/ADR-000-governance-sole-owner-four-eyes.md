# ADR-000: Sole-Owner Governance and the Four-Eyes Review Model

| Field | Value |
| --- | --- |
| **Status** | Accepted |
| **Owner** | `@JourneyOfLife` |
| **Date** | 2026-09-09 |
| **Deciders** | `@JourneyOfLife` (sole proprietor) |
| **Consulted** | `@IterVitae` (independent reviewer) |
| **Supersedes** | — |
| **Superseded by** | — |

---

## Context

This record is numbered `000` because it governs every other decision in the repository:
it fixes who owns a change, who reviews it, and which controls are real rather than
documented. It was written after an audit of the `Via-Vitae` organisation on 2026-09-09
found that the governance model described in the documentation did not match what GitHub
was enforcing.

Every command below was executed against the GitHub REST API on 2026-09-09 and its output
is quoted, so the finding can be re-verified rather than trusted.

### What the documentation claimed

`README.md`, `CONTRIBUTING.md` and `.github/CODEOWNERS` described a multi-team model:
`@Via-Vitae/architects`, `@Via-Vitae/platform`, `@Via-Vitae/security`,
`@Via-Vitae/compliance`, `@Via-Vitae/dpo` and `@Via-Vitae/legal` approving changes by path,
with separate security, compliance and DPO functions.

### What GitHub was actually enforcing

**The teams exist, but not for this repository.**

```
gh api orgs/Via-Vitae/teams                → architects, compliance, dpo, legal, platform, security
gh api orgs/Via-Vitae/teams/platform       → privacy=closed  members_count=1  repos_count=1
gh api orgs/Via-Vitae/teams/platform/repos → Via-Vitae/viavitae-brand
gh api orgs/Via-Vitae/viavitae-infra/teams → (empty)
```

All six teams have exactly one member, `@JourneyOfLife`, and access to exactly one
repository, `viavitae-brand`. No team has access to `viavitae-infra`.

**Consequence: every owner in CODEOWNERS was unresolvable.**

```
gh api repos/Via-Vitae/viavitae-infra/codeowners/errors  → 34 errors
  Unknown owner on line 8: make sure the team @Via-Vitae/platform exists,
  is publicly visible, and has write access to the repository
```

A `closed` team *can* be a code owner — `viavitae-brand` reports zero errors with the same
team handles, which isolates the operative condition as **write access to this repository**,
not team visibility. Because `viavitae-infra` granted access to no team, all 34 rules
silently resolved to nobody.

**Combined with branch protection, that is a deadlock, not a cosmetic defect.**

```
gh api repos/Via-Vitae/viavitae-infra/branches/main/protection
  required_pull_request_reviews.require_code_owner_reviews   = true
  required_pull_request_reviews.required_approving_review_count = 1
  required_pull_request_reviews.dismiss_stale_reviews        = true
  enforce_admins.enabled                                     = true
  required_status_checks.contexts                            = ["CI status", "Compliance status"]
```

Code-owner review was mandatory, no code owner resolved, and the only human with write
access is `@JourneyOfLife` — who is also the author of every pull request, and an author
cannot approve their own pull request. No pull request could be merged through its own
controls. The procedure actually used was to disable `enforce_admins`, merge, and restore
it, which is documented in [`docs/runbooks/branch-protection.md`](../runbooks/branch-protection.md).
That procedure suspends the control at the exact moment the control is needed.

**The four-eyes reviewer had no access at all.**

```
gh api orgs/Via-Vitae/members                     → JourneyOfLife
gh api repos/Via-Vitae/viavitae-infra/collaborators → JourneyOfLife
```

`@IterVitae` is a real GitHub user (`gh api users/IterVitae → type=User`) but holds no
access to any of the ten repositories, and GitHub reports the consequence directly where
they are already named as an owner:

```
gh api repos/Via-Vitae/viavitae-web/codeowners/errors
  Unknown owner on line 34: make sure @IterVitae exists and has write access to the repository
```

Per [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches),
required approving reviews must come from reviewers **with write permissions**. Across 27
closed pull requests in five repositories, `@IterVitae` has submitted **zero** reviews.
Four-eyes review was documented, configured in prose, and never mechanically possible.

**A published security policy asserted a control that was off.**

`SECURITY.md` stated that private vulnerability reporting "is enabled on repositories in
the `Via-Vitae` organisation". It was not:

```
gh api repos/Via-Vitae/viavitae-infra/private-vulnerability-reporting → {"enabled":false}
```

Its email channels were also undeliverable. `viavitae.com` is parked (`NS` at
`dns-parking.com`, no `A`, no `MX`) and `viavitae.site` has no `MX` record, so
`security@`, `legal@` and `dpo@viavitae.com` could not receive a report. A researcher
following the policy would have reported into a void and the 24-hour acknowledgement SLA
could not have started.

**Every free repository-level security control was disabled in all ten repositories.**

```
for r in <all 10>; do gh api repos/Via-Vitae/$r --jq '.security_and_analysis'; done
  secret_scanning                  = disabled
  secret_scanning_push_protection  = disabled
  dependabot_security_updates      = disabled
```

All three are free on public repositories, and this repository holds SOPS/age recipient
configuration and infrastructure-as-code for production.

## Decision

### 1. Accountability is named by human handle, not by team

| Function | Accountable | Basis |
| --- | --- | --- |
| Code owner, security owner, incident commander | `@JourneyOfLife` | Sole proprietor; only member of the organisation |
| Independent reviewer (four-eyes) | `@IterVitae` | Separate GitHub identity; reviews only, never commits code, never shares credentials with `@JourneyOfLife` |
| Privacy / DPO function | `@JourneyOfLife` | See section 3 — an assessment, not a designation |
| Escalation channel | GitHub private vulnerability reporting | The only channel verified to be deliverable; see `SECURITY.md` |

`.github/CODEOWNERS` names `@JourneyOfLife @IterVitae`. Path-scoped rules are retained even
though they currently resolve to the same two handles: they record which paths are security-
and privacy-sensitive, and the routing already exists when a second reviewer with write
access arrives.

The six organisation teams are **not** deleted — `viavitae-brand` depends on them and its
CODEOWNERS resolves cleanly — but they are no longer referenced by any repository that has
not granted them write access.

### 2. Four-eyes review is recorded as an open, unenforceable control

`@IterVitae` holds no repository access as of this decision. Until they are granted **write**
access:

- their approval cannot satisfy `required_approving_review_count`, and
- CODEOWNERS entries naming them remain reported as unknown owners by GitHub.

This is recorded as an **accepted risk with named compensating controls**, not as a
satisfied control:

| # | Compensating control | Verified state |
| --- | --- | --- |
| C1 | No direct push to `main`; every change passes through a pull request | `enforce_admins=true`, `allow_force_pushes=false`, `allow_deletions=false` |
| C2 | Strict required status checks — `CI status` and `Compliance status` must pass on the merge commit | `required_status_checks.strict=true` |
| C3 | Stale approvals dismissed when the diff changes | `dismiss_stale_reviews=true` |
| C4 | Linear history, so every landed change maps to one reviewed commit range | `required_linear_history=true` |
| C5 | Secret scanning with push protection on all ten repositories | Enabled 2026-09-09 |
| C6 | Any `enforce_admins` suspension to force a merge is recorded in the pull request with the reason, and reviewed by `@IterVitae` after the fact | Procedural — see Consequences |

**Closing action (single step):** grant `@IterVitae` write access to all ten repositories,
then confirm `gh api repos/Via-Vitae/<repo>/codeowners/errors` returns zero errors. Write
access is the minimum GitHub requires for a review to count; the ability to push to `main`
remains blocked by C1–C4, so "reviews only, never commits" stays enforceable by branch
protection rather than by trust.

### 3. No Data Protection Officer is designated, and none is claimed

The instruction that prompted this ADR asked for the note *"DPO function is self-assigned
per GDPR Art. 37(4) exception"*. That wording was **not adopted**, because it is not what
Article 37(4) says:

- **Art. 37(1)** lists the three cases where designation is mandatory: a public authority;
  core activities requiring regular and systematic monitoring of data subjects on a large
  scale; or core activities consisting of large-scale processing of Article 9 special-category
  data.
- **Art. 37(4)** covers cases *outside* paragraph 1, where Union or Member State law may
  require designation. It is an extension provision. It is not an exception permitting
  self-designation.
- **Art. 38(6)** allows a DPO to fulfil other tasks only where the controller ensures those
  tasks "do not result in a conflict of interests". A sole proprietor who is also the
  controller, the processor, the security function and the DPO cannot separate the duty to
  advise and monitor from the interest in the processing being monitored.

What is recorded instead, as fact:

1. **No DPO is designated.** No DPO mailbox exists, and no external DPO is contracted.
2. **The Article 37(1) assessment is not complete.** It is the owner's to complete, and it
   must be completed before processing begins, not after. The determinative question for
   this platform is Art. 37(1)(c): a church vertical processes data revealing religious
   belief, which is Article 9 special-category data, and whether that processing is
   "large-scale" and part of "core activities" is a factual judgement about the pilot.
3. **Trigger for contracting an external DPO:** the first processing of Article 9 data at
   scale, the first regular and systematic monitoring of data subjects at scale, or the
   completion of the Art. 37(1) assessment with a positive result — whichever comes first.
   Until then, the privacy function is performed by `@JourneyOfLife` and the conflict of
   interest is disclosed rather than described away.
4. Where `docs/DPIA-template.md` or an existing ADR names `@Via-Vitae/dpo` as a signatory,
   that signature is `@JourneyOfLife` acting in the privacy function, with the conflict
   above disclosed.

### 4. Automated actors are GitHub's built-in apps only

| Actor | Role | Configuration |
| --- | --- | --- |
| `github-actions[bot]` | CI/CD, plan and apply, releases | Inherent to Actions; no account exists |
| `dependabot[bot]` | Dependency and SHA-pin pull requests | `.github/dependabot.yml`, `terraform` and `github-actions` ecosystems |

No human-impersonating bot account is created. A synthetic "engineer" identity would
manufacture an approval that did not happen and would falsify the review record this ADR
exists to make honest.

### 5. CodeQL is not added to the required status checks yet

`codeql.yml` emits a dynamic check context, `Analyze (${{ matrix.language }})`, gated behind
a `detect` job that skips when a language is absent, and it has no aggregate status job.
A required context that can silently never report blocks every pull request forever. Adding
CodeQL as a required check therefore first requires an aggregate job — the same pattern
`ci.yml` and `compliance-check.yml` already use to publish `CI status` and
`Compliance status`. That is a CI structure change and is deferred to its own change.

### 6. Repository-level security controls enabled across the organisation

On 2026-09-09, for all ten public repositories: secret scanning, secret scanning push
protection, Dependabot security updates, Dependabot alerts, and private vulnerability
reporting were enabled and verified by read-back. `SECURITY.md` was corrected so that its
claim about private vulnerability reporting is true, its email row states plainly that no
mailbox is deliverable instead of publishing a dead address, and its scope row names hosts
by what they resolve to rather than by a hardcoded domain.

## Consequences

### Positive

- CODEOWNERS entries resolve to real principals with write access, so the file describes
  enforcement instead of contradicting it.
- The deadlock is documented with its mechanism, so the next person does not rediscover it
  by finding that a pull request will not merge.
- Four free security controls are on in all ten repositories, including push protection on
  the repository that holds SOPS/age configuration.
- `SECURITY.md` no longer publishes an undeliverable reporting channel or asserts a control
  that is disabled. A researcher's report now reaches a queue someone can read.
- The privacy position is stated as an incomplete assessment with a trigger, which is
  defensible in an audit, instead of a fabricated legal basis, which is not.

### Negative

- **Four-eyes review is not enforceable today.** With one identity holding write access, no
  second approval is mechanically obtainable, and merges still require suspending
  `enforce_admins`. C6 makes that suspension visible and reviewed after the fact, which is
  a detective control, not a preventive one. This is the material residual risk of this ADR.
- Separation of duties is claimed nowhere. One person authors, owns, secures and approves
  the infrastructure. SOC 2 CC1.3 and ISO 27001 A.5.2 will read this as a structural
  limitation of a sole-proprietor organisation, and it is recorded as such rather than
  dressed as a six-team structure with one member.
- Removing the email channel reduces the ways a researcher can report. It replaces a
  channel that silently discarded reports with one that cannot.

### Neutral

- `viavitae-brand` keeps team-based CODEOWNERS, so the organisation runs two ownership
  styles until the remaining team-based repositories (`.github`, `viavitae-template`,
  `viavitae-api`) are converted. The five repositories already using
  `@JourneyOfLife @IterVitae` needed no change.
- Existing ADR and DPIA "Owner" rows naming `@Via-Vitae/<team>` are **left as written**.
  They are historical records of who owned a decision when it was taken; rewriting them
  would falsify audit evidence. Section 3(4) supplies the interpretation instead.

## Alternatives Considered

### 1. `* @Via-Vitae` as the default owner (Rejected)

**Pros:** Matches the wording of the instruction that prompted this ADR.

**Cons:** `gh api users/Via-Vitae` returns `type=Organization`. An organisation handle is not
a valid CODEOWNERS principal — only a user, a team or an email address is. It would resolve
to "Unknown owner" exactly like the teams did, and it would also delete the path-scoped
rules. It reproduces the defect it was meant to fix, in a repository where
`require_code_owner_reviews` is on and `enforce_admins` is on.

**Verdict:** Rejected. It converts a 34-error file into a one-error file with the same
effect, and the acceptance test proposed alongside it — `grep -ri 'viavitae-org/'` returns
zero hits — passes on this repository without a single change, because the slug it searches
for never existed here. A test that passes before the fix cannot detect the fix.

### 2. Grant the six existing teams write access to this repository (Rejected for now)

**Pros:** Zero file edits; all 34 errors disappear; `viavitae-brand` already proves the
pattern works.

**Cons:** All six teams have the identical single member. Six approvals from one person is
not separation of duties, and presenting it as such is the exact failure this ADR exists to
correct. It also multiplies grants across ten repositories.

**Verdict:** Rejected as the primary model. Reconsider only if a team acquires a second
member who is not `@JourneyOfLife`.

### 3. Disable `require_code_owner_reviews` and require no approvals (Rejected)

**Pros:** Pull requests merge without an admin bypass, so the bypass procedure disappears.

**Cons:** It removes the last review control on infrastructure that provisions production
compute, tenant databases and backups, and it does so to make a metric look healthy.

**Verdict:** Rejected. Weakening a control to clear a queue is the failure mode QODER.md
Rule 7 and the working agreement exist to prevent.

### 4. Grant `@IterVitae` write access now (Deferred by owner decision)

**Pros:** Makes four-eyes real in one step; resolves the CODEOWNERS errors naming
`@IterVitae`; removes the need to suspend `enforce_admins`.

**Cons:** Grants push ability to a second identity. Mitigated by C1–C4: branch protection
still requires a pull request, a code-owner approval and green strict status checks.

**Verdict:** Deferred by the owner on 2026-09-09. Recorded as the single closing action in
section 2, with its verification command.

## Compliance Impact

### SOC 2

- **CC1.3 (Structures, reporting lines, authorities):** A sole-proprietor structure is now
  documented with its limitation stated, rather than implied to have six separate functions.
- **CC6.3 (Role-based access):** The gap between documented and enforced access is closed for
  CODEOWNERS; the remaining gap is the reviewer's absence, recorded as accepted risk.
- **CC8.1 (Change management):** C1–C4 plus the disclosure requirement in C6 make every
  admin-bypass merge a recorded, reviewable event.
- **CC7.1 / CC7.2 (Vulnerability detection):** Secret scanning, push protection and private
  vulnerability reporting enabled across all ten repositories.

### ISO 27001

- **A.5.2 (Information security roles and responsibilities):** Responsibilities are assigned
  to named individuals, not to teams with no members in this repository.
- **A.5.3 (Segregation of duties):** Not achieved. Recorded as an accepted limitation with
  compensating controls, which is what A.5.2 and the Statement of Applicability require when
  segregation is not feasible.
- **A.5.7 (Threat intelligence) / A.8.8 (Management of technical vulnerabilities):**
  Dependabot alerts and security updates enabled.

### GDPR

- **Art. 37 / Art. 38(6):** No DPO designated; the conflict of interest in the sole
  proprietor performing the privacy function is disclosed, and the trigger for contracting an
  external DPO is written down. No legal basis is asserted that the regulation does not
  provide.
- **Art. 33 / Art. 34:** The breach-notification workflow in `SECURITY.md` now names a
  reachable channel, so the 72-hour clock can actually start.
- **Art. 5(2) (Accountability):** The accountability model is evidenced by API output quoted
  in this record, which is reproducible by an auditor rather than taken on trust.

## Implementation

Landed with this ADR:

- `.github/CODEOWNERS` — rewritten to `@JourneyOfLife @IterVitae`, path rules retained, with
  the root cause and the verification command recorded in the file header.
- `SECURITY.md` — disclosure channel, escalation path, breach-workflow ownership, scope and
  contact table corrected to what is verifiably true.
- `README.md` — branch-protection checklist, so the enforced configuration is reviewable
  without an API call.
- `CONTRIBUTING.md` — approval step and help table name real accountable people.
- `.github/workflows/compliance-check.yml` — the CODEOWNERS gate message named
  `@Via-Vitae/architects`, which no longer appears in this repository's CODEOWNERS.
- Organisation settings, applied and verified by read-back on 2026-09-09 across all ten
  repositories: secret scanning, push protection, Dependabot alerts, Dependabot security
  updates, private vulnerability reporting.

Outstanding, with owners:

| Action | Owner | Blocks |
| --- | --- | --- |
| Grant `@IterVitae` write access to all ten repositories | `@JourneyOfLife` | Four-eyes enforcement; closing the accepted risk in section 2 |
| Complete the Art. 37(1) assessment and record the outcome | `@JourneyOfLife` | Any Article 9-scale processing |
| Add MX records for `viavitae.site` and provision `security@viavitae.site` with a PGP key | `@JourneyOfLife` | Email disclosure channel (GitHub reporting remains the working channel until MX is live) |
| Register an EU self-hosted runner with labels `[self-hosted, linux, x64, eu-infra]` | `@JourneyOfLife` | `security.yml` and `deploy.yml` jobs (currently queue forever with 0 runners) |
| Add an aggregate `CodeQL status` job before making CodeQL a required check | `@JourneyOfLife` | Adding CodeQL to required status checks |

### Decisions recorded 2026-09-09

- **Mailbox**: `security@viavitae.site` chosen over `viavitae.org` (existing GoDaddy MX) and no-email. Rationale: full control over the domain, matches the domain already in SECURITY.md scope. Owner action: add MX records, create mailbox, publish PGP key.
- **Runner**: Register EU self-hosted runner now. Rationale: `security.yml` Gate 8 writes `AGE_SECRET_KEY_CI` to the runner (EEA residency constraint per QODER.md Rule 7); GitHub-hosted runners are outside the EEA. Owner action: create VM in Proxmox EU cluster, install runner software, register with org.

## Break-glass log

| Date | Action | Reason | Operator |
|------|--------|--------|----------|
| 2026-09-09 | Disabled `enforce_admins`, merged PR #5 via `gh pr merge --admin`, restored full protection | Sole-owner bootstrap: CODEOWNERS fix could not be reviewed by a second CODEOWNER because @IterVitae has no write access yet. This is the only PR that establishes the governance model itself; subsequent PRs will be reviewable once @IterVitae is granted access. | @JourneyOfLife |
| 2026-09-09 | Disabled `enforce_admins`, pushed commit `16b5457` directly to `main`, restored full protection | Factual ADR record appended as part of the break-glass procedure above. Not a governance change; documents what already happened. | @JourneyOfLife |

## References

- [`docs/runbooks/branch-protection.md`](../runbooks/branch-protection.md) — protection
  configuration and the admin-bypass merge procedure this ADR puts under disclosure
- [`SECURITY.md`](../../SECURITY.md) — disclosure channel and breach workflow
- [`.github/CODEOWNERS`](../../.github/CODEOWNERS) — ownership map
- [`QODER.md`](../../QODER.md) — Rule 3 (ask before permissions-model changes) and Rule 7
  (compliance stop-conditions)
- [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
  — required approvals must come from reviewers with write permissions
- [About code owners](https://docs.github.com/en/repositories/managing-your-repositories-settings-and-configuration/customizing-your-repository/about-code-owners)
  — valid principals, and the write-access requirement for teams
- Regulation (EU) 2016/679 Art. 37(1), Art. 37(4), Art. 38(6), Art. 9, Art. 33, Art. 34
