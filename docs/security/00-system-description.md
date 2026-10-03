# 00 — System Description

**Part of:** the Homelab Information Security Program (see `README.md` in this
directory) · **Version:** 0.1 draft · **Last verified:** 2026-10-01

This is the system description section of the System Security Plan (SSP). It
says what the system is, where its boundary runs, what it holds, who and what
can touch it, and how data moves. Every statement here was verified against
the repository or the running environment on the date above. Anything not
verified says **[UNVERIFIED]**. A control implementation in `ssp/` may only
rely on a fact that appears here, or on evidence it cites itself.

## 1. System identification

| Field | Value |
|---|---|
| System name | Sandstorm Homelab (`*.sandstorm.chat`) |
| System type | Single-operator self-hosted platform: GitOps-managed Kubernetes, storage, and supporting hosts |
| Operational status | Operational |
| System owner, authorizing official, security officer | The owner (one person holds every role; see `01-policy.md` §3) |
| Configuration source of truth | `github.com/Keylessboi/k8s-gitops` (public repository), branch `main` |
| Security categorization | **MODERATE** (FIPS 199; derivation in `01-policy.md` §4) |
| Control baseline | NIST SP 800-53 Rev. 5 MODERATE, tailored (`02-tailoring.md`) |

## 2. Authorization boundary

### 2.1 Inside the boundary

| Component | Role | Location / identity | Notes |
|---|---|---|---|
| **pve** | Proxmox VE hypervisor | Dell Vostro 3681, LAN `192.168.1.153`, Tailscale `100.125.108.56` | No IPMI/BMC. BIOS settings are changed from the running OS with `smbios-token-ctl`. SSH as `root`. |
| **CT 200** | The k3s server (control plane and main worker) | LXC container on pve, LAN `192.168.1.172` | `onboot: 1` since 2026-09-05. k3s `v1.31.5+k3s1`. Bundled Traefik disabled; CoreDNS taken over from k3s on 2026-09-14. |
| **nas** | Storage node and second k3s node | Arch Linux, LAN `192.168.1.67`, Tailscale `100.69.240.8` | ZFS pool `tank` (mirror, ADR-0001) with native encryption; key at `/etc/zfs/keys/tank.key` on the nas, copy in Doppler. Serves NFS (nfs-ganesha) and MinIO. SSH as `travis`; privilege escalation via `doas`, which prompts for a password. Carries the taint `storage=true:NoSchedule`. Runs the external watchdog and Pelican Wings (ADR-0011). |
| **travisbackupserver** | Off-site edge probe and notification relay | Debian 13, different site (Long Island), Tailscale `100.81.123.74` | Runs ntfy and an edge probe. fail2ban active. SSH as `root`. |
| **Kubernetes workloads** | 35 ArgoCD Applications, one per `apps/*` directory | Namespaces declared under `apps/*/namespace.yaml` | Inventory in §4. |
| **Operator workstation** | Where the owner and the AI agents work | Laptop, on a *different* L2 segment that reuses `192.168.1.0/24` | Reaches the homelab only over Tailscale. Holds the SSH key (`~/.ssh/worker_key`), a kubeconfig, a Doppler CLI login and GitHub credentials. |

### 2.2 Outside the boundary (external services the system depends on)

Each is an interconnection. Its controls are **inherited** or **not
controlled**, as recorded in `02-tailoring.md`.

| Service | Used for | Data that crosses |
|---|---|---|
| GitHub (`Keylessboi/k8s-gitops`, Actions) | Source of truth, CI | Configuration, which is public. Never credentials (HS-SEC-01). |
| Doppler (projects `kubernetes`, `proxmox`) | Secret store; synced into Kubernetes by the Doppler operator | Every credential the cluster uses |
| Tailscale | Administrative network between laptop, pve, nas and the backup server | Admin traffic, off-site backup stream |
| Cloudflare | Public DNS for `sandstorm.chat` | DNS records |
| Let's Encrypt (via cert-manager) | Public TLS certificates | Certificate requests |
| AirVPN | Egress tunnel for the torrent stack (gluetun) | Peer-to-peer traffic |
| Container registries (Docker Hub, ghcr.io, others) | Image pulls | Image references |
| Anthropic / other model providers | AI agents operating the system | Whatever an agent reads into its context. This is why HS-SEC-03 exists. |
| Off-site borgmatic target | Off-site backup copy, nightly over Tailscale | Encrypted backup data. **[UNVERIFIED]**: which host receives it. |

## 3. Network architecture

- **Public ingress:** a MetalLB IP fronts Traefik, which terminates TLS for the
  published hosts. Every published route has rate limiting (50 req/s
  sustained, 100 burst, keyed on the forwarded client address). CrowdSec
  reads Traefik's access logs, and its bouncer blocks in `stream` mode, so
  protection degrades rather than failing closed if CrowdSec dies. The
  cluster and LAN ranges are trusted and cannot be bounced. Geo-blocking is
  deliberately off.
