# Phase 1 / Phase 2 Verification

Checked against the real plans (`~/.omo/plans/kubernetes-gitops.md`, `~/.omo/drafts/kubernetes-phase2.md`) rather than a summary of them, and verified against the running cluster.

## Phase 1 — Met

| Requirement | Evidence |
|---|---|
| ArgoCD app-of-apps + ApplicationSets | 23 apps, all Synced/Healthy |
| CNPG: one cluster, all DBs, per-app roles | `app-databases`, 6 app databases |
| Redis: one shared instance | `redis-master`, single StatefulSet |
| Doppler secrets operator | syncing 8 DopplerSecrets; nothing secret in git |
| Authentik SSO (OIDC + forward-auth) | 9 apps, OIDC and proxy providers |
| CrowdSec | LAPI + agent, bouncer registered and pulling |
| NetworkPolicies per app | every namespace has `app-isolation` |
| PSA baseline | enforced per namespace (monitoring is `privileged` — node-exporter needs it) |
| ZFS AES-256-GCM at rest | `tank` encrypted |
| TLS via cert-manager | 13 certificates, all Ready |
| **etcd snapshots to MinIO S3** | 6-hourly, 9 snapshots in `s3://etcd-snapshots/`, retention 24 |
| Monitoring: Prometheus, Grafana, Loki, **Alloy** | all running; Loki chunks on S3 |
| Borg backup off-site | nightly, rate-limited |
| Kiwix, Nextcloud, Immich, Lidarr, Prowlarr, FlareSolverr | deployed and reachable |
| **Email via Gmail app password** | Authentik, Vaultwarden, Grafana — added this session |
| Tailscale on NAS | in place |

## Phase 1 — Not Met

| Gap | Detail |
|---|---|
| **S3 primary storage** | The plan calls for MinIO S3 as primary with *NFS fallback for media streaming only*. Reality is the inverse: 22 PVCs on NFS, S3 used only for CNPG backups, restic and Loki chunks. Nextcloud's `objectstore` is unset. JuiceFS was the intended gateway for S3-incompatible apps and was rejected for a sound reason (its metadata lives in the same Postgres it would back, so Vaultwarden's volume would depend on Vaultwarden's own database) — but the goal was never re-solved. Nextcloud and Immich both speak S3 natively and could move without a gateway. |
| **smartctl_exporter** | Not deployed. No disk SMART metrics, so a failing drive is invisible. |
| **ArgoCD Image Updater** | Not deployed. Image bumps are manual. |
| **Navidrome SQLite → PostgreSQL** | Not done. Still `/data/navidrome.db`; no `navidrome` database in the CNPG cluster. The plan specifies a pgloader migration. |
| Per-app Grafana dashboards | 29 dashboards exist but they are kube-prometheus-stack's generic set plus one homelab overview. No per-app dashboards (Lidarr, Immich, etc). |

## Deliberately Dropped (Owner's Decision, Not Gaps)

- **Pangolin** — removed; Traefik middlewares do the same job declaratively in git.
- **Geo-blocking** — explicitly not wanted.
- **Extra k3s agents** (phones, Pi, DL360P) — owner handling separately.

## Leftover to Clean

- A `juicefs` database and role still exist in the CNPG cluster from the rejected JuiceFS evaluation.

## Phase 2 — Music Scope Only

Delivered: Tubifarry (C3, partial — MCP not deployed), Slskd (C4, on AirVPN rather than WARP, which the plan anticipated as the upgrade path), Beets (C5), Octo-Fiesta (C6), Calibre-Web Automated (C18), Prowlarr (C20).

Not started: Funkwhale (C1), ListenBrainz (C2), Lidarr MCP (C3), Real-Debrid/zurg (C7), Tor hidden services (C8), Vikunja (C9), Homarr (C10), Headscale (C11), Matrix (C12), XMPP (C13), Checkmate (C14), OpenTripPlanner (C15), Radicle (C16), librarr (C17 — a different book downloader was used), Forgejo (C19).
