# AC — Access Control

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Access control in this system has two halves. The **service-user plane** is
largely in place: Authentik is the single identity provider, published apps sit
behind forward-auth or native OIDC, admin-type apps have been bound to
`authentik Admins` since 2026-09-04 (`docs/accounts.md`), and every non-Helm
namespace carries default-deny NetworkPolicies whose cross-namespace flows are
checked on both ends in CI. The **operator plane** is the weak half. One person
holds every role, and the AI agents that make most changes act with that
person's credentials. Those credentials are root on pve and cluster-admin through
`ssh pve 'pct exec 200 -- kubectl …'`, so the target access matrix in policy
§9.2 is enforced today only by a Claude Code hook, auto-mode rules and agents
obeying the policy (§9.2 "Today's actual state"; HS-SEC-04, HS-AGENT-09). `main`
has no branch protection (HS-GIT-03), so the zone model in policy §8 is also
followed by convention, not enforced.

The most serious gaps found while writing this family: (1) remux's Jellyfin API
paths are routed **without** forward-auth (`apps/remux/ingress-api.yaml`), while
`remux-user-sync` creates accounts with an **empty password** on the stated
assumption that no such carve-out exists. Whether remux accepts an empty
password is **[UNVERIFIED]** (G-AC-07). (2) Deactivating a leaver in Authentik
does not reach the apps that keep their own credentials (G-AC-04). (3) ArgoCD has
an Ingress, allowlisted to the LAN and Tailscale, which conflicts with policy
§9.5 (G-AC-11). (4) Six NetworkPolicy selectors name namespaces that no longer
exist (G-AC-08). (5) No Kubernetes API audit log exists (G-AC-13).

Family-wide decisions: AC-8's U.S.-Government banner text does not apply, but
its notice intent does, so it is Planned. Wireless (AC-18) and mobile-device
(AC-19) controls are Planned rather than tailored out, because components inside
the boundary use WiFi and the owner's devices hold admin credentials. Four controls are Not
applicable: emergency accounts (AC-2(2), none exist), device lock (AC-11,
AC-11(1), headless servers) and portable storage on external systems (AC-20(2)).


Wherever this family says "agents" it means the Automated Operator role in
policy §3.1 (Claude Code, opencode, Codex, Gemini and their subagents). Wherever
it says "owner" it means the System Owner, who holds every human role
(policy §3.1).

| Disposition | Count |
|---|---|
| Implemented | 2 |
| Partially implemented | 23 |
| Planned | 8 |
| Inherited | 1 |
| Alternative implementation | 1 |
| Not applicable | 4 |
| **Total** | **39** |
---

### AC-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (as Security Officer) |
| **Parameters** | ac-1_prm_1 = the System Owner, and every Automated Operator through `AGENTS.md`; ac-01_odp.03 = system-level; ac-01_odp.04 = the System Owner, acting as Security Officer (policy §3.1); ac-01_odp.05 = 12 months (policy App. A); ac-01_odp.06 = a SEV-1 or SEV-2 incident, a new Tier 0 or Tier 1 component, a change in who has privileged access, or a major platform change recorded in an ADR (policy App. A); ac-01_odp.07 = 12 months (policy App. A); ac-01_odp.08 = the same events as ac-01_odp.06 |

> a. Develop, document, and disseminate to [Assignment: the System Owner, and every Automated Operator through `AGENTS.md`]:
>   1. [Selection: system-level] access control policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the access control policy and the associated access controls;
> b. Designate an [Assignment: the System Owner, acting as Security Officer] to manage the development, documentation, and dissemination of the access control policy and procedures; and
> c. Review and update the current access control:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident, a new Tier 0 or Tier 1 component, a change in who has privileged access, or a major platform change recorded in an ADR]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events].

**Implementation.**

