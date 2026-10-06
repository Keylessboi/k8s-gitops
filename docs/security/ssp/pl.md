# PL — Planning

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

This program is the planning family: the system description and SSP (`00`, `ssp/`), the rules of behavior (policy §10 for agents, §9 for users), and the baseline selection and tailoring (`02`). Its main weakness is status: everything is a DRAFT until the owner merges it, and the rules of behavior bind agents only as far as each harness loads `AGENTS.md`.

| Disposition | Count |
|---|---|
| Implemented | 2 |
| Partially implemented | 5 |
| **Total** | **7** |
---

### PL-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Planning rules are policy §19 (review) and §21 (approval); the README explains how the documents fit together.

**Evidence.** `docs/security/README.md`; policy §19, §21

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** PL-2.

### PL-2 System Security and Privacy Plans

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** The SSP is `00-system-description.md` plus `ssp/` (one file per family, 287 controls), `02-tailoring.md` and `04-poam.md`. Drafted 2026-10-01..03 from the repository only; runtime verification pending (`G-CA-01`). Kept current by `scripts/security/ssp-index.py`.

**Evidence.** `docs/security/`

**Gaps.** Covered by `G-CA-01`.

**Related.** CA-2, PL-10.

### PL-4 Rules of Behavior

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Rules of behavior: policy §10 and `AGENTS.md` for AI agents (never read secrets, no Zone 0, Zone 1 through PR, stop-and-ask points); policy §9 for service users. Agents acknowledge them only implicitly by loading `AGENTS.md`; service users never see theirs.

**Evidence.** Policy §9, §10; `AGENTS.md`

**Gaps.** Covered by `G-AT-02`, `G-AT-03`.

**Related.** PL-4(1), AT-2.

### PL-4(1) Social Media and External Site/Application Usage Restrictions

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Social media and external-site rules apply to agents as "do not send C3/C4 to external services" (policy §10, HS-SEC-03). Not applicable to service users' own use.

**Evidence.** Policy §10

**Gaps.** None.

**Related.** PL-4.

### PL-8 Security and Privacy Architectures

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Security architecture is described in `00-system-description.md` §3 and §6 and in ADRs (state protection ADR-0012, storage ADR-0001/0009, incident classes ADR-0007). No single architecture document.

**Evidence.** `docs/adr/`; `00-system-description.md`

**Gaps.** Covered by `G-SA-08`.

**Related.** SA-8.

### PL-10 Baseline Selection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** NIST SP 800-53 Rev. 5 MODERATE baseline selected from the FIPS 199 categorization (`02-tailoring.md` §1).

**Evidence.** `02-tailoring.md` §1

**Gaps.** None.

**Related.** RA-2, PL-11.

### PL-11 Baseline Tailoring

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** The baseline is tailored with recorded scoping considerations (S1–S7), dispositions per control, and parameter values (`02-tailoring.md` §2–§3).

**Evidence.** `02-tailoring.md`

**Gaps.** None.

**Related.** PL-10.

