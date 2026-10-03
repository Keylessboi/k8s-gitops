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
| Partially implemented | 8 |
| Alternative implementation | 3 |
| **Total** | **11** |
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

### CP-3 Contingency Training

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |
| **Responsible** | System Owner |
| **Parameters** | cp-03_odp.01 = before first acting in a contingency role (for automated operators: at the start of every session, through `AGENTS.md`); cp-03_odp.02 = every 12 months, at the policy review; cp-03_odp.03 = 12 months; cp-03_odp.04 = a SEV-1 or SEV-2 incident, any change to a recovery runbook, and any change to boot order, host or network (HS-REC-04) |

> a. Provide contingency training to system users consistent with assigned roles and responsibilities:
>   1. Within [Assignment: before first acting in a contingency role; for automated operators, at the start of every session] of assuming a contingency role or responsibility;
>   2. When required by system changes; and
>   3. [Assignment: every 12 months] thereafter; and
> b. Review and update contingency training content [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident, any change to a recovery runbook, and any change to boot order, host or network].

**Implementation.** There is no training programme, and one cannot be justified: the only person with a contingency role wrote every runbook. The intent is that whoever executes recovery knows how. Three mechanisms stand in for it:

- **The owner.** The awareness-training default in policy App. A ("the owner reads this policy and the doctor log at each review") covers the contingency material: `docs/recovery/cluster-down.md`, `docs/RUNDOWN.md` § Backups and the doctor-log entries for every outage. HS-REC-04 requires the full-outage runbook to be *walked through* after any change to boot order, host or network. That walk-through is the practical exercise (**a.2**). The 2026-09-04/05 outage was a real execution of the runbook.
- **Automated operators.** Agents receive the routing at every session start ("A full outage → `docs/recovery/cluster-down.md`", `AGENTS.md`). Their contingency role is deliberately narrow. Backups, `tank`, snapshots and BIOS tokens are Z0 (policy §8.2), so agents may diagnose and describe a recovery but never execute the Z0 steps. Their "training" is therefore the rules that stop them, not recovery skills.
- **Service users** have no contingency role.

**b.** The content is the runbooks themselves. They are updated by the same change that alters the system (policy §11.5.5, HS-REC-04).

**Evidence.** `AGENTS.md` "Where things are"; policy App. A, §8.2; HS-REC-04; `docs/recovery/cluster-down.md` "Resolution — 2026-09-05".

**Gaps.**
- `G-CP-08` No walk-through has ever been recorded, although HS-REC-04 is marked MET. At least two qualifying changes followed the runbook's last edit: CT 200 moving from DHCP to a static address (doctor-log, "The same log file took the cluster down again") and the CoreDNS takeover on 2026-09-14. The owner has also never practised the data-restore paths: a barman recovery, `borg extract`, or restoring an NFS PVC. Risk: the first time the owner performs a restore is during a real loss. Remedy: record each walk-through as a dated doctor-log line, and make the timed exercise in G-CP-06 the hands-on practice. Target **2027-01-31**.

**Related.** HS-REC-04; policy §8.2, §19, App. A; AT-3; CP-4.

### CP-4 Contingency Plan Testing

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; `restore-drill` and `backup-freshness` CronJobs (`apps/databases/`) |
| **Parameters** | cp-04_odp.01 = every 6 months for the timed restore exercise; monthly for the automated database drill (policy App. A, §19); cp-4_prm_2 = (1) automated restore drill of every logical dump; (2) timed restore exercise, one tier each time, against the §7.1 RTO and RPO; (3) walk-through of the full-outage runbook (HS-REC-04) |

> a. Test the contingency plan for the system [Assignment: every 6 months (timed restore exercise); monthly (automated database drill)] using the following tests to determine the effectiveness of the plan and the readiness to execute the plan: [Assignment: automated restore drill of every logical dump; timed restore exercise, one tier each time, against the policy §7.1 RTO and RPO; walk-through of the full-outage runbook].
> b. Review the contingency plan test results; and
> c. Initiate corrective actions, if needed.

