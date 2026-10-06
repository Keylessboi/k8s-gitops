# 02 — Baseline Selection and Tailoring

**Part of:** the Homelab Information Security Program (see `README.md` in this
directory) · **Version:** 0.1 draft · **Written:** 2026-10-03 · **Status:**
DRAFT, in force when the System Owner merges it (`01-policy.md` §21)

This document records which NIST SP 800-53 Rev. 5 controls apply to the
homelab, which are met by someone else, which are tailored out, and why. The
per-control reasoning lives in `ssp/`. This file is the index of those
decisions and the rules they were made under.

The tables in §5–§8 are **generated** from the `ssp/` files by
`scripts/security/ssp-index.py write`. Edit the SSP section, then rerun the
script. Do not edit a generated table by hand.

## 1. Baseline selection

The system is categorized **MODERATE** (`01-policy.md` §4): confidentiality
MODERATE and integrity MODERATE, driven by the credentials in Doppler, the
password vaults in Vaultwarden and the identity store in Authentik.
Availability is LOW.

| Option | Why not |
|---|---|
| LOW baseline | It would leave out controls that the credential and identity data need, among them: automated account management (AC-2(1)–(4)), separation of duties (AC-5), public-key authenticator management and authenticator protection (IA-5(2), IA-5(6)), automated audit review and correlation (AU-6(1), AU-6(3)), configuration change control (CM-3), boundary protection enhancements (SC-7(3)–(5), (7), (8)) and supplier assessment (SR-6). Those are where this system's real risks sit. |
| HIGH baseline | No information type here reaches HIGH (`01-policy.md` §4), so the controls and enhancements HIGH adds are not called for by the impact. Where a specific HIGH-only enhancement would address a real risk here, it is added as supplementation (§3.4) rather than by adopting the whole baseline. |

**Selected:** NIST SP 800-53 Rev. 5 **MODERATE** baseline, catalog release
5.2.0 as published by NIST in OSCAL (`usnistgov/oscal-content`), **287
controls and enhancements**. The list, in catalog order, is
`ssp/baseline-moderate.tsv`.

A FIPS 199 high-water mark of MODERATE means the MODERATE baseline applies
in full, including its availability controls, before tailoring. The low
availability impact is used as a *tailoring* argument, control by control
(§3.1 S5). It does not remove the availability controls wholesale.

## 2. How tailoring was done

NIST SP 800-53B describes tailoring as a set of activities: identify common
(inherited) controls, apply scoping considerations, select compensating
controls, assign values to organization-defined parameters, supplement the
baseline where the risk calls for it, and record the specification
information. Each of those is recorded here:

| Activity | Where it is recorded |
|---|---|
| Inherited controls | §4 here, and each SSP section marked **Inherited** |
| Scoping considerations | §3.1 here, cited in each **Not applicable** section |
| Compensating controls | Each SSP section marked **Alternative implementation**, summarised in §6 |
| Parameter values | Each SSP section's **Parameters** row; defaults in `01-policy.md` Appendix A |
| Supplementation | §3.4 here, and the testable requirements in `03-homelab-standard.md` |
| Specification information | The **Implementation** paragraphs in `ssp/` |

Every control in the baseline has a section in `ssp/`, even when it is
tailored out. That is deliberate: a control dropped without a written
reason cannot be reviewed.

