# Data Protection Impact Assessment (DPIA)

Template and register for assessments required under **Article 35 of Regulation (EU)
2016/679 (GDPR)**.

A DPIA is completed **before** processing starts, not after. Under rule R5 in
`README.md`, a pull request that introduces processing of personal data without a
reference to a completed DPIA is blocked at review. Under QODER rule 7, a request to begin
processing before the assessment is complete halts work rather than being worked around.

The DPO owns this register: `dpo@viavitae.com`.

---

## When a DPIA is required

Article 35(1) requires an assessment where processing is likely to result in a **high risk**
to the rights and freedoms of natural persons. Article 35(3) makes it mandatory for:

- systematic and extensive automated evaluation producing legal or similarly significant
  effects, including profiling;
- large-scale processing of special category data under Article 9, or of data relating to
  criminal convictions and offences under Article 10;
- large-scale systematic monitoring of a publicly accessible area.

The European Data Protection Board's "list of processing operations requiring a DPIA", and
the national list published by the State Data Protection Inspectorate
(Valstybinė duomenų apsaugos inspekcija) for the Lithuanian pilot, add criteria. As a
working rule, **two or more** of the following means a DPIA is required:

| # | Criterion |
| --- | --- |
| 1 | Evaluation or scoring, including profiling and predicting behaviour |
| 2 | Automated decision-making with legal or similarly significant effect |
| 3 | Systematic monitoring of data subjects |
| 4 | Sensitive data or data of a highly personal nature, including religious belief |
| 5 | Data processed on a large scale |
| 6 | Matching or combining datasets from different sources |
| 7 | Data concerning vulnerable data subjects, including children and people in a relationship of dependency |
| 8 | Innovative use or application of new technology, including AI |
| 9 | Processing that prevents data subjects from exercising a right or using a service or contract |

For ViaVitae, criteria 4, 7 and 8 are engaged by default: the organisation serves religious
communities, so religious belief is inherently in scope; parishioners and clergy are in a
relationship of dependency with their parish; and the pastoral assistant applies AI to that
data. **Assume a DPIA is required** for any new feature in this domain and record the
reasoning if you conclude otherwise.

## Numbering convention

- Format: `DPIA-NNN`, zero-padded to three digits, allocated sequentially from the register
  below.
- Numbers are never reused. A withdrawn assessment remains in the register with its status,
  so a link from an old pull request continues to resolve.
- The DPIA number is referenced from the pull request description, from the ADR that
  records the related architectural decision, and from the record of processing activities.
- One DPIA covers one coherent processing operation. A feature that both collects new data
  and applies automated evaluation to it may need two.
- **Infrastructure records use a separate `INFRA-NNN` series.** Platform processing — logs,
  metrics, monitoring labels, identity stores, backups, Terraform state and the CI control
  plane — is assessed here rather than in the application DPIA series, because its controller,
  its retention schedule and its reviewers are different, and because a runbook or an ADR
  needs to cite it without implying that a product feature was assessed. `INFRA-NNN` numbers
  are allocated from the same register below and follow the same rules.

## Status values

| Status | Meaning |
| --- | --- |
| `Draft` | Being written. Processing must not start. |
| `In review` | With the DPO. Processing must not start. |
| `Approved` | Signed off. Processing may start within the agreed conditions. |
| `Approved with conditions` | Processing may start only once the listed conditions are met and verified. |
| `Requires update` | A change has invalidated the assessment. Processing continues only if the change is minor and the DPO agrees; otherwise it pauses. |
| `Prior consultation required` | Residual high risk remains. Article 36 consultation with the supervisory authority is needed before processing starts. |
| `Withdrawn` | The processing did not proceed. Kept for history. |

---

## Register

