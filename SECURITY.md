# Security Policy

ViaVitae IT Technologies takes the security of its systems and the privacy of the people
it serves seriously. This policy describes how to report a vulnerability, what to expect
from us, and the protections we extend to good-faith researchers.

## Reporting a vulnerability

**Please do not open a public GitHub issue.** Public disclosure before a fix is available
puts users at risk.

| Channel | Detail |
| --- | --- |
| **Email** | `security@viavitae.com` |
| **Encryption** | Strongly encouraged. Our PGP public key is published on the [OpenPGP key servers](https://keys.openpgp.org/search?q=security%40viavitae.com); fetch and verify the fingerprint out of band before first use. |
| **GitHub** | Private vulnerability reporting is enabled on repositories in the `Via-Vitae` organisation. Use *Security* -> *Report a vulnerability* when available. |

Include as much of the following as you can:

1. The type of issue (for example: SQL injection, broken access control, secret exposure,
   dependency vulnerability, misconfigured storage).
2. The affected repository, and the branch, tag or commit SHA.
3. The affected environment (production, staging, demo tenant) and URL or host.
4. Step-by-step instructions to reproduce the issue.
5. Proof of concept, exploit code, or a screenshot where it helps.
6. The impact you believe the issue has, and who is affected.
7. Whether you have already accessed, stored or altered any personal data. If you have,
   say so explicitly and stop — we will take over handling under the breach process below.

Please do not access, exfiltrate, modify or delete data belonging to other users beyond
the minimum needed to demonstrate the issue, and do not use an exploit to maintain
persistent access.

## Response service levels

### Acknowledgement and triage

| Stage | Target |
| --- | --- |
| **Acknowledgement** | Within **24 hours** of receipt. |
| **Triage and severity assignment** | Within **72 hours** of receipt. |
| **Status update cadence** | At least every 5 business days until closure. |
| **Researcher notification of fix** | Within 5 business days of deployment. |

If you have not received an acknowledgement within 24 hours, resend to the same address
and copy `legal@viavitae.com`. Email delivery failures happen, and we would rather receive
a duplicate than lose a report.

### Remediation SLA

Severity is assigned during triage using CVSS v3.1 as a starting point, adjusted for
exploitability, the sensitivity of the data involved and whether the affected system holds
personal data.

| Severity | CVSS | Containment | Remediation | Public advisory |
| --- | --- | --- | --- | --- |
| **Critical** | 9.0 - 10.0 | **72 hours** | 7 days | Within 5 business days of fix |
| **High** | 7.0 - 8.9 | 72 hours | **7 days** | Within 10 business days of fix |
| **Medium** | 4.0 - 6.9 | Best effort | **30 days** | At next scheduled release |
| **Low** | 0.1 - 3.9 | Best effort | Next scheduled release | Optional |

**Containment** means the immediate action that stops active exploitation — disabling an
endpoint, rotating a credential, revoking a token, blocking a route, or taking a demo
tenant offline. **Remediation** means the durable fix, with a regression test, merged and
deployed.

Where a Critical or High issue cannot be remediated within the SLA, the security team
records the reason, the compensating control and a revised date as an ADR in
`docs/architecture.md`, and notifies the compliance team.

## GDPR breach notification workflow

A confirmed security incident involving personal data is handled under Regulation (EU)
2016/679 in parallel with technical remediation. The two tracks run concurrently; neither
waits for the other.

1. **Detect and log.** The incident is recorded with the time of awareness. This timestamp
   starts the statutory clock.
2. **Assess within 24 hours.** The Data Protection Officer assesses whether the incident
   is a personal data breach under Article 4(12), and its likely risk to the rights and
   freedoms of data subjects.
3. **Notify the supervisory authority within 72 hours** of becoming aware, where the breach
   is likely to result in a risk to data subjects, per Article 33. For the Lithuanian
   pilot the competent authority is the State Data Protection Inspectorate (Valstybinė
   duomenų apsaugos inspekcija). Where 72 hours is not met, the notification includes the
   reasons for the delay.
4. **Notify data subjects without undue delay** where the breach is likely to result in a
   high risk to them, per Article 34, in clear and plain language.
5. **Record internally** in every case, including where no notification is made: the facts,
   the effects, and the remedial action taken, per Article 33(5). The record is retained
   for review by the supervisory authority.
6. **Close the loop.** The DPIA for the affected processing is revisited under Article 35(7)
   and, where the breach reveals an architectural weakness, an ADR records the decision.

The DPO (`dpo@viavitae.com`) owns steps 2 to 5. The security team owns technical
containment and remediation and provides the factual record.

## Safe harbour for good-faith research

We will not initiate legal action against a researcher who:

- reports a vulnerability promptly through the channels above, and does not disclose it
  publicly before a fix is deployed or before 90 days have elapsed, whichever is sooner;
- accesses only the minimum data necessary to demonstrate the issue, and does not access,
  modify, exfiltrate or delete data belonging to other users;
- performs testing only against accounts and demo tenants they own or control, and not
  against production data belonging to third parties;
- avoids techniques that degrade service for others — no denial of service, no spamming,
  no social engineering of staff or clergy, no physical intrusion;
- does not use an obtained vulnerability to maintain persistent access or to move laterally
  beyond the initial finding;
- acts in good faith and does not seek compensation beyond any published bounty terms.

If you follow these conditions, we consider your research authorised, we will work with you
to understand and resolve the issue quickly, and we will not pursue a complaint under
computer-misuse legislation. Where an inadvertent breach of these conditions occurs, tell us
in your report and we will assess it in good faith.

This safe harbour does not extend to a third party who receives a report and discloses it
without consent, nor to any activity that is independently unlawful.

## Scope

In scope for reporting under this policy:

| Scope | Detail |
| --- | --- |
| **Repositories** | All repositories in the `Via-Vitae` GitHub organisation, including public, private and internal repositories, their CI/CD configuration, and their build and deployment artefacts. |
| **Domains and subdomains** | All `*.viavitae.com` hosts, including demo tenant subdomains provisioned by `viavitae-infra` and `viavitae-clients`. |
| **Marketplace** | `jolarca.com` and the `jolarca` repository, including the vendor dashboard and vendor onboarding and KYC flows. |
| **Infrastructure** | Self-hosted Proxmox, k3s and Terraform-managed resources, where testing is coordinated with us in advance. |
| **Third parties** | Processors and subprocessors acting on our behalf, where the issue arises from our configuration or use of them. |

Out of scope: findings that require physical access to a device or premises, findings in a
browser or operating system unrelated to our code, reports that consist only of missing
security headers without a demonstrated impact, rate limiting on unauthenticated endpoints
without a demonstrated abuse case, and issues in a third-party service that you have not
been authorised by that service to test.

## Supported versions

Security fixes are delivered on the default branch of each repository. Tagged releases
receive fixes according to the table below.

| Version | Supported |
| --- | --- |
| Latest release on `main` | Yes — all severities |
| Previous minor release | Yes — Critical and High only, for 90 days after the next release |
| Older releases | No — upgrade required |

Because repositories in this organisation are deployed continuously from `main`, the
deployed production version is normally the latest. If you are running an older tag,
upgrade before reporting a finding that has already been fixed.

## Contact

| Role | Contact |
| --- | --- |
| Security team | `security@viavitae.com` |
| Data Protection Officer | `dpo@viavitae.com` |
| Legal | `legal@viavitae.com` |

This policy is reviewed at least annually, and after any Critical severity incident.
Changes are recorded in `CHANGELOG.md`.