**Implementation.**
**a.** One of the three tests runs.

- **The monthly drill** runs at 03:20 on the 1st (`apps/databases/restore-drill-cronjob.yaml`). It restores the newest restic snapshot, then works in two stages. Stage 1 streams every dump through `pg_restore` to `/dev/null`, which reads every block. Stage 2 restores each dump under 300 MB into a `drill_`-prefixed scratch database and compares its table count against the archive's table of contents. A missing `globals.sql` or a surviving scratch database is a failure. The last recorded run checked 17 dumps and fully restored 16, with bitmagnet integrity-checked only (`docs/RUNDOWN.md` § Backups).
- **The timed exercise** (§19) has never been run, so every RTO and RPO is UNMEASURED (§7.1; G-CP-06).
- **The runbook walk-through** has no record (G-CP-08).

The drill is narrower than it looks. It proves the logical dumps of the newest snapshot only. It restores into the **production** instance, so it proves neither that Postgres can be stood up from nothing nor that the apps work on the restored data. It does not touch barman PITR, the off-site borg copy, ZFS snapshots, file PVCs, the Vaultwarden data mirror or the etcd snapshots. It also needs the cluster to be up to run at all.

**b.** A failed drill fires `BackupRestoreDrillFailed` (critical). A drill that has not succeeded in 40 days fires `BackupRestoreDrillStale` (`apps/monitoring/backup-alerts.yaml`). Both are `Backup*`, the prefix routed to the owner by email. The per-database table exists only in the pod log of the Jobs kept by `successfulJobsHistoryLimit: 3`.
**c.** The first run's findings were corrected the same day (doctor-log 2026-09-03, "The new restore drill restarted the apiserver twice"): the two stages, the 300 MB cap and a correct table count. The 2026-09-04 outage led to the BIOS, `onboot` and external-watchdog fixes.

**Evidence.** `apps/databases/restore-drill-cronjob.yaml`; `apps/monitoring/backup-alerts.yaml` lines 104–135; `kubectl -n databases get cronjob restore-drill`; doctor-log 2026-09-03.

**Gaps.**
- `G-CP-09` No restore test exists for file data or for the non-dump layers: NFS PVCs on `tank/extra` (the Immich library, Vaultwarden attachments), the borg off-site copy, the etcd snapshots and the Vaultwarden mirror (HS-REC-03 GAP). Risk: the photo library and the off-site copy could be unrestorable, and nobody would know until they were needed. Remedy: a monthly sampled restore — extract N random files from the latest borg archive and from the newest ZFS snapshot, and compare checksums against live — alerting on mismatch. Target **2027-03-31**.
- `G-CP-10` Test results are not retained. The drill's per-database output lives only in the last three Jobs' pod logs. Risk: no history to show the drill passed, or when it began to degrade. Remedy: the drill writes its summary line (checked, restored, failed) as a metric or a doctor-log line, and each 6-monthly exercise is recorded with its measured times. Target **2026-12-31**.

**Related.** HS-REC-02, HS-REC-03, HS-REC-04; policy §7.1, §16.2, §19; CP-2(3), CP-9(1).

### CP-4(1) Coordinate with Related Plans

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |
| **Responsible** | System Owner |
| **Parameters** | None |

> Coordinate contingency plan testing with organizational elements responsible for related plans.

**Implementation.** One person owns every related plan, so coordination is with plans, not with people. The intent is that tests neither collide with other plans nor go unnoticed by them. That is met in three ways:

1. **With incident response.** A failed backup or drill is SEV-3 (policy §16.2). The drill's alerts use the `Backup*` prefix so that they reach a human rather than being triaged by a model (`apps/monitoring/backup-alerts.yaml` comments).
2. **With capacity planning.** The drill's 300 MB cap and its 12 GB free-space floor exist because a full restore restarted the apiserver twice on a node at 92% memory. The cap is tied to the headroom work in ADR-0005/ADR-0007, and is to be raised "after the headroom work, not before" (doctor-log 2026-09-03).
3. **With the backup schedule.** Jobs are offset: `pgdump-backup` runs at :40 every six hours, the drill at 03:20 on the 1st, and `backup-freshness` at 09:20.

