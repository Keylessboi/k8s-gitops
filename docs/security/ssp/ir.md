# IR — Incident Response

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Incident response here is real and well exercised for **availability** incidents, and almost untested for **security** incidents. The doctor log (`docs/doctor-log.md`, 70 top-level entries from 2026-08-26 to 2026-09-28 in this tree; 81 through 2026-10-01 on `origin/main`) is a genuine incident record with a symptom index that `scripts/doctor.sh` greps automatically, and its "Prevention" discipline has turned repeated incidents into CI checks (`scripts/ci/check-invariants.py`; ADR-0007). Detection and notification have been rebuilt twice after real failures (the 2026-09-04 pve power-off went unnoticed for 3h37m), and now include an external watchdog on the nas, an edge probe on travisbackupserver, and two delivery paths (ntfy and email). The written plan is policy §16 (severity scale, phases, a credential-exposure playbook, an agent-misbehaviour playbook, and a 72-hour duty to tell affected service users). The gaps: the policy is still a DRAFT (§21); the §16 severity scale has never been applied to an entry; the log records degraded security controls (CrowdSec dead, 2026-09-11; DNS in plaintext to the ISP, 2026-09-14) but no confidentiality incident, while three access or credential exposures documented elsewhere in the repo never reached it (`docs/accounts.md`, `docs/RUNDOWN.md`, ADR-0012); none of the §16 playbooks has been exercised; service users have no documented way to report anything; and the incident record is public, with no provision for keeping an active security incident private. The family-wide decision is that a single person is the whole incident response capability, with AI agents as assistants that diagnose and record but never declare, approve or contain by themselves (policy §3.1, §10).

| Disposition | Count |
|---|---|
| Implemented | 1 |
| Partially implemented | 10 |
| Planned | 2 |
| Inherited | 0 |
| Alternative implementation | 0 |
| Not applicable | 0 |

### IR-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (Security Officer role, policy §3.1) |
| **Parameters** | ir-1_prm_1 = the System Owner and every automated operator (policy §3.1); ir-01_odp.03 = system-level; ir-01_odp.04 = the System Owner; ir-01_odp.05 = 12 months (policy App. A); ir-01_odp.06 = a SEV-1 or SEV-2 incident, a new Tier 0 or 1 component, a change in who has privileged access, a major platform change recorded in an ADR (App. A); ir-01_odp.07 = 12 months (App. A); ir-01_odp.08 = the ir-01_odp.06 events, plus any doctor-log entry whose prevention changes a runbook |

> a. Develop, document, and disseminate to [Assignment: the System Owner and every automated operator]:
>   1. [Selection: system-level] incident response policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the incident response policy and the associated incident response controls;
> b. Designate an [Assignment: the System Owner] to manage the development, documentation, and dissemination of the incident response policy and procedures; and
> c. Review and update the current incident response:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident; a new Tier 0 or 1 component; a change in who has privileged access; a major platform change (an ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, and any doctor-log entry whose prevention changes a runbook].

**Implementation.**

**a.1.** The incident response policy is `docs/security/01-policy.md` §16, read with the sections it depends on. Purpose and scope are §1 and §2 (§2.1 brings agent transcripts and the operator workstation into scope, which matters for credential exposure). Roles and responsibilities are §3.1: the owner holds every human role, and the Automated Operator role "never approves its own work". Management commitment is the approval clause (§21) and risk acceptance (§20). Coordination among entities is §16.6 (telling service users) and §3.2 (compensating controls for having one person). Compliance is §19. **(b)** Consistency with law is not addressed. The policy says nothing about statutory breach-notification duties for the friends' and family's data it holds (G-IR-02).

**a.2.** Procedures are runbooks, not a single document: `scripts/doctor.sh` and `docs/doctor-log.md` (diagnosis and prior art); `docs/recovery/cluster-down.md` (full outage); `docs/ntfy.md` (notification chain, including hand verification); `docs/access-procedures.md` "Emergency Bypass" and policy §9.6 (break-glass); `docs/RUNDOWN.md` "When Something Breaks" and "Security at the Edge" (CrowdSec lockout); `.github/pull_request_template.md` and `CONTRIBUTING.md` (the shape of a fix and its log entry). The two security playbooks, credential exposure (§16.5) and agent misbehaviour (§16.7), exist only inside the policy.

**Dissemination.** The repository is public, so the policy reaches every reader. Agents reach it through `AGENTS.md:78`, which points them at §5–6, §8 and §10, but **not** §16 (G-IR-03). `docs/security/README.md:27-34` gives agents the same short list, also without §16.

