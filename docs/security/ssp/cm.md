# CM — Configuration Management

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Configuration management is this system's strongest family on paper and its
most uneven one in practice. Everything under `apps/*` is a git-declared
baseline that ArgoCD applies continuously with `prune` and `selfHeal`
(`apps/argocd/root-applicationset.yaml`), so cluster drift is normally reverted
within minutes and every change has a commit. Three things undercut it. First,
the controls that would make the baseline *authoritative* are missing: `main`
has no branch protection, `validate` is not a required check, and on `main`
Renovate now merges its own PRs, platform apps included (ADR-0013), which
contradicts the change types in policy §11 and the zones in §8. Second, a large
part of the system is outside git altogether: the host configuration of pve,
the nas, CT 200 and travisbackupserver, ArgoCD's own installation, and the
waivered Authentik objects (W-01..W-03). Third, drift detection has failed
silently three times (the ServerSideDiff class), and nothing automated catches
it. With one person holding every role, change-board controls (CM-3g, CM-3(4))
are met by the owner plus the rule that agents never approve their own Z0/Z1
work (policy §3.2). Travel controls (CM-2(7)) are tailored out.

| Disposition | Count |
|---|---|
| Implemented | 3 |
| Partially implemented | 17 |
| Planned | 1 |
| Alternative implementation | 2 |
| Not applicable | 1 |
| **Total** | **24** |
### Reading this family: which tree is "the system"

This section was written in the `homelab-standard` branch (worktree
`agent-guardrails`), whose branch point is commit `13d65cf` (2026-09-27).
`origin/main`, which ArgoCD deploys, is **44 commits ahead** of that point
(head `6152ddc`, 2026-10-02, a Renovate automerge). Three differences change CM
answers and are called out per control:

1. **PR #21 is not on `main`.** `components/protect-state`,
   `preserveResourcesOnDeletion: true`, `scripts/ci/check-protected-state.py`,
   ADR-0012 and the gitleaks job exist only in this branch
   (`git diff HEAD origin/main --stat` shows them deleted on `main`).
   `03-homelab-standard.md` §2 says its counts are "after PR #21 merges";
   this SSP treats those mechanisms as **not yet in production**.
2. **ADR-0013 is on `main` and not here.** Commit `dcc8703` (PR #24) made
   Renovate the only updater, enabled majors, and set it to merge its own
   PRs overnight once `validate` is green. It retired Image Updater as an
   updater (the `ImageUpdater` CR is removed; the controller, its namespace
   and its git deploy key remain, per ADR-0013 "Decommissioning … is a
   follow-up"). This contradicts policy §8.3.3, §11.1, §11.5.3 and §15.3,
   which were written after it (see CM-3).
3. **`validate` may be green on `main`.** Commit `bb5c07d` (2026-09-30, on
   `main` only) says it "un-reds the validate workflow" by baselining the
   seven wait-init findings. `03-homelab-standard.md` (HS-GIT-03, HS-WL-06)
   still says `main` is red. In this branch the check still fails. Current
   status is **[UNVERIFIED]**; it does not change any disposition, because a
   green check that nothing requires is still not a gate.

Where this file says "the repository" without qualification it means this
worktree; "`main`" means `origin/main` at `6152ddc`.

### CM-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (in the Security Officer role, policy §3.1) |
| **Parameters** | cm-1_prm_1 = the System Owner, the automated operators (through `AGENTS.md`), and service users for the parts that affect them; cm-01_odp.03 = system-level; cm-01_odp.04 = System Owner (Security Officer role); cm-01_odp.05 = 12 months (policy App. A); cm-01_odp.06 = SEV-1/SEV-2 incident, new Tier 0/1 component, change in privileged access, major platform change recorded in an ADR (App. A); cm-01_odp.07 = 12 months; cm-01_odp.08 = same events as odp.06 |

> a. Develop, document, and disseminate to [Assignment: the System Owner, the automated operators (through `AGENTS.md`), and service users for the parts that affect them]:
>   1. [Selection: system-level] configuration management policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the configuration management policy and the associated configuration management controls;
> b. Designate an [Assignment: System Owner, in the Security Officer role] to manage the development, documentation, and dissemination of the configuration management policy and procedures; and
> c. Review and update the current configuration management:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident, a new Tier 0 or 1 component, a change in who has privileged access, or a major platform change recorded in an ADR]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events].

