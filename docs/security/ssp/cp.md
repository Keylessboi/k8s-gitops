# CP — Contingency Planning

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Contingency planning here is strongest where an outage has already hurt. The
database chain has four overlapping layers, freshness alerts that read the
stored data, and a monthly automated restore drill (`apps/databases/`). The
2026-09-04 power loss led to an external watchdog, a full-outage runbook
(`docs/recovery/cluster-down.md`) and the CT 200 `onboot` fix. Coverage falls
away from the databases outward:

- the RTO/RPO targets in policy §7 have never been timed;
- file data on NFS PVCs has no restore test, and its dataset (`tank/extra`)
  has no snapshot policy;
- the off-site borgmatic copy has no freshness alert, and its target and
  coverage are recorded only in a stale script;
- several state-holding stores have no backup at all (Notesnook's MongoDB and
  most `local-path` PVCs);
- the main restore runbook (`scripts/restore.sh`) describes an architecture
  that no longer exists.

Family-wide decision: alternate processing sites and alternate
telecommunications (CP-7, CP-8 and their enhancements) are **not applicable**.
Availability is categorized LOW (policy §4), the platform is single-site by
design (W-06), and recovery after a site loss is rebuilding from git and the
off-site backup (CP-10). That makes the off-site storage copy (CP-6) the only
"alternate site" the system has, and the one that most needs work.

| Disposition | Count |
|---|---|
| Implemented | 0 |
| Partially implemented | 14 |
| Planned | 0 |
| Inherited | 0 |
| Alternative implementation | 2 |
| Not applicable | 7 |
| **Total** | **23** |

---

### CP-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | cp-1_prm_1 = System Owner and automated operators; cp-01_odp.03 = system-level; cp-01_odp.04 = System Owner (Security Officer role, policy §3.1); cp-01_odp.05 = 12 months (policy App. A); cp-01_odp.06 = SEV-1 or SEV-2 incident, new Tier 0/1 component, change in privileged access, major platform change (App. A); cp-01_odp.07 = 12 months; cp-01_odp.08 = the App. A events plus any change to boot order, host or network (HS-REC-04) |

> a. Develop, document, and disseminate to [Assignment: System Owner and automated operators]:
>   1. [Selection: system-level] contingency planning policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the contingency planning policy and the associated contingency planning controls;
> b. Designate an [Assignment: System Owner] to manage the development, documentation, and dissemination of the contingency planning policy and procedures; and
> c. Review and update the current contingency planning:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident; a new Tier 0 or 1 component; a change in who has privileged access; a major platform change (an ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, and any change to boot order, host or network].

**Implementation.**
**a.1.** The contingency policy has no section of its own. It is spread through `docs/security/01-policy.md`:
- purpose and scope: §1–§2;
- roles: §3. The owner holds every role and automated operators hold none above Operator;
- recovery tiers and objectives: §7;
- backup, retention and 3-2-1: §13.1–§13.2;
- key escrow: §12.2.5;
- incident phases and restore order: §16.3;
- the review cadence for the restore exercise and escrow checks: §19.

Management commitment is §20–§21. Coordination with other organizations does not arise beyond the inherited providers. Compliance is §19. The policy is **DRAFT** and not in force until the owner merges it (§21).
**a.2.** These are the procedures:
- `docs/recovery/cluster-down.md` (full outage);
- `docs/RUNDOWN.md` § Backups;
- `docs/access-procedures.md` § Emergency Bypass and § Restore Procedure;
- `scripts/restore.sh`;
- `apps/databases/restore-verify-job.yaml.example`;
- `scripts/bootstrap-argocd.sh`.

Agents receive them through `AGENTS.md` ("A full outage → `docs/recovery/cluster-down.md`").
**b.** The owner, as Security Officer.
**c.** The policy carries the 12-month cycle in its document control. HS-REC-04 adds the event trigger for the outage runbook. No review has been recorded yet.

**Evidence.** `docs/security/01-policy.md` (document control, §7, §12, §13, §16, §19, §21); `AGENTS.md` "Where things are"; the runbooks listed above.

**Gaps.**
- `G-CP-01` The policy is unapproved (DRAFT, §21), so no contingency rule is yet in force. Risk: rules nobody approved are not binding when they become inconvenient during an outage. Remedy: the owner reviews and merges HL-POL-001. Target **2026-11-01**.
- `G-CP-02` `scripts/restore.sh` describes the 2026-08-23 architecture, which no longer exists:
  - per-app CNPG clusters (`vaultwarden-db`, `immich-db`, `authentik-postgresql`);
  - dumps on NFS at `/mnt/nas-nfs/backups/pg`;
  - borg "every 6h".

  It has no path for restic or barman. Its `immich-rebuild` function decodes a Secret into a variable and runs `kubectl delete pvc` (lines 430–432, 489), against HS-SEC-03 and HS-STATE-03. Risk: the owner or an agent follows it during a crisis and destroys state. Remedy: rewrite it around the restic, barman and borg paths, and remove the destructive functions. Target **2026-12-15**.

