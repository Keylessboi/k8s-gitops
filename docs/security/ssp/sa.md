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

**d.** Risk management is built into the cycle in four places. Zones (§8) set who may change what. Change types (§11.1) set the approval each change needs. The Normal-change template asks for risk, blast radius and rollback (§11.2). Incident lessons feed back into checks (§16.3.5; HS-GIT-07). The integration is weakened by two things: `validate` does not gate `main` (HS-GIT-03), and on `origin/main` Renovate merges its own PRs, including some majors, into Z1 platform apps (see SA-4, G-SA-05).

**Evidence.** `CONTRIBUTING.md`; `docs/adr/README.md`; `docs/security/01-policy.md` §§3, 7.2, 8, 11; `.github/workflows/validate.yaml`; ADR-0012; `apps/spatial-sidecar/deployment.yaml:63-70`.

**Gaps.**
- `G-SA-03`: The four locally built images and the host daemons are built and deployed by hand, outside CI and outside the repository's change control. Risk: what runs cannot be reproduced or audited from git, and a node rebuild loses the images (see the earlier yt-dlp-shim case, `apps/downloads/octo-yt-dlp-shim.yaml:15-16`). Remedy: build the redistributable images in GitHub Actions from pinned commits, like `.github/workflows/octo.yaml`. For `wrapper-lite-src`, which contains non-redistributable Apple libraries, record the source commit and image digest in the manifest and list the image in the waiver register. Deploy the host daemons through the existing `ansible/` playbooks. Target: **2027-03-31**.

**Related.** Policy §§3, 8, 11, 13.4; HS-GIT-01/03, HS-STATE-01/02, HS-SUP-02; ADR-0007, ADR-0012; CM-3, SA-10, SA-15.

### SA-4 Acquisition Process

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (selects and admits components); Automated Operators (propose); Renovate (updates, on `main` per ADR-0013) |
| **Parameters** | sa-04_odp.01 = standardized contract language, meaning the upstream project's open-source licence or the external provider's standard terms of service, which the owner accepts and cannot negotiate; sa-04_odp.02 = the organization's own admission requirements, applied at selection in place of contract clauses: `CONTRIBUTING.md` ("Standing rules for any new app", "Adding an app") and policy §§7.2, 11.1, 15 |

