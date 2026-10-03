# IA — Identification and Authentication

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

IA rests on Authentik as the single identity provider for people, SSH keys for hosts, and in-cluster ServiceAccounts or provider tokens for machines. The weak points are what cannot be seen from the repository: whether MFA is on for the owner's provider accounts and for Authentik users is **[UNVERIFIED]** everywhere, and Authentik's flows, stages and policies live outside git (W-01). AI agents have no identity of their own; they authenticate as the owner, so nothing distinguishes an agent's action from the owner's (S6). Federal-specific controls (PIV, identity proofing to federal levels) are tailored out (S4), but the intent of identity proofing still applies to the accounts tool's invitation step.

| Disposition | Count |
|---|---|
| Implemented | 2 |
| Partially implemented | 13 |
| Planned | 1 |
| Alternative implementation | 3 |
| Not applicable | 5 |
| **Total** | **24** |

---

### IA-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** IA rules are in policy §9.4 (authentication, MFA) and §12 (keys and credentials); App. A gives review periods. Procedures: `docs/accounts.md` (joiner), `docs/access-procedures.md` (SSH, kubeconfig), `scripts/setup-image-updater-key.sh`. The policy is a DRAFT until merged (§21).

**Evidence.** Policy §9.4, §12, §21, App. A

**Gaps.** Approval tracked with `G-AU-01`/`G-AC-01` (policy unapproved).

**Related.** AC-1, all IA.

### IA-2 Identification and Authentication (Organizational Users)

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Service users and the owner are identified individually in Authentik; the owner's host access is by the `worker_key` SSH key. Processes acting for a user are not tied back to that user: agents act as the owner (S6), and `akadmin` is a shared-name admin account.

**Evidence.** `00-system-description.md` §5; `docs/accounts.md`

**Gaps.**
- `G-IA-01` AI agents have no identity distinct from the owner. Risk: no record can separate an agent's action from the owner's, so misbehaviour cannot be traced or contained by revoking the agent alone. Remedy: the scoped agent kubeconfig (POA&M item 1) as a distinct identity, plus a commit trailer check (HS-AGENT-13). Target **2026-12-31**.

**Related.** AC-6, AU-3; HS-AGENT-13.

### IA-2(1) Multi-factor Authentication to Privileged Accounts

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Policy §9.4 requires phishing-resistant MFA (else TOTP) on the owner's GitHub, Doppler, Tailscale, Cloudflare, registrar and Authentik `akadmin`. Status is **[UNVERIFIED]** for each. Host root by SSH key is single-factor (key possession).

**Evidence.** Policy §9.4; `00-system-description.md` §5

**Gaps.**
- `G-IA-02` MFA on the owner's privileged provider accounts and `akadmin` is unverified. Risk: one phished password gives control of Doppler (every credential) or GitHub (production deploys). Remedy: the owner checks each console, enables WebAuthn/passkeys, and records the result in `00-system-description.md` §5. Target **2026-11-15**.

**Related.** IA-5, AC-6.

### IA-2(2) Multi-factor Authentication to Non-privileged Accounts

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Policy §9.4 says service users SHOULD use MFA; whether Authentik offers or enforces it is **[UNVERIFIED]** (flows are out of git, W-01).

**Evidence.** Policy §9.4

**Gaps.**
- `G-IA-03` No MFA requirement enforced for service users. Risk: a reused password exposes that user's photos, files and vault metadata. Remedy: an Authentik flow that requires TOTP/WebAuthn enrolment for new users, offered to existing ones, captured in a blueprint. Target **2027-03-31**.

**Related.** IA-2(1).

### IA-2(8) Access to Accounts — Replay Resistant

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authentik sessions run over TLS and use signed, time-limited tokens; WebAuthn (if enabled) is replay-resistant. SSH key auth is replay-resistant by protocol. Remains UNVERIFIED with `G-IA-02`.

**Evidence.** `00-system-description.md` §3

**Gaps.** Covered by `G-IA-02`.

**Related.** SC-23.

### IA-2(12) Acceptance of PIV Credentials

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S4: not a federal system; no PIV credentials exist or are accepted.

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** None.

**Related.** IA-8(1).

### IA-3 Device Identification and Authentication

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Devices joining the admin network authenticate to Tailscale with device keys (inherited). Kubernetes nodes join with the k3s token. LAN devices are not authenticated (home network, G-AC-14).

**Evidence.** `00-system-description.md` §2.1, §2.2

**Gaps.** Covered by `G-AC-14`.

**Related.** AC-17, SC-7.

### IA-4 Identifier Management

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Identifiers are assigned by the owner through the accounts tool (people) and in git (ServiceAccounts, DopplerSecrets). Reuse of a deleted username is not prevented, and no register lists identifiers (G-AC-02).

**Evidence.** `docs/accounts.md`; `apps/*/`

**Gaps.** Covered by `G-AC-02`.

**Related.** AC-2.

### IA-4(4) Identify User Status

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authentik groups mark status (`authentik Admins` for admins). Non-person identities are listed in `00-system-description.md` §5, which does not mark agents as such in any system record.

**Evidence.** `00-system-description.md` §5

**Gaps.** Covered by `G-IA-01`.

**Related.** AC-2.