**Implementation.**
**a.1** The CM policy is not a separate document; it is the change-related part of `docs/security/01-policy.md` (HL-POL-001): purpose and scope §1–2, roles §3 (including the one-person compensating controls in §3.2), protection zones §8, the agent rules of behaviour §10, change management §11, supply chain §15.3, waivers §18, compliance and review §19. Management commitment is the owner's approval (§21). Consistency with external requirements is handled by citing sources per requirement in `03-homelab-standard.md` §13. Dissemination: the policy is in the public repository; agents receive it through `AGENTS.md`, which points to §8 and §10. **The policy is a DRAFT** and "not in force until the owner approves it" (document control table; §21).
**a.2** Procedures exist as runbooks, not as one CM procedure: `AGENTS.md` (push = deploy, dry-run, digest rule), `scripts/README.md` and `scripts/bootstrap-argocd.sh` (the hand-applied `apps/argocd/` path), `docs/access-procedures.md` (break-glass and restore), `docs/recovery/cluster-down.md`, `.github/pull_request_template.md`, the `docs/doctor-log.md` header, and `scripts/host/ganesha/README.md` (the only written host-configuration procedure). Some are wrong: `access-procedures.md` "Maintenance Windows" is template text (system description §7.4) and "Not Published" says ArgoCD has no Ingress (it has one, see CM-7).
**b.** The System Owner, as Security Officer (§3.1).
**c.** §19 sets a 12-month policy review and event triggers; §11.5.5 requires SSP and standard updates in the same PR as a policy change. No review has yet happened (the policy dates from 2026-10-01).

**Evidence.** `docs/security/01-policy.md` (document control, §3, §8, §10, §11, §19, §21); `AGENTS.md`; `scripts/README.md`; `docs/access-procedures.md` lines 181–212.

**Gaps.**
- `G-CM-01` The policy is unapproved, so no CM rule is formally in force. Risk: agents and the owner may treat the zones and change types as advisory. Remedy: owner reviews and merges HL-POL-001 to `main` (§21). Target 2026-11-15.
- `G-CM-02` No single change procedure; existing runbooks contain wrong or template text. Risk: a reader follows a stale step (e.g., a Sunday window or an `#ops-alerts` channel that does not exist). Remedy: write `docs/change-procedure.md` covering Standard/Normal/Emergency paths, the `apps/argocd/` apply step and host changes; delete the template text. Target 2027-01-31.

**Related.** Policy §3, §8, §11, §19, §21; HS-GIT-*, HS-AGENT-*; CM-3, CM-9.

### CM-2 Baseline Configuration

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; ArgoCD (`apps/argocd/root-applicationset.yaml`); GitHub (`Keylessboi/k8s-gitops`, inherited availability) |
| **Parameters** | cm-02_odp.01 = with every change (version-controlled), full review every 12 months (policy App. A); cm-02_odp.02 = a SEV-1/SEV-2 incident, a new Tier 0/1 component, an accepted ADR, or a waiver reaching its review date |

> a. Develop, document, and maintain under configuration control, a current baseline configuration of the system; and
> b. Review and update the baseline configuration of the system:
>   1. [Assignment: with every change, as it is version-controlled; full review every 12 months];
>   2. When required due to [Assignment: a SEV-1 or SEV-2 incident, a new Tier 0 or Tier 1 component, an accepted ADR, or a waiver reaching its review date]; and
>   3. When system components are installed or upgraded.

**Implementation.**
**a.** The baseline for the Kubernetes workloads is the `main` branch of `github.com/Keylessboi/k8s-gitops`: one directory per Application under `apps/*`, each a kustomization (CI enforces that every directory has one, `validate.yaml` "Every apps/* directory must be a kustomization"). The root ApplicationSet generates one Application per directory and syncs it with `prune: true, selfHeal: true` (lines 85–89), so the declared baseline is also the running one (HS-GIT-01, ENFORCED). Helm charts are pinned by version in each `kustomization.yaml`; container images are pinned by tag and only 16 of 85 by digest (HS-WL-01), so a re-pushed tag changes the running image without a commit.

