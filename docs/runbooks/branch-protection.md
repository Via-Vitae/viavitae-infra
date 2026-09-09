# Branch Protection Runbook

**Audience.** Platform engineer configuring GitHub branch protection rules. **Prerequisites:** GitHub org admin or repo admin access.

---

## Purpose

This runbook documents the exact branch protection settings for the `main` branch of `viavitae-infra`. These settings enforce the quality gates defined in CI workflows and prevent unauthorized changes to protected paths.

---

## Branch Protection Rules for `main`

### Required status checks

The following workflows must pass before a PR can merge:

| Check | Workflow | Purpose |
|---|---|---|
| `CI status` | `ci.yml` | Aggregate gate for lint, SAST, dependency scan, preflight |
| `Compliance` | `compliance-check.yml` | Gitleaks, licence check, governance files, action SHA pinning, SOPS placeholder check |
| `CodeQL` | `codeql.yml` | Static analysis (Python, JavaScript/TypeScript) |

**How to configure:**

1. Go to **Settings** → **Branches** → **Branch protection rules**
2. Click **Add rule** (or edit existing rule for `main`)
3. Branch name pattern: `main`
4. Enable **Require status checks to pass before merging**
5. Enable **Require branches to be up to date before merging**
6. Add the following status checks:
   - `CI status`
   - `Compliance`
   - `CodeQL`

### Required reviewers

- **Require pull request reviews before merging:** ✅ Enabled
- **Required number of approvals:** 1 (default)
- **Dismiss stale pull request approvals when new commits are pushed:** ✅ Enabled
- **Require review from Code Owners:** ✅ Enabled (enforces CODEOWNERS)

**Special paths requiring additional reviewers:**

| Path | Required reviewers |
|---|---|
| `/.github/workflows/` | `@Via-Vitae/platform`, `@Via-Vitae/security` |
| `/terraform/**/backend.tf` | `@Via-Vitae/platform`, `@Via-Vitae/security`, `@Via-Vitae/architects` |
| `/.sops.yaml` | `@Via-Vitae/platform`, `@Via-Vitae/security`, `@Via-Vitae/compliance` |
| `/.sops-recipients.allowlist` | `@Via-Vitae/platform`, `@Via-Vitae/security`, `@Via-Vitae/compliance` |
| `/docs/DPIA-*.md` | `@Via-Vitae/compliance`, `@Via-Vitae/dpo` |

These are enforced automatically by CODEOWNERS — GitHub requests reviews from the listed teams when these paths are changed.

### Security workflow (conditional)

**⚠️ Do NOT add `security.yml` as a required check yet.**

The `security.yml` workflow (Gate 7/8 SOPS verification) will fail until:
1. Real age keys replace the placeholders in `.sops.yaml`
2. `AGE_SECRET_KEY_CI` is set in GitHub Secrets
3. The vault files are encrypted

**When to add `security.yml` as a required check:**

1. Complete WS2.2 (update `.sops.yaml` with real keys)
2. Complete WS2.3 (encrypt vault files)
3. Set `AGE_SECRET_KEY_CI` in GitHub Secrets
4. Wait for the first green run of `security.yml` on `main`
5. Then add `Security` to the required status checks

**How to add `security.yml` later:**

1. Go to **Settings** → **Branches** → **Branch protection rules** → Edit `main`
2. Add `Security` to the required status checks
3. Commit the change in a separate PR (so the change is auditable)

---

## Additional protections

### Restrict pushes

- **Restrict who can push to matching branches:** ✅ Enabled
- **Allowed pushers:** `@Via-Vitae/platform` (or leave blank to allow anyone with write access)

### Require signed commits

- **Require signed commits:** ✅ Enabled (optional, but recommended)

This ensures all commits are GPG-signed, providing non-repudiation.

### Include administrators

- **Do not allow bypass rules for administrators:** ✅ Enabled

This ensures even org admins must go through the PR process — no direct pushes to `main`.

---

## Verification

After configuring branch protection, verify the settings:

```bash
# Using GitHub CLI
gh api repos/Via-Vitae/viavitae-infra/branches/main/protection | jq '.required_status_checks.contexts'

# Expected output:
# [
#   "CI status",
#   "Compliance",
#   "CodeQL"
# ]
```

---

## Workflow-specific notes

### ci.yml

- Runs on every PR and push to `main`
- The `ci-status` job is the aggregate gate — it fails if any required job fails
- Skipped jobs (e.g., Python tests when no Python code changed) count as passing

### compliance-check.yml

- Runs on every PR and push to `main`, plus weekly schedule
- The `sops-check` job will fail until placeholders are replaced (WS2.2)
- The `action-pinning` job enforces 40-char SHA pinning for all GitHub Actions

### codeql.yml

- Runs on every PR and push to `main`, plus weekly schedule
- Analyzes Python and JavaScript/TypeScript code
- Uploads SARIF results to GitHub Security tab

### security.yml

- Runs on every PR and push to `main`, plus weekly schedule
- **Gate 7:** Diffs `.sops.yaml` against `.sops-recipients.allowlist` — will pass once both are updated with real keys
- **Gate 8:** Encrypts with real recipients, decrypts with `AGE_SECRET_KEY_CI` — will pass once real keys are provisioned and the CI secret is set
- **Binary smoke test:** Non-gating (continue-on-error), proves the SOPS binary works
- **Encryption coverage:** Asserts all SOPS-governed files are encrypted — will pass once vaults are encrypted (WS2.3)

### deploy.yml

- **Plan job:** Runs on every PR (read-only credentials, no environment gate)
- **Apply job:** Manual dispatch only, requires GitHub Environment approval
  - `dev-apply`, `staging-apply`, `prod-apply` environments
  - `prod-apply` requires ≥2 reviewers and a 5-minute wait timer
- **Drift job:** Nightly cron, detects state drift

---

## Troubleshooting

### "Required status check is expected"

**Cause:** A required check did not run (e.g., the workflow was skipped).

**Fix:**
- Check the workflow file — ensure the job runs on PRs to `main`
- If the job is conditional (e.g., `if: needs.setup.outputs.has_terraform == 'true'`), ensure the condition is met

### "Pull request is not mergeable"

**Cause:** Required reviewers have not approved, or stale approvals need to be dismissed.

**Fix:**
- Request reviews from the required teams (CODEOWNERS)
- If new commits were pushed, reviewers must re-approve

### "You require Code Owner review, but the Code Owners file is invalid"

**Cause:** CODEOWNERS file has syntax errors or references non-existent teams.

**Fix:**
- Validate CODEOWNERS syntax: `*` must have at least one owner
- Ensure team names match GitHub org teams (e.g., `@Via-Vitae/platform`)

---

## References

- [CODEOWNERS](../.github/CODEOWNERS)
- [CONTRIBUTING.md](../CONTRIBUTING.md) (PR process)
- [docs/audit-plan.md](audit-plan.md) (WS2.6)