**a.1.** The access control policy is `docs/security/01-policy.md` (HL-POL-001):
§1 gives the purpose, §2 the scope, §3 the roles and responsibilities, §9 the
access rules (principles, the access matrix, the service-user lifecycle,
authentication, session and remote access, break-glass), §8 the zones that decide
who may *change* what, and §10 the acceptable use rules for agents. §19 covers
compliance measurement and §20 risk acceptance. "Management commitment" is the
owner's approval under §21, and "coordination" is §3.2's compensating controls
for one person holding every role. **(b)** Consistency with law is not argued
anywhere in the policy. That is a gap, although a small one for a private
homelab. Dissemination to agents happens because `AGENTS.md` is loaded by every
harness (its header says so) and HS-AGENT-01 makes `03-homelab-standard.md` win
over it.

**a.2.** There is no single AC procedure document. The procedures are spread
across runbooks: `docs/accounts.md` (joiner workflow, app bindings),
`docs/access-procedures.md` (SSH, privilege escalation, ArgoCD admin, emergency
bypass), `docs/RUNDOWN.md` ("Adding a Person", "Not Published"), `AGENTS.md`
("Reaching the cluster", "Secrets", "Deleting state takes a human") and
`docs/recovery/cluster-down.md`. Several of these are stale (G-AC-01).

**b.** The owner, as Security Officer (policy §3.1).

**c.** The review cadence is in the policy's document control table and §19. The
policy is **DRAFT** and "not in force until the owner approves it" (§21), so no
review has happened yet.

**Evidence.**
- `docs/security/01-policy.md` document control, §1–§3, §8–§10, §19, §21
- `AGENTS.md`; `docs/accounts.md`; `docs/access-procedures.md`; `docs/RUNDOWN.md`

**Gaps.**
- **G-AC-01.** The policy is unapproved, and the AC procedures are scattered and partly stale. Policy §9.3 still tells the owner to remove a leaver from Invidious, which was decommissioned on 2026-09-05 (`apps/accounts/app.py:12-14`). `docs/RUNDOWN.md` "Adding a Person" omits the `accounts` tool. `docs/access-procedures.md` "k3s Down" and "Kubeconfig" use LAN paths (`ssh root@192.168.1.172`, `scp root@192.168.1.172:…`) that cannot work from the laptop. "Maintenance Windows" is template text. `docs/accounts.md` step 1 still says the tool creates Invidious accounts. *Risk:* an agent follows a procedure literally and does the wrong thing. *Remedy:* the owner approves the policy, and one AC runbook (joiner, mover, leaver, review, break-glass) is consolidated into `docs/accounts.md`, with the others linking to it. **Target 2026-11-30.**

**Related.** Policy §1–§3, §8–§10, §19, §21; HS-AGENT-01; all AC controls.

---

### AC-2 Account Management

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (sole account manager); Authentik (`apps/authentik`); `accounts` tool (`apps/accounts`) |
| **Parameters** | ac-02_odp.01 = owner's decision per policy §9.3: only the groups the person needs, never `authentik Admins` for a service user; ac-02_odp.02 = Authentik group membership, user type, active flag; ac-02_odp.03 = System Owner; ac-02_odp.04 = policy §9.3 and `docs/accounts.md`; ac-02_odp.05 = System Owner; ac-02_odp.06 = 7 days; ac-02_odp.07 = 7 days; ac-02_odp.08 = 7 days (policy §9.3, App. A); ac-02_odp.09 = Authentik group membership; ac-02_odp.10 = every 90 days (policy App. A) |

