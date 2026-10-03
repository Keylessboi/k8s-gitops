# CA — Assessment, Authorization, and Monitoring

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

The owner is assessor and authorizing official at once (S1), so CA's independence requirements are met by an alternative: assessments that machines run (CI checks, backup freshness, the monthly restore drill, the heartbeat watchdog) plus self-assessment recorded in this program, with every unmeasured status said out loud. Authorization is the owner merging the policy and this SSP (policy §21). The POA&M (`04-poam.md`) is the plan of action. There is no independent assessment and no scheduled re-measurement yet.

| Disposition | Count |
|---|---|
| Implemented | 2 |
| Partially implemented | 6 |
| Alternative implementation | 2 |
| **Total** | **10** |
---

### CA-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Policy §19 (compliance, measurement, review) and §20–21 (risk acceptance, approval) are the CA policy. Procedures: `03-homelab-standard.md` (how each requirement is measured), `scripts/security/ssp-index.py`, `scripts/doctor.sh`. DRAFT until merged.

**Evidence.** Policy §19–21

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All CA.

### CA-2 Control Assessments

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** This program (00–04 and `ssp/`) is the first assessment, written 2026-10-01..03 from the repository only; runtime state was not inspected, and the status columns of `03` are self-measured. Policy §19 sets a 3-monthly re-measurement of `03`.

**Evidence.** `README.md` ("How this was produced"); policy §19

**Gaps.**
- `G-CA-01` The assessment never inspected the running system; every [UNVERIFIED] item is open. Risk: the documents describe intent, not reality. Remedy: one runtime verification pass that settles each [UNVERIFIED] item with a command and records the result, then the 3-monthly re-measure. Target **2027-01-31**.

**Related.** CA-7, RA-3.

### CA-2(1) Independent Assessors

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S1: no independent assessor is available. Compensation: automated checks whose results are not the owner's opinion (CI `validate`, `check-protected-state.py`, `check-invariants.py`, backup freshness, restore drill), and AI-drafted assessment checked against cited evidence. Residual risk: blind spots shared by the owner and the tooling.

**Evidence.** `.github/workflows/validate.yaml`; `scripts/ci/`; `apps/databases/restore-drill-cronjob.yaml`

**Gaps.** None.

**Related.** CA-7(1).

### CA-3 Information Exchange

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Interconnections with external providers are listed in `00-system-description.md` §2.2 and `02-tailoring.md` §4 (what crosses, what is inherited). No per-connection agreement exists beyond each provider's terms of service.

**Evidence.** `02-tailoring.md` §4

**Gaps.** Covered by `G-SA-09` (external-service register).

**Related.** SA-9, SC-7(4).

### CA-5 Plan of Action and Milestones

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** `04-poam.md` is the plan of action and milestones: every SSP gap is traced to a POA&M item (checked by `scripts/security/ssp-index.py check`), reviewed monthly (policy §19).

**Evidence.** `04-poam.md`; `scripts/security/ssp-index.py`

**Gaps.** None.

**Related.** PM-4 (not in baseline), CA-7.

### CA-6 Authorization

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** The System Owner is the authorizing official; authorization happens when the owner merges this program (policy §21) and accepts residual risk per POA&M item (§20). Not yet merged.

**Evidence.** Policy §20–21

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** CA-2.

### CA-7 Continuous Monitoring

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Continuous monitoring today: CI on every push (render, schema, invariants, protected-state, gitleaks), Prometheus alerts to ntfy, the heartbeat watchdog, backup freshness from stored data (HS-REC-02), and the monthly restore drill. Gaps: CI does not gate (HS-GIT-03) and `main` is red; security events are unmonitored (`G-SI-09`); no vulnerability scanning (`G-SI-02`).

**Evidence.** `.github/workflows/validate.yaml`; `docs/ntfy.md`; HS-REC-02, HS-GIT-03

**Gaps.** Covered by `G-AC-09`, `G-SI-09`, `G-SI-02`.

**Related.** SI-4, RA-5.

### CA-7(1) Independent Assessment

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** As CA-2(1): automated checks stand in for an independent assessor.

**Evidence.** —

**Gaps.** None.

**Related.** CA-2(1).

### CA-7(4) Risk Monitoring

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Risk monitoring: monthly POA&M review and 3-monthly re-measurement of `03` (policy §19), and doctor-log entries after incidents. Neither cadence has run yet.

**Evidence.** Policy §19

**Gaps.** Covered by `G-CA-01`.

**Related.** RA-3.

### CA-9 Internal System Connections

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Internal connections between namespaces are declared as NetworkPolicy allows on both ends and checked in CI (HS-NET-02). Internal host connections (NFS, Tailscale) are listed in `00-system-description.md` §3 and §6.

**Evidence.** `scripts/ci/check-invariants.py`; `00-system-description.md` §3, §6

**Gaps.** Dead selectors tracked as `G-AC-08`.

**Related.** AC-4.

