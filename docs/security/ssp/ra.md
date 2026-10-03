# RA — Risk Assessment

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

The system is categorized MODERATE (C=M, I=M, A=L) in policy §4, and risk has been assessed informally but repeatedly: ADR-0007's incident-class analysis, the doctor log's prevention rules, and this program's gap list. What is missing is the routine machinery: no vulnerability scanning of images or hosts, no written risk register beyond the POA&M, and no criticality analysis of supporting components (laptop, backup server, off-site target). The AI-agent risk (credentials sent to a model provider; prompt injection) is recognized in policy §10 and is this system's most distinctive risk.

| Disposition | Count |
|---|---|
| Implemented | 2 |
| Partially implemented | 4 |
| Planned | 4 |
| **Total** | **10** |
---

### RA-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Risk rules: policy §4 (categorization), §17 (vulnerabilities), §20 (risk acceptance), App. A (scan frequency, remediation times). DRAFT until merged.

**Evidence.** Policy §4, §17, §20

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All RA.

### RA-2 Security Categorization

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** FIPS 199 categorization by information type with a high-water mark: MODERATE (policy §4), reviewed by the owner when the policy is merged.

**Evidence.** Policy §4

**Gaps.** None.

**Related.** RA-9, PL-2.

### RA-3 Risk Assessment

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Assessments so far: ADR-0007 (incident classes and their causes), the doctor log's prevention lines, policy §10's agent threat analysis, and this program's gaps rated in `04-poam.md`. There is no standalone risk assessment document or threat model.

**Evidence.** `docs/adr/`; `docs/doctor-log.md`; `04-poam.md`

**Gaps.**
- `G-RA-01` No single risk assessment with likelihood and impact per threat. Risk: effort follows the last incident, not the largest risk. Remedy: `04-poam.md` risk ratings serve as the register; add a one-page threat list (internet attacker, stolen laptop, malicious image, agent error, prompt injection, hardware loss) reviewed yearly. Target **2027-03-31**.

**Related.** RA-3(1), PM-9.

### RA-3(1) Supply Chain Risk Assessment

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Supply-chain risk is considered for images (digest pinning, HS-WL-01) and providers (`02-tailoring.md` §4), not assessed systematically.

**Evidence.** HS-WL-01

**Gaps.** Covered by `G-CM-12` and `G-SA-09`.

**Related.** SR-*.

### RA-5 Vulnerability Monitoring and Scanning

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Policy App. A sets monthly scans of internet-facing images and scans on digest bumps; no scanner exists (HS-SUP-04 UNMEASURED).

**Evidence.** Policy App. A, §17; HS-SUP-04

**Gaps.** Covered by `G-SI-02`.

**Related.** SI-2.

### RA-5(2) Update Vulnerabilities to Be Scanned

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Vulnerability data would be updated by the scanner's database (e.g. Trivy DB) once `G-SI-02` is done.

**Evidence.** —

**Gaps.** Covered by `G-SI-02`.

**Related.** RA-5.

### RA-5(5) Privileged Access

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** Privileged (authenticated) host scanning is not done; would follow the CIS scan (HS-HOST-02).

**Evidence.** HS-HOST-02

**Gaps.** Covered by `G-SC-02`.

**Related.** RA-5.

### RA-5(11) Public Disclosure Program

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** No public channel for reporting vulnerabilities. The repository is public on GitHub.

**Evidence.** —

**Gaps.**
- `G-RA-02` No vulnerability disclosure channel. Risk: someone who notices a flaw in the public repo has no way to report it privately. Remedy: a `SECURITY.md` with a contact and GitHub private vulnerability reporting enabled. Target **2026-12-31**.

**Related.** IR-6.

### RA-7 Risk Response

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Findings are answered through the POA&M (`04-poam.md`) with a risk rating and milestone, accepted per item by the owner (policy §20).

**Evidence.** `04-poam.md`; policy §20

**Gaps.** None.

**Related.** CA-5.

### RA-9 Criticality Analysis

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Criticality tiers (policy §7) cover cluster components. Supporting components (operator laptop, backup server, off-site target, escrow) have no tier (`G-CP-07`).

**Evidence.** Policy §7

**Gaps.** Covered by `G-CP-07`.

**Related.** SA-15(3).