**Evidence.** The CronJob schedules in `apps/databases/*.yaml` and `apps/vaultwarden/backup-cronjob.yaml`; policy §16.2; doctor-log 2026-09-03.

**Gaps.**
- `G-CP-11` The schedule coordination missed one collision. The barman base backup runs at 03:15 daily (`apps/databases/scheduledbackup.yaml`), and its comment says that time "keeps it clear of everything else". On the 1st of each month the drill starts five minutes later against the same instance. A base backup's duration is **[UNVERIFIED]**. Risk: on a memory-constrained node the two overlap and repeat the 2026-09-03 apiserver restarts. Remedy: move the drill to 04:20 in a Z1 PR. Target **2026-11-15**.

**Related.** CP-2(1), CP-4, IR-3.

### CP-6 Alternate Storage Site

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; borgmatic on the nas; travisbackupserver |
| **Parameters** | None |

> a. Establish an alternate storage site, including necessary agreements to permit the storage and retrieval of system backup information; and
> b. Ensure that the alternate storage site provides controls equivalent to that of the primary site.

**Implementation.**
**a.** The alternate storage site is the off-site borgmatic copy. It runs nightly from the nas over Tailscale, rate-limited to 1 MB/s (`docs/RUNDOWN.md` § Backups).

The repository's only record of the target is `scripts/restore.sh` lines 16 and 41: `ssh://root@100.81.123.74/mnt/backups`. That address is travisbackupserver, the Debian host "at another site … Long Island" (`docs/access-procedures.md` § Infrastructure). The same script is dated 2026-08-23 and is wrong about the rest of the backup architecture (G-CP-02), and the system description marks the receiving host **[UNVERIFIED]** (§2.2). Several facts are unknown:
- what the copy covers (which datasets; whether it includes `/tank/minio`, where the database backups live);
- its retention;
- its encryption mode.

Even if it is the backup server, no agreement covers the premises. That host has "no remote hands" (`docs/access-procedures.md` § GPU on travisbackupserver), and who controls physical access to it is not recorded **[UNVERIFIED]**. Retrieval is `scripts/restore.sh borg-list` / `borg-extract`, which needs a `~/.ssh/id_borg` key whose escrow is unknown **[UNVERIFIED]**.

**b.** Equivalence is partial:
- **Confidentiality.** Borg encrypts client-side, and the passphrase stays on the nas with its escrow in Doppler (policy §12.1), so per §5.2.5 the key does not travel with the data.
- **Integrity.** It depends on whether the nas's key can delete archives (G-CP-13).
- **Availability.** There is **no freshness alert** (policy §13.1). Every other layer has one.
- **Shared role.** The host is also the alerting relay (ntfy) and the edge probe. A fault there takes out both the off-site copy and the only alert path that survives pve's death (`docs/recovery/cluster-down.md`).

**Evidence.** `scripts/restore.sh` lines 12–16, 41–42, 253–300; `docs/access-procedures.md` § Infrastructure, § Credential Locations; policy §12.1, §13.1.

**Gaps.**
- `G-CP-12` The off-site copy has no freshness alert. Risk: the only copy that survives a site loss can be stale for weeks, and the backup alerts — which run inside the cluster — never notice. Remedy: borgmatic's `after_backup`/`on_error` hooks push to ntfy. The external watchdog (or a timer on the backup server reading `borg list --last 1`) alerts when the newest archive is more than 36 h old. Target **2026-12-15**.
- `G-CP-14` The off-site target, coverage, retention, encryption mode and append-only status are recorded nowhere current. Risk: the plan relies on a copy whose contents nobody can state. Remedy: the owner confirms them (a Z0 read) and records the non-secret facts in the system description §2.2 and §4.2, retiring the stale lines in `restore.sh`. Target **2026-11-30**.

