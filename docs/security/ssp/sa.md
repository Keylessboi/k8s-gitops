# SA — System and Services Acquisition

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

<!-- Family summary and disposition counts are written last. -->

### SA-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (policy §3.1, Security Officer role) |
| **Parameters** | sa-1_prm_1 = the System Owner and every Automated Operator (policy §3.1); sa-01_odp.03 = organization-level; sa-01_odp.04 = the System Owner, acting as Security Officer; sa-01_odp.05 = 12 months (policy App. A); sa-01_odp.06 = a SEV-1 or SEV-2 incident, a new Tier 0 or Tier 1 component, a change in who has privileged access, or a major platform change recorded in an ADR (policy App. A); sa-01_odp.07 = 12 months (App. A); sa-01_odp.08 = the events in sa-01_odp.06, plus any new external service or change of updater (policy §15.1) |

> a. Develop, document, and disseminate to [Assignment: the System Owner and every Automated Operator]:
>   1. [Selection: organization-level] system and services acquisition policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the system and services acquisition policy and the associated system and services acquisition controls;
> b. Designate an [Assignment: System Owner, acting as Security Officer] to manage the development, documentation, and dissemination of the system and services acquisition policy and procedures; and
> c. Review and update the current system and services acquisition:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident, a new Tier 0 or 1 component, a change in privileged access, or a major platform change (ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, plus any new external service or change of updater].

**Implementation.**
**a.1.** There is no separate acquisition policy. The organization-level policy `docs/security/01-policy.md` (HL-POL-001) covers it: purpose (§1), scope including external services (§2.1, last bullet), roles (§3), management commitment through owner approval and risk acceptance (§20, §21), compliance and measurement (§19), and the acquisition rules themselves in §15 (external services and supply chain), §17 (patching) and §7.2.2 (tier and class before first deploy). For (b), the only external obligations that apply to a private homelab are the providers' terms of service and software licences. Licence handling is recorded case by case, for example GPL-3.0 source not vendored in `.github/workflows/octo-yt-dlp-shim.yaml` (header) and the non-redistributable Apple APK in `apps/applemusic-wrapper/applemusic-wrapper.yaml:4-8`. **a.2.** The procedures are `CONTRIBUTING.md` ("Adding an app", "Standing rules for any new app"), `renovate.json` together with ADR-0013 (on `origin/main`) for updates, `.github/workflows/octo*.yaml` for building the owner's own images, and `docs/RUNDOWN.md` for operating what has been acquired. **a. dissemination:** the repository is public, and agents get the rules through `AGENTS.md`. **b.** The System Owner holds the role (policy §3.1). **c.** Review cadence is set in policy §19 and the header table.

The policy is still a **DRAFT** and not in force (policy header, §21), so the review cycle has never run. §15 has four rules and says nothing about how to select a component, which licences are acceptable, or what to check before adopting an upstream project.

**Evidence.** `docs/security/01-policy.md` §§1–3, 7.2, 15, 17, 19–21; `CONTRIBUTING.md`; `renovate.json`; `git show origin/main:docs/adr/0013-renovate-owns-updates.md`.

**Gaps.**
- `G-SA-01`: The policy is unapproved, and there is no written procedure for selecting and admitting a third-party component or external service. Risk: acquisition decisions are made ad hoc, by whichever agent is driving at the time. Remedy: the owner approves HL-POL-001, and an "Acquiring a component or service" section is added to `CONTRIBUTING.md` holding the SA-4 criteria (see G-SA-04). Target: **2026-12-15**.

**Related.** Policy §§3, 15, 19, 21; SA-4, SA-9, SA-15; PM-family policy controls.

### SA-2 Allocation of Resources

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | None |

> a. Determine the high-level information security and privacy requirements for the system or system service in mission and business process planning;
> b. Determine, document, and allocate the resources required to protect the system or system service as part of the organizational capital planning and investment control process; and
> c. Establish a discrete line item for information security and privacy in organizational programming and budgeting documentation.

**Implementation.**
**a.** High-level requirements are set. The FIPS 199 categorization (policy §4) puts the system at MODERATE because other people's vaults, identities and photos are held here (§1.1). The tiers and recovery objectives are in §7, and the testable requirements in `03-homelab-standard.md`. Privacy requirements come from the data classes C3 and C4 (§5–6), service users' data rights (§13.3) and the duty to notify them (§16.6).

**b.** This is a one-person homelab with no capital planning process. Resources come in three forms, and only some are documented:
- **Compute headroom**, treated as a security resource. ADR-0007 makes headroom decision #1 because resource exhaustion caused the widest-blast-radius incidents. `docs/expansion-plan.md` records the hardware actually present: RAM per host, the disks in `tank`, and the slots that remain.
- **Owner time.** The recurring obligations in policy §19 (monthly POA&M review, 90-day account review, 6-monthly restore and escrow tests, annual policy review) are the de facto allocation, but nothing records how many hours they take or whether they get done.
- **Paid services.** Doppler, Tailscale, AirVPN, GitHub and the model providers. Which tiers are paid and what they cost is not recorded **[UNVERIFIED]**.