- **Authentication at the edge:** most published apps sit behind Authentik
  forward-auth or OIDC. Exceptions by design: `blog.sandstorm.chat` (Ghost,
  public site) and `kiwix.sandstorm.chat` (no login). Since 2026-09-04,
  admin-type apps (Grafana, Alertmanager, Lidarr, Prowlarr, bitmagnet, qui,
  accounts) are bound to the `authentik Admins` group. Before that, every
  Authentik user could reach every app. Pelican, Forgejo and bookdl are open
  to any Authentik user, pending the owner's decision (`docs/accounts.md`).
- **Not published:** ArgoCD, Prometheus, FlareSolverr, the bgutil provider,
  and the slskd and qBittorrent web UIs are reached by port-forward or over
  Tailscale only.
- **In-cluster segmentation:** every namespace has at least one NetworkPolicy
  (measured on the 22 namespaces declared outside Helm). Cross-namespace
  flows must be declared on both ends; CI checks this. kube-router enforces
  the policies, and REJECTs read as `connection refused`.
- **Torrent egress:** qBittorrent shares a pod network namespace with gluetun,
  so it has no route out except the AirVPN WireGuard tunnel. If the tunnel
  drops, traffic is dropped, not leaked.
- **Administrative path:** laptop → Tailscale → pve (root) →
  `pct exec 200 -- kubectl` (cluster-admin). In practice this is the normal
  path for both the owner and agents today. It is broader than it should be;
  see HS-SEC-04 and HS-AGENT-09.

## 4. Component and data inventory

**Tier** is the criticality tier and **Class** the highest data classification
held. Both are defined in `01-policy.md` §5–6. Tier 0 is foundational: if it
fails, everything does.

| App (`apps/*`) | What it is | Data held | Class | Tier |
|---|---|---|---|---|
| argocd (hand-applied) | GitOps reconciler | Cluster desired state, repo credentials | C4 | 0 |
| cnpg | CloudNativePG operator | — | C2 | 0 |
| databases | Central CNPG Postgres cluster; pg_dump, restore drill, backup freshness | Every app database: Vaultwarden vault, Authentik, Immich catalogue, Nextcloud, Memos, others | **C4** | 0 |
| doppler | Doppler operator | Syncs credentials into Secrets | C4 | 0 |
| nfs-csi | NFS CSI driver | — | C2 | 0 |
| metallb | Bare-metal load balancer | — | C2 | 0 |
| coredns | Cluster DNS | DNS queries | C2 | 0 |
| traefik | Ingress controller | Access logs (client IPs, URLs) | C3 | 0 |
| cert-manager | TLS issuance | TLS private keys | C4 | 0 |
| authentik | SSO / identity provider (server, worker, Postgres, Redis) | User identities, password hashes, sessions, OIDC client secrets | **C4** | 1 |
| vaultwarden | Password manager | Users' encrypted vaults (in Postgres), attachments on an NFS claim | **C4** | 1 |
| crowdsec | Edge detection and blocking | Attacker IPs, decisions | C2 | 1 |
| accounts | Account-provisioning tool (Authentik + remux) | Handles new users' passwords in transit | C4 | 1 |
| monitoring | Prometheus, Grafana, Loki, Alloy, Alertmanager | Metrics and logs from every node (logs may contain C3) | C3 | 1 |
| image-updater | ArgoCD Image Updater; commits tag bumps to git | Git write credential | C4 | 1 |
| immich | Photo library (server, worker, ML) | Personal photos and videos, face data | **C3** | 2 |
| nextcloud | Files and office | Personal files (in MinIO S3), DB in shared Postgres | **C3** | 2 |
| memos | Per-user notes, OIDC | Personal notes | C3 | 2 |
| notesnook | End-to-end-encrypted notes sync (+ MinIO, MongoDB) | Ciphertext of personal notes | C3 | 2 |
| redis | Shared Redis | Caches and sessions | C3 | 2 |
| ghost | Public blog (single pod, SQLite on a PVC) | Published posts (C1), staff accounts and drafts (C3) | C3 | 3 |
| pelican | Game-server panel (Wings on the nas) | Panel accounts, game-server data | C3 | 3 |
| navidrome | Music streaming | Library index, users' play history | C3 | 3 |
| remux | Jellyfin-compatible media server, via AirVPN | Watch history, mirrored accounts | C3 | 3 |
| lidarr, prowlarr, bitmagnet, flaresolverr, downloads, books, music, kiwix, convertx, hermes, spatial-sidecar, applemusic-wrapper | Media acquisition, processing and serving | Media library, indexer API keys, tracker passkeys | C2 (API keys and passkeys are C4) | 3 |

### 4.1 Data stores