What is **not** under configuration control:
- `apps/argocd/` is in git but applied by hand (W-03, HS-GIT-08). Its live copy drifted both ways on 2026-09-27 (doctor-log, "a git-tracked manifest that git does not deliver"). ArgoCD's own install manifests (v2.12.3) are not in git at all; `scripts/bootstrap-argocd.sh` applies only five of the seven files in `apps/argocd/` (it omits `argocd-notifications-cm.yaml` and `networkpolicy.yaml`).
- Authentik applications, providers, flows and groups (W-01) and the stray `metallb` namespace (W-02).
- Host configuration of pve, CT 200 (LXC config, nfs-ganesha, k3s flags), the nas (ZFS, NFS exports, MinIO, sanoid, borgmatic, Wings) and travisbackupserver. `scripts/host/` holds copies of some systemd units and the ganesha config, installed by hand (`scripts/host/ganesha/README.md`); nothing compares them with the hosts.

**b.1–b.3** Every change to `apps/*` updates the baseline by construction. Component upgrades arrive as Renovate PRs (on `main`, merged automatically, see CM-3). No 12-month full review has happened yet; out-of-git items have no review trigger beyond waiver dates.

**Evidence.** `apps/argocd/root-applicationset.yaml`; `.github/workflows/validate.yaml`; `scripts/bootstrap-argocd.sh` lines 18–22; `03-homelab-standard.md` §3 and §12; doctor-log 2026-09-27.

**Gaps.**
- `G-CM-03` Host configuration is not baselined. Risk: a host rebuild or silent drift (the 2026-09-08 ganesha fix that "never once ran") cannot be detected or reproduced. Remedy: commit a non-secret host baseline (`hosts/<name>/`: `pct config 200`, exports, sanoid and sshd config, unit files) plus a read-only diff script run monthly. Target 2027-03-31.
- `G-CM-04` ArgoCD's installation and two bootstrap files are outside any applied baseline. Risk: a restore re-creates a different ArgoCD, or notifications silently stay stale. Remedy: vendor the pinned install manifest into `apps/argocd/kustomization.yaml` and have the bootstrap script run `kubectl apply -k apps/argocd`. Target 2026-12-31.

**Related.** HS-GIT-01, -02, -08; W-01..W-03; policy §8.2, §11; CM-2(2), CM-6, CM-8.

### CM-2(2) Automation Support for Accuracy and Currency

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | ArgoCD; GitHub Actions (`validate`); Renovate (GitHub App); System Owner |
| **Parameters** | cm-02.02_odp = ArgoCD automated sync with prune and selfHeal; the `validate` workflow; Renovate dependency updates |

> Maintain the currency, completeness, accuracy, and availability of the baseline configuration of the system using [Assignment: ArgoCD automated sync with prune and selfHeal, the `validate` GitHub Actions workflow, and Renovate dependency updates].

**Implementation.**
*Accuracy* (live matches git): ArgoCD polls `main` and re-applies any drift (`selfHeal: true`); manual `kubectl edit`/`scale` is reverted (doctor-log 2026-09-10). Drift detection itself is unreliable. For apps hit by the ServerSideDiff bug, ArgoCD reports `Synced/Healthy` while applying nothing; this happened silently on 2026-09-11 (prowlarr) and 2026-09-30 (lidarr, `main` doctor-log), each time fixed by adding the app to a hand-maintained opt-out list and forcing a sync with `kubectl patch` (a break-glass write). Nine apps in this branch, ten on `main`, therefore use client-side diff, and nothing makes a newly affected app join the list. `apps/argocd/` is not reconciled at all. ArgoCD notifications fire only on sync failure and Degraded health (`argocd-notifications-cm.yaml` lines 12–17), not on "applied revision is behind git".
*Currency*: Renovate. In this branch it sees only Helm charts and majors are disabled (`renovate.json`); on `main` (ADR-0013) it scans every `apps/**/*.yaml` and automerges after a 3-day release age. Image Updater is retired on `main`.
*Completeness*: CI renders every app with the exact kustomize/Helm versions ArgoCD uses (HS-GIT-06) and validates against the k8s 1.31.5 schema (HS-GIT-05).
*Availability*: GitHub hosts the repository (inherited); every clone, including the laptop and ArgoCD's repo-server cache, is a full copy.
No automation covers hosts or Authentik.