The SSP sections were drafted by AI agents from the repository and its
documentation, without inspecting the running system (`README.md`, "How
this was produced"). A disposition is therefore the drafter's reading of the
evidence it cites. Claims that need a live check are marked
**[UNVERIFIED]** and carry a gap.

About 50 sections (written 2026-10-01/02) are in **full form**: the control
statement quoted with parameters filled in, and several paragraphs of
implementation. The rest (written 2026-10-03) are in **compact form**: no
quoted statement, parameters take the `01-policy.md` Appendix A defaults, and
the implementation is a short paragraph that cites the standard's HS-IDs.
Both forms carry the same disposition, evidence, gaps and related fields, and
the same no-invented-facts rule. A compact section can be expanded at any
review without changing its disposition.

## 3. Tailoring rules

### 3.1 Scoping considerations

These are the facts about this system that justify scoping a control, or a
part of one, out. A **Not applicable** or **Alternative implementation**
section names the consideration it relies on.

| Id | Consideration | Effect |
|---|---|---|
| **S1** | **One person holds every role** (`01-policy.md` §3). There is no second person to approve, review, separate duties from, or assess independently. | Controls that require separation between people (AC-5, CA-2(1), CA-7(1), the approval step in CM-3) are met by an alternative: automated checks, an immutable record, or a time delay standing in for the second person (`01-policy.md` §3.2). |
| **S2** | **The servers are in a home**, not a facility. pve and nas share one site; travisbackupserver is at a second residential site. | Facility controls (visitor logs, badge systems, guards, emergency lighting, fire suppression, water shutoff valves) are not applicable. Physical *risk* is not: theft, a child or guest at the console, power loss and heat remain, and are covered in `ssp/pe.md`. |
| **S3** | **No employees, contractors or third-party personnel.** Service users are friends and family who use the apps; they have no administrative role. | Personnel screening, position risk designation and personnel sanctions are not applicable as written. Account lifecycle for service users (`01-policy.md` §9.3) and AI agents as non-person actors (S6) carry the parts of the intent that remain. |
| **S4** | **Not a federal system.** No U.S. Government users, no PIV cards, no federal agency interconnections, no FIPS 140 validation requirement. | PIV acceptance (IA-2(12), IA-8(1)) is not applicable. "FIPS-validated" cryptography is read as "current, maintained, standard cryptography" (TLS 1.2+, ZFS native encryption, SSH ed25519) unless a section says otherwise. |
| **S5** | **Availability is LOW and the cluster is a single node by design** (waiver W-06, `03-homelab-standard.md` §12). | Controls that assume redundancy (alternate processing site, redundant secondary systems, failover) are tailored out. W-06 does **not** excuse backup, restore or monitoring requirements (`01-policy.md` §18.5). |
| **S6** | **AI agents operate the system with the owner's credentials** (`01-policy.md` §9.2, §10). They are not people and have no identity of their own today. | They are treated as *automated operators*: their rules of behavior are `01-policy.md` §10 and `AGENTS.md`, and controls written for "users" or "personnel" are applied to them where the risk is the same (rules of behavior, least privilege, accountability). |
| **S7** | **The configuration repository is public** (`00-system-description.md` §1). | Confidentiality controls on configuration are moot. Integrity controls on it are not, since a merge deploys to production. |

### 3.2 Dispositions

Every SSP section has exactly one of these. They are defined in the SSP
brief and repeated here so that a reader of the SSP does not need it.

| Disposition | Meaning |
|---|---|
| **Implemented** | Fully in place, with cited evidence |
| **Partially implemented** | Some parts in place; the rest is a gap in the POA&M |
| **Planned** | Not in place; a POA&M item says how and by when |
| **Inherited (provider)** | Satisfied by an external provider, for the parts named; the owner's remaining share is stated |
| **Alternative implementation** | The intent is met another way suited to this system (a compensating control); the section explains why the intent still holds |
| **Not applicable** | Cannot apply here, for a reason specific to this system (§3.1); any residual risk is named and covered elsewhere |

A **Not applicable** disposition is a decision the System Owner accepts by
merging this file. Agents **MUST NOT** change a disposition to
**Not applicable** without saying so in the PR description (`01-policy.md`
§18.3: an agent may propose, not grant).

### 3.3 Parameter values

Organization-defined parameters take the defaults in `01-policy.md`
Appendix A unless the SSP section gives a different value and a reason.
"Organization-defined personnel or roles" resolves to the System Owner
(S1).

Two Appendix A values are themselves tailoring decisions and are recorded
here:

- **Audit record retention: 30 days online, no long-term archive.** The
  logs hold no record that a law or contract requires keeping. The cost is that a compromise found later than 30 days after it began
  cannot be reconstructed from logs; git history, the doctor log and backups
  are the longer record. See AU-11 in `ssp/au.md`.
- **Personnel screening: not applicable** (S3). See PS-3 in `ssp/ps.md`.

### 3.4 Supplementation

The MODERATE baseline has no control written for an AI agent that acts with
an administrator's credentials, sends what it reads to a third party, and
can be steered by text it reads. That is this system's most distinctive
risk, so the program adds requirements the baseline does not have:

- `01-policy.md` §10 (agent conduct) and the `HS-AGENT-*` requirements in
  `03-homelab-standard.md`;
- the rule that no secret value is ever read (`HS-SEC-03`, `AGENTS.md`),
  enforced on the owner's machine by a command hook;
- the state-protection component that stops any agent, or any git change,
  from pruning a PVC, PV, Namespace or database cluster (ADR-0012,
  `components/protect-state`, `scripts/ci/check-protected-state.py`).

These are carried in the SSP under the controls whose intent they serve
(rules of behavior, least privilege, information handling, configuration
change control). Search `ssp/` for `HS-AGENT` to find them.

## 4. Inherited controls and interconnections

Each external service in `00-system-description.md` §2.2 is an
interconnection. What the provider does inside its own infrastructure
(physical security, its personnel, its hardware, its availability) is
**inherited**: the owner relies on it and cannot inspect it. What the
owner configures (accounts, MFA, token scope, what data is sent) is **not**
inherited and stays in the owner's controls.

| Provider | Inherited from it | Stays with the owner | Data class that crosses |
|---|---|---|---|
| GitHub (repository, Actions) | Hosting, availability and integrity of the git history; isolation of Actions runners | Account MFA; branch protection (none today); which secrets Actions may use; that nothing secret is committed (HS-SEC-01, gitleaks) | C1 (public configuration) |
| Doppler | Storage, encryption and availability of the secret store | Account MFA; service-token scope per project; who and what can read; rotation (`01-policy.md` §12) | C4 (every credential) |
| Tailscale | The coordination server, key distribution, NAT traversal | Account MFA; ACLs; which devices join; key expiry | C3–C4 in transit (admin sessions, backup stream) |
| Cloudflare | Authoritative DNS service | Account MFA; the records; API token scope | C1 |
| Let's Encrypt | Certificate issuance and revocation infrastructure | cert-manager configuration; private keys, which never leave the cluster | C1 |
| AirVPN | The egress tunnel and its exit servers | That only the torrent stack uses it (gluetun); account credentials | C1–C2 (peer-to-peer traffic) |
| Container registries | Hosting and availability of images | Which images are trusted; digest pinning (HS-WL-01); update policy (Renovate) | C1 |
| Model providers (Anthropic and others) | Processing and retention of what agents send | What agents are allowed to read (`01-policy.md` §10, HS-SEC-03); which provider and plan is used | Whatever an agent reads; C4 if a secret is printed |
| Off-site borgmatic target | Storage of the off-site backup copy | Encryption before upload; freshness; restore tests | C2–C4, encrypted. **[UNVERIFIED]** which host receives it |

**What is not established:** the owner has not reviewed any provider's
security attestation (for example a SOC 2 report or published security
whitepaper) for this program. The inherited column is therefore *reliance*,
not *assurance*. Recording which attestation each provider publishes, and
reviewing it at the yearly policy review, is a POA&M item (see SA-9 and
SR-6 in `ssp/`).

SSP sections marked **Inherited**:

<!-- BEGIN generated: inherited -->
| Control | Title | Disposition |
|---|---|---|
| [AC-17(2)](ssp/ac.md#ac-172-protection-of-confidentiality-and-integrity-using-encryption) | Protection of Confidentiality and Integrity Using Encryption | Inherited (Tailscale) |
| [SC-7(4)](ssp/sc.md#sc-74-external-telecommunications-services) | External Telecommunications Services | Inherited (ISP, Tailscale, AirVPN) |
| [SC-17](ssp/sc.md#sc-17-public-key-infrastructure-certificates) | Public Key Infrastructure Certificates | Inherited (Let's Encrypt) |
| [SC-20](ssp/sc.md#sc-20-secure-nameaddress-resolution-service-authoritative-source) | Secure Name/Address Resolution Service (Authoritative Source) | Inherited (Cloudflare) |
| [SC-22](ssp/sc.md#sc-22-architecture-and-provisioning-for-nameaddress-resolution-service) | Architecture and Provisioning for Name/Address Resolution Service | Inherited (Cloudflare) |
| [SI-16](ssp/si.md#si-16-memory-protection) | Memory Protection | Inherited (OS and runtime) |
<!-- END generated: inherited -->

## 5. Controls tailored out

Each row links to its SSP section, which gives the full rationale and any
residual risk. The summary column is the section's first sentence.

<!-- BEGIN generated: not-applicable -->
| Control | Title | Why it does not apply here |
|---|---|---|
| [AC-2(2)](ssp/ac.md#ac-22-automated-temporary-and-emergency-account-management) | Automated Temporary and Emergency Account Management | The system creates no temporary or emergency accounts. |
| [AC-11](ssp/ac.md#ac-11-device-lock) | Device Lock | Device lock is a property of the user's own device, which is outside the boundary (policy §2.2) except for the operator laptop, whose screen lock is the owner's setting and **[UNVERIFIED]**. |
| [AC-11(1)](ssp/ac.md#ac-111-pattern-hiding-displays) | Pattern-hiding Displays | Follows AC-11: no in-boundary device presents a console session that needs pattern-hiding. |
| [AC-20(2)](ssp/ac.md#ac-202-portable-storage-devices--restricted-use) | Portable Storage Devices — Restricted Use | No portable storage is used with external systems. |
| [CM-2(7)](ssp/cm.md#cm-27-configure-systems-and-components-for-high-risk-areas) | Configure Systems and Components for High-risk Areas | Tailored out. |
| [CP-7](ssp/cp.md#cp-7-alternate-processing-site) | Alternate Processing Site | S5: availability is LOW and the cluster is single-node and single-site by design (W-06). |
| [CP-7(1)](ssp/cp.md#cp-71-separation-from-primary-site) | Separation from Primary Site | Follows CP-7: no alternate processing site. |
| [CP-7(2)](ssp/cp.md#cp-72-accessibility) | Accessibility | Follows CP-7. |
| [CP-7(3)](ssp/cp.md#cp-73-priority-of-service) | Priority of Service | Follows CP-7. |
| [CP-8](ssp/cp.md#cp-8-telecommunications-services) | Telecommunications Services | S5: a single residential ISP link; |
| [CP-8(1)](ssp/cp.md#cp-81-priority-of-service-provisions) | Priority of Service Provisions | Follows CP-8. |
| [CP-8(2)](ssp/cp.md#cp-82-single-points-of-failure) | Single Points of Failure | Follows CP-8. |
| [IA-2(12)](ssp/ia.md#ia-212-acceptance-of-piv-credentials) | Acceptance of PIV Credentials | S4: not a federal system; |
| [IA-8(1)](ssp/ia.md#ia-81-acceptance-of-piv-credentials-from-other-agencies) | Acceptance of PIV Credentials from Other Agencies | S4: no PIV credentials from other agencies. |
| [IA-8(2)](ssp/ia.md#ia-82-acceptance-of-external-authenticators) | Acceptance of External Authenticators | No external authenticators (federated logins from other IdPs) are accepted; |
| [IA-12(2)](ssp/ia.md#ia-122-identity-evidence) | Identity Evidence | No documentary identity evidence is collected; |
| [IA-12(3)](ssp/ia.md#ia-123-identity-evidence-validation-and-verification) | Identity Evidence Validation and Verification | Follows IA-12(2). |
| [MA-3(1)](ssp/ma.md#ma-31-inspect-tools) | Inspect Tools | No maintenance tools are brought in from outside; |
| [MA-3(2)](ssp/ma.md#ma-32-inspect-media) | Inspect Media | No diagnostic media is introduced to the systems. |
| [MA-3(3)](ssp/ma.md#ma-33-prevent-unauthorized-removal) | Prevent Unauthorized Removal | No maintenance equipment leaves the home; |
| [MP-3](ssp/mp.md#mp-3-media-marking) | Media Marking | No media leaves the systems or is distributed; |
| [MP-5](ssp/mp.md#mp-5-media-transport) | Media Transport | No system media is transported; |
| [PE-4](ssp/pe.md#pe-4-access-control-for-transmission) | Access Control for Transmission | Cabling is inside the home; |
| [PE-5](ssp/pe.md#pe-5-access-control-for-output-devices) | Access Control for Output Devices | Output devices (console screens) are not used in normal operation; |
| [PE-6](ssp/pe.md#pe-6-monitoring-physical-access) | Monitoring Physical Access | S2: no facility monitoring. |
| [PE-6(1)](ssp/pe.md#pe-61-intrusion-alarms-and-surveillance-equipment) | Intrusion Alarms and Surveillance Equipment | Follows PE-6. |
| [PE-8](ssp/pe.md#pe-8-visitor-access-records) | Visitor Access Records | S2: no visitor records in a home. |
| [PE-9](ssp/pe.md#pe-9-power-equipment-and-cabling) | Power Equipment and Cabling | Power cabling is household wiring; |
| [PE-10](ssp/pe.md#pe-10-emergency-shutoff) | Emergency Shutoff | No facility emergency shutoff; |
| [PE-12](ssp/pe.md#pe-12-emergency-lighting) | Emergency Lighting | Household lighting; |
| [PE-13(1)](ssp/pe.md#pe-131-detection-systems--automatic-activation-and-notification) | Detection Systems — Automatic Activation and Notification | No automatic fire detection that notifies anyone other than household alarms. |
| [PE-15](ssp/pe.md#pe-15-water-damage-protection) | Water Damage Protection | No water shutoff valves to manage; |
| [PE-16](ssp/pe.md#pe-16-delivery-and-removal) | Delivery and Removal | Equipment delivery and removal is the owner's; |
| [PS-2](ssp/ps.md#ps-2-position-risk-designation) | Position Risk Designation | S3: no positions to designate. |
| [PS-3](ssp/ps.md#ps-3-personnel-screening) | Personnel Screening | S3: no personnel to screen. |
| [PS-7](ssp/ps.md#ps-7-external-personnel-security) | External Personnel Security | No external personnel (contractors) have access. |
| [PS-8](ssp/ps.md#ps-8-personnel-sanctions) | Personnel Sanctions | S3: no employees to sanction. |
| [SA-4(10)](ssp/sa.md#sa-410-use-of-approved-piv-products) | Use of Approved PIV Products | The system implements no PIV capability. |
| [SC-15](ssp/sc.md#sc-15-collaborative-computing-devices-and-applications) | Collaborative Computing Devices and Applications | No collaborative computing devices (cameras, microphones) are part of the system. |
| [SC-18](ssp/sc.md#sc-18-mobile-code) | Mobile Code | No mobile code policy is meaningful for a server system serving web apps; |
| [SI-8](ssp/si.md#si-8-spam-protection) | Spam Protection | The system runs no mail server; |
| [SI-8(2)](ssp/si.md#si-82-automatic-updates) | Automatic Updates | Follows SI-8. |
| [SR-2(1)](ssp/sr.md#sr-21-establish-scrm-team) | Establish SCRM Team | S1: a team cannot be established; |
| [SR-11(1)](ssp/sr.md#sr-111-anti-counterfeit-training) | Anti-counterfeit Training | S1/S3: no personnel to train; |
<!-- END generated: not-applicable -->

## 6. Alternative (compensating) implementations

<!-- BEGIN generated: alternative -->
| Control | Title | How the intent is met instead |
|---|---|---|
| [AC-5](ssp/ac.md#ac-5-separation-of-duties) | Separation of Duties | S1 (`02-tailoring.md` §3.1): one person holds every role, so duties cannot be split between people. |
| [AT-3](ssp/at.md#at-3-role-based-training) | Role-based Training | Role-based training for the only privileged role is the owner reading the policy and the doctor log at each review (App. |
| [AU-9(4)](ssp/au.md#au-94-access-by-subset-of-privileged-users) | Access by Subset of Privileged Users | S1: only one person can hold privileged access, so a subset of privileged users cannot be defined. |
| [CA-2(1)](ssp/ca.md#ca-21-independent-assessors) | Independent Assessors | S1: no independent assessor is available. |
| [CA-7(1)](ssp/ca.md#ca-71-independent-assessment) | Independent Assessment | As CA-2(1): automated checks stand in for an independent assessor. |
| [CM-3(4)](ssp/cm.md#cm-34-security-and-privacy-representatives) | Security and Privacy Representatives | The change authority is one person, who also holds the Security Officer role and is Data Owner for system data (policy §3.1). |
| [CM-12(1)](ssp/cm.md#cm-121-automated-tools-to-support-information-location) | Automated Tools to Support Information Location | No automated discovery tool; |
| [CP-2(1)](ssp/cp.md#cp-21-coordinate-with-related-plans) | Coordinate with Related Plans | One person writes the incident response policy (§16), the change rules (§11), the POA&M, the capacity plan (`docs/expansion-plan.md`) and the ADRs. |
| [CP-3](ssp/cp.md#cp-3-contingency-training) | Contingency Training | There is no training programme, and one cannot be justified: the only person with a contingency role wrote every runbook. |
| [CP-4(1)](ssp/cp.md#cp-41-coordinate-with-related-plans) | Coordinate with Related Plans | One person owns every related plan, so coordination is with plans, not with people. |
| [IA-7](ssp/ia.md#ia-7-cryptographic-module-authentication) | Cryptographic Module Authentication | S4: FIPS 140 validation is not required. |
| [IA-12](ssp/ia.md#ia-12-identity-proofing) | Identity Proofing | S3/S4: service users are people the owner knows personally; |
| [IA-12(5)](ssp/ia.md#ia-125-address-confirmation) | Address Confirmation | Address confirmation is replaced by the owner delivering initial credentials over a channel already known to belong to the person. |
| [IR-7](ssp/ir.md#ir-7-incident-response-assistance) | Incident Response Assistance | S1: there is no help desk. |
| [MA-5](ssp/ma.md#ma-5-maintenance-personnel) | Maintenance Personnel | S1: the owner is the only maintenance person. |
| [MP-2](ssp/mp.md#mp-2-media-access) | Media Access | Digital media are fixed disks inside servers in a home (S2). |
| [PE-2](ssp/pe.md#pe-2-physical-access-authorizations) | Physical Access Authorizations | S2: authorized physical access is the household; |
| [PE-3](ssp/pe.md#pe-3-physical-access-control) | Physical Access Control | As PE-2: the home's locks control entry. |
| [PE-13](ssp/pe.md#pe-13-fire-protection) | Fire Protection | Household smoke detection is the home's; |
| [PS-6](ssp/ps.md#ps-6-access-agreements) | Access Agreements | Access agreements: service users accept no written terms. |
| [SA-4(2)](ssp/sa.md#sa-42-design-and-implementation-information-for-controls) | Design and Implementation Information for Controls | The intent is that the organization can see how a control is built. |
| [SC-13](ssp/sc.md#sc-13-cryptographic-protection) | Cryptographic Protection | S4: no FIPS-validated mode. |
<!-- END generated: alternative -->

## 7. Summary by family

<!-- BEGIN generated: summary -->
| Family | Controls | Impl. | Partial | Planned | Inherited | Alt. | N/A |
|---|---|---|---|---|---|---|---|
| [AC](ssp/ac.md) Access Control | 39 | 2 | 23 | 8 | 1 | 1 | 4 |
| [AT](ssp/at.md) Awareness and Training | 6 | — | 4 | 1 | — | 1 | — |
| [AU](ssp/au.md) Audit and Accountability | 16 | 1 | 12 | 2 | — | 1 | — |
| [CA](ssp/ca.md) Assessment, Authorization, and Monitoring | 10 | 2 | 6 | — | — | 2 | — |
| [CM](ssp/cm.md) Configuration Management | 24 | 3 | 17 | 1 | — | 2 | 1 |
| [CP](ssp/cp.md) Contingency Planning | 23 | — | 13 | — | — | 3 | 7 |
| [IA](ssp/ia.md) Identification and Authentication | 24 | 2 | 13 | 1 | — | 3 | 5 |
| [IR](ssp/ir.md) Incident Response | 13 | 1 | 10 | 1 | — | 1 | — |
| [MA](ssp/ma.md) Maintenance | 9 | — | 5 | — | — | 1 | 3 |
| [MP](ssp/mp.md) Media Protection | 7 | 1 | 2 | 1 | — | 1 | 2 |
| [PE](ssp/pe.md) Physical and Environmental Protection | 18 | — | 4 | — | — | 3 | 11 |
| [PL](ssp/pl.md) Planning | 7 | 2 | 5 | — | — | — | — |
| [PS](ssp/ps.md) Personnel Security | 9 | 1 | 3 | — | — | 1 | 4 |
| [RA](ssp/ra.md) Risk Assessment | 10 | 2 | 4 | 4 | — | — | — |
| [SA](ssp/sa.md) System and Services Acquisition | 17 | — | 14 | 1 | — | 1 | 1 |
| [SC](ssp/sc.md) System and Communications Protection | 25 | 3 | 15 | — | 4 | 1 | 2 |
| [SI](ssp/si.md) System and Information Integrity | 18 | — | 14 | 1 | 1 | — | 2 |
| [SR](ssp/sr.md) Supply Chain Risk Management | 12 | — | 6 | 4 | — | — | 2 |
| **Total** | **287** | **20** | **170** | **25** | **6** | **22** | **44** |
<!-- END generated: summary -->

## 8. Every control

<!-- BEGIN generated: full -->
| Control | Title | Baseline | Disposition | Gaps |
|---|---|---|---|---|
| [AC-1](ssp/ac.md#ac-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-AC-01 |
| [AC-2](ssp/ac.md#ac-2-account-management) | Account Management | LOW, MODERATE | Partially implemented | G-AC-02, G-AC-03, G-AC-04, G-AC-31 |
| [AC-2(1)](ssp/ac.md#ac-21-automated-system-account-management) | Automated System Account Management | MODERATE | Partially implemented | — |
| [AC-2(2)](ssp/ac.md#ac-22-automated-temporary-and-emergency-account-management) | Automated Temporary and Emergency Account Management | MODERATE | Not applicable | — |
| [AC-2(3)](ssp/ac.md#ac-23-disable-accounts) | Disable Accounts | MODERATE | Planned | G-AC-05 |
| [AC-2(4)](ssp/ac.md#ac-24-automated-audit-actions) | Automated Audit Actions | MODERATE | Partially implemented | — |
| [AC-2(5)](ssp/ac.md#ac-25-inactivity-logout) | Inactivity Logout | MODERATE | Partially implemented | G-AC-06 |
| [AC-2(13)](ssp/ac.md#ac-213-disable-accounts-for-high-risk-individuals) | Disable Accounts for High-risk Individuals | MODERATE | Partially implemented | — |
| [AC-3](ssp/ac.md#ac-3-access-enforcement) | Access Enforcement | LOW, MODERATE | Partially implemented | G-AC-07, G-AC-12 |
| [AC-4](ssp/ac.md#ac-4-information-flow-enforcement) | Information Flow Enforcement | MODERATE | Partially implemented | G-AC-08 |
| [AC-5](ssp/ac.md#ac-5-separation-of-duties) | Separation of Duties | MODERATE | Alternative implementation | G-AC-09 |
| [AC-6](ssp/ac.md#ac-6-least-privilege) | Least Privilege | MODERATE | Partially implemented | G-AC-10 |
| [AC-6(1)](ssp/ac.md#ac-61-authorize-access-to-security-functions) | Authorize Access to Security Functions | MODERATE | Partially implemented | — |
| [AC-6(2)](ssp/ac.md#ac-62-non-privileged-access-for-nonsecurity-functions) | Non-privileged Access for Nonsecurity Functions | MODERATE | Partially implemented | — |
| [AC-6(5)](ssp/ac.md#ac-65-privileged-accounts) | Privileged Accounts | MODERATE | Partially implemented | — |
| [AC-6(7)](ssp/ac.md#ac-67-review-of-user-privileges) | Review of User Privileges | MODERATE | Planned | — |
| [AC-6(9)](ssp/ac.md#ac-69-log-use-of-privileged-functions) | Log Use of Privileged Functions | MODERATE | Partially implemented | G-AC-13 |
| [AC-6(10)](ssp/ac.md#ac-610-prohibit-non-privileged-users-from-executing-privileged-functions) | Prohibit Non-privileged Users from Executing Privileged Functions | MODERATE | Partially implemented | — |
| [AC-7](ssp/ac.md#ac-7-unsuccessful-logon-attempts) | Unsuccessful Logon Attempts | LOW, MODERATE | Partially implemented | — |
| [AC-8](ssp/ac.md#ac-8-system-use-notification) | System Use Notification | LOW, MODERATE | Planned | — |
| [AC-11](ssp/ac.md#ac-11-device-lock) | Device Lock | MODERATE | Not applicable | — |
| [AC-11(1)](ssp/ac.md#ac-111-pattern-hiding-displays) | Pattern-hiding Displays | MODERATE | Not applicable | — |
| [AC-12](ssp/ac.md#ac-12-session-termination) | Session Termination | MODERATE | Partially implemented | — |
| [AC-14](ssp/ac.md#ac-14-permitted-actions-without-identification-or-authentication) | Permitted Actions Without Identification or Authentication | LOW, MODERATE | Implemented | — |
| [AC-17](ssp/ac.md#ac-17-remote-access) | Remote Access | LOW, MODERATE | Partially implemented | G-AC-11 |
| [AC-17(1)](ssp/ac.md#ac-171-monitoring-and-control) | Monitoring and Control | MODERATE | Partially implemented | — |
| [AC-17(2)](ssp/ac.md#ac-172-protection-of-confidentiality-and-integrity-using-encryption) | Protection of Confidentiality and Integrity Using Encryption | MODERATE | Inherited (Tailscale) | — |
| [AC-17(3)](ssp/ac.md#ac-173-managed-access-control-points) | Managed Access Control Points | MODERATE | Implemented | — |
| [AC-17(4)](ssp/ac.md#ac-174-privileged-commands-and-access) | Privileged Commands and Access | MODERATE | Partially implemented | — |
| [AC-18](ssp/ac.md#ac-18-wireless-access) | Wireless Access | LOW, MODERATE | Planned | G-AC-14 |
| [AC-18(1)](ssp/ac.md#ac-181-authentication-and-encryption) | Authentication and Encryption | MODERATE | Planned | — |
| [AC-18(3)](ssp/ac.md#ac-183-disable-wireless-networking) | Disable Wireless Networking | MODERATE | Planned | — |
| [AC-19](ssp/ac.md#ac-19-access-control-for-mobile-devices) | Access Control for Mobile Devices | LOW, MODERATE | Planned | G-AC-15 |
| [AC-19(5)](ssp/ac.md#ac-195-full-device-or-container-based-encryption) | Full Device or Container-based Encryption | MODERATE | Planned | — |
| [AC-20](ssp/ac.md#ac-20-use-of-external-systems) | Use of External Systems | LOW, MODERATE | Partially implemented | — |
| [AC-20(1)](ssp/ac.md#ac-201-limits-on-authorized-use) | Limits on Authorized Use | MODERATE | Partially implemented | — |
| [AC-20(2)](ssp/ac.md#ac-202-portable-storage-devices--restricted-use) | Portable Storage Devices — Restricted Use | MODERATE | Not applicable | — |
| [AC-21](ssp/ac.md#ac-21-information-sharing) | Information Sharing | MODERATE | Partially implemented | G-AC-16 |
| [AC-22](ssp/ac.md#ac-22-publicly-accessible-content) | Publicly Accessible Content | LOW, MODERATE | Partially implemented | — |
| [AT-1](ssp/at.md#at-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-AT-01 |
| [AT-2](ssp/at.md#at-2-literacy-training-and-awareness) | Literacy Training and Awareness | LOW, MODERATE | Partially implemented | G-AT-02, G-AT-03 |
| [AT-2(2)](ssp/at.md#at-22-insider-threat) | Insider Threat | LOW, MODERATE | Planned | — |
| [AT-2(3)](ssp/at.md#at-23-social-engineering-and-mining) | Social Engineering and Mining | MODERATE | Partially implemented | — |
| [AT-3](ssp/at.md#at-3-role-based-training) | Role-based Training | LOW, MODERATE | Alternative implementation | — |
| [AT-4](ssp/at.md#at-4-training-records) | Training Records | LOW, MODERATE | Partially implemented | — |
| [AU-1](ssp/au.md#au-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-AU-01 |
| [AU-2](ssp/au.md#au-2-event-logging) | Event Logging | LOW, MODERATE | Partially implemented | G-AU-02, G-AU-03 |
| [AU-3](ssp/au.md#au-3-content-of-audit-records) | Content of Audit Records | LOW, MODERATE | Partially implemented | G-AU-04 |
| [AU-3(1)](ssp/au.md#au-31-additional-audit-information) | Additional Audit Information | MODERATE | Partially implemented | — |
| [AU-4](ssp/au.md#au-4-audit-log-storage-capacity) | Audit Log Storage Capacity | LOW, MODERATE | Partially implemented | G-AU-05 |
| [AU-5](ssp/au.md#au-5-response-to-audit-logging-process-failures) | Response to Audit Logging Process Failures | LOW, MODERATE | Partially implemented | — |
| [AU-6](ssp/au.md#au-6-audit-record-review-analysis-and-reporting) | Audit Record Review, Analysis, and Reporting | LOW, MODERATE | Planned | — |
| [AU-6(1)](ssp/au.md#au-61-automated-process-integration) | Automated Process Integration | MODERATE | Planned | — |
| [AU-6(3)](ssp/au.md#au-63-correlate-audit-record-repositories) | Correlate Audit Record Repositories | MODERATE | Partially implemented | — |
| [AU-7](ssp/au.md#au-7-audit-record-reduction-and-report-generation) | Audit Record Reduction and Report Generation | MODERATE | Partially implemented | — |
| [AU-7(1)](ssp/au.md#au-71-automatic-processing) | Automatic Processing | MODERATE | Partially implemented | — |
| [AU-8](ssp/au.md#au-8-time-stamps) | Time Stamps | LOW, MODERATE | Partially implemented | G-AU-06 |
| [AU-9](ssp/au.md#au-9-protection-of-audit-information) | Protection of Audit Information | LOW, MODERATE | Partially implemented | G-AU-07 |
| [AU-9(4)](ssp/au.md#au-94-access-by-subset-of-privileged-users) | Access by Subset of Privileged Users | MODERATE | Alternative implementation | — |
| [AU-11](ssp/au.md#au-11-audit-record-retention) | Audit Record Retention | LOW, MODERATE | Implemented | — |
| [AU-12](ssp/au.md#au-12-audit-record-generation) | Audit Record Generation | LOW, MODERATE | Partially implemented | — |
| [CA-1](ssp/ca.md#ca-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [CA-2](ssp/ca.md#ca-2-control-assessments) | Control Assessments | LOW, MODERATE | Partially implemented | G-CA-01 |
| [CA-2(1)](ssp/ca.md#ca-21-independent-assessors) | Independent Assessors | MODERATE | Alternative implementation | — |
| [CA-3](ssp/ca.md#ca-3-information-exchange) | Information Exchange | LOW, MODERATE | Partially implemented | — |
| [CA-5](ssp/ca.md#ca-5-plan-of-action-and-milestones) | Plan of Action and Milestones | LOW, MODERATE | Implemented | — |
| [CA-6](ssp/ca.md#ca-6-authorization) | Authorization | LOW, MODERATE | Partially implemented | — |
| [CA-7](ssp/ca.md#ca-7-continuous-monitoring) | Continuous Monitoring | LOW, MODERATE | Partially implemented | — |
| [CA-7(1)](ssp/ca.md#ca-71-independent-assessment) | Independent Assessment | MODERATE | Alternative implementation | — |
| [CA-7(4)](ssp/ca.md#ca-74-risk-monitoring) | Risk Monitoring | LOW, MODERATE | Partially implemented | — |
| [CA-9](ssp/ca.md#ca-9-internal-system-connections) | Internal System Connections | LOW, MODERATE | Implemented | — |
| [CM-1](ssp/cm.md#cm-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-CM-01, G-CM-02 |
| [CM-2](ssp/cm.md#cm-2-baseline-configuration) | Baseline Configuration | LOW, MODERATE | Partially implemented | G-CM-03, G-CM-04 |
| [CM-2(2)](ssp/cm.md#cm-22-automation-support-for-accuracy-and-currency) | Automation Support for Accuracy and Currency | MODERATE | Partially implemented | G-CM-05 |
| [CM-2(3)](ssp/cm.md#cm-23-retention-of-previous-configurations) | Retention of Previous Configurations | MODERATE | Partially implemented | G-CM-06 |
| [CM-2(7)](ssp/cm.md#cm-27-configure-systems-and-components-for-high-risk-areas) | Configure Systems and Components for High-risk Areas | MODERATE | Not applicable | — |
| [CM-3](ssp/cm.md#cm-3-configuration-change-control) | Configuration Change Control | MODERATE | Partially implemented | G-CM-07, G-CM-08 |
| [CM-3(2)](ssp/cm.md#cm-32-testing-validation-and-documentation-of-changes) | Testing, Validation, and Documentation of Changes | MODERATE | Partially implemented | G-CM-09 |
| [CM-3(4)](ssp/cm.md#cm-34-security-and-privacy-representatives) | Security and Privacy Representatives | MODERATE | Alternative implementation | — |
| [CM-4](ssp/cm.md#cm-4-impact-analyses) | Impact Analyses | LOW, MODERATE | Partially implemented | — |
| [CM-4(2)](ssp/cm.md#cm-42-verification-of-controls) | Verification of Controls | MODERATE | Partially implemented | G-CM-10 |
| [CM-5](ssp/cm.md#cm-5-access-restrictions-for-change) | Access Restrictions for Change | LOW, MODERATE | Partially implemented | — |
| [CM-6](ssp/cm.md#cm-6-configuration-settings) | Configuration Settings | LOW, MODERATE | Partially implemented | G-CM-11 |
| [CM-7](ssp/cm.md#cm-7-least-functionality) | Least Functionality | LOW, MODERATE | Partially implemented | — |
| [CM-7(1)](ssp/cm.md#cm-71-periodic-review) | Periodic Review | MODERATE | Partially implemented | — |
| [CM-7(2)](ssp/cm.md#cm-72-prevent-program-execution) | Prevent Program Execution | MODERATE | Partially implemented | — |
| [CM-7(5)](ssp/cm.md#cm-75-authorized-software--allow-by-exception) | Authorized Software — Allow-by-exception | MODERATE | Planned | G-CM-12 |
| [CM-8](ssp/cm.md#cm-8-system-component-inventory) | System Component Inventory | LOW, MODERATE | Implemented | — |
| [CM-8(1)](ssp/cm.md#cm-81-updates-during-installation-and-removal) | Updates During Installation and Removal | MODERATE | Partially implemented | G-CM-13 |
| [CM-8(3)](ssp/cm.md#cm-83-automated-unauthorized-component-detection) | Automated Unauthorized Component Detection | MODERATE | Partially implemented | — |
| [CM-9](ssp/cm.md#cm-9-configuration-management-plan) | Configuration Management Plan | MODERATE | Implemented | — |
| [CM-10](ssp/cm.md#cm-10-software-usage-restrictions) | Software Usage Restrictions | LOW, MODERATE | Partially implemented | — |
| [CM-11](ssp/cm.md#cm-11-user-installed-software) | User-installed Software | LOW, MODERATE | Partially implemented | — |
| [CM-12](ssp/cm.md#cm-12-information-location) | Information Location | MODERATE | Implemented | — |
| [CM-12(1)](ssp/cm.md#cm-121-automated-tools-to-support-information-location) | Automated Tools to Support Information Location | MODERATE | Alternative implementation | — |
| [CP-1](ssp/cp.md#cp-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-CP-01, G-CP-02 |
| [CP-2](ssp/cp.md#cp-2-contingency-plan) | Contingency Plan | LOW, MODERATE | Partially implemented | G-CP-03, G-CP-04, G-CP-05 |
| [CP-2(1)](ssp/cp.md#cp-21-coordinate-with-related-plans) | Coordinate with Related Plans | MODERATE | Alternative implementation | — |
| [CP-2(3)](ssp/cp.md#cp-23-resume-mission-and-business-functions) | Resume Mission and Business Functions | MODERATE | Partially implemented | G-CP-06 |
| [CP-2(8)](ssp/cp.md#cp-28-identify-critical-assets) | Identify Critical Assets | MODERATE | Partially implemented | G-CP-07 |
| [CP-3](ssp/cp.md#cp-3-contingency-training) | Contingency Training | LOW, MODERATE | Alternative implementation | G-CP-08 |
| [CP-4](ssp/cp.md#cp-4-contingency-plan-testing) | Contingency Plan Testing | LOW, MODERATE | Partially implemented | G-CP-09, G-CP-10 |
| [CP-4(1)](ssp/cp.md#cp-41-coordinate-with-related-plans) | Coordinate with Related Plans | MODERATE | Alternative implementation | G-CP-11 |
| [CP-6](ssp/cp.md#cp-6-alternate-storage-site) | Alternate Storage Site | MODERATE | Partially implemented | G-CP-12, G-CP-14 |
| [CP-6(1)](ssp/cp.md#cp-61-separation-from-primary-site) | Separation from Primary Site | MODERATE | Partially implemented | G-CP-13 |
| [CP-6(3)](ssp/cp.md#cp-63-accessibility) | Accessibility | MODERATE | Partially implemented | G-CP-15 |
| [CP-7](ssp/cp.md#cp-7-alternate-processing-site) | Alternate Processing Site | MODERATE | Not applicable | — |
| [CP-7(1)](ssp/cp.md#cp-71-separation-from-primary-site) | Separation from Primary Site | MODERATE | Not applicable | — |
| [CP-7(2)](ssp/cp.md#cp-72-accessibility) | Accessibility | MODERATE | Not applicable | — |
| [CP-7(3)](ssp/cp.md#cp-73-priority-of-service) | Priority of Service | MODERATE | Not applicable | — |
| [CP-8](ssp/cp.md#cp-8-telecommunications-services) | Telecommunications Services | MODERATE | Not applicable | — |
| [CP-8(1)](ssp/cp.md#cp-81-priority-of-service-provisions) | Priority of Service Provisions | MODERATE | Not applicable | — |
| [CP-8(2)](ssp/cp.md#cp-82-single-points-of-failure) | Single Points of Failure | MODERATE | Not applicable | — |
| [CP-9](ssp/cp.md#cp-9-system-backup) | System Backup | LOW, MODERATE | Partially implemented | G-CP-16 |
| [CP-9(1)](ssp/cp.md#cp-91-testing-for-reliability-and-integrity) | Testing for Reliability and Integrity | MODERATE | Partially implemented | — |
| [CP-9(8)](ssp/cp.md#cp-98-cryptographic-protection) | Cryptographic Protection | MODERATE | Partially implemented | — |
| [CP-10](ssp/cp.md#cp-10-system-recovery-and-reconstitution) | System Recovery and Reconstitution | LOW, MODERATE | Partially implemented | — |
| [CP-10(2)](ssp/cp.md#cp-102-transaction-recovery) | Transaction Recovery | MODERATE | Partially implemented | — |
| [IA-1](ssp/ia.md#ia-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [IA-2](ssp/ia.md#ia-2-identification-and-authentication-organizational-users) | Identification and Authentication (Organizational Users) | LOW, MODERATE | Partially implemented | G-IA-01 |
| [IA-2(1)](ssp/ia.md#ia-21-multi-factor-authentication-to-privileged-accounts) | Multi-factor Authentication to Privileged Accounts | LOW, MODERATE | Partially implemented | G-IA-02 |
| [IA-2(2)](ssp/ia.md#ia-22-multi-factor-authentication-to-non-privileged-accounts) | Multi-factor Authentication to Non-privileged Accounts | LOW, MODERATE | Planned | G-IA-03 |
| [IA-2(8)](ssp/ia.md#ia-28-access-to-accounts--replay-resistant) | Access to Accounts — Replay Resistant | LOW, MODERATE | Partially implemented | — |
| [IA-2(12)](ssp/ia.md#ia-212-acceptance-of-piv-credentials) | Acceptance of PIV Credentials | LOW, MODERATE | Not applicable | — |
| [IA-3](ssp/ia.md#ia-3-device-identification-and-authentication) | Device Identification and Authentication | MODERATE | Partially implemented | — |
| [IA-4](ssp/ia.md#ia-4-identifier-management) | Identifier Management | LOW, MODERATE | Partially implemented | — |
| [IA-4(4)](ssp/ia.md#ia-44-identify-user-status) | Identify User Status | MODERATE | Partially implemented | — |
| [IA-5](ssp/ia.md#ia-5-authenticator-management) | Authenticator Management | LOW, MODERATE | Partially implemented | G-IA-04 |
| [IA-5(1)](ssp/ia.md#ia-51-password-based-authentication) | Password-based Authentication | LOW, MODERATE | Partially implemented | — |
| [IA-5(2)](ssp/ia.md#ia-52-public-key-based-authentication) | Public Key-based Authentication | MODERATE | Partially implemented | — |
| [IA-5(6)](ssp/ia.md#ia-56-protection-of-authenticators) | Protection of Authenticators | MODERATE | Partially implemented | — |
| [IA-6](ssp/ia.md#ia-6-authentication-feedback) | Authentication Feedback | LOW, MODERATE | Implemented | — |
| [IA-7](ssp/ia.md#ia-7-cryptographic-module-authentication) | Cryptographic Module Authentication | LOW, MODERATE | Alternative implementation | — |
| [IA-8](ssp/ia.md#ia-8-identification-and-authentication-non-organizational-users) | Identification and Authentication (Non-organizational Users) | LOW, MODERATE | Partially implemented | — |
| [IA-8(1)](ssp/ia.md#ia-81-acceptance-of-piv-credentials-from-other-agencies) | Acceptance of PIV Credentials from Other Agencies | LOW, MODERATE | Not applicable | — |
| [IA-8(2)](ssp/ia.md#ia-82-acceptance-of-external-authenticators) | Acceptance of External Authenticators | LOW, MODERATE | Not applicable | — |
| [IA-8(4)](ssp/ia.md#ia-84-use-of-defined-profiles) | Use of Defined Profiles | LOW, MODERATE | Implemented | — |
| [IA-11](ssp/ia.md#ia-11-re-authentication) | Re-authentication | LOW, MODERATE | Partially implemented | — |
| [IA-12](ssp/ia.md#ia-12-identity-proofing) | Identity Proofing | MODERATE | Alternative implementation | — |
| [IA-12(2)](ssp/ia.md#ia-122-identity-evidence) | Identity Evidence | MODERATE | Not applicable | — |
| [IA-12(3)](ssp/ia.md#ia-123-identity-evidence-validation-and-verification) | Identity Evidence Validation and Verification | MODERATE | Not applicable | — |
| [IA-12(5)](ssp/ia.md#ia-125-address-confirmation) | Address Confirmation | MODERATE | Alternative implementation | — |
| [IR-1](ssp/ir.md#ir-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-IR-01, G-IR-02, G-IR-03 |
| [IR-2](ssp/ir.md#ir-2-incident-response-training) | Incident Response Training | LOW, MODERATE | Partially implemented | G-IR-04 |
| [IR-3](ssp/ir.md#ir-3-incident-response-testing) | Incident Response Testing | MODERATE | Partially implemented | G-IR-05, G-IR-06, G-IR-07 |
| [IR-3(2)](ssp/ir.md#ir-32-coordination-with-related-plans) | Coordination with Related Plans | MODERATE | Planned | G-IR-08 |
| [IR-4](ssp/ir.md#ir-4-incident-handling) | Incident Handling | LOW, MODERATE | Partially implemented | G-IR-09, G-IR-10, G-IR-11 |
| [IR-4(1)](ssp/ir.md#ir-41-automated-incident-handling-processes) | Automated Incident Handling Processes | MODERATE | Implemented | — |
| [IR-5](ssp/ir.md#ir-5-incident-monitoring) | Incident Monitoring | LOW, MODERATE | Partially implemented | G-IR-12, G-IR-14 |
| [IR-6](ssp/ir.md#ir-6-incident-reporting) | Incident Reporting | LOW, MODERATE | Partially implemented | G-IR-15 |
| [IR-6(1)](ssp/ir.md#ir-61-automated-reporting) | Automated Reporting | MODERATE | Partially implemented | G-IR-13 |
| [IR-6(3)](ssp/ir.md#ir-63-supply-chain-coordination) | Supply Chain Coordination | MODERATE | Partially implemented | — |
| [IR-7](ssp/ir.md#ir-7-incident-response-assistance) | Incident Response Assistance | LOW, MODERATE | Alternative implementation | — |
| [IR-7(1)](ssp/ir.md#ir-71-automation-support-for-availability-of-information-and-support) | Automation Support for Availability of Information and Support | MODERATE | Partially implemented | — |
| [IR-8](ssp/ir.md#ir-8-incident-response-plan) | Incident Response Plan | LOW, MODERATE | Partially implemented | — |
| [MA-1](ssp/ma.md#ma-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [MA-2](ssp/ma.md#ma-2-controlled-maintenance) | Controlled Maintenance | LOW, MODERATE | Partially implemented | G-MA-01 |
| [MA-3](ssp/ma.md#ma-3-maintenance-tools) | Maintenance Tools | MODERATE | Partially implemented | — |
| [MA-3(1)](ssp/ma.md#ma-31-inspect-tools) | Inspect Tools | MODERATE | Not applicable | — |
| [MA-3(2)](ssp/ma.md#ma-32-inspect-media) | Inspect Media | MODERATE | Not applicable | — |
| [MA-3(3)](ssp/ma.md#ma-33-prevent-unauthorized-removal) | Prevent Unauthorized Removal | MODERATE | Not applicable | — |
| [MA-4](ssp/ma.md#ma-4-nonlocal-maintenance) | Nonlocal Maintenance | LOW, MODERATE | Partially implemented | — |
| [MA-5](ssp/ma.md#ma-5-maintenance-personnel) | Maintenance Personnel | LOW, MODERATE | Alternative implementation | — |
| [MA-6](ssp/ma.md#ma-6-timely-maintenance) | Timely Maintenance | MODERATE | Partially implemented | — |
| [MP-1](ssp/mp.md#mp-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [MP-2](ssp/mp.md#mp-2-media-access) | Media Access | LOW, MODERATE | Alternative implementation | — |
| [MP-3](ssp/mp.md#mp-3-media-marking) | Media Marking | MODERATE | Not applicable | — |
| [MP-4](ssp/mp.md#mp-4-media-storage) | Media Storage | MODERATE | Partially implemented | — |
| [MP-5](ssp/mp.md#mp-5-media-transport) | Media Transport | MODERATE | Not applicable | — |
| [MP-6](ssp/mp.md#mp-6-media-sanitization) | Media Sanitization | LOW, MODERATE | Planned | G-MP-01 |
| [MP-7](ssp/mp.md#mp-7-media-use) | Media Use | LOW, MODERATE | Implemented | — |
| [PE-1](ssp/pe.md#pe-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-PE-01 |
| [PE-2](ssp/pe.md#pe-2-physical-access-authorizations) | Physical Access Authorizations | LOW, MODERATE | Alternative implementation | — |
| [PE-3](ssp/pe.md#pe-3-physical-access-control) | Physical Access Control | LOW, MODERATE | Alternative implementation | — |
| [PE-4](ssp/pe.md#pe-4-access-control-for-transmission) | Access Control for Transmission | MODERATE | Not applicable | — |
| [PE-5](ssp/pe.md#pe-5-access-control-for-output-devices) | Access Control for Output Devices | MODERATE | Not applicable | — |
| [PE-6](ssp/pe.md#pe-6-monitoring-physical-access) | Monitoring Physical Access | LOW, MODERATE | Not applicable | — |
| [PE-6(1)](ssp/pe.md#pe-61-intrusion-alarms-and-surveillance-equipment) | Intrusion Alarms and Surveillance Equipment | MODERATE | Not applicable | — |
| [PE-8](ssp/pe.md#pe-8-visitor-access-records) | Visitor Access Records | LOW, MODERATE | Not applicable | — |
| [PE-9](ssp/pe.md#pe-9-power-equipment-and-cabling) | Power Equipment and Cabling | MODERATE | Not applicable | — |
| [PE-10](ssp/pe.md#pe-10-emergency-shutoff) | Emergency Shutoff | MODERATE | Not applicable | — |
| [PE-11](ssp/pe.md#pe-11-emergency-power) | Emergency Power | MODERATE | Partially implemented | G-PE-02 |
| [PE-12](ssp/pe.md#pe-12-emergency-lighting) | Emergency Lighting | LOW, MODERATE | Not applicable | — |
| [PE-13](ssp/pe.md#pe-13-fire-protection) | Fire Protection | LOW, MODERATE | Alternative implementation | — |
| [PE-13(1)](ssp/pe.md#pe-131-detection-systems--automatic-activation-and-notification) | Detection Systems — Automatic Activation and Notification | MODERATE | Not applicable | — |
| [PE-14](ssp/pe.md#pe-14-environmental-controls) | Environmental Controls | LOW, MODERATE | Partially implemented | — |
| [PE-15](ssp/pe.md#pe-15-water-damage-protection) | Water Damage Protection | LOW, MODERATE | Not applicable | — |
| [PE-16](ssp/pe.md#pe-16-delivery-and-removal) | Delivery and Removal | LOW, MODERATE | Not applicable | — |
| [PE-17](ssp/pe.md#pe-17-alternate-work-site) | Alternate Work Site | MODERATE | Partially implemented | — |
| [PL-1](ssp/pl.md#pl-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [PL-2](ssp/pl.md#pl-2-system-security-and-privacy-plans) | System Security and Privacy Plans | LOW, MODERATE | Partially implemented | — |
| [PL-4](ssp/pl.md#pl-4-rules-of-behavior) | Rules of Behavior | LOW, MODERATE | Partially implemented | — |
| [PL-4(1)](ssp/pl.md#pl-41-social-media-and-external-siteapplication-usage-restrictions) | Social Media and External Site/Application Usage Restrictions | LOW, MODERATE | Partially implemented | — |
| [PL-8](ssp/pl.md#pl-8-security-and-privacy-architectures) | Security and Privacy Architectures | MODERATE | Partially implemented | — |
| [PL-10](ssp/pl.md#pl-10-baseline-selection) | Baseline Selection | LOW, MODERATE | Implemented | — |
| [PL-11](ssp/pl.md#pl-11-baseline-tailoring) | Baseline Tailoring | LOW, MODERATE | Implemented | — |
| [PS-1](ssp/ps.md#ps-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [PS-2](ssp/ps.md#ps-2-position-risk-designation) | Position Risk Designation | LOW, MODERATE | Not applicable | — |
| [PS-3](ssp/ps.md#ps-3-personnel-screening) | Personnel Screening | LOW, MODERATE | Not applicable | — |
| [PS-4](ssp/ps.md#ps-4-personnel-termination) | Personnel Termination | LOW, MODERATE | Partially implemented | — |
| [PS-5](ssp/ps.md#ps-5-personnel-transfer) | Personnel Transfer | LOW, MODERATE | Partially implemented | — |
| [PS-6](ssp/ps.md#ps-6-access-agreements) | Access Agreements | LOW, MODERATE | Alternative implementation | — |
| [PS-7](ssp/ps.md#ps-7-external-personnel-security) | External Personnel Security | LOW, MODERATE | Not applicable | — |
| [PS-8](ssp/ps.md#ps-8-personnel-sanctions) | Personnel Sanctions | LOW, MODERATE | Not applicable | — |
| [PS-9](ssp/ps.md#ps-9-position-descriptions) | Position Descriptions | LOW, MODERATE | Implemented | — |
| [RA-1](ssp/ra.md#ra-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [RA-2](ssp/ra.md#ra-2-security-categorization) | Security Categorization | LOW, MODERATE | Implemented | — |
| [RA-3](ssp/ra.md#ra-3-risk-assessment) | Risk Assessment | LOW, MODERATE | Partially implemented | G-RA-01 |
| [RA-3(1)](ssp/ra.md#ra-31-supply-chain-risk-assessment) | Supply Chain Risk Assessment | LOW, MODERATE | Partially implemented | — |
| [RA-5](ssp/ra.md#ra-5-vulnerability-monitoring-and-scanning) | Vulnerability Monitoring and Scanning | LOW, MODERATE | Planned | — |
| [RA-5(2)](ssp/ra.md#ra-52-update-vulnerabilities-to-be-scanned) | Update Vulnerabilities to Be Scanned | LOW, MODERATE | Planned | — |
| [RA-5(5)](ssp/ra.md#ra-55-privileged-access) | Privileged Access | MODERATE | Planned | — |
| [RA-5(11)](ssp/ra.md#ra-511-public-disclosure-program) | Public Disclosure Program | LOW, MODERATE | Planned | G-RA-02 |
| [RA-7](ssp/ra.md#ra-7-risk-response) | Risk Response | LOW, MODERATE | Implemented | — |
| [RA-9](ssp/ra.md#ra-9-criticality-analysis) | Criticality Analysis | MODERATE | Partially implemented | — |
| [SA-1](ssp/sa.md#sa-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-SA-01 |
| [SA-2](ssp/sa.md#sa-2-allocation-of-resources) | Allocation of Resources | LOW, MODERATE | Partially implemented | G-SA-02 |
| [SA-3](ssp/sa.md#sa-3-system-development-life-cycle) | System Development Life Cycle | LOW, MODERATE | Partially implemented | G-SA-03 |
| [SA-4](ssp/sa.md#sa-4-acquisition-process) | Acquisition Process | LOW, MODERATE | Partially implemented | G-SA-04, G-SA-05 |
| [SA-4(1)](ssp/sa.md#sa-41-functional-properties-of-controls) | Functional Properties of Controls | MODERATE | Partially implemented | — |
| [SA-4(2)](ssp/sa.md#sa-42-design-and-implementation-information-for-controls) | Design and Implementation Information for Controls | MODERATE | Alternative implementation | — |
| [SA-4(9)](ssp/sa.md#sa-49-functions-ports-protocols-and-services-in-use) | Functions, Ports, Protocols, and Services in Use | MODERATE | Partially implemented | G-SA-06 |
| [SA-4(10)](ssp/sa.md#sa-410-use-of-approved-piv-products) | Use of Approved PIV Products | LOW, MODERATE | Not applicable | — |
| [SA-5](ssp/sa.md#sa-5-system-documentation) | System Documentation | LOW, MODERATE | Partially implemented | G-SA-07 |
| [SA-8](ssp/sa.md#sa-8-security-and-privacy-engineering-principles) | Security and Privacy Engineering Principles | LOW, MODERATE | Partially implemented | G-SA-08 |
| [SA-9](ssp/sa.md#sa-9-external-system-services) | External System Services | LOW, MODERATE | Partially implemented | G-SA-09 |
| [SA-9(2)](ssp/sa.md#sa-92-identification-of-functions-ports-protocols-and-services) | Identification of Functions, Ports, Protocols, and Services | MODERATE | Partially implemented | — |
| [SA-10](ssp/sa.md#sa-10-developer-configuration-management) | Developer Configuration Management | MODERATE | Partially implemented | — |
| [SA-11](ssp/sa.md#sa-11-developer-testing-and-evaluation) | Developer Testing and Evaluation | MODERATE | Partially implemented | — |
| [SA-15](ssp/sa.md#sa-15-development-process-standards-and-tools) | Development Process, Standards, and Tools | MODERATE | Partially implemented | — |
| [SA-15(3)](ssp/sa.md#sa-153-criticality-analysis) | Criticality Analysis | MODERATE | Planned | — |
| [SA-22](ssp/sa.md#sa-22-unsupported-system-components) | Unsupported System Components | LOW, MODERATE | Partially implemented | G-SA-10 |
| [SC-1](ssp/sc.md#sc-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [SC-2](ssp/sc.md#sc-2-separation-of-system-and-user-functionality) | Separation of System and User Functionality | MODERATE | Partially implemented | — |
| [SC-4](ssp/sc.md#sc-4-information-in-shared-system-resources) | Information in Shared System Resources | MODERATE | Partially implemented | G-SC-01 |
| [SC-5](ssp/sc.md#sc-5-denial-of-service-protection) | Denial-of-service Protection | LOW, MODERATE | Partially implemented | — |
| [SC-7](ssp/sc.md#sc-7-boundary-protection) | Boundary Protection | LOW, MODERATE | Partially implemented | — |
| [SC-7(3)](ssp/sc.md#sc-73-access-points) | Access Points | MODERATE | Implemented | — |
| [SC-7(4)](ssp/sc.md#sc-74-external-telecommunications-services) | External Telecommunications Services | MODERATE | Inherited (ISP, Tailscale, AirVPN) | — |
| [SC-7(5)](ssp/sc.md#sc-75-deny-by-default--allow-by-exception) | Deny by Default — Allow by Exception | MODERATE | Partially implemented | G-SC-02 |
| [SC-7(7)](ssp/sc.md#sc-77-split-tunneling-for-remote-devices) | Split Tunneling for Remote Devices | MODERATE | Partially implemented | — |
| [SC-7(8)](ssp/sc.md#sc-78-route-traffic-to-authenticated-proxy-servers) | Route Traffic to Authenticated Proxy Servers | MODERATE | Implemented | — |
| [SC-8](ssp/sc.md#sc-8-transmission-confidentiality-and-integrity) | Transmission Confidentiality and Integrity | MODERATE | Partially implemented | G-SC-03 |
| [SC-8(1)](ssp/sc.md#sc-81-cryptographic-protection) | Cryptographic Protection | MODERATE | Partially implemented | — |
| [SC-10](ssp/sc.md#sc-10-network-disconnect) | Network Disconnect | MODERATE | Partially implemented | — |
| [SC-12](ssp/sc.md#sc-12-cryptographic-key-establishment-and-management) | Cryptographic Key Establishment and Management | LOW, MODERATE | Partially implemented | G-SC-04 |
| [SC-13](ssp/sc.md#sc-13-cryptographic-protection) | Cryptographic Protection | LOW, MODERATE | Alternative implementation | — |
| [SC-15](ssp/sc.md#sc-15-collaborative-computing-devices-and-applications) | Collaborative Computing Devices and Applications | LOW, MODERATE | Not applicable | — |
| [SC-17](ssp/sc.md#sc-17-public-key-infrastructure-certificates) | Public Key Infrastructure Certificates | MODERATE | Inherited (Let's Encrypt) | — |
| [SC-18](ssp/sc.md#sc-18-mobile-code) | Mobile Code | MODERATE | Not applicable | — |
| [SC-20](ssp/sc.md#sc-20-secure-nameaddress-resolution-service-authoritative-source) | Secure Name/Address Resolution Service (Authoritative Source) | LOW, MODERATE | Inherited (Cloudflare) | G-SC-06 |
| [SC-21](ssp/sc.md#sc-21-secure-nameaddress-resolution-service-recursive-or-caching-resolver) | Secure Name/Address Resolution Service (Recursive or Caching Resolver) | LOW, MODERATE | Partially implemented | — |
| [SC-22](ssp/sc.md#sc-22-architecture-and-provisioning-for-nameaddress-resolution-service) | Architecture and Provisioning for Name/Address Resolution Service | LOW, MODERATE | Inherited (Cloudflare) | — |
| [SC-23](ssp/sc.md#sc-23-session-authenticity) | Session Authenticity | MODERATE | Partially implemented | G-SC-07 |
| [SC-28](ssp/sc.md#sc-28-protection-of-information-at-rest) | Protection of Information at Rest | MODERATE | Partially implemented | G-SC-05 |
| [SC-28(1)](ssp/sc.md#sc-281-cryptographic-protection) | Cryptographic Protection | MODERATE | Partially implemented | — |
| [SC-39](ssp/sc.md#sc-39-process-isolation) | Process Isolation | LOW, MODERATE | Implemented | — |
| [SI-1](ssp/si.md#si-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | G-SI-01 |
| [SI-2](ssp/si.md#si-2-flaw-remediation) | Flaw Remediation | LOW, MODERATE | Partially implemented | G-SI-02, G-SI-03, G-SI-04 |
| [SI-2(2)](ssp/si.md#si-22-automated-flaw-remediation-status) | Automated Flaw Remediation Status | MODERATE | Partially implemented | G-SI-05 |
| [SI-3](ssp/si.md#si-3-malicious-code-protection) | Malicious Code Protection | LOW, MODERATE | Planned | G-SI-06, G-SI-07 |
| [SI-4](ssp/si.md#si-4-system-monitoring) | System Monitoring | LOW, MODERATE | Partially implemented | G-SI-08, G-SI-09, G-SI-10, G-SI-11 |
| [SI-4(2)](ssp/si.md#si-42-automated-tools-and-mechanisms-for-real-time-analysis) | Automated Tools and Mechanisms for Real-time Analysis | MODERATE | Partially implemented | — |
| [SI-4(4)](ssp/si.md#si-44-inbound-and-outbound-communications-traffic) | Inbound and Outbound Communications Traffic | MODERATE | Partially implemented | G-SI-12 |
| [SI-4(5)](ssp/si.md#si-45-system-generated-alerts) | System-generated Alerts | MODERATE | Partially implemented | — |
| [SI-5](ssp/si.md#si-5-security-alerts-advisories-and-directives) | Security Alerts, Advisories, and Directives | LOW, MODERATE | Partially implemented | — |
| [SI-7](ssp/si.md#si-7-software-firmware-and-information-integrity) | Software, Firmware, and Information Integrity | MODERATE | Partially implemented | — |
| [SI-7(1)](ssp/si.md#si-71-integrity-checks) | Integrity Checks | MODERATE | Partially implemented | — |
| [SI-7(7)](ssp/si.md#si-77-integration-of-detection-and-response) | Integration of Detection and Response | MODERATE | Partially implemented | — |
| [SI-8](ssp/si.md#si-8-spam-protection) | Spam Protection | MODERATE | Not applicable | — |
| [SI-8(2)](ssp/si.md#si-82-automatic-updates) | Automatic Updates | MODERATE | Not applicable | — |
| [SI-10](ssp/si.md#si-10-information-input-validation) | Information Input Validation | MODERATE | Partially implemented | G-SI-13 |
| [SI-11](ssp/si.md#si-11-error-handling) | Error Handling | MODERATE | Partially implemented | — |
| [SI-12](ssp/si.md#si-12-information-management-and-retention) | Information Management and Retention | LOW, MODERATE | Partially implemented | G-SI-14 |
| [SI-16](ssp/si.md#si-16-memory-protection) | Memory Protection | MODERATE | Inherited (OS and runtime) | — |
| [SR-1](ssp/sr.md#sr-1-policy-and-procedures) | Policy and Procedures | LOW, MODERATE | Partially implemented | — |
| [SR-2](ssp/sr.md#sr-2-supply-chain-risk-management-plan) | Supply Chain Risk Management Plan | LOW, MODERATE | Planned | G-SR-01 |
| [SR-2(1)](ssp/sr.md#sr-21-establish-scrm-team) | Establish SCRM Team | LOW, MODERATE | Not applicable | — |
| [SR-3](ssp/sr.md#sr-3-supply-chain-controls-and-processes) | Supply Chain Controls and Processes | LOW, MODERATE | Partially implemented | — |
| [SR-5](ssp/sr.md#sr-5-acquisition-strategies-tools-and-methods) | Acquisition Strategies, Tools, and Methods | LOW, MODERATE | Partially implemented | — |
| [SR-6](ssp/sr.md#sr-6-supplier-assessments-and-reviews) | Supplier Assessments and Reviews | MODERATE | Planned | — |
| [SR-8](ssp/sr.md#sr-8-notification-agreements) | Notification Agreements | LOW, MODERATE | Partially implemented | — |
| [SR-10](ssp/sr.md#sr-10-inspection-of-systems-or-components) | Inspection of Systems or Components | LOW, MODERATE | Planned | G-SR-02 |
| [SR-11](ssp/sr.md#sr-11-component-authenticity) | Component Authenticity | LOW, MODERATE | Partially implemented | — |
| [SR-11(1)](ssp/sr.md#sr-111-anti-counterfeit-training) | Anti-counterfeit Training | LOW, MODERATE | Not applicable | — |
| [SR-11(2)](ssp/sr.md#sr-112-configuration-control-for-component-service-and-repair) | Configuration Control for Component Service and Repair | LOW, MODERATE | Partially implemented | — |
| [SR-12](ssp/sr.md#sr-12-component-disposal) | Component Disposal | LOW, MODERATE | Planned | — |
<!-- END generated: full -->

## 9. Keeping this current

- This file is Zone 1 (`01-policy.md` §8): changes go through a PR the
  System Owner merges.
- After any change to `ssp/`, run `scripts/security/ssp-index.py write` and
  commit the result in the same PR. `scripts/security/ssp-index.py check`
  fails if any of the 287 controls lacks a complete section, has an unknown
  disposition, or reuses a gap id.
- Review the whole tailoring at the yearly policy review (`01-policy.md`
  §19), and whenever a scoping consideration in §3.1 stops being true (for
  example: a second operator, a second site, an employee, or an agent that
  gets its own identity).