**c.** No budget documents exist, so a discrete line item has nothing to sit in. A short annual resource statement would meet the intent: a fixed share of owner time, plus a hardware reserve for replacing a failed `tank` disk (`apps/monitoring/smartctl-alerts.yaml` alerts ahead of rated end of life to give "lead time to order").

**Evidence.** `docs/security/01-policy.md` §§4, 7, 19; ADR-0007; `docs/expansion-plan.md` ("Where the hardware stands").

**Gaps.**
- `G-SA-02`: Nothing documents the time or money set aside for security, or for replacing failed hardware. Risk: the §19 reviews and disk replacements compete with feature work and slip without anyone noticing. Remedy: an annual resource statement in the POA&M (owner hours per month for §19 activities; a spare-disk and hardware reserve; the list of paid tiers), reviewed at the monthly POA&M review. Target: **2027-01-31**.

**Related.** Policy §§4, 7, 19, 20; ADR-0007; PM-3; CP-family recovery objectives.

### SA-3 System Development Life Cycle

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; Automated Operators (authoring); ArgoCD (deployment); GitHub Actions (checks) |
| **Parameters** | sa-03_odp = the GitOps life cycle in `CONTRIBUTING.md` ("The loop") and policy §11: decision (ADR) → change in git → CI `validate` → owner merge (Z1) or in-session commit (Z2) → ArgoCD apply → data-plane verification → doctor-log entry for fixes |

> a. Acquire, develop, and manage the system using [Assignment: the GitOps life cycle in `CONTRIBUTING.md` and policy §11] that incorporates information security and privacy considerations;
> b. Define and document information security and privacy roles and responsibilities throughout the system development life cycle;
> c. Identify individuals having information security and privacy roles and responsibilities; and
> d. Integrate the organizational information security and privacy risk management process into system development life cycle activities.

**Implementation.**
**a.** Every in-cluster component goes through one life cycle. **Initiation and design:** a decision that is not obvious from the code gets an ADR (`docs/adr/README.md`), and a new component is given a tier and data class before its first deploy (policy §7.2.2). **Development:** manifests live under `apps/<name>/` with Pod Security labels and default-deny NetworkPolicies (`CONTRIBUTING.md`, "Adding an app"). **Validation:** the CI jobs listed under SA-11, plus a server-side dry-run (HS-GIT-05). **Deployment:** ArgoCD with prune and selfHeal (HS-GIT-01). **Operation:** `scripts/doctor.sh` and the doctor log. **Disposal:** removing an app from git deliberately leaves its state behind (ADR-0012, HS-STATE-01/02), the owner performs the final delete, and disks are sanitized under policy §13.4.

Three classes of component sit partly outside this cycle:
- **Images the owner builds locally** (`applemusic-decryptor`, `applemusicarr-plugin`, `wrapper-lite-src`, `spatial-sidecar`). They are built by hand on the nas from repositories outside this one and imported into containerd. The manifests reference them by tag only (see SA-10).
- **Host daemons** in `scripts/host/`. They are deployed by hand: `scripts/host/ganesha/README.md:4` says "nothing else in this repo deploys them".
- **Out-of-git state:** W-01 (Authentik objects), W-02 (`metallb`), W-03 (`apps/argocd`).

**b–c.** The roles in policy §3.1 cover the whole life cycle. The System Owner approves and accepts risk. Automated Operators author changes and never approve their own Z0/Z1 work (§3.2.1). System Agents are named and scoped (§9.3). One person holds every human role, and §3.2 lists the controls that compensate for that.

**d.** Risk management is built into the cycle in four places. Zones (§8) set who may change what. Change types (§11.1) set the approval each change needs. The Normal-change template asks for risk, blast radius and rollback (§11.2). Incident lessons feed back into checks (§16.3.5; HS-GIT-07). The integration is weakened by two things: `validate` does not gate `main` (HS-GIT-03), and on `origin/main` Renovate merges its own PRs, including some majors, into Z1 platform apps (see SA-10, G-SA-05).

**Evidence.** `CONTRIBUTING.md`; `docs/adr/README.md`; `docs/security/01-policy.md` §§3, 7.2, 8, 11; `.github/workflows/validate.yaml`; ADR-0012; `apps/spatial-sidecar/deployment.yaml:63-70`.

**Gaps.**
- `G-SA-03`: The four locally built images and the host daemons are built and deployed by hand, outside CI and outside the repository's change control. Risk: what runs cannot be reproduced or audited from git, and a node rebuild loses the images (see the earlier yt-dlp-shim case, `apps/downloads/octo-yt-dlp-shim.yaml:15-16`). Remedy: build the redistributable images in GitHub Actions from pinned commits, like `.github/workflows/octo.yaml`. For `wrapper-lite-src`, which contains non-redistributable Apple libraries, record the source commit and image digest in the manifest and list the image in the waiver register. Deploy the host daemons through the existing `ansible/` playbooks. Target: **2027-03-31**.

**Related.** Policy §§3, 8, 11, 13.4; HS-GIT-01/03, HS-STATE-01/02, HS-SUP-02; ADR-0007, ADR-0012; CM-3, SA-10, SA-15.