**Evidence.** `apps/argocd/root-applicationset.yaml` lines 71, 85–89; `apps/argocd/argocd-notifications-cm.yaml`; doctor-log 2026-09-11 and (on `main`) 2026-09-30 "ArgoCD said Synced a third time"; `renovate.json` (both branches); ADR-0013.

**Gaps.**
- `G-CM-05` No automated check that each app applied the last commit touching its path. Risk: a pushed change, including a security fix, is silently not live for days. Remedy: implement the per-path audit from the `main` doctor-log 2026-09-30 entry as a CronJob that alerts via ntfy; also diff the live `apps/argocd/` objects against git. Target 2026-12-31.

**Related.** HS-GIT-01, -05, -06; HS-AGENT-07; ADR-0007, ADR-0013; CM-2, CM-3(2), CM-8(3).

### CM-2(3) Retention of Previous Configurations

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; GitHub (inherited hosting of history); ArgoCD |
| **Parameters** | cm-02.03_odp = every previous version in git history (no limit), plus the last 10 sync records per Application in ArgoCD (`revisionHistoryLimit: 10`) |

> Retain [Assignment: every previous version held in git history, without limit, plus the last 10 sync records per ArgoCD Application] of previous versions of baseline configurations of the system to support rollback.

**Implementation.**
For everything in git, every previous baseline is retained: each commit on `main` is a complete prior configuration, and rollback is `git revert` of the bad commit through the normal path (policy §11.4, HS-AGENT-10). ArgoCD additionally keeps the last ten sync operations per Application (`root-applicationset.yaml` line 127), which identifies the revision that was live at a given time. Copies of the history exist on GitHub, on the laptop's clone and in each worktree.

Retention is not protected. Policy §10.2.6 forbids force-pushing and rebasing `main`, and HS-AGENT-05 requires owner approval for a history rewrite, but the only mechanism is Claude Code's auto-mode soft-deny; there is no branch protection or ruleset on `main` (HS-GIT-03/-04 GAP), so the owner's credentials, which every agent harness uses, can rewrite or delete it.

Rollback does not cover what is outside version control: hand-applied `apps/argocd/` objects (W-03), Authentik objects (W-01), host configuration, and anything a revert cannot undo (data migrations, rotated credentials; §11.4). Major-version updates on `main` are often one-way: ADR-0013 holds back Nextcloud, Immich, Postgres, Mongo, Redis and MinIO majors for exactly that reason, and the `main` history shows a stepped Mongo 7.0 → 8.0 upgrade (`7037ebc`). For those, the previous *configuration* is retained but the previous *state* is only recoverable from backup (CP family).

**Evidence.** `git log origin/main`; `apps/argocd/root-applicationset.yaml` line 127; policy §10.2.6, §11.4; `03-homelab-standard.md` HS-GIT-03, HS-AGENT-05; ADR-0013 (on `main`).

**Gaps.**
- `G-CM-06` `main` can be force-pushed or deleted. Risk: the retained baseline, and the record of who changed what, can be rewritten by any harness holding the owner's GitHub credential. Remedy: owner adds a GitHub ruleset on `main` blocking force-push and deletion (Z0, owner action). Target 2026-11-30.
- Out-of-git configuration has no version history: see `G-CM-03` and `G-CM-04`.

**Related.** HS-AGENT-05, -10; HS-GIT-03, -04; policy §10.2.6, §11.4; CM-2, CM-3; CP-9, CP-10.

### CM-2(7) Configure Systems and Components for High-risk Areas

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |
| **Responsible** | System Owner |
| **Parameters** | cm-02.07_odp.01 = not assigned; cm-02.07_odp.02 = not assigned; cm-02.07_odp.03 = not assigned |

> (a) Issue [Assignment: not assigned] with [Assignment: not assigned] to individuals traveling to locations that the organization deems to be of significant risk; and
> (b) Apply the following controls to the systems or components when the individuals return from travel: [Assignment: not assigned].

**Implementation.**
Tailored out. The control concerns an organisation issuing loaner equipment to staff who travel to locations it has designated as high-risk. This system has no staff, issues no equipment, and the owner has designated no high-risk locations. Service users reach the apps from their own devices, which are out of scope (policy §2.2).