**b.** The System Owner holds the Security Officer role (§3.1).

**c.** The review cadence is in the document control table and §19. The policy is version 0.1, **DRAFT**, and "not in force until the owner approves it" (§21), so no review cycle has started yet (G-IR-01).

**Evidence.** `docs/security/01-policy.md` (document control, §3, §16, §19, §21); the runbooks listed above; `AGENTS.md:78`; `docs/security/README.md`.

**Gaps.**
- `G-IR-01`: The policy, including §16, is an unapproved draft. Risk: nothing in the IR family is formally in force, and agents are told only that they "SHOULD" follow it (§21). Remedy: the owner reviews and merges `01-policy.md`. Target 2026-11-01.
- `G-IR-02`: No analysis of legal breach-notification obligations toward service users. Risk: the 72-hour user notice in §16.6 may not match an obligation that applies, or a regulator that should be told might not be. Remedy: the owner records the applicable jurisdiction and any notification duty in §16.6, or records that none applies and why. Target 2027-01-31.
- `G-IR-03`: Agents are not pointed at §16. `AGENTS.md:78` and the README's agent brief name §5–6, §8 and §10 only; `AGENTS.md:41-42` says a printed value "has to be rotated" but not that it is a SEV-2, that the agent must stop and tell the owner, or that the transcript must be purged. Risk: an agent that prints a credential or finds one in a log may carry on, or "fix" it by editing the log, instead of handing the owner a SEV-2. Remedy: add §16.5 and §16.7 to the `AGENTS.md` "Where things are" row and to the README brief, with a one-line "if you expose a credential, stop and tell the owner". Target 2026-11-01.

**Related.** Policy §1–3, §16, §19, §21; IR-8; HS-AGENT-08; HS-OBS-05.

### IR-2 Incident Response Training

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | ir-02_odp.01 = for automated operators, before acting (at the start of every session, through `AGENTS.md`); for service users, at account creation (policy §9.3 Joiner); ir-02_odp.02 = 12 months (policy App. A, "the owner reads this policy and the doctor log at each review"); ir-02_odp.03 = 12 months; ir-02_odp.04 = a SEV-1 or SEV-2 incident, any change to policy §16, or a doctor-log entry whose prevention changes a runbook |

> a. Provide incident response training to system users consistent with assigned roles and responsibilities:
>   1. Within [Assignment: before acting, at the start of every session (automated operators); at account creation (service users)] of assuming an incident response role or responsibility or acquiring system access;
>   2. When required by system changes; and
>   3. [Assignment: every 12 months] thereafter; and
> b. Review and update incident response training content [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident; any change to policy §16; a doctor-log entry whose prevention changes a runbook].

**Implementation.** There are three populations with different roles, and the "training" each gets is different in kind.

**a. The owner** (every human IR role). Policy App. A defines training as the owner reading the policy and the doctor log at each review. The doctor log is in practice the training corpus: every entry is a worked incident with symptom, cause, fix and prevention, and the header (`docs/doctor-log.md:1-11`) teaches the confidence discipline. No record shows that a review-time reading has happened, and none can until the policy is approved (G-IR-01).

**a. Automated operators** (diagnose and record; never declare or contain alone). Their training is the context they load at session start: `AGENTS.md` "Where things are" (`doctor.sh` first, then grep the log), "The doctor log" section (`AGENTS.md:114-121`), and the long comment at the top of `scripts/doctor.sh:1-47`, which teaches why the script names no cause. This happens on every session, which satisfies a.1 and a.2 automatically when those files change. It does not cover §16: agents are never told what an exposure is or that they must stop (G-IR-03). It is also harness-specific: a harness that does not read `AGENTS.md` gets nothing.

**a. Service users** have one IR responsibility, "reporting suspected compromise" (policy §3.1), and receive nothing that tells them how or to whom (G-IR-04).

**b.** The training content is the documents themselves, so it changes whenever they do. There is no separate review.

**Evidence.** Policy §3.1 and App. A; `AGENTS.md:76-89, 114-121`; `scripts/doctor.sh:1-47`; `docs/doctor-log.md:1-11`; `docs/accounts.md` (joiner steps, no user guidance).

