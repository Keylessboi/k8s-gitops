# IR — Incident Response

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Incident response here is real and well exercised for **availability** incidents, and almost untested for **security** incidents. The doctor log (`docs/doctor-log.md`, 70 top-level entries from 2026-08-26 to 2026-09-28) is a genuine incident record with a symptom index that `scripts/doctor.sh` greps automatically, and its "Prevention" discipline has turned repeated incidents into CI checks (`scripts/ci/check-invariants.py`; ADR-0007). Detection and notification have been rebuilt twice after real failures (the 2026-09-04 pve power-off went unnoticed for 3h37m), and now include an external watchdog on the nas, an edge probe on travisbackupserver, and two delivery paths (ntfy and email). The written plan is policy §16 (severity scale, phases, a credential-exposure playbook, an agent-misbehaviour playbook, and a 72-hour duty to tell affected service users). The gaps: the policy is still a DRAFT (§21); the §16 severity scale has never been applied to an entry; no security incident or near-miss has ever been recorded, although at least two are documented elsewhere in the repo; none of the §16 playbooks has been exercised; service users have no documented way to report anything; and the incident record is public, with no provision for keeping an active security incident private. The family-wide decision is that a single person is the whole incident response capability, with AI agents as assistants that diagnose and record but never declare, approve or contain by themselves (policy §3.1, §10).

| Disposition | Count |
|---|---|
| Implemented | 1 |
| Partially implemented | 10 |
| Planned | 2 |
| Inherited | 0 |
| Alternative implementation | 0 |
| Not applicable | 0 |

### IR-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (Security Officer role, policy §3.1) |
| **Parameters** | ir-1_prm_1 = the System Owner and every automated operator (policy §3.1); ir-01_odp.03 = system-level; ir-01_odp.04 = the System Owner; ir-01_odp.05 = 12 months (policy App. A); ir-01_odp.06 = a SEV-1 or SEV-2 incident, a new Tier 0 or 1 component, a change in who has privileged access, a major platform change recorded in an ADR (App. A); ir-01_odp.07 = 12 months (App. A); ir-01_odp.08 = the ir-01_odp.06 events, plus any doctor-log entry whose prevention changes a runbook |

> a. Develop, document, and disseminate to [Assignment: the System Owner and every automated operator]:
>   1. [Selection: system-level] incident response policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the incident response policy and the associated incident response controls;
> b. Designate an [Assignment: the System Owner] to manage the development, documentation, and dissemination of the incident response policy and procedures; and
> c. Review and update the current incident response:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident; a new Tier 0 or 1 component; a change in who has privileged access; a major platform change (an ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, and any doctor-log entry whose prevention changes a runbook].

**Implementation.**

**a.1.** The incident response policy is `docs/security/01-policy.md` §16, read with the sections it depends on. Purpose and scope are §1 and §2 (§2.1 brings agent transcripts and the operator workstation into scope, which matters for credential exposure). Roles and responsibilities are §3.1: the owner holds every human role, and the Automated Operator role "never approves its own work". Management commitment is the approval clause (§21) and risk acceptance (§20). Coordination among entities is §16.6 (telling service users) and §3.2 (compensating controls for having one person). Compliance is §19. **(b)** Consistency with law is not addressed. The policy says nothing about statutory breach-notification duties for the friends' and family's data it holds (G-IR-02).

**a.2.** Procedures are runbooks, not a single document: `scripts/doctor.sh` and `docs/doctor-log.md` (diagnosis and prior art); `docs/recovery/cluster-down.md` (full outage); `docs/ntfy.md` (notification chain, including hand verification); `docs/access-procedures.md` "Emergency Bypass" and policy §9.6 (break-glass); `docs/RUNDOWN.md` "When Something Breaks" and "Security at the Edge" (CrowdSec lockout); `.github/pull_request_template.md` and `CONTRIBUTING.md` (the shape of a fix and its log entry). The two security playbooks, credential exposure (§16.5) and agent misbehaviour (§16.7), exist only inside the policy.

**Dissemination.** The repository is public, so the policy reaches every reader. Agents reach it through `AGENTS.md:78`, which points them at §5–6, §8 and §10, but **not** §16 (G-IR-03).

**b.** The System Owner holds the Security Officer role (§3.1).

**c.** The review cadence is in the document control table and §19. The policy is version 0.1, **DRAFT**, and "not in force until the owner approves it" (§21), so no review cycle has started yet (G-IR-01).

**Evidence.** `docs/security/01-policy.md` (document control, §3, §16, §19, §21); the runbooks listed above; `AGENTS.md:78`.

**Gaps.**
- `G-IR-01`: The policy, including §16, is an unapproved draft. Risk: nothing in the IR family is formally in force, and agents are told only that they "SHOULD" follow it (§21). Remedy: the owner reviews and merges `01-policy.md`. Target 2026-11-01.
- `G-IR-02`: No analysis of legal breach-notification obligations toward service users. Risk: the 72-hour user notice in §16.6 may not match an obligation that applies, or a regulator that should be told might not be. Remedy: the owner records the applicable jurisdiction and any notification duty in §16.6, or records that none applies and why. Target 2027-01-31.

**Related.** Policy §1–3, §16, §19, §21; IR-8; HS-AGENT-08; HS-OBS-05.

