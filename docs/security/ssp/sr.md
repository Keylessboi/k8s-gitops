# SR — Supply Chain Risk Management

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

The supply chain is open-source images and charts from public registries, a few owner-built images, and external services. Controls in place: Renovate for updates (majors meant to be manual), digest pinning for 19% of containers, gitleaks against leaking credentials into the public repo. Missing: an SCRM plan, provider assessments, image provenance (no signatures or SBOMs), and a component disposal record. Most SR controls are planned rather than tailored out, because a hijacked image or chart is a realistic way into this system.

| Disposition | Count |
|---|---|
| Partially implemented | 6 |
| Planned | 4 |
| Not applicable | 2 |
| **Total** | **12** |
---

### SR-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Supply-chain rules sit in policy §15 (external services and supply chain) and §17. No SCRM procedure. DRAFT until merged.

**Evidence.** Policy §15, §17

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All SR.

### SR-2 Supply Chain Risk Management Plan

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** There is no SCRM plan. Policy §15 states the rules (sources, update policy, provider dependence) that a plan would carry out.

**Evidence.** Policy §15

**Gaps.**
- `G-SR-01` No supply chain risk management plan. Risk: images, charts and providers are admitted ad hoc. Remedy: a one-page plan in `docs/security/` covering trusted registries, digest pinning, scan-before-bump, provider register (`G-SA-09`), and exit plans. Target **2027-03-31**.

**Related.** SR-3, SA-4.

### SR-2(1) Establish SCRM Team

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S1: a team cannot be established; the owner is the SCRM function.

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** None.

**Related.** SR-2.

### SR-3 Supply Chain Controls and Processes

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Controls applied: Renovate PRs and automerge rules (`renovate.json`), image-updater for selected images, digest pinning (19%), CI rendering. Contradiction: policy §15.3 and HS-SUP-01 say majors are not automated, but `G-SA-05` records that Renovate on `main` automerges majors of some Z1/Tier 0–1 components.

**Evidence.** `renovate.json`; HS-SUP-01; `G-SA-05`

**Gaps.** Covered by `G-SA-05`, `G-CM-12`, `G-SR-01`.

**Related.** SA-4, SI-2.

### SR-5 Acquisition Strategies, Tools, and Methods

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Acquisition strategy: prefer upstream official images and charts, pin versions, avoid adding components (HS-PLAT-01). Not written as admission criteria (`G-SA-04`).

**Evidence.** HS-PLAT-01

**Gaps.** Covered by `G-SA-04`.

**Related.** SA-4.

### SR-6 Supplier Assessments and Reviews

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** No supplier assessment has been done; provider attestations are not reviewed (`02-tailoring.md` §4).

**Evidence.** `02-tailoring.md` §4

**Gaps.** Covered by `G-SA-09`.

**Related.** SA-9.

### SR-8 Notification Agreements

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Notification of supply-chain compromise comes from upstream security advisories and GitHub/Renovate. No agreements exist with any supplier (open source).

**Evidence.** —

**Gaps.** Covered by `G-SI-05`.

**Related.** SI-5.

### SR-10 Inspection of Systems or Components

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Components are not inspected for tampering: images are not verified by signature, and the owner-built images are not verified after push (HS-SUP-02 GAP).

**Evidence.** HS-SUP-02

**Gaps.**
- `G-SR-02` No image signature or content verification. Risk: a tampered image (upstream or the owner's own registry) runs unnoticed. Remedy: verify cosign signatures where upstream publishes them, sign the owner-built images in CI, and check after push (HS-SUP-02). Target **2027-06-30**.

**Related.** SR-11, SI-7.

### SR-11 Component Authenticity

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authenticity rests on pulling from official registries over TLS and on digest pinning (19%). No signatures, no SBOM (HS-SUP-03 GAP).

**Evidence.** HS-WL-01, HS-SUP-03

**Gaps.** Covered by `G-CM-12`, `G-SR-02`.

**Related.** SR-10.

### SR-11(1) Anti-counterfeit Training

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S1/S3: no personnel to train; the owner and agents follow `G-SR-01` once written.

**Evidence.** —

**Gaps.** None.

**Related.** AT-3.

### SR-11(2) Configuration Control for Component Service and Repair

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Hardware service and repair is done by the owner; no third-party repair has occurred. Configuration of component service is not recorded.

**Evidence.** —

**Gaps.** Covered by `G-MA-01`.

**Related.** MA-2.

### SR-12 Component Disposal

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Component disposal follows MP-6 (no procedure yet).

**Evidence.** Policy §13.4

**Gaps.** Covered by `G-MP-01`.

**Related.** MP-6.

