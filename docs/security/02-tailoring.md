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
<!-- END generated: inherited -->

## 5. Controls tailored out

Each row links to its SSP section, which gives the full rationale and any
residual risk. The summary column is the section's first sentence.

<!-- BEGIN generated: not-applicable -->
<!-- END generated: not-applicable -->

## 6. Alternative (compensating) implementations

<!-- BEGIN generated: alternative -->
<!-- END generated: alternative -->

## 7. Summary by family

<!-- BEGIN generated: summary -->
<!-- END generated: summary -->

## 8. Every control

<!-- BEGIN generated: full -->
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