**Related.** Policy §5.2.5, §12, §13.1; CP-6(1), CP-6(3), CP-9, CP-9(8).

### CP-6(1) Separation from Primary Site

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | None |

> Identify an alternate storage site that is sufficiently separated from the primary storage site to reduce susceptibility to the same threats.

**Implementation.**

**Physical separation.** The backup server is in a different building, on a different network. The outage runbook relies on exactly that: the edge probe "survives the *building* dying" (`docs/recovery/cluster-down.md`, "What is in place now"). That covers the threats seen so far — a power cut at the primary site, a fire or theft there, and the nas or pve failing. The distance between the sites, and whether they share a power grid, regional weather (both may be on Long Island) or an ISP, are not recorded **[UNVERIFIED]**.

**Logical separation** is weaker, and for the threats this system actually faces it matters more:
- The same owner credential (`worker_key`, root) opens both sites.
- Both are on the same Tailscale tailnet.
- The nas pushes as `root@` on the backup server (`scripts/restore.sh` line 16).

Unless the nas's borg key is restricted to append-only `borg serve` **[UNVERIFIED]**, a compromise of the nas — ransomware, or a mistaken agent with `doas` — reaches the off-site archives too. The repository encryption does not help there: deletion needs no key.

**Evidence.** `docs/recovery/cluster-down.md`; `docs/access-procedures.md` § SSH Access; `scripts/restore.sh`.

**Gaps.**
- `G-CP-13` The off-site repository is not shown to be protected from deletion by the primary site. Risk: one compromise destroys the primary data and the off-site copy together. Remedy: a forced command in `authorized_keys` on the backup server (`borg serve --append-only --restrict-to-path /mnt/backups`), a non-root user for it, and periodic compaction run only from the backup server. Target **2027-01-31**.
- The geographic facts are part of `G-CP-14`.

**Related.** CP-6, CP-9(8); AC-6; policy §8.2 (backup repositories are Z0).

### CP-6(3) Accessibility

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | None |

> Identify potential accessibility problems to the alternate storage site in the event of an area-wide disruption or disaster and outline explicit mitigation actions.

**Implementation.** One accessibility problem has been identified and mitigated: losing the remote host to a bad boot. Because the host has "no remote hands", a GRUB one-shot fallback and `panic=30` let a failed kernel return to the known-good one without intervention (`docs/access-procedures.md` § GPU on travisbackupserver).

These problems have not been analysed, and have no mitigation:
1. **Bandwidth.** Uploads are throttled to 1 MB/s. Restore speed is bounded by the backup site's uplink, which is unknown **[UNVERIFIED]**. Restoring the 566 G `tank/appdata/personal` dataset (`docs/expansion-plan.md`) at, for example, 10 MB/s would take about 16 hours. At 1 MB/s it would take a week, which breaks the Tier 2 RTO of 72 h.
2. **Tailscale dependency.** Retrieval runs over Tailscale (inherited). The plan has no path for when the tailnet or its coordination service is unavailable.
3. **Keys.** If the nas is lost, the borg passphrase survives only in Doppler. Reaching Doppler needs the owner's account, whose MFA and recovery codes are **[UNVERIFIED]** (policy §9.4).
4. **Physical access.** Physical access to the backup site in an area-wide event is not documented.

**Evidence.** `docs/access-procedures.md`; `docs/RUNDOWN.md` § Backups; policy §12.1.

**Gaps.**
- `G-CP-15` There is no accessibility analysis. Risk: in a regional event the off-site copy exists but cannot be reached or read in time. Remedy: a section of the contingency plan (G-CP-03) that records the measured restore throughput from the backup site. It also lists the fallbacks: physically fetching the backup disk; an offline escrow of the borg passphrase and repository key independent of Doppler (G-CP-19); and a non-Tailscale path. Target **2027-02-28**.

**Related.** CP-6, CP-9(8), CP-10; policy §7.1, §12.2.5.
