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
password is **[UNVERIFIED]** (G-AC-05). (2) Deactivating a leaver in Authentik
does not reach the apps that keep their own credentials (G-AC-04). (3) ArgoCD has
an Ingress, allowlisted to the LAN and Tailscale, which conflicts with policy
§9.5 (G-AC-10). (4) Six NetworkPolicy selectors name namespaces that no longer
exist (G-AC-08). (5) No Kubernetes API audit log exists (G-AC-13).

Family-wide decisions: AC-8's U.S.-Government banner text does not apply, but
its notice intent does, so it is Planned. Wireless (AC-18) and mobile-device
(AC-19) controls are Planned rather than tailored out, because components inside
the boundary use WiFi and the owner's devices hold admin credentials. Portable
storage on external systems (AC-20(2)) is the only control here that is Not
applicable.

| Disposition | Count |
|---|---|
| Implemented | 1 |
| Partially implemented | 26 |
| Planned | 10 |
| Inherited | 0 |
| Alternative implementation | 1 |
| Not applicable | 1 |
| **Total** | **39** |

Wherever this family says "agents" it means the Automated Operator role in
policy §3.1 (Claude Code, opencode, Codex, Gemini and their subagents). Wherever
it says "owner" it means the System Owner, who holds every human role
(policy §3.1).

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
