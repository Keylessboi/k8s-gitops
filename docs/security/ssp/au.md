# AU — Audit and Accountability

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

---

| Disposition | Count |
|---|---|
| Partially implemented | 4 |
| **Total** | **4** |

### AU-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (Security Officer role, policy §3.1) |
| **Parameters** | au-1_prm_1 = System Owner and automated operators; au-01_odp.03 = system-level; au-01_odp.04 = System Owner; au-01_odp.05 = 12 months (policy App. A); au-01_odp.06 = SEV-1 or SEV-2 incident, new Tier 0/1 component, change in privileged access, major platform change (App. A); au-01_odp.07 = 12 months (App. A); au-01_odp.08 = the App. A events, plus any change to the monitoring stack's routing, retention or collectors |

> a. Develop, document, and disseminate to [Assignment: System Owner and automated operators]:
>   1. [Selection: system-level] audit and accountability policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the audit and accountability policy and the associated audit and accountability controls;
> b. Designate an [Assignment: System Owner] to manage the development, documentation, and dissemination of the audit and accountability policy and procedures; and
> c. Review and update the current audit and accountability:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident; a new Tier 0 or 1 component; a change in who has privileged access; a major platform change (an ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, and any change to the monitoring stack's alert routing, retention or log collectors].

**Implementation.**
**a.1.** There is no stand-alone audit policy. The audit rules sit in `docs/security/01-policy.md`:
- purpose and scope: §1–§2;
- roles: §3.1, with the single-person compensating rule "everything leaves a record" in §3.2.4;
- what is logged, what must never be logged (C4 values), log classification (C3) and the 30-day target for security events: §14;
- retention of logs, metrics and agent transcripts: §13.2;
- the accountability duties of agents (honest reporting, doctor-log entries with a confidence line): §10.5 and §16.3.5;
- audit-log retention and failure-alert recipients: Appendix A;
- review cadence: §19.

Management commitment is §20–§21. Coordination with other organizations is limited to the inherited providers (GitHub, Doppler, Tailscale), whose own logs are outside the owner's control. The policy is a **DRAFT** and is not in force until the owner merges it (§21). Agents receive the rules through `AGENTS.md`, which points to the policy, and through the "doctor log" section of `AGENTS.md`.
**a.2.** No dedicated audit procedure exists. The working procedures are:
- `scripts/doctor.sh` (one-command evidence collection, including Loki pointers);
- `docs/doctor-log.md` header (how an incident record is written);
- `docs/ntfy.md` § "Verifying the chain by hand" (alert path check);
- `docs/recovery/cluster-down.md` (reading host journals after an outage).

None of them says how to query Loki, how long anything is kept, or how to review security events.
**b.** The owner, as Security Officer.
**c.** The 12-month cycle is in the policy's document control. No review has taken place yet; the policy was written on 2026-10-01.

**Evidence.** `docs/security/01-policy.md` (document control, §3, §10.5, §13.2, §14, §19–§21, App. A); `AGENTS.md` § "The doctor log"; the procedure files above.

**Gaps.**
- `G-AU-01` The policy is unapproved (DRAFT, §21), and no audit procedure says how logs are queried, retained or reviewed. Risk: logging stays whatever each component's default is, and nobody knows where to look during an incident. Remedy: the owner merges HL-POL-001. Then add a "Logs and audit records" runbook to `docs/RUNDOWN.md` covering the records inventory in AU-2, the Loki query path (AU-7) and the review routine (AU-6). Target **2026-12-15**.

**Related.** Policy §3, §13.2, §14, §19; AU-2, AU-6, AU-7; CA-1.

### AU-2 Event Logging

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; `apps/monitoring` (Alloy, Loki, Prometheus); Traefik; Authentik; GitHub (inherited) |
| **Parameters** | au-02_odp.01 = the event types in the table below; au-2_prm_2 = the rows marked "selected", logged continuously; au-02_odp.04 = every 12 months, and whenever a Tier 0/1 component is added (policy App. A review events) |

> a. Identify the types of events that the system is capable of logging in support of the audit function: [Assignment: the event types listed in the table below];
> b. Coordinate the event logging function with other organizational entities requiring audit-related information to guide and inform the selection criteria for events to be logged;
> c. Specify the following event types for logging within the system: [Assignment: the event types marked "selected" in the table below, each logged continuously as it occurs];
> d. Provide a rationale for why the event types selected for logging are deemed to be adequate to support after-the-fact investigations of incidents; and
> e. Review and update the event types selected for logging [Assignment: every 12 months, and when a Tier 0 or Tier 1 component is added].

**Implementation.**
**a.** The event types below are drawn from the policy and the manifests. Policy §14.5 names the security-relevant ones.

| Event type | Source and record | Selected? | Status |
|---|---|---|---|
| Configuration change (who, what, when) | Git commits on `main`; ArgoCD sync history (`revisionHistoryLimit: 10`, `apps/argocd/root-applicationset.yaml:127`) | Yes | Logged |
| Container stdout/stderr, every pod | Alloy `loki.source.kubernetes` → Loki | Yes | Logged |
| Kubernetes Events (scheduling, probes, evictions, pulls) | Alloy `loki.source.kubernetes_events` → Loki, job `kubernetes-events` | Yes | Logged |
| Edge HTTP access (client IP, host, path, status) | Traefik `logs.access.enabled: true` (`apps/traefik/kustomization.yaml:117-121`) → stdout → Loki and CrowdSec | Yes | Logged |
| Edge blocking decisions | CrowdSec LAPI database | Yes | Logged (in CrowdSec only) |
| SSO logins, failures, admin actions | Authentik's event log, in its database | Yes (policy §14.5) | Logged by the product; retention **[UNVERIFIED]** |
| Kubernetes API requests (who did what to which object) | k3s API server audit log | Yes (policy §14.5) | **Not enabled** (HS-AGENT-13) |
| Host logins, `doas`/root use, daemons | journald on pve, nas, travisbackupserver | Yes | Local only, not shipped |
| Alert state changes | Prometheus `ALERTS` series; Alertmanager | Yes | Logged |
| Agent actions (commands run, files read) | Agent transcripts, `~/.claude/projects/*.jsonl` on the laptop (system description §4.1) | Yes | Claude Code only; other harnesses **[UNVERIFIED]** |
| CI results | GitHub Actions run logs | Yes | Inherited (GitHub) |
| Secret store access | Doppler activity log | Yes | Inherited (Doppler); not reviewed |
| Network flow records | none (kube-router REJECTs are not logged) | No | Not selected |

**b.** There is no other organization. The coordination that applies is with the inherited providers, whose logs the owner can read but not configure.
**c.** The "selected" rows, logged continuously as events occur.
**d.** The rationale comes from the doctor log, not theory. Kubernetes Events were added after three pg_dump failures on 2026-09-03 could not be explained because the Events had aged out of etcd (comment in `apps/monitoring/kustomization.yaml`, Alloy block). The weak point is the actor dimension. The API audit log is missing, and agents act with the owner's credentials (policy §9.2). So "which agent ran which `kubectl` write" can only be reconstructed from a transcript on the laptop, if one survives.
**e.** No review yet.

**Evidence.** `apps/monitoring/kustomization.yaml` (Alloy `configMap.content`); `apps/traefik/kustomization.yaml` § `logs`; `apps/crowdsec/kustomization.yaml` § `agent.acquisition`; policy §14.5; HS-AGENT-13.

**Gaps.**
- `G-AU-02` No Kubernetes API audit log (HS-AGENT-13 GAP; policy §14.5 "not enabled today"). Risk: a destructive or secret-reading API call by a person, agent or stolen kubeconfig leaves no record of who made it. Remedy: the owner (Z0: CT 200 configuration) enables the k3s API server audit log on CT 200. Use a policy that logs `Secret` access at `Metadata` level only (never `Request`/`RequestResponse`, which would write C4 values into the log), RBAC and `delete` verbs at `RequestResponse`, and drops read-only noise. Rotate with `audit-log-maxage=30`, and ship the file to Loki with Alloy. Target **2027-01-31**.
- `G-AU-03` Host journals (pve, nas, travisbackupserver) are not collected centrally. Neither are the outputs of the host daemons in `scripts/host/`. Risk: root logins, `doas` use and watchdog history disappear with the host, and nobody reviews them (cluster-down.md: the edge probe logged `edge: FAIL` "to a journal nobody reads"). Remedy: add a `loki.source.journal` component for the nas (Alloy already runs as a DaemonSet with `operator: Exists`), and ship pve and travisbackupserver journals with a host Alloy or `systemd-journal-upload`. Target **2027-02-28**.

**Related.** Policy §14; HS-AGENT-13, HS-OBS-01; AU-3, AU-12; AC-2 (G-AC-13 records the same missing audit log).

### AU-3 Content of Audit Records

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; the components named in AU-2 |
| **Parameters** | none |

> Ensure that audit records contain information that establishes the following:
>   a. What type of event occurred;
>   b. When the event occurred;
>   c. Where the event occurred;
>   d. Source of the event;
>   e. Outcome of the event; and
>   f. Identity of any individuals, subjects, or objects/entities associated with the event.

**Implementation.** Content varies by record:

- **Git commits** record a-e well: what changed (diff), when (author and commit dates), where (paths), the outcome (the commit exists). For f, all 319 commits on this branch carry the same author, `Travis Fiorito <travis@sandstorm.chat>` (`git log --format='%an <%ae>' | sort | uniq -c`), because agents commit with the owner's identity. 283 of the 319 carry a `Co-Authored-By: Claude …` trailer naming the model. The other 36 could be the owner's own work or an agent that omitted the trailer; nothing distinguishes them. argocd-image-updater commits as `argocd-image-updater` (`apps/image-updater/kustomization.yaml:66-67`), so its changes are attributable.
- **Loki streams** carry `namespace`, `pod`, `container`, `node` and `app` labels (Alloy `discovery.relabel "pods"`), and a timestamp per line. That covers a-d. Outcome and identity depend on each app's log format.
- **Traefik access logs** carry client address (preserved by `externalTrafficPolicy: Local`, `apps/traefik/kustomization.yaml:75-86`), host, path, status and time. For forward-auth routes the authenticated user is not in the access line; Authentik's event log holds it.
- **Kubernetes Events** carry the involved object, reason and count, but no human actor.
- **Kubernetes API calls** have no record at all (G-AU-02), so f cannot be met for `kubectl` writes. That includes break-glass writes, which policy §9.6.3 compensates for with a doctor-log entry written afterwards.

**Evidence.** `git log --format='%an|%ae|%(trailers:key=Co-Authored-By)'`; `apps/monitoring/kustomization.yaml` (Alloy relabel rules); `apps/traefik/kustomization.yaml`; `apps/image-updater/kustomization.yaml:66-67`.

**Gaps.**
- `G-AU-04` Agent and owner actions are indistinguishable at the identity level (f), in git and in the cluster. Risk: after an incident it cannot be shown whether a person or which agent made a change, and policy §3.2.4 ("everything leaves a record") is not met in substance. Remedy:
  1. A CI check that fails a commit on `main` without either a `Co-Authored-By` trailer or an owner-only marker trailer (e.g. `Human-Authored: yes`).
  2. A separate, named kubeconfig identity for agents (policy §9.2, POA&M item 1), so the API audit log in G-AU-02 can tell them apart.

  Target **2027-03-31**.

**Related.** Policy §3.2.4, §9.2, §9.6; HS-AGENT-13; AU-2, AU-3(1), AU-12; IA-2.

### AU-3(1) Additional Audit Information

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; automated operators (for their commit trailers) |
| **Parameters** | au-03.01_odp = for every change, the harness and model that authored it (`Co-Authored-By` trailer) and the incident or request it serves; for every API write, the client identity, user agent and source address; for every edge request, the forwarded client address |

> Generate audit records containing the following additional information: [Assignment: for every change, the harness and model that authored it (`Co-Authored-By` trailer) and the incident or request it serves; for every Kubernetes API write, the client identity, user agent and source address; for every edge request, the forwarded client address].

**Implementation.**
- **Authoring model.** The `Co-Authored-By` trailer is on 283 of 319 commits. Three model names appear (Claude Opus 5, Opus 5.5, Sonnet 5). No commit names opencode, Codex or Gemini, although `AGENTS.md` says those harnesses work here. Either they have not committed, or they commit without a trailer; the record cannot say which.
- **Reason for the change.** CI job "fix() updates the doctor's log" (`.github/workflows/validate.yaml:360-430`) requires a `fix()` commit that touches `apps/` to add a `docs/doctor-log.md` entry. That ties a fix to its incident record (HS-GIT-07, CHECKED). The PR template asks for symptom, root cause, fix, prevention and confidence (`.github/pull_request_template.md`).
- **Edge client address.** Present in every Traefik access line since `externalTrafficPolicy: Local` was set. Before that, every request was logged as `10.42.0.1` (comment at `apps/traefik/kustomization.yaml:75-84`).
- **API client identity and user agent.** Not generated (G-AU-02).

**Evidence.** `git log --format=%B | grep -i '^co-authored-by' | sort | uniq -c`; `.github/workflows/validate.yaml` job `fix() updates the doctor's log`; `.github/pull_request_template.md`.

**Gaps.** Covered by `G-AU-02` (API client fields) and `G-AU-04` (trailer not enforced, other harnesses unmarked). No separate gap.

**Related.** HS-GIT-07, HS-AGENT-08, HS-AGENT-13; AU-3; CM-3.