**Gaps.**
- `G-IR-04`: Service users get no guidance on recognising or reporting a suspected compromise. Risk: the person most likely to notice a stolen account (its owner) has no channel, so detection depends on the owner noticing it himself. Remedy: a short "if something looks wrong with your account" note (whom to message, what to include, "change your Vaultwarden master password first if you suspect the vault") handed out at account creation by `accounts.sandstorm.chat` or in the welcome message. Target 2027-02-28.

**Related.** IR-1 (G-IR-03), IR-6, IR-7; AT family; policy §3.1, §9.3; HS-AGENT-01, HS-AGENT-08.

### IR-3 Incident Response Testing

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; `homelab-external-watchdog` (nas) |
| **Parameters** | ir-03_odp.01 = daily for the out-of-band notification path (automated); every 6 months for the rest, run with the restore exercise (policy §19); ir-03_odp.02 = (1) the external watchdog's daily "alive" push; (2) an end-to-end test of every alert path (Alertmanager → relay → ntfy, Alertmanager → email, watchdog → ntfy, edge probe → ntfy); (3) a tabletop walk-through of one §16 playbook, alternating credential exposure (§16.5) and agent misbehaviour (§16.7) |

> Test the effectiveness of the incident response capability for the system [Assignment: daily for the out-of-band notification path; every 6 months for the rest, with the restore exercise] using the following tests: [Assignment: the watchdog's daily "alive" push; an end-to-end test of every alert path; a tabletop of one §16 playbook, alternating §16.5 and §16.7].

**Implementation.**

**Test (1), in place.** `scripts/host/homelab-external-watchdog:62, 208-215` publishes one "Homelab watchdog alive" message to ntfy every day at 09:00. It proves daily that the nas can reach ntfy on travisbackupserver over Tailscale without pve, which is the path that failed on 2026-09-04. It is a test that relies on a human noticing an *absence*: nothing alerts if the 09:00 message does not arrive.

**Test (2), procedure exists, never scheduled.** `docs/ntfy.md` "Verifying the chain by hand" gives the relay health check, an in-cluster end-to-end publish and the ntfy journal check. It covers only the relay path; there is no documented test of the email path or the edge probe. The real outage of 2026-09-04 served as an unplanned test of the watchdog (`docs/doctor-log.md` 2026-09-04, "Verified live against the real outage"), and the later 19-hour outage confirmed the 30-minute re-nag (`docs/recovery/cluster-down.md` "What the watchdogs did"). Neither is a repeatable test.

**Test (3), never done.** Neither §16 playbook has been walked through. Both depend on steps nobody has timed: rotating a Doppler value and confirming each consumer (HS-SEC-05 is GAP), finding and deleting a transcript, and checking for use of a credential when there is no API audit log (HS-AGENT-13).

**Single-operator angle.** A tabletop with one participant is a read-through against a scenario. It is still worth doing: it finds missing steps and missing tooling, which is the point here, not coordination between people. An agent can play the scenario and record the result, but the owner must take the decisions, since §16.7 covers agents themselves.

**Evidence.** `scripts/host/homelab-external-watchdog`; `docs/ntfy.md`; `docs/recovery/cluster-down.md`; policy §16, §19.

**Gaps.**
- `G-IR-05`: No end-to-end alert-path test on a schedule, and no test of the email path or the edge probe. Risk: a silently broken path is found during the next real incident, as `smart-email` was (empty receiver, found 2026-09-05, `docs/ntfy.md`). Remedy: a scripted test that fires one synthetic alert through each path, run with the 6-monthly restore exercise and recorded in the doctor log. Target 2027-01-31.
- `G-IR-06`: No §16 playbook has been exercised. Risk: the first run of the credential-exposure playbook will be during a real SEV-2, with unknown rotation time and unknown consumers. Remedy: a first tabletop of §16.5 on a non-critical credential (for example an indexer API key), timed, with a doctor-log entry. Target 2027-03-31.
- `G-IR-07`: The daily watchdog push is only checked by a human noticing it is missing. Risk: if travisbackupserver or ntfy is down, both out-of-band watchers are mute and nothing says so. Remedy: have Alertmanager or the edge probe alert (by email, which does not use ntfy) when the watchdog's daily message is absent, or have ntfy's own health be probed from the nas with an email fallback. Target 2027-02-28.

**Related.** IR-3(2), IR-4, CP-4; policy §16, §19; HS-OBS-01.

### IR-3(2) Coordination with Related Plans

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |
| **Responsible** | System Owner |
| **Parameters** | — |

> Coordinate incident response testing with organizational elements responsible for related plans.

**Implementation.** The related plans are the contingency plan (`docs/recovery/cluster-down.md`, the restore drill `apps/databases/restore-drill-cronjob.yaml`, and the 6-monthly restore exercise in policy §19) and the break-glass procedure (policy §9.6, `docs/access-procedures.md` "Emergency Bypass"). In a one-person organisation every "organizational element" is the owner, so coordination means scheduling: running IR tests on the same occasion as the contingency tests, so that a restore exercise also tests whether the outage was detected, notified and recorded. Today nothing does that. The monthly restore drill is automated and has its own alerts (`BackupRestoreDrillFailed`, `BackupRestoreDrillStale` in `apps/monitoring/backup-alerts.yaml`), but it is a CP test, not an IR test, and IR testing beyond the daily watchdog push does not exist (IR-3). The ODP in IR-3 assigns the alert-path test and the tabletop to the restore exercise, which is how this control will be met.

**Evidence.** Policy §9.6, §19; `docs/recovery/cluster-down.md`; `apps/monitoring/backup-alerts.yaml`.

**Gaps.**
- `G-IR-08`: IR testing is not tied to contingency testing. Risk: a restore exercise can pass while the detection and notification for the same outage fail unnoticed. Remedy: add an "incident" checklist (was it detected, by which watcher, how fast, was it logged with a severity) to the 6-monthly restore exercise, starting with the first one. Target 2027-03-31.

**Related.** IR-3, CP-2(1), CP-4; policy §19.

### IR-4 Incident Handling

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (declares, contains, approves); automated operators (diagnose and record, policy §10.1, HS-AGENT-08) |
| **Parameters** | — |

> a. Implement an incident handling capability for incidents that is consistent with the incident response plan and includes preparation, detection and analysis, containment, eradication, and recovery;
> b. Coordinate incident handling activities with contingency planning activities;
> c. Incorporate lessons learned from ongoing incident handling activities into incident response procedures, training, and testing, and implement the resulting changes accordingly; and
> d. Ensure the rigor, intensity, scope, and results of incident handling activities are comparable and predictable across the organization.

**Implementation.**

**a.** Policy §16.3 sets the phases. In practice they run like this:
- *Preparation:* `scripts/doctor.sh`, the doctor-log symptom index, the runbooks named in IR-1, and break-glass (§9.6).
- *Detection and analysis:* Alertmanager, the external watchdog and the edge probe (IR-6(1)), then `doctor.sh <app>` and a grep of the log. `doctor.sh` correlates and retrieves but deliberately names no cause (`scripts/doctor.sh:19-40`). That is a sound defence against confident wrong diagnoses, which the log records happening (2026-08-31 Ghost).
- *Containment, eradication and recovery:* for availability incidents this is well practised: git revert, pause sync, restore in tier order (§7.2.3, §11.4). For security incidents the tools exist but have never been used in anger: deactivate a user and revoke sessions (§9.3), `cscli decisions` (`docs/RUNDOWN.md` "Security at the Edge"), rotate in Doppler (§16.5). Eradication after a host compromise has no procedure: pve, the nas and travisbackupserver are configured by hand, and only some host units are in git (`scripts/host/`).
- *Evidence:* §16.4 says preserve logs, events and ArgoCD history. There is no Kubernetes API audit log (HS-AGENT-13), and Loki retention is UNVERIFIED (policy §13.2), so "who did what" after a credential leak cannot be answered from the system.

**Agent angle.** The usual responder is an agent acting with the owner's credentials (cluster-admin through `ssh pve`, system description §3). In an agent-misbehaviour incident the responder and the cause can be the same kind of actor, so §16.7 step 1 ("stop the session") is the owner's job. Break-glass writes must be written up within 72 hours (§9.6.3), but the log has no entry that names break-glass, although `ssh pve 'pct exec 200 -- kubectl'` is "the normal path today" (HS-AGENT-09).

**b.** Contingency is part of the same procedures: `docs/recovery/cluster-down.md` is both the outage runbook and the incident's write-up, and §16.3.3 uses the §7.2 restore order.

**c.** This is the strongest part. The log's Prevention field and the PR template's "Prefer a CHECK over a sentence" have turned repeated incidents into CI checks (`docs/doctor-log.md` "The traps that have bitten more than once"; `scripts/ci/check-invariants.py`), into ADRs (0007, 0012), and into HS requirements, each of which cites its incident as its source (`03-homelab-standard.md` §1). Lessons reach training through the log itself (IR-2). They do not yet reach testing (IR-3).

**d.** Rigour is made comparable by the fixed entry shape (symptom, root cause, fix, prevention, confidence: PR template; `AGENTS.md:114-121`), by CI `fix-needs-log`, and by HS-AGENT-07's data-plane evidence rule. Two things are not comparable: 33 of 70 entries in this tree carry no confidence line (all older ones), and no entry carries a §16.2 severity.

**Evidence.** Policy §7.2, §9.6, §16.3–16.4; `scripts/doctor.sh`; `docs/doctor-log.md`; `.github/pull_request_template.md`; `.github/workflows/validate.yaml` job `fix-needs-log`; `docs/recovery/cluster-down.md`; ADR-0007, ADR-0012.

**Gaps.**
- `G-IR-09`: No severity on any incident. Risk: the SEV-1/2 triggers for policy review (§19), user notice (§16.6) and the 72-hour break-glass write-up cannot fire if nobody classifies. Remedy: add a `Severity:` line to the PR template and the log header, and make `fix-needs-log` require it on new entries. Target 2026-12-31.
- `G-IR-10`: Break-glass use is not recorded. Risk: direct cluster-admin writes by agents leave no incident-level trace. Remedy: record each break-glass write in the log as §9.6.3 requires, until HS-AGENT-09 is closed by a scoped agent kubeconfig. Target 2026-12-31.
- `G-IR-11`: No eradication procedure for a compromised host, and no API audit log for investigation. Risk: after a pve or nas compromise the only option is a rebuild nobody has written down, and the scope of a leaked kubeconfig cannot be determined. Remedy: enable k3s API audit logging (HS-AGENT-13) and write a host-rebuild runbook for pve and the nas. Target 2027-06-30.

**Related.** IR-4(1), IR-5, IR-8, CP-2, CP-10, AU-2; policy §9.6, §16; HS-AGENT-07, -08, -09, -13; HS-GIT-07.

### IR-4(1) Automated Incident Handling Processes

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Implemented |
| **Responsible** | System Owner; the mechanisms listed |
| **Parameters** | ir-04.01_odp = Alertmanager routing to ntfy and email; the external watchdog (nas) and edge probe (travisbackupserver); `scripts/doctor.sh` with its doctor-log lookup; ArgoCD selfHeal and sync-failure notifications; CI `repo invariants` and `fix-needs-log` |

> Support the incident handling process using [Assignment: Alertmanager routing to ntfy and email; the external watchdog and edge probe; `scripts/doctor.sh` with its doctor-log lookup; ArgoCD selfHeal and sync-failure notifications; CI `repo invariants` and `fix-needs-log`].

**Implementation.** Each assigned mechanism automates one phase:
- *Detection and notification:* Alertmanager's `smart-email` receiver sends to the ntfy relay and to email (`apps/monitoring/kustomization.yaml:565-571`). ArgoCD posts `on-sync-failed` and `on-health-degraded` to ntfy (`docs/ntfy.md`).
- *Out-of-band notification:* `homelab-external-watchdog` on the nas probes pve and k3s every 60 s, alerts after 3 strikes, re-nags every 30 min and sends Wake-on-LAN while pve is down. `homelab-edge-probe` on travisbackupserver re-nags every 30 min (`scripts/host/`; `docs/recovery/cluster-down.md`).
- *Analysis:* `scripts/doctor.sh` collects nodes, pods, events, logs, firing alerts, edge probes and ArgoCD state in one screen, says loudly when it cannot collect a section, and greps the log for prior art by app name (`scripts/doctor.sh:342-356`).
- *Recovery:* ArgoCD selfHeal reverts drift (HS-GIT-01).
- *Lessons learned:* CI `repo invariants` encodes past incidents as checks. CI `fix-needs-log` refuses a `fix()` commit to `apps/` that does not add a log entry (HS-GIT-07).

These mechanisms are in place and cited. Two limits matter. All of them are about availability and configuration; none automates a security phase (see IR-5 and IR-6(1)). And the CI checks report but do not block, because `main` has no branch protection (HS-GIT-03).

**Evidence.** The files cited above; `.github/workflows/validate.yaml`; `scripts/ci/check-invariants.py`.

**Gaps.** None for the mechanisms assigned. Security-event automation is tracked as G-IR-13 (IR-6(1)).

**Related.** IR-4, IR-5, IR-6(1), SI-4; HS-OBS-01, HS-OBS-05, HS-GIT-03, HS-GIT-07.