> Include the following requirements, descriptions, and criteria, explicitly or by reference, using [Selection: standardized contract language; [Assignment: the organization's admission requirements in `CONTRIBUTING.md` and policy §§7.2, 11.1, 15, applied at selection]] in the acquisition contract for the system, system component, or system service:
>   a. Security and privacy functional requirements;
>   b. Strength of mechanism requirements;
>   c. Security and privacy assurance requirements;
>   d. Controls needed to satisfy the security and privacy requirements.
>   e. Security and privacy documentation requirements;
>   f. Requirements for protecting security and privacy documentation;
>   g. Description of the system development environment and environment in which the system is intended to operate;
>   h. Allocation of responsibility or identification of parties responsible for information security, privacy, and supply chain risk management; and
>   i. Acceptance criteria.

**Implementation.**
There are no acquisition contracts. Nearly everything inside the boundary is off-the-shelf open-source software, pulled anonymously from public registries (no manifest under `apps/` sets `imagePullSecrets`) or inflated from public Helm chart repositories (twelve kustomizations use `helmCharts:`; `.github/workflows/validate.yaml`, kustomize-build comment). The upstream licence is the only "contract", and it disclaims warranty. External services (system description §2.2) are taken on the providers' standard terms. "Acquisition" here therefore means two acts the owner controls: **choosing a component** (a new `apps/<name>/` directory, a chart, an image tag) and **updating it**. The requirements are applied at those two points instead of in a contract:

- **a, d (functional requirements and controls):** a new app must ship Pod Security labels and default-deny NetworkPolicies on both ends, use the shared Postgres if it can, and keep state in backed-up stores (`CONTRIBUTING.md`, "Adding an app" and standing rules 0–5; ADR-0008, ADR-0009). Published apps go behind Authentik (system description §3).
- **c (assurance):** digest pinning is required (policy §15.3, HS-WL-01) but met for 16 of 85 containers. On `main`, Renovate waits 3 days after a release (`minimumReleaseAge`) and merges only after `validate` is green (`git show origin/main:renovate.json`).
- **g (environment):** the placement rules in `AGENTS.md` and the tier and data class assigned before first deploy (policy §7.2.2).
- **h (responsibility):** policy §3.1; supply-chain decisions sit with the System Owner.
- **i (acceptance):** CI `validate` plus data-plane proof (policy §11.3, HS-AGENT-07).
- **b, e, f:** not addressed. Nothing states a strength-of-mechanism requirement for a component (for example, "supports OIDC" or "encrypts at rest"), and no admission record captures the upstream's security documentation.

Selection reasoning is recorded case by case in manifest headers, for example Notesnook chosen "over TriliumNext and Joplin" (`apps/notesnook/kustomization.yaml:4-6`) and the Bitnami Redis chart rejected as deprecated (`apps/redis/deployment.yaml:1-5`). There is no checklist.

**The update path contradicts the policy.** Policy §15.3 says Renovate MUST NOT auto-apply majors, §11.1 makes "any Renovate major" a Normal change the owner merges, and HS-SUP-01 is marked MET against this branch's `renovate.json:7-11`. On `main`, ADR-0013 (PR #24, `dcc8703`) enables majors and lets Renovate merge its own PRs overnight, except for the listed data-migrating images, Lidarr, Mongo and ArgoCD. Z1 platform charts (Authentik, Traefik, cert-manager, CNPG, kube-prometheus-stack) are therefore automerged on majors, and `renovate[bot]` already commits to `main` (`6152ddc`, #59).

**Evidence.** `CONTRIBUTING.md`; `renovate.json` (this branch) vs `git show origin/main:renovate.json`; `git show origin/main:docs/adr/0013-renovate-owns-updates.md`; `grep -rn imagePullSecrets apps/` (no matches); `git log origin/main --author='renovate' --oneline`.

**Gaps.**
- `G-SA-04`: There are no written admission criteria for a new component or service: licence, maintainer health, security features (SSO, encryption, non-root), strength of mechanism, published security documentation, exit plan. Risk: components are admitted on functional fit alone, and weak or abandoned ones (see SA-22) come in unflagged. Remedy: an "Acquiring a component or service" checklist in `CONTRIBUTING.md`, with its answers recorded in the new app's `kustomization.yaml` header or its PR description. Target: **2026-12-15**.
- `G-SA-05`: Renovate on `main` automerges major versions of Z1 and Tier 0/1 components, contrary to policy §§11.1, 15.3 and HS-SUP-01. Risk: a breaking or compromised major release of the identity provider or ingress lands unreviewed at night, and `validate` only proves that it renders. Remedy: the owner either adds every Z1 app to a `"automerge": false` rule in `renovate.json`, or amends policy §§11.1, 15.3 and HS-SUP-01 to record the ADR-0013 trade-off as an accepted risk. Either way, the policy and the config must agree. Target: **2026-11-15**.

**Related.** Policy §§7.2, 11.1, 15, 17; HS-WL-01, HS-SUP-01..04; ADR-0008, ADR-0009, ADR-0013; SA-9, SA-22, CM-3, SR family.

### SA-4(1) Functional Properties of Controls

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; upstream projects (as publishers of documentation) |
| **Parameters** | None |

> Require the developer of the system, system component, or system service to provide a description of the functional properties of the controls to be implemented.

**Implementation.**
Nobody can be *required* to provide anything: the developers are volunteer upstream projects and SaaS providers with standard terms (SA-4). The owner instead **obtains** the functional description from what upstream publishes, and writes down the properties that matter in the manifest that deploys the component. Examples:
- The FairPlay daemon's privilege needs (SYS_CHROOT, SYS_ADMIN, SYS_PTRACE, unconfined seccomp) and the reason it has its own namespace: `apps/applemusic-wrapper/applemusic-wrapper.yaml:26-32`.
- Notesnook's end-to-end encryption, its lack of OIDC, and upstream's "alpha, unsupported" label for self-hosting: `apps/notesnook/kustomization.yaml:1-21`.
- Vaultwarden SSO behaviour, confirmed against upstream source (`FAKE_IDENTIFIER`) and live endpoints: `docs/RUNDOWN.md`, "Vaultwarden SSO".

For the components the owner develops (manifests, `scripts/`, the forked Octo build, the locally built images), the "developer" is the owner and their agents. The functional properties of the guardrails they built are described in ADR-0012, the `validate.yaml` job comments and `CONTRIBUTING.md` ("What CI enforces").

The gap is coverage. These descriptions exist where an incident or a hard choice forced them. Nothing guarantees that each admitted component has a recorded statement of its security functions (authentication method, encryption, privilege needs, logging), and the Tier 0/1 Helm charts (Authentik, Traefik, cert-manager, CNPG) rely on upstream docs that are not referenced from the repo.

**Evidence.** The manifest headers cited above; ADR-0012; `.github/workflows/validate.yaml` comments; `CONTRIBUTING.md`.

**Gaps.**
- Covered by `G-SA-04`: the admission checklist must record each component's security functions and link the upstream security documentation, starting with the Tier 0/1 components.

**Related.** SA-4, SA-5, SA-15(3); policy §7.2.2.

### SA-4(2) Design and Implementation Information for Controls

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |
| **Responsible** | System Owner |
| **Parameters** | sa-04.02_odp.01 = security-relevant external system interfaces; source code; sa-04.02_odp.02 = none; sa-04.02_odp.03 = as published by the upstream project (public source repository and documentation), plus the deployed manifests in this repository |

> Require the developer of the system, system component, or system service to provide design and implementation information for the controls that includes: [Selection: security-relevant external system interfaces; source code] at [Assignment: the level published by the upstream project, plus the deployed manifests in this repository].

**Implementation.**
The intent is that the organization can see how a control is built. For open-source components this holds without any contract, because the source code is public. The owner has used it that way: the Vaultwarden SSO behaviour was settled from a constant in its source (`docs/RUNDOWN.md`, "Vaultwarden SSO"), the Lidarr plugin-branch decision from upstream commit dates (`apps/lidarr/deployment.yaml:80-90`), and the Octo fixes were written against upstream source and offered back as pull requests (`.github/workflows/octo.yaml:4-17`). The system's own design and implementation information is the repository itself: every manifest, CI check and ADR is public (system description §1).

Availability is not review. Nobody audits upstream source before adopting or updating it, and Renovate updates without anyone reading a diff (SA-4).

Exceptions, where no design information exists:
- **`wrapper-lite-src`** loads Apple's proprietary Android native libraries, extracted from an APK that cannot be redistributed (`apps/applemusic-wrapper/applemusic-wrapper.yaml:4-7`). Its behaviour is known only by observation, and it runs with elevated capabilities in a `privileged` namespace (W-04).
- **SaaS providers** (Doppler, Tailscale's coordination service, GitHub, Cloudflare, AirVPN, model providers) publish documentation, not implementation detail. Those controls are inherited (SA-9).

**Evidence.** The cited manifest headers and workflow; system description §§1, 2.2; W-04 in `03-homelab-standard.md` §12.

**Gaps.** None beyond `G-SA-04` (record the closed-source exceptions at admission) and `G-SA-12` (SA-22).

**Related.** SA-4, SA-9, SA-11; W-04.

### SA-4(9) Functions, Ports, Protocols, and Services in Use

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; Automated Operators (author NetworkPolicies) |
| **Parameters** | None |

> Require the developer of the system, system component, or system service to identify the functions, ports, protocols, and services intended for organizational use.

**Implementation.**
For in-cluster components, the ports and protocols in use are taken from upstream documentation or compose files (for example, Notesnook was built "following upstream's docker-compose.yml service for service", `apps/notesnook/kustomization.yaml:12-21`). They are then declared three times in git: the container and Service ports, the Ingress host, and a default-deny NetworkPolicy that opens only those ports, on both ends of every cross-namespace flow (`CONTRIBUTING.md`, rule 5; 32 `apps/*/networkpolicy*.yaml` files). CI checks the pairing (`scripts/ci/check-invariants.py`), so the identified set is also the permitted set. Externally reachable ports have their own record: AirVPN forwards 6877 and 6874 and must agree in three places (`docs/RUNDOWN.md`, "AirVPN and the Torrent Stack"), and Pelican game ports are mapped on the router only while a server runs, then left to lapse (`scripts/host/pelican-portmap`, header).

Not covered:
- **Host-level services** on pve, the nas, CT 200 and travisbackupserver: SSH, NFS, MinIO, the Proxmox UI, ntfy, the edge probe, and the k3s API at 6443. They are not inventoried in one place. The ganesha config documents its own transports (`scripts/host/ganesha/README.md`, `Enable_UDP = false`), but nothing lists every listening port per host.
- **Pods with broad egress.** Some policies allow `0.0.0.0/0` minus private ranges (for example `apps/doppler/networkpolicy.yaml`), so the external services such a pod actually contacts are not identified.

**Evidence.** `apps/*/networkpolicy*.yaml`; `scripts/ci/check-invariants.py`; `docs/RUNDOWN.md`; `scripts/host/`.

**Gaps.**
- `G-SA-06`: There is no per-host inventory of listening ports and services, and no list of the external destinations of pods with wildcard egress. Risk: an unexpected listener or egress path cannot be recognised as unexpected. Remedy: a "Ports, protocols and services" table in system description §3, one row per host listener and per external egress destination, regenerated from `ss -tulpn` on each host and from the NetworkPolicies, and reviewed at the 12-month baseline review. Target: **2027-02-28**.

**Related.** CM-7, SC-7, SA-9(2); HS-NET-*; `CONTRIBUTING.md` rule 5.

### SA-4(10) Use of Approved PIV Products

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |
| **Responsible** | System Owner |
| **Parameters** | None |

> Employ only information technology products on the FIPS 201-approved products list for Personal Identity Verification (PIV) capability implemented within organizational systems.

**Implementation.**
The system implements no PIV capability. Personal Identity Verification is the US federal credential standard (FIPS 201), and neither the owner nor any service user holds a PIV card. No component accepts one. People authenticate to Authentik with passwords (MFA status **[UNVERIFIED]**, system description §5). The owner reaches hosts with the SSH key `worker_key`. Machine identities use service tokens and ServiceAccounts (system description §5). None of these is a PIV product, so the FIPS 201 approved products list has nothing to govern.

The remaining intent, using strong and assured authenticator products, is handled under IA-2 and IA-5 (MFA for the owner and service users, key handling in policy §12). If the owner later adopts hardware security keys (FIDO2/WebAuthn) for Authentik, that is still not PIV, and this control stays not applicable.

**Evidence.** System description §5; policy §§9.4, 12.1.

**Gaps.** None for this control. The MFA gaps are tracked under IA-2.

**Related.** IA-2, IA-5, IA-8; policy §9.4.

### SA-5 System Documentation

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; Automated Operators (write most runbooks and doctor-log entries) |
| **Parameters** | sa-05_odp.01 = record the attempt and its result in the deploying manifest's header comment or in `docs/doctor-log.md`, and derive the missing information from upstream source code or by testing against the live component; sa-05_odp.02 = the System Owner and every Automated Operator (through the repository and `AGENTS.md`); service users for user documentation |

> a. Obtain or develop administrator documentation for the system, system component, or system service that describes:
>   1. Secure configuration, installation, and operation of the system, component, or service;
>   2. Effective use and maintenance of security and privacy functions and mechanisms; and
>   3. Known vulnerabilities regarding configuration and use of administrative or privileged functions;
> b. Obtain or develop user documentation for the system, system component, or system service that describes:
>   1. User-accessible security and privacy functions and mechanisms and how to effectively use those functions and mechanisms;
>   2. Methods for user interaction, which enables individuals to use the system, component, or service in a more secure manner and protect individual privacy; and
>   3. User responsibilities in maintaining the security of the system, component, or service and privacy of individuals;
> c. Document attempts to obtain system, system component, or system service documentation when such documentation is either unavailable or nonexistent and take [Assignment: record the attempt in the manifest header or doctor log, and derive the information from upstream source or live testing] in response; and
> d. Distribute documentation to [Assignment: the System Owner and every Automated Operator; service users for user documentation].

**Implementation.**
**a.1–a.2 (administrator documentation).** This is extensive and lives in the repository: `docs/RUNDOWN.md` (operation, edge security, backups), `docs/access-procedures.md` (access paths), `docs/accounts.md` (account provisioning and app access), `docs/recovery/cluster-down.md`, `docs/ntfy.md`, `CONTRIBUTING.md`, the ADRs, `AGENTS.md`, and the "why" comments at the top of most manifests. Upstream vendor documentation is used but not mirrored.

**a.3 (known vulnerabilities in privileged functions).** These are recorded in three places: the doctor log (for example, the `NFS_CORE_PARAM` duplicate block that silently left a vulnerable UDP listener running, `scripts/host/ganesha/README.md`), the waiver register (W-01..W-06), and system description §7, which lists runbook defects. Since §7 was written, the ArgoCD password and `--cascade` items have been corrected on this branch (`docs/access-procedures.md:108-117, 129-132`; commit `6a99803`). The "Maintenance Windows" block is still template text: a Sunday window, an `#ops-alerts` channel, and "keep previous ArgoCD sync revision" as the rollback plan, which contradicts policy §11.4 (`docs/access-procedures.md:181-185`). `docs/SESSION-HANDOFF.md` and `docs/handoff.md` are flagged as historical in `AGENTS.md`, but the files themselves are not marked.

**b (user documentation).** Service users get almost nothing written. What exists is how-to material that is mostly addressed to the operator: `docs/kindle-koreader-setup.md`, the Vaultwarden SSO client table in `docs/RUNDOWN.md`, and step 2 of `docs/accounts.md` ("Tell the person to log in anywhere"). Nothing tells a service user to set a strong, unique Vaultwarden master password, to enable MFA, which apps hold their photos and files, how to report a suspected compromise (policy §3.1 makes that their responsibility), or what their data rights are (policy §13.3).

**c.** Attempts are recorded where documentation was missing: registry probes for an unpublished shim image (`apps/downloads/octo-yt-dlp-shim.yaml:3-8`), the SSO-fork survey for Invidious (`docs/accounts.md`, "Invidious"), and behaviour derived from source (Vaultwarden `FAKE_IDENTIFIER`).

**d.** Administrator documentation reaches the owner and agents through the public repository, and agents are pointed to it by `AGENTS.md` ("Where things are").

**Evidence.** The files named above; system description §7; `03-homelab-standard.md` §12.

**Gaps.**
- `G-SA-07`: There is no service-user documentation of security functions, responsibilities, reporting or data rights, and `docs/access-procedures.md` "Maintenance Windows" still holds template text that contradicts policy §11.4. Risk: service users with C3/C4 data (vaults, photos) cannot do their part (master-password strength, MFA, reporting), and an operator following the runbook rolls back the wrong way. Remedy: a one-page `docs/users.md` (later surfaced in Authentik's user interface) covering MFA, master passwords, which apps hold what, how to report, and policy §13.3 rights; replace the template block with a pointer to policy §11; add a "historical, not current" banner to the two handoff files. Target: **2027-01-31**.

**Related.** Policy §§3.1, 9.4, 11.4, 13.3, 16.6; AT-2, PL-4; system description §7.

### SA-8 Security and Privacy Engineering Principles

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (decides, through ADRs); Automated Operators (apply) |
| **Parameters** | sa-8_prm_1 = the principles in the accepted ADRs and policy: (1) reduce moving parts and keep the platform frozen (ADR-0007); (2) prevention as a check, not prose (ADR-0007; policy §1.3); (3) verify on the data plane, not by status (ADR-0007; policy §11.3); (4) disposable pods with state in protected, backed-up stores (ADR-0008, ADR-0009); (5) destruction takes two deliberate steps (ADR-0012; policy §3.2.3); (6) least privilege and deny by default (policy §9.1; default-deny NetworkPolicies, `CONTRIBUTING.md` rule 5); (7) single writer per datum (ADR-0004); (8) shared infrastructure over per-app copies (`CONTRIBUTING.md` rule 4); (9) mechanism over instruction for agents (policy §§1.2, 16.7.3) |

> Apply the following systems security and privacy engineering principles in the specification, design, development, implementation, and modification of the system and system components: [Assignment: the nine principles listed under Parameters, drawn from ADR-0004, -0007, -0008, -0009, -0012, policy §§1, 3.2, 9.1, 11.3, 16.7 and `CONTRIBUTING.md`].

**Implementation.**
The ADR process is how principles are recorded and applied. `docs/adr/README.md` asks for an ADR whenever a decision is "not obvious from the code", especially where "the obvious choice is wrong". The template (`docs/adr/0000-template.md`) requires the context with the evidence, the alternatives tried and rejected, the bad consequences, and a **tripwire** that tells a future reader the decision is being violated. That last field is what turns a principle into something an assessor or an agent can check.

The principles are visibly applied in design and modification, not just stated. Some examples:
- Principle 2: the CI invariants exist because a prose prevention failed twice (`CONTRIBUTING.md`, "The two invariants").
- Principle 5: `components/protect-state` and `preserveResourcesOnDeletion` (ADR-0012; this branch only, PR #21).
- Principle 4: the SQLite audit and its exemptions (`CONTRIBUTING.md` rule 1).
- Principle 6: separate namespaces so `lidarr` can keep PSA baseline while the FairPlay daemon is privileged (`apps/applemusic-wrapper/applemusic-wrapper.yaml:26-32`).
- Principle 1: the platform freeze (ADR-0007). ADR-0013 (on `main`) is a documented case of weighing one risk against another: it accepts unreviewed updates because "stale was the failure that actually happened".

Weaknesses:
- The principles are scattered across nine sources and have never been listed as one set (they are listed here for the first time).
- The ADR index is incomplete. On this branch `docs/adr/README.md` omits 0008, 0010 and 0012. On `main` it omits 0008 and 0010, and 0012 does not exist there.
- No **privacy** engineering principle (data minimisation, purpose limitation) appears in any ADR. Privacy appears only as handling rules in policy §§5–6 and 13.

**Evidence.** `docs/adr/README.md`; `docs/adr/0000-template.md`; ADR-0004, 0007, 0008, 0009, 0012; `git show origin/main:docs/adr/0013-renovate-owns-updates.md`; `CONTRIBUTING.md`; policy §§1, 3.2, 9.1.

**Gaps.**
- `G-SA-08`: There is no single statement of engineering principles, the ADR index is incomplete, and privacy-by-design principles are absent. Risk: an agent designing a change reads only the ADRs it finds and misses a governing principle, and personal data gets collected or copied without anyone asking whether it is needed. Remedy: add a "Design principles" section to `docs/adr/README.md` that lists the nine principles with their source ADRs, plus data minimisation and purpose limitation for C3/C4 data; complete the index; have CI check that every `docs/adr/0*.md` file appears in the index. Target: **2026-12-31**.

**Related.** ADR-0004, -0007, -0008, -0009, -0012, -0013; policy §§1, 3.2, 9.1; PL-8, SA-15, PT family.

### SA-9 External System Services

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (sole administrator of every provider account; Z0 per policy §8.2); providers for their internal controls (inherited, policy §2.2) |
| **Parameters** | sa-09_odp.01 = the provider's published security programme under its standard terms (accepted, not negotiated), plus the owner-side controls listed per provider below; sa-09_odp.02 = availability and integrity monitoring of each dependency from inside the system (edge probes, certificate-expiry alerts, CI results, Renovate's Dependency Dashboard), and the annual policy review (policy §19) |

> a. Require that providers of external system services comply with organizational security and privacy requirements and employ the following controls: [Assignment: the provider's published security programme under its standard terms, plus the owner-side controls listed below];
> b. Define and document organizational oversight and user roles and responsibilities with regard to external system services; and
> c. Employ the following processes, methods, and techniques to monitor control compliance by external service providers on an ongoing basis: [Assignment: availability and integrity monitoring from inside the system, and the annual policy review].

**Implementation.**
**a.** A single person cannot impose requirements on GitHub or Anthropic. What the owner controls is what each provider is **given** and how the account is **held**. The services are listed in system description §2.2, and policy §15.1 requires a new one that holds C3/C4 data to be added there first.

| Provider | Data that crosses | Owner-side controls (evidence) |
|---|---|---|
| GitHub (repo, Actions, GHCR, Renovate App) | Public configuration; owner-built images | No credentials in git: gitleaks job (`validate.yaml`, this branch only); `validate` token `contents: read`; image builds use `GITHUB_TOKEN` with `packages: write`, no PAT (`.github/workflows/octo.yaml:19-32`). Branch protection absent (HS-GIT-03/04). |
| Doppler | Every credential | Z0 (policy §8.2); agents may list names only (`AGENTS.md`, "Secrets"); service tokens rotated every 12 months (policy §12.1) |
| Tailscale | Admin traffic, off-site backup stream | ACLs and device approval are Z0 (policy §8.2); the content is SSH and WireGuard, encrypted end to end |
| Cloudflare | Public DNS records only | Z0 (§8.2); no Cloudflare API credential in-cluster, because certificates use HTTP-01 (`apps/cert-manager/clusterissuer.yaml:21-22`) |
| Let's Encrypt | Certificate requests | Certificate-expiry alert (`apps/monitoring/edge-probes.yaml:159-169`) |
| AirVPN | Torrent peer traffic | gluetun network namespace: no route out except the tunnel (system description §3); the WireGuard key is in Doppler (`docs/RUNDOWN.md`) |
| Registries | Image pulls (anonymous) | Digest pinning, partial (HS-WL-01, 16/85) |
| Model providers | Whatever an agent reads | Agents never read secret values (HS-SEC-03; `~/.claude/hooks/secret-guard.py` on the laptop, Claude Code only; policy §15.4) |
| Off-site borgmatic target | Encrypted backups | Borg passphrase escrow (policy §12.1); receiving host **[UNVERIFIED]** |

**b.** The System Owner holds every provider account and every oversight role (policy §3.1). Provider configuration is Z0, so agents may not change it (§8.2). Agents are users of the model providers and of GitHub, acting with the owner's credentials (§9.2). Policy §15.2 says the owner SHOULD know each provider's exit plan. None is written down.

**c.** Monitoring covers **availability and integrity of the service as consumed**, not the provider's compliance. The edge probe from travisbackupserver walks public DNS, the router and the certificate (`scripts/host/homelab-edge-probe`, header), and CI shows GitHub working. There is no alert for a failing Doppler sync or a down VPN tunnel (no rule found under `apps/monitoring/`). Nothing tracks provider security notices or breach disclosures, or reviews provider-side audit logs (GitHub security log, Doppler activity log, Tailscale admin log). MFA on each provider account is **[UNVERIFIED]** (system description §5), and so are the model providers' data-retention and training settings.

**Evidence.** System description §2.2; policy §§3.1, 8.2, 12.1, 15; `.github/workflows/*.yaml`; `apps/cert-manager/clusterissuer.yaml`; `apps/monitoring/edge-probes.yaml`; `scripts/host/homelab-edge-probe`.

**Gaps.**
- `G-SA-09`: There is no external-service register with exit plans, account MFA status, retention and training settings, monitoring method and a review date, and there are no alerts for Doppler-sync or VPN-tunnel failure. Risk: a provider breach, a policy change (for example, a model provider's training terms) or an account takeover goes unnoticed, and a provider loss has no rehearsed way out. Remedy: extend system description §2.2 with "inherited controls", "owner-side controls", "MFA (verified date)", "exit plan" and "how we'd notice" columns; subscribe the owner's ntfy or email to each provider's status and security feeds; add Prometheus alerts for DopplerSecret sync errors and gluetun health; review the register at the annual policy review. Target: **2027-02-28**.

**Related.** Policy §§2.2, 8.2, 15; HS-SEC-01, HS-SEC-03, HS-GIT-03; CA-3, SR-6, AC-20.

### SA-9(2) Identification of Functions, Ports, Protocols, and Services

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | sa-09.02_odp = every service in system description §2.2: GitHub, Doppler, Tailscale, Cloudflare, Let's Encrypt, AirVPN, container registries, AI model providers, the off-site borgmatic target |

> Require providers of the following external system services to identify the functions, ports, protocols, and other services required for the use of such services: [Assignment: every service in system description §2.2].

**Implementation.**
Providers publish what their services need, and the owner has taken those requirements into the configuration wherever a NetworkPolicy or firewall had to permit them. The identified flows, with where each is recorded:
- **Let's Encrypt:** ACME over HTTPS, with HTTP-01 validation, so inbound port 80 must reach Traefik (`apps/cert-manager/clusterissuer.yaml:16-22`).
- **AirVPN:** a WireGuard tunnel from gluetun, plus forwarded inbound ports 6877 and 6874 (`docs/RUNDOWN.md`, "AirVPN and the Torrent Stack"). gluetun's firewall drops everything not on `tun0` (`apps/downloads/networkpolicy.yaml:6-11`).
- **Doppler:** HTTPS API from the operator pod, allowed through a `0.0.0.0/0`-minus-private egress rule (`apps/doppler/networkpolicy.yaml`).
- **GitHub:** HTTPS from ArgoCD's repo-server (polls `main`, system description §6.1) and from the laptop.
- **Tailscale:** WireGuard between the laptop, pve, the nas and travisbackupserver. Its coordination and relay endpoints are **[UNVERIFIED]**; no host firewall rules are in the repository.
- **Cloudflare:** public DNS resolution only.
- **Model providers:** HTTPS from the laptop's agent harnesses, outside the cluster.

The gap is precision, not absence. Where the egress is a wildcard, the specific provider endpoints are not recorded, so a pod's traffic to anything else on the internet is indistinguishable from traffic to its provider. No host firewall configuration for pve, the nas or travisbackupserver is in git, so the host-level flows to Tailscale and the borgmatic target are not identified at all.

**Evidence.** The files cited above; system description §§2.2, 3, 6.

**Gaps.**
- Covered by `G-SA-06` (the ports, protocols and services table includes a row per external provider flow) and `G-SA-09` (the register links each provider's published network requirements).

**Related.** SA-4(9), SA-9, CM-7, SC-7; policy §15.

