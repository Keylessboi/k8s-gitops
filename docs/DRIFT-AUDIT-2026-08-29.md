# Version Drift Audit — 2026-08-29

Audit of every pinned image and chart in `apps/` against upstream latest,
plus the Immich v2.6.3 → v3.1.0 upgrade executed the same day.

Method: GitHub releases API per upstream repo, Docker Hub tags for
docker-hub-only images, `index.yaml` per chart repo. Live versions read
from the cluster (`kubectl get deploy -o jsonpath`) where the manifest
does not pin (Nextcloud's floating `stable` tag).

## Drift table

Sorted by risk-adjusted urgency: security/broken-infra first, then majors
with breaking changes, then minors. "current" = what the repo pins (or, for
floating tags, what actually runs).

### Tier 1 — on fire / broken now

| app | current | latest | delta | breaking? | notes |
|---|---|---|---|---|---|
| **MinIO (NAS, 192.168.1.67:9000)** | — | — | — | — | **Cluster health endpoint returns 503; writes fail with `SlowDownWrite`.** Both backup paths (CNPG barman WAL archiving + pgdump restic) are down. Last good CNPG backup 2026-08-29 03:15 UTC; last good pgdump 2026-08-28 18:40. This is NAS-side (disk full or erasure-set degraded) — fix before anything else; until then the cluster has no working backup destination. |
| **pgdump-backup CronJob** | restic 0.17.3 | 0.19.1 | 2 minors | no | 3 consecutive failures (BackoffLimitExceeded), same root cause as above — restic cannot write to MinIO. |
| **octo-fiesta** | `:latest` | v0.10 | unknown | — | **Repo-convention violation: the only `:latest` pin in the repo.** Running version is unknowable and un-reproducible. Pin to `v0.10` (or a digest). |
| **nextcloud image tag** | `stable` (runs 34.0.3) | 34.0.3 | app current | — | App is current but the tag floats — a `stable` repush changes the running server with no git diff, defeating the whole pinning scheme. Pin the tag (e.g. `34.0.3`) and bump deliberately. |

### Tier 2 — majors behind, breaking changes documented

| app | current | latest | delta | breaking? | notes |
|---|---|---|---|---|---|
| immich (server + ML) | v2.6.3 | v3.1.0 | 1 major | YES | **Upgraded this run — see below.** |
| nextcloud chart | 6.6.10 | 9.2.6 | 3 chart majors | YES | Chart 7/8/9 each carry breaking values changes; server itself is current. Read the three chart majors' CHANGELOGs before bumping. |
| calibre-web-automated | V3.1.4 | v4.0.6 | 1 major | YES | V4 changed the DB/layout; read its release notes, take a library + DB backup first. |
| authentik | 2025.6.4 | 2026.8.0 | 14 months of calver | YES | Crosses multiple yearly-schema migrations (2025.6 → 2026.8). Authentik requires sequential major-version upgrades and blue/outpost compatibility checks. It is the SSO everything defers to — schedule a window, snapshot the DB first. |
| loki chart | 6.30.1 | 7.3.0 | 1 chart major | YES | Loki 3.x storage-schema changes; single-binary S3 setup needs a values review. |
| alloy chart | 0.12.6 | 1.12.1 | 0.x → 1.x | YES | 1.0 renamed several values; collector config rewrite risk. |
| traefik chart | 33.2.1 | 41.4.0 | 8 chart majors | YES | App is v3.x throughout (current v3.7.12), so the risk is chart-values churn, not the proxy itself. Bump one major at a time; the crowdsec plugin pin (v1.7.1) is already latest. |
| kube-prometheus-stack | 75.18.1 | 88.6.1 | 13 chart releases | YES (CRDs) | CRD upgrades must be applied manually (helm does not touch CRDs); Prometheus rules/recording-rule renames between 75→88. |
| redis | 7.4-alpine | 8.10.1 | 1 major | YES | Deliberately pinned (data service). Redis 8 changes licensing and adds new data types; every app shares this instance — plan a maintenance window. |
| vectorchord (CNPG cluster image) | 16-0.4.1 | VectorChord 1.1.1 / PG 17/18 images | PG major + ext major | YES | PG major upgrade = pg_upgrade via CNPG (requires full backup chain working — currently broken, see Tier 1). Owner decision: stay on PG16 + bump VectorChord, or jump PG majors too. |

### Tier 3 — minors behind, no documented breaking changes

| app | current | latest | delta | breaking? | notes |
|---|---|---|---|---|---|
| cert-manager | v1.16.3 | v1.21.1 | 5 minors | no | API stable across these; routine bump. |
| cnpg chart | 0.23.2 | 0.29.0 (operator 1.30.0) | 6 chart minors | no | Operator is backward-compatible; check the 1.27–1.30 notes for barman changes (relevant while backups are broken). |
| metallb | 0.14.9 | 0.16.1 | 2 chart minors | check | 0.15/0.16 changelog skim recommended; config CRDs stable. |
| doppler operator | 1.5.7 | 1.7.1 | 2 minors | check | Routine. |
| nfs-csi | v4.9.0 | v4.13.4 | 4 minors | no | Routine. |
| navidrome | 0.58.0 | 0.63.2 | 5 minors (0.x) | check | 0.x project — skim notes; music DB is small, backup is cheap. |
| beets | 2.2.0 | 2.13.1 | 11 minors | check | Plugin behavior changes likely across 11 minors; the beets-import CronJob depends on CLI behavior. |
| qbittorrent | 5.1.2 | 5.2.3 | 2 minors | no | Image Updater would do this itself if lscr.io rate-limits didn't block its tag lookups (see below). |
| slskd | 0.23.2 | 0.26.0 | 3 minors | 0.x risk | Deliberately pinned to the 0.23 patch stream by the ImageUpdater policy; widening `allowTags` to `^0\.2[4-6]\.` is an owner call after reading 0.24–0.26 notes. |
| qui | v1.26.0 | v1.27.0 | 1 minor | no | Image Updater covers this; blocked by the same lscr.io issue? No — qui is ghcr.io; it just hasn't reconciled a preference yet. |
| kiwix-serve | 3.7.0 | 3.8.2 | 2 minors | no | Routine. |
| restic (pgdump) | 0.17.3 | 0.19.1 | 2 minors | no | Bump when the CronJob is fixed. |
| busybox (init) | 1.36 | 1.38.0 | 2 minors | no | Cosmetic. |
| python (jobs) | 3.12-slim | 3.14 (3.12 still supported) | 2 minors | no | No urgency. |
| curl (kiwix sidecar) | 8.11.1 | 8.21.0 | 10 minors | no | No urgency. |
| minio/mc (vaultwarden backup) | RELEASE.2025-04-16 | RELEASE.2025-08-13 | 4 months | no | Bump with the next vaultwarden backup review. |
| hermes-agent | v2026.8.19 | v2026.8.27 | 8 days (calver) | no | Routine. |
| argocd-image-updater chart | 1.2.4 (app v1.2.2) | 1.2.4 (app v1.3.0) | chart current, app 1 minor | no | Chart hasn't shipped 1.3.0 yet. |

### Current (no action)

forgejo 16.0.3, jellyfin 10.11.11, vaultwarden (oidcwarden) v2026.8.0-1,
gluetun v3.41.3, flaresolverr v3.5.0, convertx v0.18.0, bitmagnet v0.10.0
(upstream quiet since 2025-03), book-downloader v1.3.12, aiostreams v2.33.2,
bgutil-pot 1.3.2, pelican v1.0.0-beta38, seedboxapi 20250413-0519 (upstream
stale since 2025-04), prowlarr 2.5.2.5491-ls156 (= upstream stable),
crowdsec chart 0.24.0 / agent v1.7.8, immich chart 0.12.0 (latest chart;
images now pinned explicitly ahead of it), traefik crowdsec-bouncer-plugin
v1.7.1, lidarr testing-3.1.3.4987 (ahead of stable v3.1.0.4875 on its chosen
channel).

### Dead upstream — owner decision

| app | current | notes |
|---|---|---|
| readarr | 0.4.19-nightly | Upstream Readarr/Readarr was **archived 2025-06**; 0.4.19-nightly is the final state. No updates will ever come. Decide: keep frozen, or migrate to a successor (community forks / Lidarr-books). |

## Immich upgrade story (executed 2026-08-29)

Path: v2.6.3 → v2.7.5 → v3.0.3 → v3.1.0, one commit per step, ArgoCD sync +
pod/log/HTTP verification after each.

Pre-flight:
- Chart 0.12.0 is the latest chart; its appVersion (v2.6.3) was what ran.
  Images are now pinned explicitly via `controllers.main.containers.main.image.tag`
  and `machine-learning.controllers.main.containers.main.image.tag` so
  upgrades can move ahead of the chart.
- v3.0.0 breaking changes checked against this deployment: DB already on
  VectorChord (`vchord 0.4.1` — pgvecto.rs drop is a no-op); node CPU meets
  x86-64-v2 (sse4_2/popcnt present); none of the removed env vars
  (`IMMICH_MACHINE_LEARNING_PING_TIMEOUT`, `MACHINE_LEARNING_PRELOAD__*`)
  are set; OAuth issuerUrl is a valid https URL and `allowInsecureRequests`
  default (false) is fine; API endpoint changes affect third-party API
  consumers only — none declared in the repo; immich metrics are disabled so
  the metric-name renames touch no dashboard.
- **Backup**: MinIO was down (see Tier 1), so the CNPG on-demand backup
  stalled in `walArchivingFailing` and the pgdump CronJob could not write
  either. A fresh logical backup was taken directly instead: `pg_dump -Fc`
  of every database + `pg_dumpall --globals-only`, streamed off
  `app-databases-1` to the operator host (`/tmp/opencode/backups/`,
  immich dump 16.9 MB, PGDMP magic verified). No destructive step ran before
  that existed.

Commits (all on main):
1. `a9efd6b` — immich: v2.6.3 → v2.7.5 (step 1 of 3)
2. `dcbfcb9` — immich: v2.7.5 → v3.0.3 (step 2, crosses the v3 major)
3. `7273dff` — immich: v3.0.3 → v3.1.0 (step 3, latest stable)

Verification per step (evidence):
- ArgoCD: each step ended `Synced Healthy` at the pushed sha (ArgoCD sat
  Synced-but-stale twice; forced with the documented
  `kubectl patch application immich` operation trigger).
- Pods: server + ML `1/1 Running`, 0 restarts, on the new tag, old pods gone.
- Migrations: "Running migrations … succeeded … Finished running migrations"
  in server logs each step; v3.0.3 ran the v3 schema set
  (PartnerAssetSyncReset, UpdateWorkflowTables, AssetOcrSync,
  CreateIntegrityReportTable, …); `immich-admin schema-check` after the final
  step: "Migrations are up to date. No schema drift detected."
- Bootstrap: "Immich Microservices is running [v3.1.0] [production]".
- HTTP: `https://immich.sandstorm.chat/` 200 and
  `/api/server/ping` → `{"res":"pong"}` after the final step.
  (One 403 window during step 1 was the concurrent crowdsec-lapi rollout
  failing closed at the edge — unrelated to Immich, self-recovered.)

Final version: **v3.1.0** (server + ML in lockstep).

Rollback path if ever needed: re-point the two `tag:` values in
`apps/immich/kustomization.yaml` at v2.6.3 and restore
`pre-immich-immich.dump` + globals into a fresh DB — the v3 migrations are
not reversible in place, which is why the dump was taken first.

## ArgoCD Image Updater status

- Controller runs and reconciles (5–6 apps, 8–9 images considered, 0 errors
  in steady state).
- **The write deploy key still does not exist.** The `image-updater/image-updater-git`
  secret contains only Doppler metadata keys (`DOPPLER_CONFIG`,
  `DOPPLER_ENVIRONMENT`, `DOPPLER_PROJECT`) — no SSH private key. `scripts/setup-image-updater-key.sh`
  was never run. The updater therefore could not write back even if it found
  an update.
- It has never needed to: 0 images updated so far, partly because lscr.io
  rate-limits (44000/min shared pool) reject its tag lookups for
  qbittorrent/beets roughly hourly (`toomanyrequests` in the logs), so those
  two never even get a candidate list.
- Net: the updater is currently decorative. It needs (a) the deploy key
  minted, (b) the lscr.io rate-limit issue addressed (registry creds or
  reduced reconcile frequency), before it can do its job.

## Renovate recommendation (go/no-go)

**Go — adopt Renovate, but scoped and sequenced.** This audit found 20+
drifting pins and two pins that violate the repo's own no-floating-tag rule;
the Image Updater cannot be the fix because it only covers a subset of
images, cannot touch chart versions at all, and has never had write access.
Renovate handles both worlds (Docker digests *and* Helm chart versions),
respects the existing pin discipline via config, and — critically for this
repo — can be configured to group nothing, automerge nothing, and open PRs
only, which fits the "one commit per version step, human-verified" Immich
workflow used here. Run it in dry-run/PR-only mode with a `helmCharts` +
`docker` manager config that encodes the same major-pinning the ImageUpdater
CRs express (e.g. `allowedVersions` per dependency), and let it replace the
Image Updater entirely once the deploy-key question is settled — running
both would just create write contention on main. Owner effort: one
`renovate.json`, a GitHub App install, and an hour of triage per week.

## Owner actions

1. **Fix MinIO on the NAS (192.168.1.67:9000)** — cluster health 503,
   writes rejected. Until then the cluster has no working backup path
   (barman WAL + restic both fail). This is the single most urgent item.
2. **After MinIO is fixed**: verify the pgdump CronJob goes green, confirm a
   new CNPG base backup completes, and re-establish the WAL chain (the WAL
   gap since 2026-08-29 03:15 means PITR is impossible for that window).
3. **Mint the Image Updater deploy key** (`scripts/setup-image-updater-key.sh`)
   or decommission the updater in favor of Renovate — do not leave it
   half-wired.
4. **Adopt Renovate** (recommendation above).
5. **Pin octo-fiesta** to `v0.10` (or a digest) — the only `:latest` in the
   repo.
6. **Pin the Nextcloud image tag** to `34.0.3` instead of `stable`, then
   plan the chart 6.6.10 → 9.2.6 jump separately.
7. **Decide Readarr's fate** — upstream is archived; keep frozen or migrate.
8. **Schedule the authentik 2025.6.4 → 2026.8.0 upgrade** — the largest
   remaining breaking-change jump (SSO for everything; DB snapshot first,
   follow its sequential-major rules).
9. **Plan the remaining chart majors** (traefik 33→41, kube-prometheus-stack
   75→88 with manual CRD apply, loki 6→7, alloy 0.12→1.12, nextcloud chart).
10. **Owner decision: PostgreSQL/VectorChord major** — stay on PG16 and bump
    VectorChord to 1.x, or plan a CNPG pg_upgrade to PG17/18 (requires the
    backup chain from #1 working first).
11. **Mobile apps**: after the Immich v3 upgrade, phone clients must be on
    the v3-compatible release (v2-era clients had album breakage fixed
    server-side in v3.0.1, but the legacy timeline is gone in v3 mobile).