The intent still touches one component: the operator workstation (system description §2.1) travels with its holder and carries the SSH key `worker_key`, a cluster-admin kubeconfig, Doppler and GitHub logins, and agent transcripts that may be C4 (§6 of the system description). The relevant risk is loss, theft or inspection of that laptop, wherever it happens. It is covered by the key rotation rule on laptop loss (policy §12.1, `worker_key`), the credential-exposure playbook (§16.5), and the freeze option for travel (§11.5.4); the controls that would address it directly belong to AC-19 and SC-28 (disk encryption of the laptop is **[UNVERIFIED]**, system description §4.1).

**Evidence.** System description §2.1, §4.1; policy §2.2, §11.5.4, §12.1, §16.5.

**Gaps.** None for this control. The laptop risk is tracked under AC-19/SC-28.

**Related.** AC-19; SC-28; IR-4; policy §12.1, §16.5.

### CM-3 Configuration Change Control

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (sole change authority); automated operators (authors only); Renovate; ArgoCD; GitHub Actions |
| **Parameters** | cm-03_odp.01 = for the life of the repository (git history and GitHub PR records are not pruned); cm-03_odp.02 = the System Owner, acting alone as the change authority; cm-03_odp.03 = both; cm-03_odp.04 = weekly (Renovate review, policy §17); cm-03_odp.05 = whenever a Normal or Emergency change is proposed |

> a. Determine and document the types of changes to the system that are configuration-controlled;
> b. Review proposed configuration-controlled changes to the system and approve or disapprove such changes with explicit consideration for security and privacy impact analyses;
> c. Document configuration change decisions associated with the system;
> d. Implement approved configuration-controlled changes to the system;
> e. Retain records of configuration-controlled changes to the system for [Assignment: the life of the repository];
> f. Monitor and review activities associated with configuration-controlled changes to the system; and
> g. Coordinate and provide oversight for configuration change control activities through [Assignment: the System Owner, acting alone as the change authority] that convenes [Selection: [Assignment: weekly]; when [Assignment: a Normal or Emergency change is proposed]].

