# PS — Personnel Security

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

There are no employees (S3). PS is mostly tailored out, but two parts of its intent remain: service users joining and leaving (policy §9.3), and AI agents as non-person "personnel" that act with the owner's authority under rules of behavior (policy §10). Termination maps to leaver deprovisioning, which does not reach apps with local accounts (`G-AC-04`).

| Disposition | Count |
|---|---|
| Implemented | 1 |
| Partially implemented | 3 |
| Alternative implementation | 1 |
| Not applicable | 4 |
| **Total** | **9** |
---

### PS-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Personnel-equivalent rules: policy §9.3 (service-user lifecycle) and §10 (agents). Screening not applicable (App. A).

**Evidence.** Policy §9.3, §10, App. A

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All PS.

### PS-2 Position Risk Designation

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S3: no positions to designate. The only privileged role is the owner; agents' risk is handled by least privilege (`G-AC-10`).

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** None.

**Related.** AC-6.

### PS-3 Personnel Screening

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S3: no personnel to screen. Service users are known personally (IA-12). Recorded as a tailoring decision (`02-tailoring.md` §3.3).

**Evidence.** `02-tailoring.md` §3.3

**Gaps.** None.

**Related.** IA-12.

### PS-4 Personnel Termination

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Leaver handling for service users: disable in Authentik within 7 days (policy §9.3, App. A). Apps with local accounts are not reached (`G-AC-04`). For agents, "termination" is revoking the owner credentials they use, which is only possible by rotating the owner's own keys.

**Evidence.** Policy §9.3

**Gaps.** Covered by `G-AC-04` and `G-IA-01`.

**Related.** AC-2.

### PS-5 Personnel Transfer

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Transfers map to group changes in Authentik (e.g. leaving `authentik Admins`), done by the owner; no review after a change.

**Evidence.** `docs/accounts.md`

**Gaps.** Covered by `G-AC-31`.

**Related.** AC-2.

### PS-6 Access Agreements

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** Access agreements: service users accept no written terms. Agents operate under policy §10 and `AGENTS.md`, which they load as context.

**Evidence.** Policy §10

**Gaps.** Service-user notice is `G-SI-11`.

**Related.** PL-4.

### PS-7 External Personnel Security

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No external personnel (contractors) have access. The model providers process data but hold no access; they are SA-9 external services.

**Evidence.** `02-tailoring.md` §4

**Gaps.** None.

**Related.** SA-9.

### PS-8 Personnel Sanctions

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S3: no employees to sanction. Agent misbehaviour is handled by the agent-misbehaviour playbook (policy §16) and by reverting and tightening rules.

**Evidence.** Policy §16

**Gaps.** None.

**Related.** IR-4.

### PS-9 Position Descriptions

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Roles and responsibilities, including the agents' and service users', are in policy §3.1.

**Evidence.** Policy §3.1

**Gaps.** None.

**Related.** PL-4.