> a. Define and document the types of accounts allowed and specifically prohibited for use within the system;
> b. Assign account managers;
> c. Require [Assignment: the owner's decision per policy §9.3 — only the groups needed; never `authentik Admins` for a service user] for group and role membership;
> d. Specify:
>   1. Authorized users of the system;
>   2. Group and role membership; and
>   3. Access authorizations (i.e., privileges) and [Assignment: Authentik group membership, user type and active flag] for each account;
> e. Require approvals by [Assignment: the System Owner] for requests to create accounts;
> f. Create, enable, modify, disable, and remove accounts in accordance with [Assignment: policy §9.3 and `docs/accounts.md`];
> g. Monitor the use of accounts;
> h. Notify account managers and [Assignment: the System Owner] within:
>   1. [Assignment: 7 days] when accounts are no longer required;
>   2. [Assignment: 7 days] when users are terminated or transferred; and
>   3. [Assignment: 7 days] when system usage or need-to-know changes for an individual;
> i. Authorize access to the system based on:
>   1. A valid access authorization;
>   2. Intended system usage; and
>   3. [Assignment: Authentik group membership];
> j. Review accounts for compliance with account management requirements [Assignment: every 90 days]; and
> k. Establish and implement a process for changing shared or group account authenticators (if deployed) when individuals are removed from the group; and
> l. Align account management processes with personnel termination and transfer processes.

**Implementation.**

**a.** Policy §3.1 and 00 §5 define the account types: owner, service user,
Automated Operator (no account of its own; it acts as the owner), and named
System Agents (ArgoCD ServiceAccount, GitHub Actions token, image-updater deploy
key, Renovate App, Doppler operator token). Policy §9.1 prohibits shared accounts
except `akadmin`, ArgoCD `admin` and remux `admin`. That exception list is
incomplete: there is also a local Grafana admin (`apps/monitoring/kustomization.yaml:243-244`,
`existingSecret: grafana-admin`), a seeded Pelican admin (`apps/pelican/admin-job.yaml`)
and Ghost staff accounts (G-AC-03). `docs/RUNDOWN.md:27` still lists an Obsidian
LiveSync CouchDB login, but that app was removed and replaced by Memos
(`apps/memos/kustomization.yaml:3`), so the row is stale rather than a live account.

**b.** The owner is the only account manager.

**c–e.** Joiners are created at `accounts.sandstorm.chat`, which is reachable
only through forward-auth and then checks `X-authentik-groups` for `authentik
Admins` itself (`apps/accounts/app.py:33-36, 223-250`). Account creation therefore
requires the owner. Apps provision their own local records on first login
(`docs/accounts.md` table). Group-to-app bindings are Authentik objects, which
are Z0 and outside git (W-01), so **d.1–d.3 are not specified anywhere an
assessor can read**. Usernames are C3 (policy §5.1), so they cannot go into this
public repo (G-AC-02).

**f.** The tool creates accounts and realigns passwords but "never deletes or
disables anything" (`app.py:27-29`). Disabling is a manual act in the Authentik UI.

**g.** See AC-2(4). Authentik's own event log is not exported or alerted on
**[UNVERIFIED]**.

**h, l.** There is no HR process. A leaver is someone the owner learns has left
(policy §9.3, 7 days). Deactivating them in Authentik does **not** remove remux,
Vaultwarden local login, Notesnook, Navidrome Subsonic or CWA OPDS access (G-AC-04).

**i.** Authentik bindings: admin apps are bound to `authentik Admins`, and the
rest are open to any Authentik user (`docs/accounts.md`).

**j.** A 90-day review is required (§9.3). No record that one has ever run
(G-AC-31).

**k.** Rotating a shared credential (`REMUX_ADMIN_PASSWORD`, ArgoCD admin) follows
§12.2.3. With one human, "removed from the group" only arises if an agent
session exposed the value (§16.5).

**Evidence.**
- `apps/accounts/app.py`, `apps/accounts/ingress.yaml`
- `docs/accounts.md` "Application access, and what it used to be"
- `docs/security/01-policy.md` §9.1, §9.3; `00-system-description.md` §5

**Gaps.**
- **G-AC-02.** No authorized-user register: who exists in Authentik, which groups, and which local app accounts. *Risk:* nobody can tell whether an account is authorized, and the 90-day review has nothing to check against. *Remedy:* a register in the owner's password manager or another private store (C3), produced from an `ak shell` export. The repo records only account *types* and counts. **Target 2026-12-31.**
- **G-AC-03.** Policy §9.1's shared/local-account exception list omits Grafana's local admin, the Pelican seeded admin and Ghost staff. *Risk:* unrecorded privileged credentials escape rotation and review. *Remedy:* amend §9.1 and record each in the §12.1 inventory. **Target 2026-11-30.**
- **G-AC-04.** Leaver deactivation is not end-to-end. `remux-user-sync` "only ever ADDS" (`apps/remux/user-sync-cronjob.yaml:23-25`), the remux API is reachable without Authentik (`apps/remux/ingress-api.yaml`), Vaultwarden keeps local login (`SSO_ONLY=false`, `apps/vaultwarden/deployment.yaml:192-193`), Notesnook has its own identity server with no Authentik link (`apps/notesnook/kustomization.yaml:19`), and the Navidrome Subsonic carve-out authenticates against Navidrome's own per-user password, so "revoking a user in Authentik does NOT revoke their Subsonic client" (`apps/navidrome/subsonic-ingress.yaml` header); Calibre-Web's `/opds` uses CWA's own Basic auth (`apps/books/opds-ingress.yaml`). *Risk:* a deactivated person keeps working credentials. *Remedy:* a leaver checklist naming each independent credential store, and a remux delete/disable step. **Target 2026-11-30.**
- **G-AC-31.** No 90-day account review has been recorded. *Risk:* stale accounts persist (for example the orphaned Vaultwarden `root@example.com` user, `docs/RUNDOWN.md:271-276`). *Remedy:* run the first review and record its date and counts in the doctor log or the POA&M. **Target 2026-12-31.**

**Related.** Policy §3.1, §9.1, §9.3, §13.2; W-01; AC-2(1)–(13), AC-6(7), IA-2, IA-4, PS-4.

---

### AC-2(1) Automated System Account Management

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Service-user accounts are created and grouped through the `accounts` tool (`accounts.sandstorm.chat`), which provisions Authentik and remux in one step (`docs/accounts.md`). Removal, disabling and review are manual, and apps that keep local accounts are not reached (G-AC-04).

**Evidence.** `apps/accounts/`; `docs/accounts.md`; `apps/remux/user-sync-cronjob.yaml`

**Gaps.** Removal is covered by `G-AC-04`; the register by `G-AC-02`.

**Related.** AC-2, AC-2(3), IA-4; policy §9.3.

### AC-2(2) Automated Temporary and Emergency Account Management

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** The system creates no temporary or emergency accounts. Break-glass access (policy §9.6) uses the owner's existing root/cluster-admin path, not a new account, so there is nothing to remove automatically. If a temporary account is ever created for a guest, policy §9.3 requires an end date set at creation.

**Evidence.** Policy §9.3, §9.6; `00-system-description.md` §5 (no such identity)

**Gaps.** None.

**Related.** AC-2, AC-17; HS-AGENT-09.

### AC-2(3) Disable Accounts

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** Policy Appendix A sets 90 days without login as the disable trigger and 7 days for a leaver. Nothing measures last login or disables an account automatically, and no review has been recorded (G-AC-31).

**Evidence.** Policy App. A, §9.3

**Gaps.**
- `G-AC-05` No automatic disable after 90 days' inactivity. Risk: a forgotten account with a reused password stays usable from the internet. Remedy: a monthly CronJob that lists Authentik users with `last_login` older than 90 days and posts them to ntfy; the owner disables. Target **2027-01-31**.

**Related.** AC-2, AC-2(1); IA-4(4).

### AC-2(4) Automated Audit Actions

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authentik records account creation, modification and deletion in its event log (an Authentik product feature). Those events are not shipped to Loki with a defined retention and nobody is notified (G-SI-09). Changes to accounts made in git (machine identities) are in git history.

**Evidence.** `apps/authentik/`; `apps/monitoring/` (Loki/Alloy)

**Gaps.** Covered by `G-SI-09` (security events not reviewed or alerted) and `G-AU-02`.

**Related.** AU-2, AU-12, SI-4.

### AC-2(5) Inactivity Logout

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Policy App. A says Authentik sessions SHOULD expire within 24 h of inactivity. The configured session duration is not in git (Authentik flows and stages are out-of-git state, W-01) and is **[UNVERIFIED]**. Apps that keep their own sessions use their defaults.

**Evidence.** Policy App. A; `03-homelab-standard.md` W-01

**Gaps.**
- `G-AC-06` Authentik session lifetime is unverified and not declared in git. Risk: a session on a shared or lost device stays valid indefinitely. Remedy: read the value in the Authentik admin UI, set it to ≤24 h idle, and record it in an Authentik blueprint (W-01 work). Target **2026-12-31**.

**Related.** AC-11, AC-12; W-01.

### AC-2(13) Disable Accounts for High-risk Individuals

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** A service user reported or suspected of compromise is disabled in Authentik by the owner (policy §16 credential-exposure playbook). There is no defined time limit for high-risk accounts beyond the 7-day leaver rule, and local app accounts are not reached (G-AC-04).

**Evidence.** Policy §9.3, §16

**Gaps.** Covered by `G-AC-04`.

**Related.** AC-2, IR-4.

### AC-3 Access Enforcement

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Logical access is enforced at three layers: Authentik forward-auth or OIDC in front of published apps, with admin-type apps bound to `authentik Admins` since 2026-09-04; each app's own authorization; and Kubernetes RBAC, where workloads use ServiceAccounts. Deliberate exceptions are the public blog and Kiwix. Two weaknesses: remux's Jellyfin API paths are routed **without** forward-auth by design (`apps/remux/ingress-api.yaml`: "That omission IS the feature"), while `remux-user-sync` creates accounts with an empty password (draft PR #20 changes this to random passwords); and Pelican, Forgejo and bookdl are open to any Authentik user pending the owner's decision (`docs/accounts.md`).

**Evidence.** `apps/remux/ingress-api.yaml`; `apps/remux/user-sync-cronjob.yaml`; PR #20; `docs/accounts.md`; `00-system-description.md` §3

**Gaps.**
- `G-AC-07` remux API is reachable from the internet without forward-auth while synced accounts may have an empty password. Risk: anyone who knows a username can log in to remux. Remedy: merge PR #20, reset existing synced accounts to random passwords, and verify an empty-password login fails. Target **2026-11-01**.
- `G-AC-12` Pelican, Forgejo and bookdl group bindings are undecided. Risk: every service user can reach admin-capable apps. Remedy: owner decides; bind to a group and record it in `docs/accounts.md`. Target **2026-11-30**.

**Related.** AC-6, IA-2, SC-7; policy §9.1–9.2.

### AC-4 Information Flow Enforcement

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Flows between namespaces are controlled by NetworkPolicies (default-deny plus explicit allows) in every non-Helm namespace; cross-namespace flows must be allowed on both ends, which CI checks (`scripts/ci/check-invariants.py`, HS-NET-02). The torrent stack can only leave through gluetun's AirVPN tunnel. Six selectors name namespaces that no longer exist (`pangolin` in authentik, convertx, kiwix and vaultwarden; `forgejo` and `invidious` in databases), measured 2026-10-03 against `apps/*` Namespace objects. Helm-deployed namespaces are UNMEASURED (HS-NET-01).

**Evidence.** `apps/*/networkpolicy.yaml`; `scripts/ci/check-invariants.py`; HS-NET-01..03

**Gaps.**
- `G-AC-08` Six NetworkPolicy rules select deleted namespaces, and CI does not check for it (HS-NET-03). Risk: dead allow rules hide intent and would silently open a flow if a namespace with that name were recreated. Remedy: remove them and add the check to `check-invariants.py`. Target **2026-11-30**.

**Related.** SC-7, CM-7; HS-NET-01..03.

### AC-5 Separation of Duties

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S1 (`02-tailoring.md` §3.1): one person holds every role, so duties cannot be split between people. The intent, that no single unchecked action can both make and hide a harmful change, is approximated by: every change being a git commit (attributable, revertable); CI checks; protect-state annotations that make ArgoCD refuse to delete state; and agents being barred from deleting state or pushing to `main` unasked (HS-STATE-03, HS-AGENT-04). Without branch protection (HS-GIT-03) nothing stops a push that skips CI.

**Evidence.** ADR-0012; `components/protect-state`; HS-STATE-01..03, HS-AGENT-04, HS-GIT-03

**Gaps.**
- `G-AC-09` `main` has no branch protection, so the automated "second person" can be bypassed. Risk: an unreviewed or failing change deploys straight to production. Remedy: POA&M item 2 — require `validate` and a PR on `main`. Target **2026-11-30**.

**Related.** AC-6, CM-3, CM-5; policy §3.2.

### AC-6 Least Privilege

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Workloads run under their own ServiceAccounts, and service users get only the Authentik groups they need. The operator plane is not least-privilege: the owner and every AI agent use root on pve and cluster-admin via `ssh pve 'pct exec 200 -- kubectl'` as the normal path (HS-SEC-04, HS-AGENT-09 GAP; policy §9.2 "Today's actual state"). Agents can therefore read Secrets, which is prevented only by the Claude Code hook (HS-SEC-03).

**Evidence.** `00-system-description.md` §3, §5; policy §9.2; HS-SEC-03, HS-SEC-04, HS-AGENT-09

**Gaps.**
- `G-AC-10` Agents and routine operations use cluster-admin and host root. Risk: one mistaken or manipulated agent command can read every credential or delete state. Remedy: POA&M item 1 — a scoped agent kubeconfig bound to `view` (no Secrets) plus write-through-git only; cluster-admin kept for break-glass. Target **2026-12-31**.

**Related.** AC-6(1)–(10), AC-17; policy §9.2.

### AC-6(1) Authorize Access to Security Functions

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Security functions (Doppler, Authentik admin, ArgoCD, host root) are reachable only with the owner's credentials. Access is not further restricted per function, and agents inherit all of it (G-AC-10).

**Evidence.** Policy §9.2

**Gaps.** Covered by `G-AC-10`.

**Related.** AC-6.

### AC-6(2) Non-privileged Access for Nonsecurity Functions

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** The owner has a non-privileged service-user experience through Authentik, but routine administration and agent work happen through the privileged path rather than a lesser account (G-AC-10).

**Evidence.** `00-system-description.md` §5

**Gaps.** Covered by `G-AC-10`.

**Related.** AC-6.

### AC-6(5) Privileged Accounts

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Privileged accounts are limited to the owner: Authentik `akadmin` and `authentik Admins` membership, root on pve and travisbackupserver, `travis`+`doas` on the nas. Shared admin accounts exist (akadmin, the ArgoCD admin, remux admin; G-AC-03). AI agents hold privileged access by inheritance (G-AC-10).

**Evidence.** `docs/accounts.md`; `docs/access-procedures.md`

**Gaps.** Covered by `G-AC-03` and `G-AC-10`.

**Related.** AC-2, AC-6.

### AC-6(7) Review of User Privileges

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** No review of privileges has been recorded. Policy §19 sets a 90-day account and access review, which should include `authentik Admins` membership, local admin accounts and the agents' access.

**Evidence.** Policy §9.3, §19

**Gaps.** Covered by `G-AC-31`.

**Related.** AC-2.

### AC-6(9) Log Use of Privileged Functions

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Privileged changes made through git are logged by git history with author and `Co-Authored-By` trailers (HS-AGENT-13). Privileged actions taken directly through kubectl or on hosts are not logged: there is no Kubernetes API audit log and no central host journal.

**Evidence.** HS-AGENT-13; `G-AU-02`, `G-AU-03`

**Gaps.**
- `G-AC-13` Direct privileged use (cluster-admin, host root) leaves no audit record. Risk: after an incident nobody can tell what an agent or intruder did. Remedy: enable the k3s API audit log with a metadata-level policy shipped to Loki (same work as `G-AU-02`). Target **2027-01-31**.

**Related.** AU-2, AU-12.

### AC-6(10) Prohibit Non-privileged Users from Executing Privileged Functions

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Service users cannot run privileged functions: they have no shell, kubeconfig or admin group. Nothing technically prevents an agent (a non-person acting as the owner) from doing so (G-AC-10).

**Evidence.** `00-system-description.md` §5

**Gaps.** Covered by `G-AC-10`.

**Related.** AC-6.

### AC-7 Unsuccessful Logon Attempts

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Failed logins are limited by Authentik's defaults and, at the edge, by Traefik rate limiting (50 req/s, burst 100) and CrowdSec, which bans IPs that show brute-force patterns in Traefik's access logs (policy App. A). Authentik's lockout settings are out of git and **[UNVERIFIED]**. Apps that bypass forward-auth (remux API) rely on their own handling.

**Evidence.** `apps/traefik/`; `apps/crowdsec/`; `00-system-description.md` §3; policy App. A

**Gaps.** Verification is part of `G-AC-06` (read and record Authentik settings).

**Related.** SC-5, SI-4.

### AC-8 System Use Notification

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** The U.S.-Government banner text does not apply (S4), but the intent — telling users what is logged and how their data is used — does. No login notice exists on Authentik or SSH.

**Evidence.** Policy §14

**Gaps.** Covered by `G-SI-11` (no notice of monitoring).

**Related.** SI-4; policy §14.

### AC-11 Device Lock

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Device lock is a property of the user's own device, which is outside the boundary (policy §2.2) except for the operator laptop, whose screen lock is the owner's setting and **[UNVERIFIED]**. The servers have no attached interactive session in normal use (pve and nas are headless).

**Evidence.** Policy §2.2; `00-system-description.md` §2.1

**Gaps.** None.

**Related.** AC-19, AC-12.

### AC-11(1) Pattern-hiding Displays

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Follows AC-11: no in-boundary device presents a console session that needs pattern-hiding.

**Evidence.** —

**Gaps.** None.

**Related.** AC-11.

### AC-12 Session Termination

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authentik sessions are meant to end within 24 h idle (policy App. A), unverified (G-AC-06). SSH sessions to hosts end when the client disconnects; no idle timeout is recorded.

**Evidence.** Policy App. A

**Gaps.** Covered by `G-AC-06`.

**Related.** AC-2(5).

### AC-14 Permitted Actions Without Identification or Authentication

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Actions allowed without identification are listed: reading the public blog (`blog.sandstorm.chat`), Kiwix, and the remux API's pre-authentication endpoints (which then require the app's own login). Everything else published sits behind Authentik (`00-system-description.md` §3).

**Evidence.** `00-system-description.md` §3; `apps/remux/ingress-api.yaml`

**Gaps.** None.

**Related.** AC-3.

### AC-17 Remote Access

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Remote administration goes laptop → Tailscale → pve/nas over SSH with the `worker_key` key (`docs/access-procedures.md`). Admin UIs (ArgoCD, Prometheus, qBittorrent, slskd) are not published. Exception: `apps/argocd/ingress.yaml` gives ArgoCD an Ingress restricted to LAN and Tailscale ranges, which policy §9.5 does not list as an allowed path. No written usage restrictions per method beyond policy §9.

**Evidence.** `docs/access-procedures.md`; `apps/argocd/ingress.yaml`; policy §9.5

**Gaps.**
- `G-AC-11` ArgoCD has an Ingress that policy §9.5 does not allow. Risk: ArgoCD's admin login is exposed to every LAN device and tailnet node, including service users' devices if any join. Remedy: owner decides — remove the Ingress or amend §9.5 with the allowlist as the control. Target **2026-11-30**.

**Related.** AC-17(1)–(4), SC-7.

### AC-17(1) Monitoring and Control

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Tailscale records device connections in its admin console (inherited). Nothing on the hosts monitors SSH sessions centrally (G-AU-03).

**Evidence.** `00-system-description.md` §2.2

**Gaps.** Covered by `G-AU-03`.

**Related.** AU-2, SI-4.

### AC-17(2) Protection of Confidentiality and Integrity Using Encryption

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Inherited (Tailscale) |

**Implementation.** Remote sessions are encrypted by Tailscale's WireGuard tunnel (inherited) and by SSH inside it (owner). The owner's share: key-only SSH (HS-HOST-04, UNMEASURED).

**Evidence.** `00-system-description.md` §2.2, §3

**Gaps.** None.

**Related.** SC-8, IA-5(2).

### AC-17(3) Managed Access Control Points

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Implemented |

**Implementation.** All remote administration enters through one path: the Tailscale tailnet into pve, the nas or travisbackupserver. The laptop cannot reach the LAN directly (`AGENTS.md`, "Reaching the cluster"). The ArgoCD Ingress is the exception (G-AC-11).

**Evidence.** `AGENTS.md`; `docs/access-procedures.md`

**Gaps.** None.

**Related.** AC-17, SC-7.

### AC-17(4) Privileged Commands and Access

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Privileged commands are run remotely by design (there is no local console routine). Policy §9.2 and §10 say who may run what; enforcement for agents is the Claude Code hook only (HS-AGENT-05).

**Evidence.** Policy §9.2, §10; HS-AGENT-05

**Gaps.** Covered by `G-AC-10`.

**Related.** AC-6.

### AC-18 Wireless Access

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Components in the boundary use the home WiFi and Ethernet, and the operator laptop uses wireless. Wireless security (WPA mode, router admin) is the home router's configuration, not recorded anywhere, **[UNVERIFIED]**. Servers are assumed wired.

**Evidence.** `AGENTS.md` (laptop on a different network)

**Gaps.**
- `G-AC-14` Home network and router configuration are undocumented. Risk: a weak WiFi or router admin password puts an attacker on the same L2 as the nas's plaintext NFS. Remedy: record the router model, WPA mode, admin-password storage and whether servers are wired in `00-system-description.md`. Target **2027-01-31**.

**Related.** SC-8, AC-18(1), AC-18(3).

### AC-18(1) Authentication and Encryption

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** WiFi authentication and encryption are the router's settings, unrecorded (G-AC-14).

**Evidence.** —

**Gaps.** Covered by `G-AC-14`.

**Related.** AC-18.

### AC-18(3) Disable Wireless Networking

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** Whether the servers' wireless interfaces are disabled is **[UNVERIFIED]** (G-AC-14).

**Evidence.** —

**Gaps.** Covered by `G-AC-14`.

**Related.** AC-18.

### AC-19 Access Control for Mobile Devices

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** The owner's laptop (and any phone with the Tailscale client) holds admin credentials: the SSH key, a kubeconfig, a Doppler login and GitHub credentials (`00-system-description.md` §2.1). Policy has no rule for these devices beyond §10.

**Evidence.** `00-system-description.md` §2.1

**Gaps.**
- `G-AC-15` No requirements for devices that hold admin credentials. Risk: a lost or compromised laptop is full control of the homelab. Remedy: add a device rule to policy §9 (disk encryption, screen lock, Tailscale key expiry, how to revoke) and record each device's status. Target **2027-01-31**.

**Related.** AC-19(5), MP-5.

### AC-19(5) Full Device or Container-based Encryption

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Planned |

**Implementation.** Full-disk encryption on the operator laptop is **[UNVERIFIED]** (G-AC-15).

**Evidence.** —

**Gaps.** Covered by `G-AC-15`.

**Related.** SC-28.

### AC-20 Use of External Systems

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Service users use their own devices, outside the boundary, through Authentik. The owner works only from the operator laptop. The model providers that agents use are external systems that receive whatever agents read; policy §10 and HS-SEC-03 restrict what may reach them.

**Evidence.** Policy §2.2, §10; HS-SEC-03

**Gaps.** Device rule tracked as `G-AC-15`.

**Related.** SA-9, AC-20(1).

### AC-20(1) Limits on Authorized Use

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Use of external systems is limited to the providers in `00-system-description.md` §2.2. Their controls are relied on, not verified (`02-tailoring.md` §4).

**Evidence.** `02-tailoring.md` §4

**Gaps.** Covered by `G-SA-09` (external-service register).

**Related.** SA-9.

### AC-20(2) Portable Storage Devices — Restricted Use

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No portable storage is used with external systems. Backups leave the site only over Tailscale to the off-site target; no removable media carries system data.

**Evidence.** `00-system-description.md` §4.2

**Gaps.** None.

**Related.** MP-7.

### AC-21 Information Sharing

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Users share content with each other inside apps (Immich albums, Nextcloud shares) under each app's own sharing controls. Public share links are allowed by those apps and not restricted by policy.

**Evidence.** Policy §6

**Gaps.**
- `G-AC-16` No rule on public share links in Immich and Nextcloud. Risk: a C3 photo or file shared by link becomes reachable by anyone with the URL, indefinitely. Remedy: a policy §6 line on public links (expiry, password) and app settings to match. Target **2027-03-31**.

**Related.** AC-3.

### AC-22 Publicly Accessible Content

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Public content is limited to the Ghost blog and Kiwix. Ghost posts are published by the owner; no review step exists, but the content is the owner's own.

**Evidence.** `00-system-description.md` §3

**Gaps.** Covered by `G-AC-16` for share links.

**Related.** AC-14.