**Implementation.**
**a.** Policy §11.1 defines Standard, Normal, Emergency and Prohibited changes; §8 assigns every path or asset to a zone (Z0–Z3), and §8.3 resolves edge cases (multi-zone, renames, generated changes, reverts). Every change to `apps/*`, `components/`, `.github/`, `scripts/ci/` and `docs/security/` is configuration-controlled.
**b.** Normal (Z1) changes go through a PR the owner merges, with the §11.2 content (intent, zone/class, risk, validation, rollback, manual steps). On `main` the 2026-09-30 catch-up landed one app per PR (#25–#58). Enforcement is weak: there is no branch protection, so any author can push to `main`; the rule that agents do not push or merge Z1 work is enforced only by Claude Code's auto-mode (HS-AGENT-04, -06). **Renovate on `main` merges its own PRs**, including platform apps (Traefik, Authentik, cert-manager, CNPG) and most majors (ADR-0013; `renovate.json` `"automerge": true`), with no owner review. Policy §8.3.3 says a Renovate PR against `apps/traefik` "is Z1 and waits for the owner"; §11.1 makes "any Renovate major" a Normal change; §15.3 says Renovate MUST NOT auto-apply majors. The policy and `main` disagree.
**c.** Commits, PR descriptions, ADRs for design decisions, doctor-log entries for fixes (CI-checked for `fix()` commits, HS-GIT-07); agent commits carry a `Co-Authored-By` trailer (HS-AGENT-13).
**d.** ArgoCD applies `main`; `apps/argocd/` and host changes are applied by hand.
**e.** Git and GitHub PRs, indefinitely; subject to `G-CM-06`.
**f.** `validate` runs on every push and PR; ArgoCD notifies sync failures and Degraded health via ntfy. Nobody reviews merged Renovate changes after the fact; the `main` doctor-log 2026-09-30 suggests `gh pr list --label renovate --state merged` weekly, as a prevention, not a schedule.
**g.** One person is the board (policy §3.2). Emergency changes follow break-glass (§9.6) with a doctor-log entry within 72 h.

**Evidence.** Policy §3.2, §8, §11, §15.3, §17; ADR-0013 and `renovate.json` on `main`; `git log origin/main` (#14–#59); `.github/workflows/validate.yaml`; `03-homelab-standard.md` HS-GIT-03/-04/-07, HS-AGENT-04/-06/-13, HS-SUP-01.

**Gaps.**
- `G-CM-07` Policy and `main` disagree on Renovate. Risk: platform and major updates reach production unreviewed while the SSP claims they are Normal changes. Remedy: owner decides in one PR either to amend §8.3.3/§11.1/§15.3 and HS-SUP-01, or to add Renovate `packageRules` setting `automerge: false` for Z1 paths (`matchFileNames` on the §8.2 Z1 list). Target 2026-11-30.
- `G-CM-08` Nothing enforces the zone rules outside Claude Code. Risk: another harness, or a mistaken session, pushes a Z1 change straight to production. Remedy: ruleset requiring a PR and the `validate` check on `main`, plus a CI zone check that fails when a PR touches Z1 paths without an owner-applied label (HS-AGENT-06). Target 2027-02-28.

**Related.** Policy §3.2, §8, §9.6, §11, §15.3; HS-GIT-03, -04, -07; HS-AGENT-04, -06, -13; HS-SUP-01; ADR-0013; CM-3(2), CM-4, CM-5.

### CM-3(2) Testing, Validation, and Documentation of Changes

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | Change author (owner or agent); GitHub Actions (`validate`) |
| **Parameters** | None |

> Test, validate, and document changes to the system before finalizing the implementation of the changes.

**Implementation.**
There is no staging environment: a push to `main` is live in about three minutes (system description §6.1), so "before finalizing" means before the push. Pre-push validation is:
- `validate` (`.github/workflows/validate.yaml`): YAML parse; `kustomize build --enable-helm` of every app with the versions ArgoCD uses; yamllint; repo invariants (wait-init, NetworkPolicy pairing, and on `main` readiness-implies-liveness, `bb5c07d`); kubeconform `-strict` against k8s 1.31.5; the `fix()`-needs-doctor-log check; and, in this branch only, the protected-state check and gitleaks. It runs on push and PR but is **not required** (HS-GIT-03), and on a push to `main` it runs in parallel with ArgoCD, so it reports after the deploy rather than preventing it.
- A server-side dry-run (`kubectl apply --dry-run=server --validate=strict`) is a SHOULD in `AGENTS.md` and HS-GIT-05; nothing records whether it ran.
- After the push, HS-AGENT-07 requires data-plane evidence; the PR template's "Verification" heading asks for it. Both are process only.

ADR-0013's own consequences state that `validate` "only proves the manifests render, not that the app starts", and that a bad release now lands on its own. Kubeconform uses `-ignore-missing-schemas`, so CRD-based objects (ArgoCD, CNPG, Traefik, Doppler, Prometheus operator) are not schema-checked.

Documentation of the change is the commit or PR, plus a doctor-log entry for fixes.

**Evidence.** `.github/workflows/validate.yaml` (jobs 1–7); `AGENTS.md`; `.github/pull_request_template.md`; ADR-0013 "Consequences"; `03-homelab-standard.md` HS-GIT-03, HS-GIT-05, HS-AGENT-07.

**Gaps.**
- CI is not a gate: see `G-CM-08`.
- `G-CM-09` No runtime test before or immediately after a change. Risk: an automerged update that renders cleanly but fails at startup stays broken until someone notices. Remedy: a post-sync check per app (applied revision matches git, readiness reached, and the app's edge probe passes within 15 minutes), alerting through ntfy and naming the commit to revert. Target 2027-03-31.

**Related.** HS-GIT-03, -05, -06, -09; HS-AGENT-07; HS-WL-06; ADR-0007, ADR-0013; CM-3, CM-4(2).

### CM-3(4) Security and Privacy Representatives

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |
| **Responsible** | System Owner (Security Officer and Data Owner roles) |
| **Parameters** | cm-3.4_prm_1 = the System Owner in the Security Officer role, also representing service users' privacy as a Data Owner (policy §3.1); cm-03.04_odp.03 = the System Owner acting alone as change authority (CM-3 g) |

> Require [Assignment: the System Owner in the Security Officer role, who also represents service users' privacy as Data Owner] to be members of the [Assignment: the System Owner acting alone as the change authority].

**Implementation.**
The change authority is one person, who also holds the Security Officer role and is Data Owner for system data (policy §3.1). Security and privacy representation is therefore present in every change decision by construction, but not independently. The intent, that security and privacy impact is weighed by someone whose job it is, is met instead by:
1. The §11.2 content every Normal change must carry: zone, data classes affected, risk and blast radius, and what a rollback will not undo.
2. The compensating controls of §3.2: agents propose and never approve their own Z0/Z1 work; machine checks the author cannot skip (once HS-GIT-03 is in force); two-step destruction of state; attributed records.
3. Classification-driven rules that apply whatever the reviewer remembers: C3/C4 handling (§6) and the requirement that a new component get a tier and class before its first deploy (§7.2.2).

Service users, as Data Owners of their own content, have no voice in change decisions; §16.6 tells them after an incident, not before a change. This is accepted for a friends-and-family service.

The alternative is weakened today wherever changes bypass the owner: Renovate's automerge on `main` takes the security representative out of platform updates (`G-CM-07`), and point 2 is not in force until branch protection exists (`G-CM-08`).

**Evidence.** Policy §3.1, §3.2, §6, §7.2, §11.2, §16.6.

**Gaps.** None beyond `G-CM-07` and `G-CM-08`.

**Related.** CM-3, CM-4; policy §3.

### CM-4 Impact Analyses

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Impact analysis is done by rendering and dry-running a change (`kubectl kustomize … | kubectl apply --dry-run=server`, AGENTS.md) and by CI. There is no security impact analysis step and no runtime test (`G-CM-09`).

**Evidence.** `AGENTS.md`; `.github/workflows/validate.yaml`

**Gaps.** Covered by `G-CM-09`.

**Related.** CM-3, SA-11.

### CM-4(2) Verification of Controls

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** After a change, agents must show data-plane evidence that it works (HS-AGENT-07, process only). Security functions are not re-verified after a change (e.g. that forward-auth still applies to a route).

**Evidence.** HS-AGENT-07

**Gaps.**
- `G-CM-10` No check that security functions still work after a change. Risk: a refactor drops a forward-auth middleware or NetworkPolicy and nobody notices. Remedy: a CI check that every published Ingress has the Authentik middleware unless listed as an exception (blog, Kiwix, remux API). Target **2027-01-31**.

**Related.** CM-4, SC-7.

### CM-5 Access Restrictions for Change

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Changes to the cluster are restricted to git → ArgoCD (HS-GIT-01, ENFORCED by selfHeal for managed objects). Who can push is restricted to the owner's GitHub account, but agents push with it and `main` is unprotected (`G-AC-09`). Direct kubectl remains possible for anyone with the admin path (`G-AC-10`).

**Evidence.** HS-GIT-01; `apps/argocd/root-applicationset.yaml`

**Gaps.** Covered by `G-AC-09` and `G-AC-10`.

**Related.** AC-3, AC-6.

### CM-6 Configuration Settings

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Configuration settings are the manifests in `apps/`, enforced by ArgoCD selfHeal. Workload hardening settings are measured in `03` and mostly GAP: memory limits 76/85, readiness probes 29/39, no-escalation 32/85, non-root 15/56 pods (HS-WL-03, -04, -10). Host settings are not in git (`G-CM-03`). No CIS benchmark has been run (HS-HOST-01/02).

**Evidence.** `03-homelab-standard.md` HS-WL-*, HS-HOST-*

**Gaps.**
- `G-CM-11` Workload security settings fall short of the standard (privilege escalation, non-root, limits) and no CIS scan exists. Risk: a compromised container has more room than it needs. Remedy: a CI report of HS-WL-03/04/10 per container, fix by tier (Tier 1 first), then a kube-bench run with the k3s profile. Target **2027-06-30**.

**Related.** CM-7, HS-WL-*, HS-HOST-01.

### CM-7 Least Functionality

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Only declared Ingress hosts are published; admin UIs are not (`00-system-description.md` §3); `HS-PLAT-01` forbids adding new operators or meshes without cause. Exceptions to least functionality: ConvertX (arbitrary file conversion, root, no forward-auth, `G-SI-07`), privileged namespaces without recorded reasons (W-04).

**Evidence.** `00-system-description.md` §3; W-04

**Gaps.** Covered by `G-SI-07`, `G-SC-02`; W-04 reasons by the 2026-11-01 waiver date.

**Related.** SC-7, CM-7(1).

### CM-7(1) Periodic Review

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Reviews of functions happen when an app is removed (e.g. Invidious decommissioned 2026-09-05), not on a schedule. Dead references remain (`G-AC-08`).

**Evidence.** `docs/doctor-log.md`

**Gaps.** Covered by `G-AC-08`.

**Related.** CM-7.

### CM-7(2) Prevent Program Execution

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Workloads run only what their images and manifests declare; ArgoCD reverts unmanaged changes to managed objects. Nothing prevents `kubectl run` of an arbitrary image via the admin path.

**Evidence.** HS-GIT-01

**Gaps.** Covered by `G-AC-10`.

**Related.** CM-7(5).

### CM-7(5) Authorized Software — Allow-by-exception

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** There is no allow-list of registries or images (no admission policy). Digest pinning, which would fix which image runs, covers 16 of 85 containers (HS-WL-01).

**Evidence.** HS-WL-01

**Gaps.**
- `G-CM-12` No image allow-listing and 19% digest pinning. Risk: a re-tagged or hijacked upstream image deploys on the next pull. Remedy: pin every image by digest (Renovate keeps them current), then a Kyverno/ValidatingAdmissionPolicy that rejects unpinned images. Target **2027-06-30**.

**Related.** SR-11, SI-7; HS-WL-01.

### CM-8 System Component Inventory

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** The component inventory is `00-system-description.md` §2 and §4 (hosts, apps, data stores, classes, tiers), and `apps/*` is the authoritative list of deployed applications.

**Evidence.** `00-system-description.md` §2, §4

**Gaps.** Off-site target and backup server tiers tracked as `G-CP-07`.

**Related.** CM-8(1), CM-8(3).

### CM-8(1) Updates During Installation and Removal

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** The inventory is updated when apps change only if the author remembers; policy §7.2 requires a tier and class before first deploy, with no check.

**Evidence.** Policy §7.2

**Gaps.**
- `G-CM-13` No check that a new app gets a tier and data class. Risk: a new C4 store appears with no backup or protection decision. Remedy: namespace labels `homelab/data-class` and `homelab/criticality` (policy §5.3) and a CI check that every namespace has them. Target **2027-03-31**.

**Related.** CM-8.

### CM-8(3) Automated Unauthorized Component Detection

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Unauthorized components in the cluster are reverted or flagged OutOfSync by ArgoCD for managed namespaces. Unauthorized hosts or devices on the LAN or tailnet are not detected.

**Evidence.** `apps/argocd/root-applicationset.yaml`

**Gaps.** Covered by `G-AC-14` (home network) and `G-SA-09` (Tailscale review).

**Related.** CM-8.

### CM-9 Configuration Management Plan

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Implemented |

**Implementation.** The configuration management plan is policy §11 (change types), §8 (zones), ADR-0012 (state protection), `AGENTS.md` and `03-homelab-standard.md` §GIT. Configuration items are everything under `apps/` and `components/`.

**Evidence.** Policy §8, §11; `AGENTS.md`

**Gaps.** None.

**Related.** CM-3.

### CM-10 Software Usage Restrictions

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Software is open source under its own licences; custom images are built by the owner. Licence compliance is not tracked, which matters only for redistribution (none).

**Evidence.** `00-system-description.md` §4

**Gaps.** None.

**Related.** SA-4.

### CM-11 User-installed Software

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Service users cannot install software on the system. The owner and agents can, through git (tracked) or directly on hosts (untracked, `G-CM-03`).

**Evidence.** `G-CM-03`

**Gaps.** Covered by `G-CM-03`.

**Related.** CM-7.

### CM-12 Information Location

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Implemented |

**Implementation.** Where each class of information lives is recorded in `00-system-description.md` §4 and §4.1 (stores, encryption, location).

**Evidence.** `00-system-description.md` §4.1

**Gaps.** None.

**Related.** CM-12(1).

### CM-12(1) Automated Tools to Support Information Location

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** No automated discovery tool; the data-store table is maintained by hand and checked at the 3-monthly re-measure. Small enough to keep by hand.

**Evidence.** Policy §19

**Gaps.** None.

**Related.** CM-12.