### IA-5 Authenticator Management

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authenticators: Authentik passwords (hashed by Authentik), SSH keys, Doppler service tokens, the image-updater git key (`scripts/setup-image-updater-key.sh`), provider API tokens. Initial service-user passwords are generated by the accounts tool. Policy §12 governs rotation and requires rotation after any exposure (HS-SEC-06, UNMEASURED). Default credentials: qBittorrent's are printed to its log on first start (`docs/RUNDOWN.md`), and the ArgoCD initial admin secret still exists. No rotation schedule exists.

**Evidence.** Policy §12; HS-SEC-05..07; `docs/RUNDOWN.md`

**Gaps.**
- `G-IA-04` No inventory or rotation schedule for machine credentials, and default/initial admin credentials (ArgoCD initial admin secret, qBittorrent default) are not confirmed changed. Risk: a credential exposed in a past transcript stays valid forever. Remedy: a credential inventory (name, consumers, last rotation) in Doppler notes, and an exposure-driven rotation run. Target **2027-01-31**.

**Related.** IA-5(1), IA-5(2), SC-12; policy §12.

### IA-5(1) Password-based Authentication

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authentik's password policy is out of git and **[UNVERIFIED]**. Generated passwords are random. No breached-password check is recorded.

**Evidence.** W-01

**Gaps.** Verification tracked with `G-AC-06` (record Authentik settings).

**Related.** IA-5.

### IA-5(2) Public Key-based Authentication

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Public-key authentication: host SSH accepts keys (key-only is HS-HOST-04, UNMEASURED); `worker_key` is the only working key (`docs/access-procedures.md`). TLS certificates are validated against public CAs (cert-manager/Let's Encrypt). No key revocation procedure exists for a lost laptop.

**Evidence.** `docs/access-procedures.md`; HS-HOST-04

**Gaps.** Covered by `G-AC-15` (device rule incl. revocation) and `G-SC-02` (host hardening scan).

**Related.** SC-12, SC-17.

### IA-5(6) Protection of Authenticators

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Authenticators are held in Doppler and synced into Kubernetes Secrets; agents must never read their values (HS-SEC-03, enforced by the Claude Code hook only). The SSH key and kubeconfig sit on the laptop. Secrets in etcd are not shown to be encrypted at rest (`G-SC-05`).

**Evidence.** HS-SEC-02, HS-SEC-03; `00-system-description.md` §4.1

**Gaps.** Covered by `G-SC-05` and `G-AC-10`.

**Related.** SC-28.

### IA-6 Authentication Feedback

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Password fields in Authentik and app login forms obscure input (product behaviour). SSH does not echo passphrases.

**Evidence.** —

**Gaps.** None.

**Related.** IA-2.

### IA-7 Cryptographic Module Authentication

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S4: FIPS 140 validation is not required. Cryptographic modules are the maintained standard ones in each component (OpenSSL/Go crypto in TLS endpoints, OpenSSH, WireGuard). Their currency depends on patching (`G-SI-03`).

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** Patch currency tracked as `G-SI-03`.

**Related.** SC-13.

### IA-8 Identification and Authentication (Non-organizational Users)

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Non-organizational users are the service users (friends and family). They are identified individually in Authentik, created only by the owner. Public visitors are anonymous by design on the blog and Kiwix (AC-14).

**Evidence.** `docs/accounts.md`

**Gaps.** MFA tracked as `G-IA-03`.

**Related.** AC-14, IA-2.

### IA-8(1) Acceptance of PIV Credentials from Other Agencies

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S4: no PIV credentials from other agencies.

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** None.

**Related.** IA-2(12).

### IA-8(2) Acceptance of External Authenticators

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No external authenticators (federated logins from other IdPs) are accepted; Authentik is the only IdP. If social login is ever enabled in Authentik, this becomes applicable.

**Evidence.** `00-system-description.md` §3

**Gaps.** None.

**Related.** IA-8.

### IA-8(4) Use of Defined Profiles

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Federation inside the system uses standard profiles: OIDC for apps that support it, and Traefik forward-auth to Authentik for the rest.

**Evidence.** `apps/authentik/`; `apps/*/ingress*.yaml`

**Gaps.** None.

**Related.** IA-8.

### IA-11 Re-authentication

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Re-authentication occurs when the Authentik session expires (`G-AC-06`, unverified) and per app. Privilege changes (e.g. group added) take effect at next login. `doas` on the nas prompts for a password.

**Evidence.** `00-system-description.md` §2.1

**Gaps.** Covered by `G-AC-06`.

**Related.** AC-12.

### IA-12 Identity Proofing

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S3/S4: service users are people the owner knows personally; identity is proofed by that relationship and the owner creating the account by hand. There is no self-registration. The residual risk is an invitation link or initial password reaching the wrong person; the accounts tool hands passwords in transit (C4).

**Evidence.** `docs/accounts.md`; `00-system-description.md` §4

**Gaps.** None.

**Related.** IA-12(2), IA-12(3), IA-12(5).

### IA-12(2) Identity Evidence

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No documentary identity evidence is collected; personal acquaintance stands in (IA-12).

**Evidence.** —

**Gaps.** None.

**Related.** IA-12.

### IA-12(3) Identity Evidence Validation and Verification

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Follows IA-12(2).

**Evidence.** —

**Gaps.** None.

**Related.** IA-12.

### IA-12(5) Address Confirmation

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** Address confirmation is replaced by the owner delivering initial credentials over a channel already known to belong to the person. That channel is not written down.

**Evidence.** `docs/accounts.md`

**Gaps.** None.

**Related.** IA-12.