**Related.** Policy §3, §7, §12, §13, §16, §19; HS-REC-04; CP-2; IR-1.

### CP-2 Contingency Plan

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | cp-2_prm_1 = System Owner; cp-2_prm_2 = System Owner and automated operators (through the repository and `AGENTS.md`); cp-02_odp.05 = every 12 months, and after any SEV-1/SEV-2 or change to boot order, host or network; cp-2_prm_4 = System Owner and automated operators |

> a. Develop a contingency plan for the system that:
>   1. Identifies essential mission and business functions and associated contingency requirements;
>   2. Provides recovery objectives, restoration priorities, and metrics;
>   3. Addresses contingency roles, responsibilities, assigned individuals with contact information;
>   4. Addresses maintaining essential mission and business functions despite a system disruption, compromise, or failure;
>   5. Addresses eventual, full system restoration without deterioration of the controls originally planned and implemented;
>   6. Addresses the sharing of contingency information; and
>   7. Is reviewed and approved by [Assignment: System Owner];
> b. Distribute copies of the contingency plan to [Assignment: System Owner and automated operators, through the repository and `AGENTS.md`];
> c. Coordinate contingency planning activities with incident handling activities;
> d. Review the contingency plan for the system [Assignment: every 12 months, and after any SEV-1/SEV-2 incident or change to boot order, host or network];
> e. Update the contingency plan to address changes to the organization, system, or environment of operation and problems encountered during contingency plan implementation, execution, or testing;
> f. Communicate contingency plan changes to [Assignment: System Owner and automated operators];
> g. Incorporate lessons learned from contingency plan testing, training, or actual contingency activities into contingency testing and training; and
> h. Protect the contingency plan from unauthorized disclosure and modification.

**Implementation.** No single plan exists. Its parts are spread across several files.

**a.1–2.** Policy §7.1 sets the tiers, with RTO and RPO for each, and §7.2.3 the restore order (Tier 0 → 3). Metrics come from the backup alerts and the drill (`apps/monitoring/backup-alerts.yaml`). The targets are explicitly UNMEASURED (§7.1).
**a.3.** There is one person. `docs/access-procedures.md` § Contacts names the owner for every escalation path.
**a.4.** There is no continuity of operations, by design (availability is LOW, W-06). Clients keep working copies for some apps: Notesnook is offline-first (`apps/notesnook/kustomization.yaml`) and Vaultwarden clients cache vaults **[UNVERIFIED]**.
**a.5.** Restoring through GitOps re-applies NetworkPolicies, forward-auth and Pod Security labels with the apps, so controls do not degrade. The exception is out-of-git state (W-01..W-03): Authentik objects come back only with Authentik's database, `apps/argocd` is applied by hand, and the `metallb` namespace is created by hand.
**a.6.** Policy §16.6 covers telling service users about incidents. There is no outage-notice channel.
**a.7.** Not yet approved (G-CP-01).
**b, f.** Distribution is the git repository. It stays readable from GitHub and any clone while the cluster is down.
**c.** The incident phases (§16.3) call for restore in tier order. A failed backup or drill is SEV-3 (§16.2).
**d–e, g.** The plan is updated after real events, through doctor-log entries and runbook edits. The 2026-09-04 outage produced the external watchdog and the BIOS and `onboot` fixes.
**h.** The repository is public by design (C1, no credentials: HS-SEC-01). Integrity rests on GitHub with no branch protection (HS-GIT-03 GAP), so anyone with push access, including an agent, can change the plan unreviewed.

**Evidence.** Policy §7, §16; `docs/recovery/cluster-down.md`; `docs/RUNDOWN.md` § Backups; `docs/access-procedures.md` § Contacts; doctor-log 2026-09-04 (evening).

**Gaps.**
- `G-CP-03` There is no single plan document that maps each failure scenario (pod, PVC, database, nas, pve, site, compromise) to its backup layer, runbook, tier, RTO and out-of-git steps. Risk: during an outage the owner has to put the plan together from six files. Remedy: write `docs/recovery/contingency-plan.md`, including a service-user outage notice. Target **2027-01-31**.
- `G-CP-04` `docs/recovery/cluster-down.md` tells the reader to `ssh root@100.69.240.8` (the nas). Every other source says the nas accepts only `travis` (`docs/access-procedures.md` § SSH Access). Risk: the first recovery step fails mid-outage. Remedy: correct the user and add `doas` where root is needed. Target **2026-11-01**.
- `G-CP-05` The plan's integrity relies on unprotected `main` (HS-GIT-03). Remedy: branch protection, as in the POA&M item. Target **2026-12-31**.

**Related.** Policy §7, §16; W-01..W-03, W-06; HS-REC-04, HS-GIT-03; CP-2(1), CP-4, IR-8.

### CP-2(1) Coordinate with Related Plans

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |
| **Responsible** | System Owner |
| **Parameters** | None |