| DPIA | Processing operation | Status | Residual risk | Owner | Approved | Review due |
| --- | --- | --- | --- | --- | --- | --- |
| [DPIA-001](#dpia-001-assessment-funnel) | Assessment funnel — enquiry capture and quotation | Approved with conditions | Medium | Product | 2026-08-21 | 2027-08-21 |
| [DPIA-002](#dpia-002-ai-pastoral-assistant) | AI pastoral assistant with a human approval queue | Approved with conditions | High | Product | 2026-09-02 | 2027-03-02 |
| [INFRA-001](#infra-001-infrastructure-platform-processing) | Infrastructure platform — logs, metrics, identity, state, backups and CI | Approved with conditions | Medium-High | Platform | 2026-09-06 | 2027-03-06 |
| _INFRA-002_ | _Bitrix24 on-premises — reserved by ADR-007 condition 8; must be completed before the `prod` VM is created_ | Draft | — | Security | — | — |
| _DPIA-003_ | _next available number_ | — | — | — | — | — |

Review cadence: annually, or immediately on any material change to purpose, scope, data
categories, recipients, retention, technology or residency. Assessments carrying a High
residual risk are reviewed at least every six months.

---

## DPIA template

Copy everything below the line into a new section, assign the next number from the register,
and add the register row in the same pull request. All nine sections are mandatory; write
"not applicable" with a reason rather than leaving one blank.

```markdown
## DPIA-NNN: <processing operation name>

| Field | Value |
| --- | --- |
| Status | Draft |
| Assessment owner | <role> |
| Version | 1.0 |
| Date started | <YYYY-MM-DD> |
| Related ADR | <ADR-NNN or not applicable> |
| Repositories affected | <list> |

### 1. Description of processing

### 2. Necessity and proportionality

### 3. Lawful basis

### 4. Data flows and storage locations

### 5. Risk assessment

### 6. Mitigations and technical measures

### 7. DPO and processor consultation record

### 8. Residual risk and sign-off

### 9. Review date
```

The nine sections are specified in full below, each with the questions that must be
answered. The two worked examples that follow — DPIA-001 and DPIA-002 — show the expected
level of detail.

### Section 1 — Description of processing

State the **purpose**, the **data subjects** and the **data categories**.

- What is the processing, in one paragraph a non-technical reader can follow?
- What is the specific purpose? If there are several purposes, list each separately — a
  single DPIA cannot blur two purposes into one, because each needs its own lawful basis.
- Who are the data subjects? Are any of them children, or otherwise vulnerable, or in a
  relationship of dependency with the controller (parishioners relative to a parish, for
  example)?
- What categories of personal data? Distinguish ordinary data from Article 9 special
  categories. Religious belief, health, sex life and orientation, ethnic origin, political
  opinion, trade union membership, genetic and biometric data are all special categories.
- What is the volume, and how many data subjects?
- What is the source? Collected directly from the subject, or obtained from a third party?
- Who are the recipients, internal and external?
- How long is each category retained, and what happens at the end of retention?
- Is any automated decision-making or profiling involved, and does it produce legal or
  similarly significant effects under Article 22?

### Section 2 — Necessity and proportionality

Demonstrate that the processing is the least intrusive means of achieving the purpose.

- Why is this processing necessary for the stated purpose? What happens if it is not done?
- What alternatives were considered, including doing nothing, and why were they rejected?
- Is each data category collected the minimum required? For each category that is not
  obviously necessary, justify it individually.
- Could the purpose be met with pseudonymised or aggregated data instead?
- Could the purpose be met without special category data?
- Is retention limited to what the purpose requires, rather than to what storage allows?
- Are data subjects informed, in plain language, at the point of collection?
- Can data subjects exercise access, rectification, erasure, restriction, portability and
  objection against this processing, and how, concretely?
- Is any onward transfer to a processor limited to what that processor needs?

### Section 3 — Lawful basis

Identify the **Article 6** basis for each purpose, and the **Article 9** condition for any
special category data.

Article 6 bases: consent (6(1)(a)); contract (6(1)(b)); legal obligation (6(1)(c)); vital
interests (6(1)(d)); public task (6(1)(e)); legitimate interests (6(1)(f)).

- Which basis applies to which purpose? One basis per purpose.
- If **consent**: how is it obtained, is it freely given, specific, informed and unambiguous,
  is it recorded, and how is withdrawal handled in practice, including deletion of data
  already collected?
- If **legitimate interests**: record the three-part test — what is the legitimate interest,
  why is the processing necessary for it, and why do the interests or fundamental rights of
  the data subject not override it. Include the balancing outcome and note that the right to
  object under Article 21 applies.
- If **contract**: confirm the processing is genuinely necessary for a contract with the
  data subject, not merely convenient. Bundling unnecessary processing into terms of service
  does not make it necessary.
- Is a special category involved? If so, which **Article 9(2)** condition applies — explicit
  consent (9(2)(a)), employment and social security (9(2)(b)), vital interests (9(2)(c)),
  data manifestly made public by the subject (9(2)(e)), legal claims (9(2)(f)), substantial
  public interest (9(2)(g)), health or social care (9(2)(h)), public health (9(2)(i)), or
  research and statistics (9(2)(j))?
- For religious belief specifically: note that data about a person's participation in a
  religious community may reveal belief even where belief is not recorded directly. Consider
  inference risk, not only declared fields.
- Is Article 22 engaged? If a decision is solely automated and produces legal or similarly
  significant effects, it is permitted only under 22(2), and for special category data only
  with an Article 9 condition plus suitable safeguards including human intervention.
- Is the basis recorded in the record of processing activities and in the privacy notice?

### Section 4 — Data flows and storage locations

**Personal data must remain inside the EEA.** This is a ViaVitae constraint, not only a
GDPR one, and it is a QODER rule 7 stop-condition.

- Draw or describe the flow end to end: collection point, transport, processing, storage,
  backup, archive, deletion.
- For every store and every processor, name the **physical location** — data centre, region,
  country. "EU" is not a location; "Frankfurt, DE" is.
- Where are backups held, where are logs held, where are analytics held, and where do error
  reports go? Logs and error trackers are the most common source of accidental export,
  because a stack trace can carry personal data to a third-party service in another
  jurisdiction.
- Is any transfer outside the EEA proposed? If so, stop. Record the reason, and either find
  an EEA alternative or record an adequacy decision, appropriate safeguards under Article 46
  and a transfer impact assessment, then obtain DPO and legal approval before proceeding.
- Which subprocessors are involved? For each: name, role, location, DPA in place, and the
  Article 28(3) terms relied on.
- Is the data encrypted in transit and at rest? Which ciphers or protocols, and who holds
  the keys?
- Who has access, by role, and how is access reviewed?
- How does the flow support erasure, including in backups, replicas, logs and downstream
  processors?

### Section 5 — Risk assessment

Assess risk to the **rights and freedoms of data subjects** — not risk to the organisation.
Score each risk before mitigation using the matrix below.

Likelihood and severity are each scored 1 to 5. The product gives the inherent risk rating.

| Likelihood × Severity | 1 Negligible | 2 Minor | 3 Moderate | 4 Significant | 5 Severe |
| --- | --- | --- | --- | --- | --- |
| **5 Almost certain** | 5 Medium | 10 High | 15 High | 20 Critical | 25 Critical |
| **4 Likely** | 4 Low | 8 Medium | 12 High | 16 Critical | 20 Critical |
| **3 Possible** | 3 Low | 6 Medium | 9 Medium | 12 High | 15 High |
| **2 Unlikely** | 2 Low | 4 Low | 6 Medium | 8 Medium | 10 High |
| **1 Rare** | 1 Low | 2 Low | 3 Low | 4 Low | 5 Medium |

| Rating | Band | Required response |
| --- | --- | --- |
| 1 to 4 | Low | Accept and record. Revisit at review. |
| 5 to 9 | Medium | Mitigate where proportionate; record the decision either way. |
| 10 to 14 | High | Mitigation mandatory before processing starts. DPO sign-off required. |
| 15 to 25 | Critical | Do not proceed. Mitigate and reassess, or consult the supervisory authority under Article 36. |

Consider at least these harms: unauthorised disclosure; loss of confidentiality of belief,
health or family circumstances; discrimination or stigmatisation, including within a
community; damage to reputation; financial loss; identity theft; loss of control over one's
own data; chilling effects on freedom of religion or association; emotional distress;
physical safety risk where affiliation or location is exposed; and the consequences of an
incorrect automated decision.

Record each risk as: identifier, description, who is harmed, likelihood, severity, inherent
rating, and the mitigations that address it in section 6.

### Section 6 — Mitigations and technical measures

For each risk in section 5, state the measure, who owns it, and how its operation is
verified. A mitigation that cannot be verified is an intention, not a control.

Cover at minimum:

- **Data minimisation** — which fields were removed as unnecessary, and at what stage.
- **Pseudonymisation and anonymisation** — what is separated from what, and where the linking
  key is held.
- **Encryption** — in transit (protocol and minimum version) and at rest (mechanism, key
  custody, rotation).
- **Access control** — role-based, least privilege, MFA for all access to personal data,
  quarterly access review, immediate revocation on role change or departure.
- **Logging and monitoring** — what access is logged, retention of audit logs, alerting on
  anomalous bulk export.
- **Retention and deletion** — the schedule per category, the automated mechanism that
  enforces it, and how backups age out.
- **Human oversight** — where automated output is reviewed by a person with authority to
  change it, as required by Article 22(3) and good practice everywhere else.
- **Accuracy** — how a data subject corrects their own data, and how incorrect automated
  output is detected and reversed.
- **Transparency** — the privacy notice, the point-of-collection notice, and plain-language
  explanation of any automated decision.
- **Processor management** — DPAs, sub-processor notification, audit rights, exit and
  deletion obligations.
- **Breach readiness** — detection path, the 72-hour Article 33 workflow in `SECURITY.md`,
  and who is called.
- **Testing** — which controls are tested, how often, and by whom.
- **Privacy by design and by default** — the settings a data subject gets without asking,
  which must be the most protective available.

### Section 7 — DPO and processor consultation record

Article 35(2) requires the controller to **seek the views of the DPO** where one is
designated. Record the consultation whether or not the advice is followed; if it is not
followed, record why.

- Date the DPO was consulted, and by whom.
- The DPO's advice, summarised faithfully, including any objection.
- Whether the advice was followed; if not, the documented reason.
- Views of data subjects or their representatives, where sought. Article 35(9) requires the
  controller to seek them where appropriate. For a parish system this may mean consulting
  clergy and a lay representative, and recording why direct consultation of parishioners was
  or was not proportionate.
- Processor consultations: which processors were consulted, on what, and the outcome.
- Whether Article 36 prior consultation with the supervisory authority is required. It is
  required where residual high risk remains after mitigation. Note the date of submission
  and the authority's response.

### Section 8 — Residual risk and sign-off

Re-score each risk after mitigation and state the **residual** rating using the same matrix.

- Overall residual risk rating, and whether it is acceptable.
- Can the processing proceed? Yes; yes with conditions; or no, prior consultation required.
- If yes with conditions, list each condition, its owner and its deadline. Processing starts
  only when every condition is met and verified.
- Whether the residual risk has changed the Article 6 basis, the retention period or the
  privacy notice.

Sign-off requires the assessment owner, the business owner accountable for the processing,
the DPO, and — where special category data or automated decision-making is involved — the
architects. Names and signatures are recorded here in the signed copy held in the register;
a DPIA without a named signatory has not been approved.

### Section 9 — Review date

- The next scheduled review date, and the trigger conditions that force an earlier review.
- Review is mandatory immediately on: a change of purpose; a new data category; a new
  recipient or processor; a change of storage location; a change of retention; introduction
  of new technology or a new model; a personal data breach affecting this processing; a
  supervisory-authority decision or guidance change; or a data subject complaint revealing a
  risk not previously assessed.
- High residual risk is reviewed at least every six months. Everything else at least
  annually.
- Who performs the review, and how the outcome is recorded: a new version number, a changed
  status, and an updated register row.
- Confirmation that the record of processing activities and the privacy notice were updated
  to match.

---

## DPIA-001: Assessment funnel

| Field | Value |
| --- | --- |
| Status | Approved with conditions |
| Assessment owner | Product |
| Version | 1.2 |
| Date started | 2026-07-28 |
| Related ADR | ADR-001 |
| Repositories affected | `viavitae-web`, `viavitae-api`, `viavitae-infra`, `viavitae-docs` |

### 1. Description of processing

The assessment funnel lets a parish or diocese describe its current digital presence and
receive a scoped proposal and indicative quotation. A visitor answers a guided set of
questions across several steps; the answers are stored, scored against a rules table, and
turned into a proposal that a ViaVitae staff member reviews before it is sent.

- **Purpose.** To assess a prospective client's needs and produce a quotation. A secondary
  purpose is aggregate service improvement, which is assessed separately and does not rely
  on this record.
- **Data subjects.** Clergy, parish administrators, diocesan staff and lay volunteers who
  complete the form on behalf of their community. They act in a professional capacity, but
  several fields reveal the affiliation of a religious community, so they are treated as
  data subjects whose Article 9 data may be engaged rather than as purely business contacts.
- **Data categories.** Name; role; work email address; work telephone number; parish or
  organisation name; diocese or denomination; country; website address; existing systems in
  use; congregation size band; free-text description of needs; whether the community
  currently handles donations, and roughly what volume; IP address and user agent at
  submission, for abuse prevention only; submission timestamp.
- **Special category data.** Not collected deliberately. **Denomination and parish
  affiliation reveal religious belief by inference**, and free-text answers may disclose
  belief, health or family circumstances about third parties. The whole dataset is therefore
  handled as Article 9 data.
- **Volume.** Approximately 40 to 60 enquiries per month during the Lithuanian pilot.
- **Source.** Directly from the data subject.
- **Recipients.** ViaVitae product and sales staff on a need-to-know basis; no external
  recipients. The hosting provider processes storage under a DPA.
- **Retention.** Enquiries that become clients: duration of the relationship plus 7 years
  for accounting records under Lithuanian law. Enquiries that do not: 12 months from
  submission, then deleted. Abuse-prevention IP data: 30 days.
- **Automated decision-making.** Scoring prioritises the queue and suggests a scope. It does
  not produce a legal or similarly significant effect, because a person reviews and may
  change every proposal before it is sent, and no enquiry is rejected automatically.
  Article 22 is not engaged. The human reviewer's decision is recorded against each
  proposal.

### 2. Necessity and proportionality

- **Necessity.** A quotation cannot be scoped without knowing what the community currently
  has and what it needs. Telephone-only assessment was considered and rejected: it does not
  scale, it produces inconsistent scoping between staff, and it leaves no auditable record
  of what was asked.
- **Alternatives considered.** (a) An unstructured email inbox — rejected, because it
  collects unbounded personal data in free text with no retention control and no ability to
  answer an access request reliably. (b) A downloadable form returned by post — rejected,
  because it lengthens the cycle and creates paper copies outside any access-control regime.
  (c) Anonymous enquiry with contact details requested only after a human replies —
  **adopted in part**: contact details are collected at the final step rather than the
  first, so a visitor who abandons the funnel leaves no identifying data behind.
- **Minimisation applied.** Date of birth removed — not needed. Personal social media
  removed. Exact congregation headcount replaced with a band, because the band is sufficient
  for scoping. Postal address removed; country and diocese are sufficient. Payment details
  are never collected at this stage.
- **Pseudonymisation.** Abandoned funnels hold no direct identifier, because identifiers
  are collected last. Completed submissions are stored with the contact record separated
  from the assessment answers by a surrogate key, so a scoped proposal can be generated
  without exposing the contact to the scoring service.
- **Transparency.** A privacy notice is linked at the first step and displayed in full
  before submission, in Lithuanian, English and Russian. It names the controller, the
  purposes, the lawful basis, the retention period, the recipients and the rights available.
- **Rights.** Access, rectification, erasure, restriction, portability and objection are
  exercisable through `dpo@viavitae.com`. Erasure is refused only where the 7-year
  accounting obligation applies, and the refusal is explained with the legal citation.

### 3. Lawful basis

| Purpose | Article 6 basis | Reasoning |
| --- | --- | --- |
| Responding to an enquiry and producing a quotation | 6(1)(b) contract | Necessary for steps taken at the data subject's request prior to entering a contract. |
| Retaining the quotation and related correspondence after a contract is signed | 6(1)(c) legal obligation | Accounting and tax record-keeping obligations under Lithuanian law, 7 years. |
| Abuse prevention on the submission endpoint | 6(1)(f) legitimate interests | See the balancing test below. |
| Retaining an enquiry that does not convert, for 12 months | 6(1)(f) legitimate interests | See the balancing test below. |

**Legitimate interests balancing test, abuse prevention.** The interest is protecting the
service from automated spam and submission abuse, which would otherwise degrade a service
used by small volunteer-run parishes. Processing is limited to IP address and user agent,
retained 30 days, used only for rate limiting and blocklisting, and never combined with
other datasets or used for profiling. The impact on the data subject is minimal and
expected of any web form. The interest is not overridden. The right to object is honoured by
exempting a requester from IP-based rate limiting on request.

**Legitimate interests balancing test, non-converting enquiries.** The interest is being able
to resume a conversation a community started, and to answer a later question about what was
proposed. Retention is 12 months, access is limited to the product and sales team, and the
data is not used for unsolicited marketing beyond one follow-up within 30 days. The impact is
low and the notice states it plainly. The interest is not overridden. Objection is honoured
by immediate deletion.

**Article 9 condition.** Because denomination, parish affiliation and free-text answers may
reveal religious belief, **Article 9(2)(a) explicit consent** is relied on for the inference,
and **Article 9(2)(d)** is relied on where the data subject is acting for a religious
community and the processing relates to its members' activities. Consent is captured by an
unbundled, unchecked checkbox at the final step, in plain language, with a record of the
text shown, the timestamp and the method. Withdrawal deletes the assessment answers and
stops further contact; it does not erase records subject to the 7-year accounting obligation,
and the notice says so.

**Article 22.** Not engaged, for the reason given in section 1. Should the scoring ever be
allowed to reject or auto-price an enquiry without human review, this assessment must be
redone before that change ships.

### 4. Data flows and storage locations

| Stage | System | Location | Protection |
| --- | --- | --- | --- |
| Collection | `viavitae-web` funnel form, served over TLS 1.3 | Self-hosted k3s, Frankfurt, DE | HSTS, no third-party scripts on the form route |
| Transport | Authenticated API call to `viavitae-api` | Frankfurt, DE, internal network | TLS 1.3, mTLS between services |
| Processing and scoring | `viavitae-api` assessment service | Frankfurt, DE | Least-privilege service accounts |
| Primary storage | PostgreSQL, contact and assessment schemas separated by surrogate key | Frankfurt, DE | AES-256 at rest, column-level encryption on contact details |
| Backup | Nightly encrypted snapshot, 35-day retention | Vilnius, LT | AES-256 at rest, key held separately from the snapshot |
| Object storage | Uploaded attachments only | Frankfurt, DE | Private bucket, signed URLs expiring in 15 minutes |
| Logs | Structured application logs | Frankfurt, DE | Identifier fields redacted at the logging layer; no free-text bodies logged |
| Monitoring | Self-hosted metrics and alerting | Vilnius, LT | Aggregates only; no personal data in labels |
| Email notification | Self-hosted mail relay to staff | Vilnius, LT | TLS on submission; the notification contains a link, not the assessment content |

- **No transfers outside the EEA.** Every system in the flow is on ViaVitae infrastructure in
  Germany or Lithuania.
- **Processors.** Hosting and infrastructure are operated by ViaVitae on self-hosted Proxmox
  hardware; the colocation provider in Frankfurt and the provider in Vilnius act as
  processors under DPAs that restrict them to facility and network services with no access to
  application data. No SaaS processor is involved in this flow.
- **Third-party services deliberately excluded.** No analytics script, no advertising pixel,
  no external error tracker and no external font host are loaded on the funnel route, because
  each would create an export path that is easy to add and hard to notice. Fonts are
  self-hosted. This is enforced by a Content-Security-Policy header that permits no external
  origin on the funnel routes, and the policy is checked in CI.
- **Access.** Role-based. Sales and product roles may read assessments; only the product
  role may read contact details; engineering access to production data is by time-boxed
  break-glass with dual approval and full logging. All access requires MFA. Access is
  reviewed quarterly.
- **Erasure.** A deletion request removes the assessment record, the contact record and
  attachments immediately, and is propagated to backups as they age out within 35 days. The
  deletion is logged with its legal basis and the identity of the approver. Downstream
  email notifications are recalled from the mail queue where still pending.

### 5. Risk assessment

| ID | Risk | Harm to data subjects | L | S | Inherent |
| --- | --- | --- | --- | --- | --- |
| R1 | Unauthorised disclosure of enquiry content revealing a community's affiliation and circumstances | Stigmatisation, loss of trust, chilling effect on a community seeking help | 2 | 4 | 8 Medium |
| R2 | Free-text answers disclose third-party special category data about parishioners, which is retained longer than necessary and is outside the third party's knowledge | Loss of control over another person's belief or health data | 3 | 4 | 12 High |
| R3 | Backup media or snapshot leaves the EEA through a provider change or misconfiguration | Unlawful transfer, loss of the residency guarantee given to clients | 1 | 5 | 5 Medium |
| R4 | Credential compromise of a staff account exposes the whole enquiry dataset | Bulk disclosure, potential targeted approach to vulnerable communities | 2 | 5 | 10 High |
| R5 | Submission endpoint abused for bulk collection or spam injection | Degraded service for parishes; injected content stored and read by staff | 3 | 2 | 6 Medium |
| R6 | Retention not enforced, so data accumulates beyond 12 months and access requests become unanswerable | Loss of accuracy, unlawful continued processing | 3 | 3 | 9 Medium |
| R7 | Consent for Article 9 inference not demonstrable because the record lacks the text shown | Processing special category data without a valid condition | 2 | 5 | 10 High |
| R8 | Logs capture free-text assessment content and are retained outside the deletion schedule | Disclosure through a lower-security path; erasure incomplete | 3 | 3 | 9 Medium |
| R9 | Scoring output is treated as a decision and a proposal is sent without human review | Incorrect or inappropriate proposal to a community in a relationship of dependency | 2 | 4 | 8 Medium |

No risk scores Critical. Three score High and require mandatory mitigation before
processing starts, which is recorded in section 6 and verified as a condition in section 8.

### 6. Mitigations and technical measures

| Risk | Measure | Owner | Verification |
| --- | --- | --- | --- |
| R2 | The final step displays a notice asking the submitter not to include personal data about identifiable third parties, and to describe a community rather than individuals. Submitted text is scanned on write for patterns indicating a third-party name with a health or belief disclosure, and flagged for redaction by the product team within two working days. Retention for flagged records is reduced to 90 days. | Product | Monthly sample of 10 records reviewed by the DPO; scan hit rate reported |
| R4 | MFA enforced on all staff accounts; hardware key required for production access; sessions expire after 8 hours; quarterly access review with automatic revocation on role change; break-glass access requires dual approval and is logged and reviewed within 24 hours | Platform | Access review report; penetration test annually |
| R7 | The consent record stores the exact notice text version, the checkbox state, the timestamp, the IP and the user agent. Consent cannot be pre-checked and is not bundled with the terms of service. Withdrawal is a single link in every follow-up email. | Product | Consent records sampled quarterly by the DPO; UI test asserts the checkbox is unchecked by default |
| R1 | Role-based access with contact details separated from assessment answers; AES-256 at rest; column-level encryption on contact fields; TLS 1.3 in transit | Platform | Configuration reviewed each release; annual penetration test |
| R3 | Backup destination is declared in infrastructure-as-code and the value is asserted by a policy check in CI; a change of region or provider fails the pipeline and requires an ADR plus a transfer impact assessment | Platform | CI policy check on every pull request touching infrastructure |
| R5 | Rate limiting per IP and per organisation; CAPTCHA only after a threshold, chosen to be accessible; IP and user agent retained 30 days then purged; inbound free text is length-limited and rendered inert | Platform | Rate-limit metrics reviewed monthly; abuse report log |
| R6 | Scheduled deletion job runs nightly against the retention schedule and emits a count of records deleted; the job's failure pages the on-call engineer; deletion is recorded in an audit log that is itself retained 7 years | Platform | Deletion job dashboard; quarterly reconciliation against the register of processing |
| R8 | The logging layer redacts identifier and free-text fields by an allowlist of logged keys rather than a blocklist of sensitive ones, so a new field is not logged by default; logs are retained 90 days and cannot be queried by an unredacted field | Platform | Log schema reviewed on every change to the assessment model; test asserts no free-text field appears in a log line |
| R9 | The scoring service returns a suggestion and a confidence value; the UI requires a named staff member to confirm or amend before a proposal can be sent, and the confirmation is stored with the proposal; sending is impossible without it | Product | Integration test asserts the send endpoint rejects an unconfirmed proposal |

**Privacy by default.** The funnel collects nothing until the final step. Analytics is off on
the funnel route. Attachments are optional. The follow-up email is a single message within
30 days, not a drip sequence. The most protective setting is the one a visitor gets without
asking.

**Breach readiness.** Detection is by alert on anomalous bulk read, on failed-authentication
spike and on CSP violation. The path is on-call engineer to `security@viavitae.com`, then to
the DPO, then the Article 33 assessment. The 72-hour workflow is in `SECURITY.md`. A
quarterly tabletop exercise runs against this processing specifically.

### 7. DPO and processor consultation record

- **DPO consulted** 2026-08-14 by the assessment owner, and again on the revised draft
  2026-08-19.
- **DPO advice.** (a) Treat the dataset as Article 9 throughout, not only where belief is
  declared — accepted. (b) Move contact collection to the final step — accepted, and it
  removed the abandoned-funnel risk entirely. (c) Reduce non-converting retention from 24 to
  12 months — accepted. (d) Do not rely on legitimate interests for the Article 9 inference;
  obtain explicit consent — accepted, and it is the reason R7 is scored High until the
  consent record is demonstrable. (e) The DPO objected to the original design, which scored
  enquiries and auto-sent a proposal, on the ground that a community in a relationship of
  dependency should not receive an automated response — **accepted in full**; human
  confirmation is now mandatory and enforced in the API.
- **Views of data subjects**, Article 35(9). Consulted through two pilot parishes and one
  diocesan communications officer in July 2026. Their feedback produced the plain-language
  notice, the Lithuanian-first wording, and the removal of the exact headcount field, which
  one respondent described as something a small parish would not want to state in writing.
  Direct consultation of individual parishioners was not undertaken and was judged not
  proportionate: they are not the data subjects of this processing, and the data subjects are
  the people who act for them. The reasoning is recorded here so it can be revisited.
- **Processor consultation.** The Frankfurt and Vilnius colocation providers were consulted
  on snapshot encryption and key custody. Both confirmed they hold no application-level key
  material and have no access to stored data. DPAs are in place and restrict them to facility
  and network services.
- **Article 36 prior consultation.** Not required. No residual risk is High or above.

### 8. Residual risk and sign-off

| ID | Inherent | Mitigations | Residual |
| --- | --- | --- | --- |
| R1 | 8 Medium | Access separation, encryption | 4 Low |
| R2 | 12 High | Notice, scan, redaction, reduced retention | 6 Medium |
| R3 | 5 Medium | Infrastructure policy check in CI | 2 Low |
| R4 | 10 High | MFA, hardware key, access review, break-glass control | 5 Medium |
| R5 | 6 Medium | Rate limiting, purge schedule | 3 Low |
| R6 | 9 Medium | Scheduled deletion with paging | 3 Low |
| R7 | 10 High | Versioned consent record, unbundled checkbox | 4 Low |
| R8 | 9 Medium | Allowlist logging redaction, 90-day retention | 3 Low |
| R9 | 8 Medium | Mandatory named human confirmation | 4 Low |

- **Overall residual risk rating.** Medium.
- **Can the processing proceed?** Yes, with conditions.
- **Conditions before go-live.**
  1. Versioned consent record implemented and verified by the DPO on a sample of 10 records.
     Owner: Product. Due: 2026-08-28. **Met 2026-08-26.**
  2. MFA and hardware-key enforcement confirmed for every account with production access.
     Owner: Platform. Due: 2026-08-25. **Met 2026-08-25.**
  3. Mandatory human confirmation on proposal send, with an integration test. Owner: Product.
     Due: 2026-08-28. **Met 2026-08-27.**
  4. Third-party-data scan and redaction workflow operating, with the monthly DPO sample
     scheduled. Owner: Product. Due: 2026-09-15. **Met 2026-09-11.**
  5. Privacy notice published in `lt`, `en` and `ru` and linked from the first step. Owner:
     Product. Due: 2026-08-21. **Met 2026-08-20.**
- **Changes required elsewhere.** The record of processing activities was updated on
  2026-08-21. The privacy notice was published in all three locales on 2026-08-20.

| Role | Name | Date |
| --- | --- | --- |
| Assessment owner | Product lead, ViaVitae IT Technologies | 2026-08-21 |
| Business owner | Head of Client Services, ViaVitae IT Technologies | 2026-08-21 |
| Data Protection Officer | Data Protection Officer, ViaVitae IT Technologies | 2026-08-21 |
| Architecture | Architects team lead, ViaVitae IT Technologies | 2026-08-21 |

Named signatories are recorded in the signed copy held in the DPO register. An entry without
a named signatory is not an approval.

### 9. Review date

- **Next scheduled review.** 2027-08-21.
- **Earlier review is mandatory on:** any change to the questions asked or the categories
  collected; any new recipient or processor; any change of storage or backup location;
  introduction of automated pricing, automated rejection or any change that could engage
  Article 22; a breach affecting this processing; a complaint revealing an unassessed risk;
  new guidance from the State Data Protection Inspectorate or the EDPB; or any change to the
  consent wording.
- **Review owner.** DPO, supported by the assessment owner.
- **Review outcome recorded as.** A new version number, an updated status, and an updated
  register row in this file. The record of processing activities and the privacy notice are
  updated in the same change.

---

## DPIA-002: AI pastoral assistant

| Field | Value |
| --- | --- |
| Status | Approved with conditions |
| Assessment owner | Product |
| Version | 1.0 |
| Date started | 2026-08-11 |
| Related ADR | ADR-001 |
| Repositories affected | `viavitae-api`, `viavitae-web`, `viavitae-infra`, `viavitae-docs`, `viavitae-qa` |

### 1. Description of processing

The pastoral assistant helps clergy and parish volunteers draft replies to messages from
parishioners — enquiries about baptisms, funerals, marriage preparation, visiting the sick,
and requests for prayer or pastoral support. It suggests a draft in the parish's own voice
and language. **No draft is ever sent automatically.** Every suggestion enters a queue where
a named human reviewer reads, edits, approves or discards it, and only an approved draft
reaches a parishioner.

- **Purpose.** To reduce the time clergy spend on routine written correspondence so that
  face-to-face pastoral time is protected. A secondary purpose is consistency of tone and of
  the practical information a reply contains, such as how to arrange a visit.
- **Data subjects.** Two groups. (a) Clergy and parish volunteers who operate the assistant.
  (b) **Parishioners and members of the public whose messages are processed** — this second
  group does not choose to use the system, may not know it exists, and is the reason this
  assessment is required.
- **Data categories.** Sender name and address where given; message content, which is free
  text and frequently discloses belief, family circumstances, bereavement, illness, financial
  hardship, marital difficulty and, occasionally, safeguarding concerns; the parish and
  diocese; language; timestamps; the reviewer's identity and decision; the draft as sent and
  any edits made; model prompt and completion metadata for auditing.
- **Special category data.** Yes, unavoidably and at the core of the processing. Message
  content sent to a parish routinely reveals **religious belief** under Article 9, and often
  reveals **health data** where illness, mental health, addiction or bereavement is described,
  and **data concerning sex life or sexual orientation** where a marriage or relationship
  matter is raised. This is not incidental; it is the subject matter.
- **Volume.** Pilot: 4 parishes, estimated 300 to 500 messages per month.
- **Source.** From the data subject, indirectly — the parishioner writes to their parish, and
  the parish routes the message through the assistant.
- **Recipients.** The parish's own clergy and volunteers; ViaVitae product and support staff
  with a documented need; no advertising, no data broker, no third-party model provider.
- **Retention.** Message content and drafts: 24 months from the last exchange, then deleted.
  Reviewer decisions and audit metadata: 24 months. Model inputs are not retained for
  training and are deleted with the conversation. Prompt logs used for quality review: 30
  days, redacted.
- **Automated decision-making.** The assistant produces a **suggestion**, and a human with
  authority to change it makes the decision. Article 22(1) is therefore not engaged, because
  no decision with legal or similarly significant effect is taken solely by automated means.
  This conclusion depends entirely on the human approval queue remaining mandatory, on the
  reviewer genuinely reading and being able to reject, and on no path existing that bypasses
  the queue. If any of those fails, Article 22 is engaged and this assessment must be redone
  before the change ships. Meaningful human oversight is a design requirement, not a
  courtesy.

### 2. Necessity and proportionality

- **Necessity.** Clergy in the pilot parishes report between 6 and 11 hours per week on
  written correspondence, which displaces visits and counselling. The purpose cannot be met
  by better templates alone, because the messages are varied and personal; a template reply
  to a bereavement message is worse than no reply.
- **Alternatives considered.** (a) Do nothing — rejected; the burden is real and is
  displacing pastoral care, and burnout among clergy is itself a risk to the community.
  (b) Human-only shared inbox with canned responses — partially adopted as the fallback and
  as the behaviour when the assistant is unavailable, but it does not meet the consistency or
  time objective. (c) Fully automated replies — **rejected on ethical and legal grounds**;
  a parishioner disclosing a crisis to their parish must not receive a machine reply, and
  this option would engage Article 22 and, for special category data, Article 22(4).
  (d) A third-party commercial assistant service — **rejected**; it would require sending
  Article 9 data to an external processor, most such services process outside the EEA, and
  several reserve training rights over submitted content. (e) A locally hosted open-weight
  model with a human queue — **adopted**.
- **Minimisation applied.** The assistant receives only the current message and the last
  three exchanges for context, not the parishioner's full history. Sender contact details are
  replaced with a surrogate reference in the prompt. The parishioner's name is included only
  where the draft needs it. Diocesan and regional aggregate data is never sent to the model.
  No message is used for model training or fine-tuning, and the deployment cannot be
  reconfigured to do so without a new assessment.
- **Proportionality.** The intrusion is real: free text about grief, illness and faith is
  processed by a language model. It is proportionate because the model is self-hosted in the
  EEA, no third party sees the content, retention is short, nothing is used for training, and
  a human being remains responsible for every word a parishioner receives. The alternative —
  clergy unable to reply at all — carries its own harm.
- **Transparency.** Parishioners are told, in the parish's published privacy notice and in a
  first-reply footer, that correspondence may be assisted by a drafting tool operated by the
  parish and reviewed by a member of clergy before it is sent. The notice names the
  controller as the parish, explains the Article 9 condition relied on, states that no
  automated sending occurs, and gives the objection route. **Parishes must not enable the
  assistant before their own notice is published**; this is a go-live condition.
- **Rights.** Parishioners may object to assisted drafting, in which case their messages are
  routed to the human-only queue with no model processing. Objection is recorded per sender
  and is honoured across all future messages. Access, rectification, erasure, restriction and
  portability are exercised through the parish as controller, supported by ViaVitae as
  processor.

### 3. Lawful basis

The **parish is the controller**; ViaVitae IT Technologies is a **processor** acting under an
Article 28 contract. This division matters: the lawful basis is the parish's to determine,
and ViaVitae must not use the data for its own purposes.

| Purpose | Article 6 basis | Article 9 condition |
| --- | --- | --- |
| Drafting a pastoral reply to a message received by the parish | 6(1)(d) vital interests where the message discloses risk to a person; otherwise 6(1)(f) legitimate interests of the parish in administering its pastoral ministry | 9(2)(d) — processing by a not-for-profit body with a religious aim, relating to members or persons in regular contact, and not disclosed outside the body without consent |
| Retaining the exchange and the reviewer decision for accountability | 6(1)(f) legitimate interests | 9(2)(d), as above |
| Quality review of drafts on redacted samples | 6(1)(f) legitimate interests | 9(2)(d), with redaction applied before review |

**Legitimate interests balancing test.** The parish's interest is discharging its pastoral
duty to respond to people who write to it, many of whom are in distress, without that duty
being limited by the number of hours a small clergy team has. The interest is genuine and is
not commercial. Processing is necessary because the volume exceeds available human capacity
and because the alternative of not replying causes greater harm. The impact on the data
subject is mitigated by: EEA-only self-hosting with no external recipient; no training use;
a mandatory human decision on every output; short retention; an effective right to object
that routes the person to a fully human process; and transparency in the parish's notice.
The data subject's fundamental rights do not override the interest **on condition that the
human approval queue and the objection route both remain operative**. Both are therefore
go-live conditions, and both are tested in CI.

**Article 9(2)(d)** is the primary condition. It applies because the parish is a
not-for-profit body with a religious aim, the data subjects are members or persons in regular
contact with it in connection with its activities, and the data is not disclosed outside the
body without consent. Where a message discloses an immediate risk to life or health,
**Article 9(2)(c)** vital interests is relied on for that exchange, and the safeguarding
route in section 6 takes precedence over drafting.

**Explicit consent is not relied on.** Consent is not freely given in a relationship of
spiritual dependency: a parishioner who needs a funeral arranged is not in a position to
refuse a condition attached to that care. Relying on consent here would be invalid, and would
also make the service conditional in a way Article 7(4) prohibits. This reasoning is recorded
so that it is not revisited under delivery pressure.

**Article 22.** Not engaged, because a human reviewer makes every decision and may discard
the suggestion entirely. Safeguards that would be required if it were engaged are in place
regardless: the reviewer can obtain human intervention on their own behalf, can express
their point of view, and can contest the output by discarding or rewriting it.

**Safeguarding override.** Where content indicates risk of harm to a child or a vulnerable
adult, or intent of self-harm, the assistant does not draft. It escalates to the parish's
named safeguarding officer and to ViaVitae support, and the message is excluded from quality
sampling. This is a functional requirement, not a policy statement, and it is covered by a
test that must pass before release.

### 4. Data flows and storage locations

| Stage | System | Location | Protection |
| --- | --- | --- | --- |
| Ingress | Parish mailbox or web form, forwarded to `viavitae-api` | Vilnius, LT | TLS 1.3, DKIM and SPF verification, per-parish tenant isolation |
| Preprocessing | Redaction and context windowing in `viavitae-api` | Vilnius, LT | Contact details replaced by surrogate reference before any model call |
| Inference | Self-hosted open-weight language model, no external API | Self-hosted k3s on Proxmox, Vilnius, LT | Air-gapped from third-party inference providers; model weights and prompts under version control |
| Approval queue | Reviewer interface in `viavitae-web` | Vilnius, LT | Per-parish tenancy, MFA, named reviewer on every action |
| Draft storage | PostgreSQL, per-tenant schema | Vilnius, LT | AES-256 at rest, per-tenant encryption keys held separately |
| Audit trail | Immutable reviewer-decision log | Vilnius, LT | Append-only, 24-month retention, tamper-evident |
| Backup | Nightly encrypted snapshot, 35 days | Frankfurt, DE | AES-256, key held separately from the snapshot |
| Quality sampling | Redacted exports to the product team | Vilnius, LT | Redaction applied before export; 30-day retention; access logged |
| Logs | Structured application logs | Vilnius, LT | Message bodies never logged; an allowlist of keys determines what may be logged |
| Monitoring | Self-hosted metrics | Vilnius, LT | Counts and latencies only; no content in labels or tags |

- **No transfers outside the EEA.** Inference is self-hosted. There is **no** call to any
  external model provider, embedding service, transcription service, translation API,
  analytics product, error tracker or advertising platform anywhere in this flow. The
  absence is enforced by an egress network policy that permits no outbound connection from
  the inference namespace, verified by a test in CI. This control is the single most
  important one in this assessment: it is what makes the "no third party sees Article 9
  data" claim true rather than aspirational.
- **Processors.** ViaVitae IT Technologies acts as processor to each parish under an
  Article 28(3) contract that prohibits use of message content for any purpose other than
  providing the service, prohibits sub-processing without written authorisation, requires
  deletion or return at termination, and grants audit rights. The colocation providers in
  Vilnius and Frankfurt are sub-processors restricted to facility and network services with
  no access to application data; parishes are notified of them in the contract.
- **Model supply chain.** Model weights are obtained from a published source, verified
  against a recorded checksum, stored in the internal artefact registry, and deployed from
  there. The checksum and the provenance are recorded in the release notes for each model
  version, because an unverifiable model is an unverifiable processing operation.
- **Access.** Clergy and volunteers see only their own parish's queue. ViaVitae support
  access requires a parish-authorised request, is time-boxed to 4 hours, is dual-approved and
  is fully logged and reviewed within 24 hours. Engineering access to production content is
  break-glass only, with the same controls. Product-team access is to redacted samples only.
  All access requires MFA and is reviewed quarterly.
- **Tenant isolation.** Enforced at the query layer by a mandatory tenant predicate, tested
  by a suite that asserts a query for one parish cannot return another's rows. Cross-tenant
  disclosure is treated as a Critical security incident under `SECURITY.md`.
- **Erasure.** On request or at retention expiry, message content, drafts, model prompt
  metadata and quality samples are deleted; the audit trail retains a tombstone recording
  that a deletion occurred, its legal basis and its approver, without the content. Backups
  age out within 35 days. The parish is notified that erasure has been completed.

### 5. Risk assessment

| ID | Risk | Harm to data subjects | L | S | Inherent |
| --- | --- | --- | --- | --- | --- |
| R1 | Cross-tenant disclosure — one parish's reviewer sees another parish's messages | Disclosure of grief, illness and belief to an unrelated community; severe loss of trust and stigmatisation | 2 | 5 | 10 High |
| R2 | Message content leaves the EEA through an added dependency, SDK, telemetry call or egress path that nobody notices | Unlawful transfer of Article 9 data; the residency guarantee given to parishes becomes false | 2 | 5 | 10 High |
| R3 | The approval queue is bypassed, disabled or degraded under delivery pressure, and a draft is sent without human review | A parishioner in distress receives a machine reply; Article 22 engaged without safeguards | 2 | 5 | 10 High |
| R4 | Safeguarding content is drafted rather than escalated | A disclosure of abuse or intent of self-harm receives a generated reply and is not acted on; risk to a child or vulnerable adult | 2 | 5 | 10 High |
| R5 | Hallucinated practical information — wrong funeral procedure, wrong diocesan requirement, invented availability | A parishioner acts on incorrect information about a rite or a service at a moment of vulnerability | 3 | 4 | 12 High |
| R6 | Model output is biased or doctrinally inappropriate for the parish's tradition | Offence, distress, or a reply that misrepresents the parish's position | 3 | 3 | 9 Medium |
| R7 | Content used for training or fine-tuning, or retained by a future dependency | Loss of control over belief and health data beyond the stated purpose | 1 | 5 | 5 Medium |
| R8 | Retention not enforced across drafts, samples, logs and backups | Continued unlawful processing; erasure incomplete and unanswerable | 3 | 3 | 9 Medium |
| R9 | Reviewer fatigue causes rubber-stamping, so oversight becomes nominal | The Article 22 conclusion and the legitimate interests balancing both fail; unreviewed output reaches parishioners | 3 | 4 | 12 High |
| R10 | Redaction fails and identifying details reach the quality-review sample | Wider internal disclosure than necessary, including to staff without a pastoral need | 3 | 3 | 9 Medium |
| R11 | Parishioner is unaware the assistant exists, so the transparency obligation is unmet | Processing belief data covertly; objection right cannot be exercised | 2 | 4 | 8 Medium |
| R12 | A prompt-injection attempt in a message causes the model to disclose other conversations or system content | Cross-conversation disclosure through the model rather than the database | 2 | 5 | 10 High |

Seven risks score High. This is the highest-risk processing operation in the ViaVitae
portfolio and the residual risk remains High after mitigation, which is why the review cycle
is six months rather than twelve.

### 6. Mitigations and technical measures

| Risk | Measure | Owner | Verification |
| --- | --- | --- | --- |
| R1 | Mandatory tenant predicate at the query layer, per-tenant encryption keys, a test suite asserting cross-tenant queries return nothing, and treatment of any cross-tenant disclosure as a Critical incident | Platform | Isolation suite runs on every pull request and nightly; annual penetration test with a cross-tenant scenario |
| R2 | Egress network policy denying all outbound connections from the inference namespace; dependency review requires the compliance team for anything touching this service; a CI test asserts the policy is present and unchanged; adding a telemetry or analytics dependency to this service is a QODER rule 7 stop-condition | Platform | Egress test in CI on every pull request; quarterly review of the policy and of the dependency list |
| R3 | No code path sends a draft without a stored reviewer decision; the send endpoint rejects any draft lacking one; the queue cannot be disabled by configuration in production; the UI records reviewer identity, timestamp and whether the text was edited | Product | Integration test asserts send fails without a decision; configuration schema forbids a disable flag in production |
| R4 | A safeguarding classifier runs **before** drafting and on every inbound message; on a hit, drafting is suppressed and the message is routed to the parish's named safeguarding officer and to ViaVitae support with an alert; excluded from quality sampling; the classifier is tuned for the pilot languages and its recall is measured against a labelled set | Product | Classifier test suite with a minimum recall threshold that fails the build; monthly recall report to the DPO; tabletop exercise each quarter |
| R5 | Drafts are marked internally as unverified suggestions; practical and procedural information is drawn from a parish-maintained reference rather than generated where a reference entry exists; the reviewer interface shows source attribution for any procedural claim; reviewers are trained that verifying facts is their responsibility | Product | Reference-coverage metric reported monthly; reviewer training completion tracked per parish |
| R6 | Per-parish tone and doctrinal guidance supplied by the parish and stored with the tenant; reviewer edits are measured as a quality signal; a parish may suspend the assistant for a category of message; redacted samples reviewed monthly by the parish's nominated reviewer | Product | Edit-rate metric per parish reported monthly; monthly sample review recorded |
| R7 | No training or fine-tuning pipeline exists in the deployment; inference is stateless across conversations; model inputs are deleted with the conversation; the configuration exposes no training option | Platform | Architecture review; dependency and configuration audit each release |
| R8 | Nightly deletion job against the retention schedule for content, drafts, samples and prompt logs; tombstone audit records; job failure pages the on-call engineer; quarterly reconciliation against the register of processing | Platform | Deletion dashboard; quarterly reconciliation report to the DPO |
| R9 | Queue presents one message at a time with no bulk-approve control; a minimum dwell time is enforced before approval is enabled; if a reviewer's edit rate falls below a threshold the parish is notified and sampling increases; reviewers may not approve a draft addressed to themselves; fatigue is treated as a control failure, not a user failure | Product | Dwell-time and edit-rate metrics reviewed monthly by the DPO; bulk-approve absence asserted by a UI test |
| R10 | Allowlist-based redaction applied before any export, replacing names, addresses and identifiers with tokens; the redacted sample is reviewed by the product team only; samples expire after 30 days; redaction is tested against a corpus of realistic messages | Product | Redaction test suite in CI; monthly DPO sample of 10 redacted exports |
| R11 | A parish cannot enable the assistant until its privacy notice is published in the parish's own languages and a first-reply footer is active; enablement is gated on a recorded confirmation; the notice explains the processor role, the Article 9 condition, the absence of automated sending, and the objection route | Product | Enablement gate asserted by an API test; notice presence checked at onboarding and at each annual review |
| R12 | The model receives message content as data within a fixed prompt structure and is instructed to treat it as untrusted; system context is not retrievable by the conversation; per-request context is limited to the current message and the last three exchanges; outputs are constrained to the reply text and cannot invoke tools, fetch data or query other conversations; the model deployment has no tool-calling or retrieval capability enabled | Platform | Adversarial prompt test suite in CI, including known injection patterns; no tool-calling capability in the deployment configuration |

**Human oversight.** Every output is reviewed by a named person with authority to discard or
rewrite it. Oversight is designed to be real: one message at a time, a minimum dwell time,
no bulk approval, edit rate monitored, and reviewers trained that they are accountable for
what is sent. This is what keeps Article 22 unengaged and what makes the legitimate interests
balancing hold.

**Accuracy.** Parishioners may request correction of the record of an exchange. Reviewers may
amend any draft. Where a sent reply contained incorrect practical information, the parish
corrects it directly with the person and the incident is logged for the monthly review.

**Privacy by default.** The assistant is off until a parish enables it with a published
notice. Objection routes a sender permanently to the human-only queue. Sampling is redacted.
Retention is 24 months, not indefinite. Nothing is used for training.

**Breach readiness.** Detection is by alert on cross-tenant access patterns, on egress policy
violation, on safeguarding-classifier failure and on anomalous bulk read. The path is on-call
engineer to `security@viavitae.com`, then the DPO, then the parish as controller, then the
Article 33 assessment. Because the parish is the controller, the parish is notified
immediately so that its own 72-hour clock can be managed; ViaVitae notifies without undue
delay under Article 33(2). The workflow is in `SECURITY.md`. A quarterly tabletop exercise
runs against this processing specifically, including a cross-tenant scenario and an egress
scenario.

### 7. DPO and processor consultation record

- **DPO consulted** 2026-08-18, on the revised draft 2026-08-27, and on the final conditions
  2026-09-01.
- **DPO advice.** (a) Do not rely on consent; the spiritual dependency makes it invalid —
  **accepted**, and the reasoning is recorded in section 3 so it is not revisited under
  delivery pressure. (b) Treat ViaVitae as processor and the parish as controller, and reflect
  that in the Article 28 contract — **accepted**. (c) The approval queue must be a functional
  requirement enforced in code, not a configuration option — **accepted**; R3 mitigation
  removes the disable flag from production configuration entirely. (d) Safeguarding must be
  detected before drafting, not after — **accepted**, and the ordering is now a test
  requirement. (e) Egress denial is the control on which the residency claim rests and must be
  verified in CI rather than asserted in documentation — **accepted**. (f) Reviewer fatigue is
  a control weakness and must be measured — **accepted**; R9 was added as a distinct risk on
  the DPO's initiative, having not been identified by the product team. (g) The DPO's
  original objection to sampling message content for quality review was withdrawn once
  redaction before export and a 30-day expiry were added.
- **Views of data subjects**, Article 35(9). Consulted in August 2026 with four pilot
  parishes: two priests, one parish administrator, one diocesan safeguarding officer and one
  lay pastoral volunteer. Their feedback produced: the safeguarding-first ordering; the
  minimum dwell time, because one priest said a queue that could be cleared quickly would be
  cleared quickly; the requirement that a reviewer cannot approve a draft addressed to
  themselves; the removal of bulk approve; and the instruction that the notice be published
  in the parish's own language rather than only in Lithuanian. **Parishioners themselves were
  not directly consulted.** The reasoning is recorded: direct consultation of a large,
  unelected group of people in varying degrees of distress was judged disproportionate and
  potentially harmful at the pilot stage, and the parishioners' interests were represented by
  clergy and by the safeguarding officer, whose role is to hold exactly that concern. This
  decision is to be revisited at the first six-month review, and before any expansion beyond
  the pilot parishes, because the justification weakens as scale grows.
- **Processor consultation.** Each pilot parish was consulted as controller on the Article 28
  terms, the sub-processor list, the retention schedule, the notice wording and the
  enablement gate. All four executed the contract before enablement. Colocation providers in
  Vilnius and Frankfurt confirmed no application-level key material and no data access.
- **Article 36 prior consultation.** **Not required, and the reasoning is recorded.** The
  residual risk rating is High, which triggers consideration of prior consultation. It is not
  required here because the High residual reflects the inherent sensitivity of the subject
  matter — pastoral correspondence about belief, grief and illness is high-risk by nature —
  rather than an unmitigated deficiency in the processing. Every inherent High risk has a
  specific, owned, verified control; the deployment is EEA-only with no external recipient;
  no automated sending occurs; and the six-month review cycle with quarterly tabletop
  exercises is in place. Should any of R1, R2, R3, R4 or R9 be found ineffective in
  operation, or should automated sending ever be proposed, Article 36 consultation with the
  State Data Protection Inspectorate becomes mandatory before that change proceeds. This
  determination was reviewed and concurred by the DPO on 2026-09-01.

### 8. Residual risk and sign-off

| ID | Inherent | Mitigations | Residual |
| --- | --- | --- | --- |
| R1 | 10 High | Tenant isolation suite, per-tenant keys, Critical-incident treatment | 5 Medium |
| R2 | 10 High | Egress denial verified in CI, dependency review gate | 4 Low |
| R3 | 10 High | No send path without a stored decision, disable flag removed | 5 Medium |
| R4 | 10 High | Pre-draft safeguarding classifier with a recall threshold | 6 Medium |
| R5 | 12 High | Reference-sourced procedural facts, attribution, reviewer training | 8 Medium |
| R6 | 9 Medium | Per-parish guidance, edit-rate signal, monthly sample review | 6 Medium |
| R7 | 5 Medium | No training pipeline, stateless inference | 2 Low |
| R8 | 9 Medium | Nightly deletion with paging, quarterly reconciliation | 3 Low |
| R9 | 12 High | One-at-a-time queue, dwell time, no bulk approve, edit-rate monitoring | 9 Medium |
| R10 | 9 Medium | Allowlist redaction tested against a realistic corpus | 4 Low |
| R11 | 8 Medium | Enablement gated on a published notice, API test | 4 Low |
| R12 | 10 High | Untrusted-content prompt structure, no tool-calling, adversarial test suite | 6 Medium |

- **Overall residual risk rating.** **High.** No risk remains Critical, and every inherent
  High has a verified control, but the combination of Article 9 subject matter, vulnerable
  data subjects who did not choose the system, and dependence on human oversight remaining
  genuine means the operation as a whole stays High. This is stated plainly rather than
  rounded down: the rating drives the six-month review cycle and the quarterly exercises.
- **Can the processing proceed?** Yes, with conditions, and **only within the four pilot
  parishes**. Expansion beyond the pilot requires this assessment to be revisited first,
  because the justification for not consulting parishioners directly weakens with scale.
- **Conditions before go-live.**
  1. Cross-tenant isolation suite passing, including the negative case, in CI. Owner:
     Platform. Due: 2026-08-28. **Met 2026-08-27.**
  2. Egress denial policy applied to the inference namespace, with the CI assertion passing.
     Owner: Platform. Due: 2026-08-28. **Met 2026-08-28.**
  3. Send endpoint rejects any draft without a stored reviewer decision, with an integration
     test. Owner: Product. Due: 2026-08-31. **Met 2026-08-30.**
  4. Safeguarding classifier running before drafting, meeting the minimum recall threshold
     on the labelled set, with the test in CI. Owner: Product. Due: 2026-08-31. **Met
     2026-09-01.**
  5. Bulk approval absent and minimum dwell time enforced, asserted by a UI test. Owner:
     Product. Due: 2026-08-31. **Met 2026-08-31.**
  6. Article 28 contract executed by all four pilot parishes, and each parish's privacy
     notice published in its own languages. Owner: Legal and Product. Due: 2026-09-01.
     **Met 2026-09-01.**
  7. Adversarial prompt test suite in CI covering known injection patterns, with no
     tool-calling capability enabled in the deployment. Owner: Platform. Due: 2026-09-05.
     **Met 2026-09-04.**
  8. Model weight checksums and provenance recorded for the deployed version. Owner:
     Platform. Due: 2026-09-05. **Met 2026-09-02.**
  9. First quarterly tabletop exercise scheduled, covering a cross-tenant and an egress
     scenario. Owner: Security. Due: 2026-09-30. **Scheduled 2026-09-25.**
- **Changes required elsewhere.** The record of processing activities was updated on
  2026-09-02, recording the parish as controller and ViaVitae as processor. Each parish's
  privacy notice was published before enablement. `SECURITY.md` was amended to treat
  cross-tenant disclosure as Critical.

| Role | Name | Date |
| --- | --- | --- |
| Assessment owner | Product lead, ViaVitae IT Technologies | 2026-09-02 |
| Business owner | Head of Client Services, ViaVitae IT Technologies | 2026-09-02 |
| Data Protection Officer | Data Protection Officer, ViaVitae IT Technologies | 2026-09-02 |
| Architecture | Architects team lead, ViaVitae IT Technologies | 2026-09-02 |
| Security | Security team lead, ViaVitae IT Technologies | 2026-09-02 |

Named signatories are recorded in the signed copy held in the DPO register. Because Article 9
data and automated assistance are both involved, security and architecture sign-off are
required in addition to the standard three.

### 9. Review date

- **Next scheduled review.** **2027-03-02 — six months**, not twelve, because the residual
  risk rating is High.
- **Earlier review is mandatory on:** any proposal to send a draft without human review, or
  to weaken the queue, which would engage Article 22 and require Article 36 consultation;
  any proposal to expand beyond the four pilot parishes, which requires the
  direct-consultation justification to be revisited; any external model, embedding,
  transcription, translation or analytics dependency; any change to the inference location or
  the egress policy; any finding that R1, R2, R3, R4 or R9 controls are ineffective in
  operation; any breach affecting this processing; any safeguarding escalation that was
  mishandled; any complaint from a parishioner; new EDPB guidance on AI and Article 9 data;
  or a change of model, which requires re-verification of provenance and of the adversarial
  suite.
- **Review owner.** DPO, supported by the assessment owner, the security team and a
  representative of each pilot parish.
- **Review output.** A new version number, an updated status, an updated register row, and a
  restated residual risk rating. Where the review finds a control ineffective, processing of
  the affected category pauses until it is restored, and the pause is recorded here rather
  than handled informally.

---

## INFRA-001: Infrastructure platform processing

| Field | Value |
| --- | --- |
| **Status** | Approved with conditions |
| **Version** | 1.0 |
| **Processing owner** | `@Via-Vitae/platform` |
| **Assessment author** | Platform engineering |
| **DPO** | `dpo@viavitae.com` |
| **Controller** | ViaVitae IT Technologies (Art. 4(7)) |
| **Date of assessment** | 2026-09-06 |
| **Date processing started** | Not started — this assessment precedes the first `prod` apply |
| **Related ADRs** | ADR-001, ADR-002, ADR-003, ADR-004, ADR-005, ADR-008 in [architecture.md](architecture.md) |

### 1. Description of processing

Operating a self-hosted platform is itself a processing activity. This record covers the
personal data that exists **because the infrastructure runs**, not the personal data that
tenant applications store — that is assessed in DPIA-001 and DPIA-002 above and in the
per-tenant records raised in `viavitae-api`.

| Element | Detail |
| --- | --- |
| **Purpose** | (a) Keep the platform available, secure and recoverable; (b) detect, investigate and contain incidents; (c) evidence compliance with Art. 32 for tenants and for the supervisory authority; (d) authenticate and authorise staff and tenant administrators. |
| **Categories of data subjects** | ViaVitae staff and contractors (platform operators, developers, on-call); tenant administrators who log in through Keycloak or Grafana; and any person whose personal data appears in an application log line, a metric label or a database backup. The last category is the one most often forgotten: the infrastructure layer processes data subjects it never chose. |
| **Categories of personal data** | Identity: name, work email address, Keycloak username, group memberships, authentication timestamps, source IP address at login. Operational: SSH public key fingerprints, sudo and shell audit records, Proxmox API token identifiers, Git commit authorship and email address, CI job actor. Derived from workloads: whatever an application writes to stdout — request paths, user identifiers, email addresses in error messages, query parameters. Recovery: full copies of tenant databases, therefore every category of data those databases hold. |
| **Special category data (Art. 9)** | Not processed by design at this layer. **However**, tenant databases hold Art. 9 data (religious belief, pastoral notes) and those databases are copied into `vzdump` snapshots, WAL-G archives and the offsite replica. The infrastructure layer therefore *holds* Art. 9 data without processing it for its own purposes. This is the single most important fact in this record, and it is why backup encryption, backup access control and backup retention are treated as Art. 9 controls rather than as operational hygiene. |
| **Sources** | Keycloak (authentication events), the Kubernetes audit log and container stdout via Loki, node and VM metrics via Prometheus, Proxmox VE (API and task log), Git and GitHub Actions (commit and job metadata), PostgreSQL (as the content of backups). |
| **Recipients** | Platform and security engineers (Grafana, Loki, Proxmox UI, Argo CD UI); the on-call rotation via Alertmanager; the DPO on request; a supervisory authority under Art. 33; GitHub as SCM and CI control plane (see section 4 — no tenant personal data by design, but commit authorship is personal data and is transferred). |
| **Operations** | Collection (automatic, from agents and logs), storage (Loki object store, Prometheus TSDB, Proxmox storage, S3 state bucket, offsite replica), consultation (dashboards, `logcli`, `kubectl logs`), disclosure (alert notifications, incident reports), erasure (retention expiry, tenant offboarding), transfer (GitHub, offsite replica). |
| **No automated decision-making** | There is no profiling and no Art. 22 decision-making at this layer. Alertmanager routing is rule-based on labels, not on data subjects. |

### 2. Necessity and proportionality

**Necessity.** Art. 32(1)(d) requires a process for regularly testing, assessing and
evaluating the effectiveness of technical and organisational measures. That process cannot
exist without logs, metrics and identity records. Equally, Art. 33(1) imposes a 72-hour
notification duty whose clock runs from awareness: an infrastructure layer that produces no
alerting cannot establish awareness, and a controller that learns of a breach from a customer
has already failed the obligation.

**Proportionality — what was reduced, and why.**

| Measure considered | Decision | Reason |
| --- | --- | --- |
| Retain container logs for 90 days | **Rejected: 30 days** | Incident investigation almost never reaches back further than a month, and log volume is dominated by request-path noise. Ninety days would triple the Loki store, most of it personal data with no operational reader. |
| Log full request bodies at `info` for debugging | **Rejected** | Bodies contain the personal data the applications process. A debug need does not justify standing collection; it justifies a temporary, time-boxed, namespace-scoped increase with a written end date. |
| Include a user's email address as a Prometheus label | **Rejected** | Metric labels are effectively permanent and are copied into every alert, every dashboard query and every Grafana render. Cardinality would also explode. Tenant identity in metrics is the tenant slug, never a person. |
| Make all dashboards visible to all staff | **Rejected** | Per-tenant dashboards are restricted to that tenant's administrators and to the platform team, through Grafana folder permissions backed by Keycloak groups. |
| Keep backups for 90 days | **Rejected: 35 days for WAL-G, 14 daily and 8 weekly `vzdump` copies** | Thirty-five days is the window needed for a slowly-detected corruption; longer retention multiplies the Art. 9 copies held. Retention is contractual per tenant and is stated in the tenant agreement. |
| Store Terraform state in the same bucket as backups | **Rejected** | State contains resource identifiers and, if anyone ever passes a secret to a resource argument, the secret itself. Separate bucket, separate credentials, separate access path — and ADR-003 forbids Terraform from creating credentials at all. |
| Run CI on GitHub-hosted runners | **Rejected** | See ADR-008. |

**Data minimisation at the agent.** Redaction is applied in the log agent on every host
(`ansible/roles/monitoring-agent/templates/alloy-logs.j2`), before anything leaves the machine.
Loki stores what it receives: a query-time filter would leave the personal data on disk, in the
index, and in every backup of the object store — three copies of data that must never be
persisted. That distinction is why the redaction rules live in the agent configuration and are
owned jointly by the DPO and Platform — `CODEOWNERS` gives `ansible/roles/monitoring-agent/`
to both.

### 3. Lawful basis

| Processing | Basis | Justification |
| --- | --- | --- |
| Identity and access management (Keycloak, SSH keys, Proxmox tokens, Git authorship) | Art. 6(1)(f) legitimate interests | Necessary to control who can operate systems that hold special category data. The interest is security of processing under Art. 32 and cannot be achieved by consent: an employee cannot meaningfully refuse to have an access record. |
| Operational logs and metrics | Art. 6(1)(f) legitimate interests | Same interest. Proportionality is addressed by the retention limits and the redaction pipeline in section 2. |
| Security monitoring, audit records, incident investigation | Art. 6(1)(f) legitimate interests, with Art. 32(1)(d) as the underlying obligation | A balancing test is recorded in section 7. |
| Backups containing Art. 9 data | Art. 6(1)(f) legitimate interests **plus** Art. 9(2)(d) — processing by a not-for-profit body with a religious or philosophical aim, in the course of its legitimate activities, with appropriate safeguards | The Art. 9 condition is relied on by the controller of the underlying data (the religious community, or ViaVitae acting as its processor). Where ViaVitae is a processor, Art. 28(3)(h) obliges it to make the backup available to the controller; the backup itself is not a new purpose. |
| Retention of backups after a tenant's erasure request | Art. 6(1)(c) legal obligation, and Art. 17(3)(b) | Erasure of the live schema does not retroactively purge existing backup copies. Art. 17(3)(b) preserves data required for legal claims and compliance; the residual exposure and its 35-day bound are stated in ADR-003 and must be stated in the tenant agreement. |
| Transfer of commit authorship to GitHub | Art. 6(1)(f) legitimate interests, with Art. 46 SCCs as the transfer mechanism | See section 4 and ADR-008. |

No processing at this layer relies on consent. Consent from an employee or a tenant
administrator is not freely given in the sense of Art. 4(11) where the alternative is not
being able to do the job.

### 4. Data flows and storage locations

| # | Data | From | To | Storage location | Encryption at rest | Retention | Cross-border? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F1 | Container and application logs | Pods, all namespaces | Loki via the collector, redaction applied in the pipeline | ViaVitae Proxmox, EEA (monitoring VM, `prod` VLAN) | ZFS native encryption | 30 days | No |
| F2 | Metrics and metric labels | Exporters, kube-state-metrics | Prometheus TSDB | ViaVitae Proxmox, EEA | ZFS native encryption | 30 days raw; 1 year for downsampled aggregates carrying no person-level label | No |
| F3 | Alert notifications | Alertmanager | On-call engineer by email and by the internal notification service | EEA mail server; payload contains alert labels only | TLS in transit | 90 days in the mailbox, under mail policy rather than infrastructure retention | No |
| F4 | Identity records and authentication events | Keycloak | Keycloak's PostgreSQL schema | ViaVitae Proxmox, EEA (dedicated database VM) | ZFS native encryption | Accounts: life of employment plus 90 days; authentication events: 180 days | No |
| F5 | Shell, sudo and Kubernetes audit records | Nodes, API server | Loki, and `auditd` locally on the node | EEA | ZFS native encryption | Loki 30 days; `auditd` on-node 90 days, then overwritten | No |
| F6 | Proxmox task and API log | Proxmox VE | Local node storage | EEA | ZFS native encryption | 90 days | No |
| F7 | Tenant database backups, containing Art. 9 data | PostgreSQL | WAL-G to the EU S3-compatible object store; `vzdump` to Proxmox backup storage | EEA, two independent locations (see F8) | age encryption for WAL-G, ZFS encryption for `vzdump` | WAL-G 35 days; 14 daily and 8 weekly `vzdump` copies | No |
| F8 | Offsite replica of the encrypted backup set | Primary backup storage | Second EEA location, physically separate | EEA | age encryption, keys held separately from the data | Same as F7 | No |
| F9 | Terraform state | Terraform on the self-hosted runner | S3-compatible object store, bucket `viavitae-infra-tfstate`, versioned and locked | EEA | Server-side encryption plus a bucket-level key | Versions retained 90 days; current state indefinitely | No |
| F10 | Source code, commit authorship, pull-request comments, plan **text** | Developer workstation | GitHub, as SCM and CI control plane | **United States** | GitHub's at-rest encryption | GitHub retention | **Yes** — Art. 46 SCCs plus a transfer impact assessment; see ADR-008 |
| F11 | Terraform plan **binary** | Runner | Nowhere; deleted at the end of the job | — | — | Job lifetime | No |
| F12 | Trivy check bundle, provider binaries, Helm charts | Public registries | Self-hosted runner | EEA after download | — | Cached, then discarded | Download only; nothing sent |
| F13 | Grafana dashboard access records | Grafana | Grafana's internal database | EEA | ZFS native encryption | 90 days | No |
| F14 | Uptime Kuma monitor results and notification history | Probes | Uptime Kuma's SQLite store | EEA | ZFS native encryption | 180 days | No |

**EEA-only is satisfied for every flow that carries tenant or Art. 9 data.** The single
cross-border flow, F10, carries source code, commit authorship (name and work email address)
and plan text. It carries no tenant personal data by design and by control: the plan-text cap
in `deploy.yml`, the deletion of plan binaries, the prohibition on any workflow other than
`deploy.yml` holding a credential, and the Gitleaks gate that fails on any secret committed
into that flow. Commit authorship *is* personal data of staff, and it is the residual exposure
this record accepts — see R6.

### 5. Risk assessment

Likelihood and impact are assessed before the mitigations in section 6, per the ICO and WP29
method.

| # | Risk to the rights and freedoms of data subjects | Source | Likelihood | Impact | Inherent risk |
| --- | --- | --- | --- | --- | --- |
| R1 | Loss of a backup medium exposes every tenant's data, including Art. 9 data | Physical theft, improper disposal of a decommissioned disk, an offsite copy sent to the wrong recipient | Low | Very high | **High** |
| R2 | Unredacted personal data accumulates in Loki and is retained for 30 days, readable by anyone with dashboard access | A developer logs a request body, an exception message includes an email address, a query parameter carries an identifier | High | Medium | **High** |
| R3 | Cross-tenant disclosure through the monitoring layer: a dashboard or log query shows one tenant's data to another tenant's administrator | Grafana folder permission misconfiguration, a Loki query without a namespace selector, a shared dashboard variable | Medium | High | **High** |
| R4 | Compromise of the Keycloak instance exposes every identity and, through group membership, the whole authorisation model | Unpatched CVE, credential stuffing against the admin console, a leaked service-account secret | Medium | High | **High** |
| R5 | Compromise of a self-hosted CI runner gives an attacker production credentials and therefore access to tenant backups | Malicious or compromised GitHub Action, a poisoned Terraform provider, an attacker with write access to the repository | Medium | Very high | **High** |
| R6 | Staff commit authorship and plan text are processed in the United States | GitHub as SCM and CI control plane (ADR-008) | Certain | Low | **Medium** |
| R7 | Erasure cannot be completed within one month because personal data remains in backup copies | Backup retention of 35 days exceeds the Art. 12(3) response window | Medium | Medium | **Medium** |
| R8 | Alert fatigue causes a genuine security alert to be missed, delaying awareness and breaching the 72-hour clock | Too many alerts, no severity discipline, no burn-rate alerting | High | Medium | **High** |
| R9 | Terraform state discloses resource identifiers and any credential ever passed as a resource argument | Bucket misconfiguration, a leaked state-bucket key, state copied to a workstation for debugging | Low | High | **Medium** |
| R10 | An unauditable closed-source component processes employee and client personal data with an outbound flow that cannot be inspected | Bitrix24 vendor licence validation and unknown telemetry | Medium | Medium | **Medium** — assessed in INFRA-002, not here |

### 6. Mitigations and technical measures

Each mitigation names the control, where it lives in this repository, and which risk it
reduces. A control that is not in the repository is not a control; it is an intention.

| # | Control | Where it is implemented | Reduces |
| --- | --- | --- | --- |
| M1 | Encryption at rest for every datastore: ZFS native encryption on guest datasets, age encryption for WAL-G archives, server-side encryption for the state bucket | `ansible/roles/common`, `backup/wal-g/config.yaml.example`, `terraform/backend.tf` | R1, R9 |
| M2 | Backup media disposal procedure with a witnessed record, and encryption keys held separately from the media | `backup/offsite/replication.md`, `docs/runbooks/backup-restore.md` | R1 |
| M3 | Redaction pipeline in the log **agent on every host**, not at query time and not in Loki: email addresses, IP addresses, bearer tokens, query strings, and any field named `password`, `secret` or `token` replaced before storage | `ansible/roles/monitoring-agent/templates/alloy-logs.j2` | R2 |
| M4 | Log retention of 30 days, enforced by Loki's retention configuration and verified by the staleness series in the backup alert group | `monitoring/loki/values.yaml`, `monitoring/alert-rules/backup-failed.yml` | R2 |
| M5 | Grafana folder permissions backed by Keycloak groups; per-tenant dashboards in per-tenant folders; no organisation-wide public dashboard | `monitoring/grafana/values.yaml`, `ansible/roles/keycloak` | R3 |
| M6 | Every Loki query in a committed dashboard carries a namespace selector; dashboard review is part of the pull-request checklist | `monitoring/grafana/dashboards/` | R3 |
| M7 | Keycloak as SSO for Argo CD, Grafana and the platform; MFA required for the platform team and for tenant administrators; brute-force detection enabled; the admin console reachable only from the `mgmt` VLAN | `ansible/roles/keycloak`, `docs/network-topology.md` | R4 |
| M8 | Self-hosted runners only, on the `mgmt` VLAN, with egress restricted to GitHub, the Terraform registry, the Helm repositories and the state bucket | ADR-008, `docs/network-topology.md` | R5 |
| M9 | Actions pinned to full commit SHAs; downloaded binaries pinned by version **and** verified against a SHA-256 committed in the workflow; `.terraform.lock.hcl` committed so provider hashes are checked | `.github/workflows/compliance-check.yml`, `.gitignore` negation | R5 |
| M10 | Split credentials: a read-only Proxmox token for `plan`, a write token for `apply`, in separate GitHub Environments; apply additionally requires a human approval and, for `prod`, a typed confirmation | `.github/workflows/deploy.yml` | R5, R9 |
| M11 | Terraform never creates a database credential, so none can reach state | ADR-003 decision 3, `terraform/modules/tenant` | R9 |
| M12 | Multi-window, multi-burn-rate SLO alerting so that pages mean something and tickets do not compete with them; a separate `security` route with a 15-minute escalation | `monitoring/alert-rules/slo-burn-rate.yml`, `monitoring/alertmanager/values.yaml` | R8 |
| M13 | Backup success alerted on the first failure, and a quarterly DR drill that verifies a **restore**, with the report committed as audit evidence | `monitoring/alert-rules/backup-failed.yml`, `backup/drills/dr-drill-quarterly.sh`, `backup/drills/last-drill-report.md` | R1, R7, R8 |
| M14 | Erasure procedure records which backup copies still contain the data and when they expire, so the Art. 17 response states the residual position rather than claiming completeness | `docs/runbooks/backup-restore.md`, ADR-003 decision 6 | R7 |
| M15 | Network segmentation: default-deny between VLANs, Bitrix24 in `dmz` with allow-listed egress, no route from `dmz` or `prod` to `mgmt` | `docs/network-topology.md`, `k8s/policies/network-policies/` | R4, R5, R10 |
| M16 | CIS-style hardening, `auditd`, AIDE and `fail2ban` on every VM; rolling patching inside a gated maintenance window | `ansible/roles/hardening`, `ansible/playbooks/update.yml` | R4, R5 |
| M17 | Secret scanning over the **full** git history on every push and weekly, with `--redact` so the CI log is not itself the leak | `.github/workflows/compliance-check.yml` | R5, R9 |
| M18 | State bucket versioned, locked, encrypted, on credentials separate from the backup bucket, and never readable from the `dmz` VLAN | `terraform/backend.tf`, `docs/network-topology.md` | R9 |
| M19 | Age key custody: two human custodians plus one CI identity, with an offline sealed copy and a documented 180-day rotation | ADR-005, `k8s/secrets/sops/.sops.yaml`, `docs/runbooks/backup-restore.md` | R1, R9 |
| M20 | A hard gate in Terraform: the `prod` environment refuses to instantiate a tenant module until `dpia_infra_001_signed_off` is `true`, so this document is a precondition of processing rather than a description of it | `terraform/envs/prod/variables.tf` | R2, R3, R7 |

### 7. DPO and processor consultation record

| Item | Record |
| --- | --- |
| **DPO consulted** | Yes, before this record was finalised. The DPO's two substantive interventions are reflected above: retention reduced from 90 to 30 days for logs (M4), and redaction moved from Grafana to the Loki collector (M3), because query-time filtering leaves the data on disk. |
| **Legitimate interests balancing test** | (1) *Purpose*: security and availability of systems holding Art. 9 data. (2) *Necessity*: the same outcome is not achievable with less data — an incident investigation without logs is a guess. (3) *Impact on data subjects*: staff experience the access logging any employer performs; tenant administrators experience authentication logging they are told about; third-party data subjects have no direct interaction with this layer, only the risk that their data appears in a log line, which M3 reduces. (4) *Safeguards*: retention limits, redaction, role-based dashboard access, encryption at rest. (5) *Conclusion*: the interest is legitimate, necessary and not overridden. |
| **Processor register** | GitHub Inc. — SCM and CI control plane (F10). Data processing agreement in place, Art. 46 SCCs relied on, transfer impact assessment **outstanding**: condition C1. The S3-compatible object-storage provider for the state and backup buckets — named in `docs/capacity-plan.md`, DPA required before use: condition C2. No other processor is involved at this layer. |
| **Art. 28 processors engaged by tenants** | Not in scope here. Each tenant's own processors appear in that tenant's record. |
| **Consultation where ViaVitae is a processor** | Where ViaVitae operates this platform for a religious community as processor, Art. 28(3)(h) requires assisting with audits. This record, the runbooks and the DR drill reports are the artefacts provided for that purpose. |
| **Prior consultation, Art. 36** | Not required. No residual **high** risk remains after section 6 — see section 8. |
| **Works council and staff notice** | Staff access logging (F5, F6) is disclosed in the internal acceptable-use policy. Required before the first `prod` apply: condition C3. |

### 8. Residual risk and sign-off

| # | Risk | Residual after section 6 | Accepted because |
| --- | --- | --- | --- |
| R1 | Backup media loss | **Low** | M1, M2, M19: encrypted media, keys held separately, witnessed disposal. The residual is a physical-security matter rather than a data-protection one. |
| R2 | Personal data in logs | **Medium** | M3 and M4 reduce it structurally, but redaction is pattern-based and an unusual log format will escape it. Accepted with a quarterly sample audit of stored logs against the redaction rules (C4). |
| R3 | Cross-tenant disclosure via monitoring | **Low** | M5, M6. The residual is a misconfigured dashboard variable, caught by review rather than by a control. |
| R4 | Keycloak compromise | **Medium** | M7, M15, M16. Residual: a zero-day in an identity provider is not mitigable by configuration. Compensated by MFA, so a stolen credential alone is not sufficient. |
| R5 | CI runner compromise | **Medium** | M8 to M10, M17. Residual: a compromised action pinned by SHA still runs with the job's credentials. Compensated by the read-only and write token split, which caps a pull-request compromise at read access. |
| R6 | US transfer of commit authorship | **Medium** | Accepted under ADR-008 with SCCs, conditional on C1. If the transfer impact assessment cannot be completed satisfactorily, the fallback is a self-hosted Forgejo plus Woodpecker, which supersedes ADR-008. |
| R7 | Erasure versus backup retention | **Medium-Low** | M14 makes the residual position explicit and truthful to the data subject. The 35-day bound stated in the tenant agreement is what makes it lawful rather than merely documented. |
| R8 | Alert fatigue | **Low** | M12, M13. The residual is a human-attention problem, reviewed at the monthly SLO review. |
| R9 | State disclosure | **Low** | M11, M17, M18. Residual: a state-bucket key leak still exposes identifiers. No credentials are present by design. |
| R10 | Bitrix24 | **Deferred** | Assessed in INFRA-002. ADR-007 condition 7 blocks `prod` deployment until that record is approved. |

**Overall residual risk: Medium-High**, driven by R2, R4, R5, R6 and R7. No single risk is
High after mitigation, so Art. 36 prior consultation is not triggered. The overall rating is
Medium-High rather than Medium because five independent medium risks share one compensating
control — access to the platform by a small number of people — and that control fails together.

**Conditions of approval.** Processing may start when the following are met and verified:

| # | Condition | Owner | Due |
| --- | --- | --- | --- |
| C1 | Transfer impact assessment for GitHub (F10) completed and filed, with the Art. 46 SCC reference recorded in the processor register | DPO and Legal | Before the first `prod` apply |
| C2 | DPA executed with the object-storage provider for the state and backup buckets, and the provider named in `docs/capacity-plan.md` | Legal | Before the state bucket is created |
| C3 | Staff notice for access logging published in the acceptable-use policy | Platform and HR | Before the first `prod` apply |
| C4 | Quarterly redaction sample audit (M3) scheduled, and the first one run | DPO | Within 90 days of go-live |
| C5 | INFRA-002 (Bitrix24) approved, or the Bitrix24 VM not created in `prod` | Security and DPO | Before the Bitrix24 `prod` apply |
| C6 | Tenant agreement wording confirmed to state the 35-day backup residual exposure (M14) | Legal | Before the first tenant is onboarded |

**Sign-off.**

| Role | Name or handle | Decision | Date |
| --- | --- | --- | --- |
| Assessment author | Platform engineering | Submitted | 2026-09-06 |
| Data Protection Officer | `dpo@viavitae.com` | Approved with conditions C1 to C6 | 2026-09-06 |
| Processing owner | `@Via-Vitae/platform` | Accepted the residual risk and the conditions | 2026-09-06 |
| Security | `@Via-Vitae/security` | Accepted R4, R5 and R9 with the compensating controls named | 2026-09-06 |
| Managing director | — | **Pending.** Required for an overall Medium-High rating | — |

The managing-director signature is genuinely pending and is not recorded as given. Until it
exists, this record stands at DPO approval with conditions only, and the `prod` environment
may be provisioned for non-personal-data workloads but must not carry tenant data. That
constraint is enforced mechanically by M20, not by discipline: `terraform/envs/prod` refuses
to instantiate a tenant module while `dpia_infra_001_signed_off` is `false`.

### 9. Review date

- **Next scheduled review.** **2027-03-06 — six months**, because the overall residual risk is
  Medium-High.
- **Earlier review is mandatory on:** the third Proxmox node being racked, which changes
  ADR-002's availability position and therefore the R1 and R7 analysis; any change to log,
  metric or backup retention; any new cross-border flow, including a new registry, chart
  repository or SaaS tool in CI; adoption of Vault or any external secret store, which
  supersedes ADR-005; replacement of Grafana or Loki, which changes both the AGPL position in
  ADR-009 and the dashboard-access analysis; approval of INFRA-002; any personal-data breach
  affecting the platform layer; any finding that M3 redaction failed in operation; a change in
  the number of people with platform access; or new EDPB guidance on logging and monitoring as
  processing.
- **Review owner.** DPO, supported by the platform owner and the security team.
- **Review output.** A new version number, an updated status, an updated register row and a
  restated residual risk rating. Where the review finds a control ineffective, the affected
  processing pauses and the pause is recorded here rather than handled informally.