| Store | Where | Holds | Encrypted at rest |
|---|---|---|---|
| ZFS pool `tank` | nas | All NFS volumes, MinIO data, media | Yes, ZFS native. Key on the same host. |
| CNPG Postgres | `local-path` on the node running it (ADR-0009) | All app databases | **[UNVERIFIED]**: depends on the node's disk |
| MinIO | nas (on `tank`) | CNPG WAL and base backups, restic pg_dump repo, Nextcloud files, ZIM files | Via `tank`; restic repo also encrypted |
| `local-path` PVCs | node local disks | App configs, SQLite (Ghost), Immich thumbnails, others | **[UNVERIFIED]** |
| etcd / k3s datastore | CT 200 | Every Kubernetes object, including Secrets | **[UNVERIFIED]**: whether k3s secrets-encryption is enabled |
| Doppler | SaaS | Every credential | By the provider (inherited) |
| Git repository | GitHub, public | Configuration and docs | Public by design. Must never hold a credential. |
| Agent transcripts | laptop `~/.claude/projects/*.jsonl` and the model provider | Anything an agent read | Laptop disk **[UNVERIFIED]** |

### 4.2 Backup architecture (as documented in `docs/RUNDOWN.md`)

| Layer | Target | Cadence | Verified by |
|---|---|---|---|
| CNPG WAL + base backups | MinIO `s3://cnpg-backups/app-databases` | Continuous WAL, scheduled base | `WALArchiverFailing`, `BackupTooOld` alerts |
| Logical `pg_dump`, every database | restic repo in MinIO (deduplicated, encrypted) | Daily; keep 8 latest / 7 daily / 4 weekly / 6 monthly | `backup-freshness` CronJob; monthly restore drill |
| ZFS snapshots of `tank` | nas | sanoid schedule | **[UNVERIFIED]** |
| Off-site | borgmatic over Tailscale | Nightly, 1 MB/s | **[UNVERIFIED]**: no freshness alert found |

The **restore drill** (`apps/databases/restore-drill-cronjob.yaml`, monthly)
streams every dump through `pg_restore`, and fully restores dumps under 300 MB
into `drill_`-prefixed scratch databases. Last recorded run: 17 checked, 16
fully restored, 1 integrity-verified, 0 failures.

## 5. Users and non-person entities

| Identity | Kind | Access | How it authenticates |
|---|---|---|---|
| Owner | Person | Everything; holds every role | SSH key `worker_key`; Authentik `akadmin`; Doppler, GitHub, Tailscale accounts. MFA status **[UNVERIFIED]** for each. |
| Service users (friends and family) | People | Apps their Authentik groups allow | Authentik password; MFA **[UNVERIFIED]**. Created via `accounts.sandstorm.chat`. |
| AI coding agents (Claude Code, opencode, Codex, Gemini) | Non-person, act as the owner | Whatever the owner's laptop credentials reach: cluster-admin, root on pve, git push | The owner's credentials. No separate identity yet. |
| GitHub Actions | Non-person | Read the repo, run CI | `contents: read` token |
| ArgoCD | Non-person | Cluster-wide apply and prune | In-cluster ServiceAccount |
| argocd-image-updater | Non-person | Writes tag bumps to git | Git credential (C4) |
| Renovate | Non-person | Opens dependency PRs | GitHub App |
| Doppler operator | Non-person | Writes Secrets | Doppler service token (C4) |

## 6. Data flows that matter for security

1. **Change:** author (person or agent) → commit → GitHub → ArgoCD polls `main`
   → applies with prune and selfHeal, live within about 3 minutes. No
   staging. CI runs in parallel and **does not gate** the apply (HS-GIT-03).
2. **Secrets:** Doppler → Doppler operator → Kubernetes Secret → pod
   environment or volume. A secret never passes through git.
3. **User request:** internet → Traefik (rate limit, CrowdSec bouncer) →
   Authentik forward-auth or OIDC → app.
4. **Backup:** Postgres → MinIO on `tank` (WAL, base, restic) → ZFS snapshot →
   borgmatic off-site over Tailscale.
5. **Alerting:** Prometheus → Alertmanager → ntfy/email. A heartbeat from inside
   the cluster reaches the external watchdog on the nas, which alerts through
   ntfy when the heartbeat stops.
6. **Agent context:** anything an agent prints is stored in its transcript on
   the laptop and sent to the model provider. That makes the transcript a C4
   data store whenever a secret is printed.

## 7. Known discrepancies found while writing this

These go to the plan of action and milestones (`04-poam.md`):

1. `docs/access-procedures.md` tells the reader to print the ArgoCD admin
   password (`kubectl get secret … | base64 -d`). That contradicts HS-SEC-03
   and invites agents to read secrets.
2. `docs/access-procedures.md`, "Emergency Bypass", deletes an Application
   with `--cascade=background`. With the resources finalizer, that deletes the
   app's namespace and PVCs. It must be `--cascade=orphan`.
3. `docs/access-procedures.md`, "Restore Procedure", re-applies ArgoCD from the
   unpinned `stable` manifest rather than the pinned `v2.12.3`.
4. `docs/access-procedures.md`, "Maintenance Windows", names an
   `#ops-alerts` channel and a Sunday window that nothing else in the repo
   mentions. Probably template text. **[UNVERIFIED]**
5. `docs/RUNDOWN.md` tells the reader to `grep -i password` in qBittorrent's
   logs.
6. `AGENTS.md` said "Images are pinned by digest". Measured: 16 of 85
   containers in the non-Helm apps are.