> Coordinate contingency plan development with organizational elements responsible for related plans.

**Implementation.** One person writes the incident response policy (§16), the change rules (§11), the POA&M, the capacity plan (`docs/expansion-plan.md`) and the ADRs. There are no other organizational elements to coordinate with. The control's intent is that related plans do not contradict each other. Two mechanisms stand in for that:
1. Policy §11.5.5 requires a policy change to update `03-homelab-standard.md` and the affected SSP sections in the same PR. The plans are therefore versioned together and reviewed as one diff.
2. Cross-references bind the plans to each other: §16.3 restores in §7.2 tier order, HS-REC-04 ties the outage runbook to boot-order and host changes, and ADR-0012 ties the deletion rules to state recovery.

The external providers (Doppler, GitHub, Tailscale) have their own continuity arrangements, which are not coordinated with this plan. They are inherited, and their loss is handled as an exit-plan question under policy §15.2.

**Evidence.** Policy §11.5.5, §15.2, §16.3; HS-REC-04; ADR-0012.

**Gaps.** None beyond G-CP-03, the single plan document that would make the coordination visible.

**Related.** CP-2, IR-8, PL-2.

### CP-2(3) Resume Mission and Business Functions

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | cp-02.03_odp.01 = essential; cp-02.03_odp.02 = 24 hours for Tier 0 and Tier 1 (policy §7.1); Tier 2 72 hours; Tier 3 7 days |

> Plan for the resumption of [Selection: essential] mission and business functions within [Assignment: 24 hours (Tier 0 and Tier 1); 72 hours (Tier 2); 7 days (Tier 3)] of contingency plan activation.

**Implementation.** The essential functions are identity, password vaults and the platform they run on: Tier 0 and Tier 1 in policy §7.1. They are planned for resumption within 24 hours. §7.2.3 forbids Tier 3 work while anything in Tier 0–2 is down.

The only evidence of actually resuming within the target is incidental. In the 2026-09-04 power loss, pve went off at 18:39:30. The k3s API was back at 13:55:46 the next day, about 19 hours later and inside the 24-hour target. That result came from physical intervention and a BIOS change, not from executing a plan. Detection alone took 3h37m. Two of the 19 hours were caused by CT 200 lacking `onboot` (`docs/recovery/cluster-down.md`, "Resolution — 2026-09-05").

No scenario that needs data restored rather than a reboot (lost nas, lost CNPG volume, lost site) has ever been timed. Under the brief, that makes the 24 h/72 h figures aspirations (§7.1: "commitments to aim at, not measurements").

**Evidence.** Policy §7.1–§7.2; `docs/recovery/cluster-down.md` timeline and Resolution; doctor-log 2026-09-04 (evening).

**Gaps.**
- `G-CP-06` The RTO and RPO have never been measured for a restore scenario. Risk: the 24-hour commitment may not be achievable, and nobody would know until it is needed. Remedy: the first timed restore exercise (Tier 0/1: rebuild the `databases` cluster from barman into a scratch namespace and time it) by **2027-01-31**, then one tier every 6 months (policy §19).

**Related.** Policy §7, §19; CP-4, CP-10.

### CP-2(8) Identify Critical Assets

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | cp-02.08_odp = essential |

> Identify critical system assets supporting [Selection: essential] mission and business functions.

**Implementation.** `00-system-description.md` §4 gives every `apps/*` workload a tier and a data class. Policy §7.1 places the hosts in Tier 0: pve, CT 200, the nas and `tank`. It also places there the git repository, Doppler, CNPG and the `databases` cluster, and the ingress and storage plumbing. Tier 1 adds Authentik, Vaultwarden, monitoring and the external watchdog. Policy §7.2.1 propagates tier upward through dependencies, and §7.2.2 requires a tier before a component's first deploy.

Several assets that recovery depends on are not tiered:
- **travisbackupserver**: it hosts ntfy, which is the only alert path when pve is down (`docs/recovery/cluster-down.md`), and, per `scripts/restore.sh` line 16, the off-site borg repository;
- **the operator laptop and `worker_key`**: the only SSH key every host accepts (`docs/access-procedures.md`). Its escrow is **[UNVERIFIED]** (policy §12.1);
- **the escrowed keys**: the ZFS key, borg passphrase and restic password. Losing any of them makes a backup layer unrecoverable (§12.2.5);
- **the MinIO buckets** `cnpg-backups` and `app-data-backups`, as distinct from MinIO the service.

**Evidence.** `00-system-description.md` §4; policy §7.1–§7.2, §12.1.

**Gaps.**
- `G-CP-07` The backup server, the off-site repository, the operator laptop and key, and the escrowed keys have no tier. Risk: a recovery dependency with no tier gets no restore order and no RTO, and is found missing only during the recovery. Remedy: add them to §7.1 and the system description. Target **2026-12-01**.

**Related.** Policy §7, §12; CM-8; RA-9.
