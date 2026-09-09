# Licence Policy — viavitae-infra

**Status:** Active  
**Last reviewed:** 2026-09-08

---

## Allowed Licences

The following licences are pre-approved for use in dependencies:

| Licence | SPDX ID | Notes |
|---|---|---|
| MIT | `MIT` | Permissive, weak copyleft |
| Apache 2.0 | `Apache-2.0` | Permissive, patent grant |
| BSD 2-Clause | `BSD-2-Clause` | Permissive |
| BSD 3-Clause | `BSD-3-Clause` | Permissive |
| ISC | `ISC` | Permissive |
| CC0 1.0 | `CC0-1.0` | Public domain dedication |
| Unlicense | `Unlicense` | Public domain dedication |
| 0BSD | `0BSD` | Permissive |
| Python 2.0 | `Python-2.0` | Permissive |
| PSF 2.0 | `PSF-2.0` | Permissive |
| Proprietary | `Proprietary` | First-party only (ViaVitae code) |

## Forbidden Licences

The following licences are **blocked** due to copyleft or commercial restrictions:

| Licence | SPDX ID | Reason |
|---|---|---|
| GPL 2.0 | `GPL-2.0` | Strong copyleft, viral |
| GPL 3.0 | `GPL-3.0` | Strong copyleft, viral |
| AGPL 3.0 | `AGPL-3.0` | Strong copyleft, network viral |
| SSPL 1.0 | `SSPL-1.0` | Commercial restriction (MongoDB) |
| BUSL 1.1 | `BUSL-1.1` | Commercial restriction (Elastic) |
| CDDL 1.0 | `CDDL-1.0` | File-level copyleft, incompatible with Apache |

## Weak Copyleft (Review Required)

| Licence | SPDX ID | Policy |
|---|---|---|
| MPL 2.0 | `MPL-2.0` | **Allowed with review** — file-level copyleft, compatible with Apache. Used by Terraform providers. Pre-approved for infrastructure use, but each new MPL dependency must be reviewed for compatibility. |
| EPL 2.0 | `EPL-2.0` | **Review required** — weak copyleft, used by some Java projects |
| LGPL 2.1 | `LGPL-2.1` | **Review required** — weak copyleft, linking exception |

---

## Enforcement

The licence gate in [`.github/workflows/compliance-check.yml`](../.github/workflows/compliance-check.yml) enforces this policy:

- **Allowed licences** pass automatically
- **Forbidden licences** fail the build
- **Unknown licences** fail the build until reviewed
- **Weak copyleft** licences require manual review (comment in PR)

---

## Adding a New Dependency

When adding a new dependency:

1. Check the licence against the tables above
2. If **allowed**: proceed, no action needed
3. If **weak copyleft**: add a comment in the PR explaining compatibility
4. If **forbidden** or **unknown**: choose an alternative, or request a licence review from `@Via-Vitae/legal`

---

## References

- [ADR-009: Licence position for the infrastructure stack](../docs/architecture.md#adr-009-licence-position-for-the-infrastructure-stack)
- [compliance-check.yml](../.github/workflows/compliance-check.yml) (licence gate)
