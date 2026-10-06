# SC — System and Communications Protection

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Boundary protection is the strongest part of SC: one MetalLB address into Traefik, TLS from cert-manager, rate limits and CrowdSec on every route, Authentik in front of almost everything, admin UIs unpublished, default-deny NetworkPolicies, and a fail-closed VPN for the torrent stack. Encryption is uneven: ZFS native encryption protects `tank`, but its key sits on the same host, NFS crosses the LAN in plaintext, and encryption at rest for `local-path` disks and for Secrets in the k3s datastore is **[UNVERIFIED]**. A past signing-key exposure (Authentik's key was the public literal `MANAGED_BY_DOPPLER`) has been fixed but shows that key material placed in a public repo is the family's most dangerous failure mode.

| Disposition | Count |
|---|---|
| Implemented | 3 |
| Partially implemented | 15 |
| Inherited | 4 |
| Alternative implementation | 1 |
| Not applicable | 2 |
| **Total** | **25** |
### SC-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** SC rules sit in policy §8 (zones), §12 (keys and cryptography) and §15 (external services); procedures are `docs/access-procedures.md`, `docs/ntfy.md` and the app READMEs. DRAFT until merged.

**Evidence.** Policy §8, §12, §15, §21

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All SC.

### SC-2 Separation of System and User Functionality

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** User functions (apps) and management functions are separated: admin UIs are unpublished or bound to `authentik Admins`, and administration goes through Tailscale and SSH. The ArgoCD Ingress is an exception (`G-AC-11`).

**Evidence.** `00-system-description.md` §3

**Gaps.** Covered by `G-AC-11`.

**Related.** AC-6, SC-7.

### SC-4 Information in Shared System Resources

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Shared resources are namespaces, the shared Postgres cluster (one database and role per app), shared Redis and MinIO. Per-app database roles prevent cross-reading inside Postgres. Shared Redis has no per-app isolation recorded **[UNVERIFIED]**.

**Evidence.** `apps/databases/`; `apps/redis/`

**Gaps.**
- `G-SC-01` Shared Redis isolation between apps is not documented. Risk: one compromised app reads another's sessions or cache. Remedy: record per-app DB numbers/ACLs, or move Tier 1 users off the shared instance. Target **2027-03-31**.

**Related.** SC-7.

### SC-5 Denial-of-service Protection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Traefik rate-limits every published route (50 req/s sustained, 100 burst per client) and CrowdSec bans abusive IPs. Volumetric attacks above the home uplink are not mitigated (no upstream scrubbing; availability LOW, S5).

**Evidence.** `apps/traefik/`; `apps/crowdsec/`; `00-system-description.md` §3

**Gaps.** None.

**Related.** SC-7, AC-7.

### SC-7 Boundary Protection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Managed interfaces: one MetalLB IP → Traefik (TLS, rate limit, CrowdSec bouncer in `stream` mode, Authentik forward-auth/OIDC); Tailscale for admin. Internal: default-deny NetworkPolicies. CrowdSec fails open if it dies (by design, `00-system-description.md` §3). Exceptions: remux API without forward-auth (`G-AC-07`), ConvertX published without forward-auth (`G-SI-07`), ArgoCD Ingress (`G-AC-11`).

**Evidence.** `apps/traefik/`; `apps/crowdsec/`; `apps/metallb/`; `apps/*/networkpolicy.yaml`

**Gaps.** Covered by `G-AC-07`, `G-SI-07`, `G-AC-11`, `G-AC-08`.

**Related.** AC-4, SC-7(3)–(8); HS-NET-*.

### SC-7(3) Access Points

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Implemented |

**Implementation.** Public traffic enters only through the Traefik MetalLB address; admin traffic only through Tailscale.

**Evidence.** `00-system-description.md` §3

**Gaps.** None.

**Related.** SC-7.

### SC-7(4) External Telecommunications Services

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Inherited (ISP, Tailscale, AirVPN) |

**Implementation.** External telecommunications are the home ISP link, Tailscale and AirVPN. Each provider's service is inherited; the owner's share is the managed interface (Traefik, Tailscale ACLs, gluetun).

**Evidence.** `02-tailoring.md` §4

**Gaps.** Tailscale ACL review sits with `G-SA-09`.

**Related.** SC-7.

### SC-7(5) Deny by Default — Allow by Exception

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Deny-by-default holds inside the cluster (default-deny NetworkPolicies, measured for non-Helm namespaces) and at the edge (only declared Ingress routes). Helm-deployed namespaces are UNMEASURED (HS-NET-01). Host firewalls on pve and the nas are not documented.

**Evidence.** HS-NET-01

**Gaps.**
- `G-SC-02` Host firewall and listening services on pve, nas and travisbackupserver are undocumented, and no host hardening scan exists (HS-HOST-02, HS-HOST-04). Risk: a service listening on a LAN or tailnet interface is reachable without anyone knowing. Remedy: record `ss -tlnp` per host and a deny-by-default nftables/pve-firewall policy; run a CIS Level 1 scan. Target **2027-03-31**.

**Related.** CM-7, SA-4(9).

### SC-7(7) Split Tunneling for Remote Devices

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** The operator laptop reaches the homelab only through Tailscale while staying on its own network, which is split tunnelling by design. Risk is limited by key-only SSH and Tailscale ACLs; laptop security is `G-AC-15`.

**Evidence.** `AGENTS.md`

**Gaps.** Covered by `G-AC-15`.

**Related.** AC-17.

### SC-7(8) Route Traffic to Authenticated Proxy Servers

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Implemented |

**Implementation.** The torrent stack's outbound traffic is forced through gluetun's AirVPN tunnel (shared network namespace); if the tunnel drops, traffic is dropped, not leaked.

**Evidence.** `apps/downloads/`; `00-system-description.md` §3

**Gaps.** None.

**Related.** SC-7.

### SC-8 Transmission Confidentiality and Integrity

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Public traffic uses TLS from cert-manager/Let's Encrypt; admin traffic uses WireGuard (Tailscale) and SSH; DNS upstream uses DNS-over-TLS to Quad9 (`apps/coredns/coredns-custom.yaml`). NFS between the nas and CT 200 is plaintext over the LAN (policy §12.4). In-cluster traffic (pods to Postgres/Redis) is plaintext on the node network.

**Evidence.** `apps/cert-manager/`; `apps/coredns/`; policy §12.4

**Gaps.**
- `G-SC-03` NFS between nas and CT 200 is plaintext on the home LAN. Risk: any LAN device that is compromised reads or alters C3/C4 file data in transit. Remedy: run NFS over a WireGuard/Tailscale link or NFS with Kerberos `krb5p`, or record a waiver with the LAN as the compensating boundary. Target **2027-03-31**.

**Related.** SC-8(1), SC-28.

### SC-8(1) Cryptographic Protection

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Cryptographic protection in transit as in SC-8, with the NFS exception (`G-SC-03`). Whether DNS-over-TLS is actually on the wire is HS-NET-04 (UNMEASURED).

**Evidence.** HS-NET-04

**Gaps.** Covered by `G-SC-03`.

**Related.** SC-8.

### SC-10 Network Disconnect

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Network sessions end at each component's default timeouts (Traefik, SSH). No explicit idle timeout is configured or recorded.

**Evidence.** —

**Gaps.** Session lifetime tracked as `G-AC-06`.

**Related.** AC-12.

### SC-12 Cryptographic Key Establishment and Management

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Policy §12 governs keys: generation by the tool that uses them, storage in Doppler, escrow of keys whose loss is unrecoverable (ZFS key, borg passphrase, restic password) with verification by test (§12.5). The ZFS key is on the nas itself (`/etc/zfs/keys/tank.key`) with a copy in Doppler. Escrow tests have never been recorded.

**Evidence.** Policy §12; `00-system-description.md` §2.1

**Gaps.**
- `G-SC-04` Escrowed keys (ZFS, borg, restic) have never been tested from their escrow copy. Risk: after a nas loss the backups exist but cannot be decrypted. Remedy: the 6-monthly escrow verification in policy §19, first run with a recorded result. Target **2026-12-31**.

**Related.** CP-9, SC-28.

### SC-13 Cryptographic Protection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S4: no FIPS-validated mode. Uses current standard algorithms: TLS 1.2+ (Traefik, cert-manager ECDSA/RSA certificates), WireGuard, OpenSSH ed25519, ZFS native AES-GCM **[UNVERIFIED]** cipher, restic/borg encryption.

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** None.

**Related.** IA-7.

### SC-15 Collaborative Computing Devices and Applications

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No collaborative computing devices (cameras, microphones) are part of the system.

**Evidence.** `00-system-description.md` §2.1

**Gaps.** None.

**Related.** —

### SC-17 Public Key Infrastructure Certificates

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Inherited (Let's Encrypt) |

**Implementation.** Public certificates come from Let's Encrypt through cert-manager ACME. The owner's share: cert-manager configuration and private keys, which stay in the cluster as Secrets; expiry alerting is not routed (`G-SI-09`).

**Evidence.** `apps/cert-manager/`

**Gaps.** Expiry alerting covered by `G-SI-09`.

**Related.** SC-12.

### SC-18 Mobile Code

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No mobile code policy is meaningful for a server system serving web apps; browser-side code is each app vendor's. The residual risk (a compromised app image serving malicious JS) is covered by SR and SI-7.

**Evidence.** —

**Gaps.** None.

**Related.** SI-7, SR-3.

### SC-20 Secure Name/Address Resolution Service (Authoritative Source)

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Inherited (Cloudflare) |

**Implementation.** Authoritative DNS for `sandstorm.chat` is Cloudflare. DNSSEC status is **[UNVERIFIED]**. The owner's share is the zone records and the API token used by cert-manager.

**Evidence.** `02-tailoring.md` §4

**Gaps.**
- `G-SC-06` DNSSEC on `sandstorm.chat` is unverified. Risk: spoofed answers for the domain. Remedy: check in Cloudflare, enable if off, record it. Target **2027-01-31**.

**Related.** SC-21, SC-22.

### SC-21 Secure Name/Address Resolution Service (Recursive or Caching Resolver)

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Cluster DNS (CoreDNS, taken over from k3s on 2026-09-14) forwards to Quad9 over TLS; whether it validates DNSSEC is **[UNVERIFIED]**. The DoT path's correctness on the wire is HS-NET-04 (UNMEASURED).

**Evidence.** `apps/coredns/`; doctor log 2026-09-14

**Gaps.** Covered by `G-SC-06`.

**Related.** SC-20.

### SC-22 Architecture and Provisioning for Name/Address Resolution Service

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Inherited (Cloudflare) |

**Implementation.** Authoritative DNS redundancy is Cloudflare's. Internal resolution has one CoreDNS deployment on a single-node cluster (S5).

**Evidence.** `apps/coredns/`

**Gaps.** None.

**Related.** SC-20.

### SC-23 Session Authenticity

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Sessions are protected by TLS and by Authentik's signed tokens. Until a fix recorded in `apps/authentik/kustomization.yaml:48-51`, Authentik's secret key — which signs every session and token — was the literal `MANAGED_BY_DOPPLER` in this public repository, so anyone could have forged sessions. It is now injected from a generated secret. Whether all sessions were invalidated and the incident logged is not recorded.

**Evidence.** `apps/authentik/kustomization.yaml:48-51`

**Gaps.**
- `G-SC-07` The Authentik signing-key exposure is not recorded as a security incident, and no check prevents a placeholder or literal key in git. Risk: the same mistake recurs in another chart; past forged sessions cannot be ruled out. Remedy: a doctor-log/incident entry (with `G-IR-14`), and a CI check that rejects known placeholder strings in secret-like Helm values. Target **2026-11-30**.

**Related.** IR-5, SC-12; HS-SEC-01.

### SC-28 Protection of Information at Rest

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** `tank` uses ZFS native encryption (key on the same host, which protects only against a removed disk). The restic repository and borgmatic copy are encrypted. Encryption of `local-path` disks (Postgres, SQLite) and of Secrets in the k3s datastore is **[UNVERIFIED]**.

**Evidence.** `00-system-description.md` §4.1

**Gaps.**
- `G-SC-05` Encryption at rest is unverified for `local-path` disks and the k3s datastore (Secrets). Risk: a stolen pve disk exposes every database and every credential. Remedy: check `k3s secrets-encrypt status` and the pve storage encryption; enable k3s secrets encryption; record results. Target **2027-01-31**.

**Related.** SC-28(1), MP-4.

### SC-28(1) Cryptographic Protection

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** As SC-28: cryptographic protection is in place for `tank` and backups, unverified for the rest.

**Evidence.** —

**Gaps.** Covered by `G-SC-05`.

**Related.** SC-28.

### SC-39 Process Isolation

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** Process isolation is provided by Linux namespaces and cgroups for every container and by the LXC boundary of CT 200; Pod Security admission is enforced per namespace (HS-PSS-01), with privileged namespaces waived (W-04).

**Evidence.** HS-PSS-01, HS-PSS-02; W-04

**Gaps.** None.

**Related.** CM-7.

