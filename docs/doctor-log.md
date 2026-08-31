# Doctor's log

One entry per incident: symptom first, then root cause, then the fix that
solved it, then what prevents a repeat. Newest first. If an incident
repeats, link the entries — a repeated incident means the prevention
failed and the entry needs revisiting.

## 2026-08-29 — Wings image pulls tripped kubelet DiskPressure; CNPG primary evicted

- **Symptom:** while pre-pulling game-server Docker images on the node
  (Wings deploy, ADR-0006), `app-databases-1` went Pending and the Pelican
  panel's DB connections were refused. The node carried the
  `node.kubernetes.io/disk-pressure` taint; the kubelet log showed a full
  ephemeral-storage eviction pass (funkwhale, invidious, metallb-speaker and
  others evicted or denied admission).
- **Root cause:** the node rootfs hit 93% during the pulls. k3s's kubelet
  eviction-hard is nodefs/imagefs < 5% free (verified via configz), and at
  93% used the threshold crossed. The DiskPressure taint evicted the CNPG
  primary; with the taint set, the pod could not reschedule.
- **Fix:** freed space on the node — journal vacuum, `k3s crictl rmi --prune`
  (old funkwhale/loki layers), `apt-get clean`, `fstrim` (returned ~12 GB to
  the thin pool). At 12 GB free (19%) the taint cleared after kubelet's
  5-minute `EvictionPressureTransitionPeriod`, and the pod rescheduled on its
  own. No data lost; CNPG re-joined as primary.
- **Prevention:** the node disk governor (ADR-0006): keep the rootfs above
  10% free, check `df -h /` before any large pull, and keep the panel's node
  disk allocation capped (10240 MiB, 0% overallocate). The kubelet's real
  threshold is 5%, not the 10%/15% upstream defaults — k3s overrides it.

## 2026-08-29 — One-off pods mounting NFS exports vanish; do host-side surgery instead

- **Symptom:** four standalone diagnostic pods (restoring the Jellyfin admin
  password) each vanished within ~2 minutes of becoming Ready — across two
  namespaces, with and without resource guarantees, while a control canary
  with no volume mounts in the same namespace survived indefinitely. The
  slskd-rotation agent's temp pod in lidarr (no NFS mount) also survived a
  full session. Deleter unidentified: no events, no controller claims, no
  eviction records.
- **Pattern:** every vanished pod mounted an NFS-backed volume (the
  jellyfin-config PVC or a raw NFS export).
- **Fix:** one-off DB surgery runs on the NAS itself — the NFS exports are
  mounted locally (`/extra/nfs-csi/...`), and `doas python3` + sqlite3 edits
  the same files the pods were trying to reach. Worked first try once `doas`
  was used (unprivileged writes fail: the files are owned by uid 1000 and
  travis is not).
- **Prevention:** for maintenance on NFS-backed data, prefer host-side
  execution over diagnostic pods. The vanishing-pod anomaly stays open —
  the next sighting should capture `kubectl get pod -w` output plus events
  and a `ps` of the kubelet.

## 2026-08-29 — Manual CronJob run deleted itself in 2 seconds

- **Symptom:** `kubectl create job --from=cronjob/pgdump-backup` for a
  post-recovery backup check — the pod was created, started, and killed
  within 2 s, followed by `BackoffLimitExceeded` with no container error.
- **Root cause:** `--from=` jobs get an `ownerReference` to the CronJob.
  Under `concurrencyPolicy: Forbid` the CronJob controller treats such a
  job as unexpected (`Saw a job that the controller did not create or
  forgot`) and garbage-collects it.
- **Fix:** strip the ownerReference right after creating:
  `kubectl -n databases patch job <name> --type=json -p '[{"op":"remove","path":"/metadata/ownerReferences"}]'`.
- **Prevention:** the strip step is part of the manual-run procedure
  (documented on issue #1).

## 2026-08-29 — MinIO saw zero drives; every backup failed silently for ~20 h

- **Symptom:** CNPG WAL archiving refused (`SlowDownWrite`), pgdump CronJob
  failed 3× (restic → MinIO), `/minio/health/cluster` returned 503 while
  `live` and `ready` returned 200. Discovered indirectly while taking a
  pre-upgrade backup for Immich.
- **Root cause:** two defects stacked. (1) MinIO's data lived on the boot
  disk at `/tank/minio`, not on the pool — the tank datasets mount inside
  `/tank` and shadowed it after import. (2) The pool did not auto-import
  after the unclean reboot, MinIO started 39 s in, and when the pool was
  manually imported ~40 min later the mount shadowed MinIO's drive path:
  `drives-online: 0`, write and read quorum gone, no restart, no alert.
- **Fix:** data copied to the pool (`cp -a` of the shadowed dir, 1.9 G →
  912 M on-disk under zstd), MinIO restarted — health 200, WAL shipped
  within minutes. `minio.service` drop-in `RequiresMountsFor=/tank/minio`
  so it can never start before its volume; `zfs-load-key.service` (see the
  closet-move entry) so the pool self-imports.
- **Prevention:** boot-order drop-in + auto-key-load; backup-pipeline
  alerts and a Backups dashboard are tracked in the healing issue. The
  shadowed 1.9 G original on the boot disk stays until the post-reboot
  test passes, then gets deleted.

## 2026-08-29 — Lidarr maintenance CronJob died with `connection refused` every night

- **Symptom:** nightly job Failed; manual rerun died on its first API call:
  `ERROR fetching queue: [Errno 111] Connection refused`. Service, DNS,
  IPv6, auth, and the NetworkPolicy rules themselves all ruled out.
- **Root cause:** kube-router programs a new pod's egress iptables chains
  ~1–2 s after sandbox start. Until then, egress the policy *does* allow
  is REJECTed (RST → refused, not dropped). The script connected on its
  first line of work and lost the race every night.
- **Fix:** `wait-for-lidarr` initContainer that retries `/ping` (urllib,
  same image as the main container) before the script runs. Verified live:
  attempt 1 timed out in the window, attempt 2 connected.
- **Prevention:** any Job that connects immediately needs the same
  treatment. The mass-search Job already carried its own 60×5 s wait loop —
  copy that pattern or the initContainer one.

## 2026-08-29 — Navidrome showed `[Unknown Album]` / `[Unknown Artist]`

- **Symptom:** placeholder entries in the UI.
- **Root cause:** one untagged test file (`_probe/Album/track.mp3`) entered
  the library on 2026-08-26 and was later deleted; Navidrome's default
  `Scanner.PurgeMissing=never` keeps records for deleted files — and their
  placeholder album/artist rows render — forever. Incremental scans never
  revisit deleted folders, so even a schedule of 1 h did not clean it.
- **Fix:** `ND_SCANNER_PURGEMISSING=full` + one `navidrome scan --full`;
  scanner purged 31 missing rows, placeholders gone.
- **Prevention:** the env setting; full scans now self-clean. (The 8
  remaining files matching "probe" are Sun Ra — a real album.)

## 2026-08-29 — Rotating Prowlarr's API key broke every downstream *arr

- **Symptom:** Lidarr health: most indexers "unavailable due to failures",
  HTTP 401 against the Prowlarr URL.
- **Root cause:** Prowlarr stamps its own API key into every synced torznab
  indexer (Lidarr, Readarr). Rotating the upstream key orphaned all synced
  copies until a re-sync.
- **Fix:** forced `POST /api/v1/command {"name":"ApplicationIndexerSync",
  "forceSync":true}`. Applies to ANY new or re-keyed indexer: adding
  bitmagnet needed the same forced sync before Lidarr saw it.
- **Prevention:** the sync is the checklist item, not an afterthought.

## 2026-08-28 — Closet move: pool not imported, NFS stale, 19 pods stuck

- **Symptom:** after an unclean shutdown everything behind NFS hung in
  ContainerCreating with `mount.nfs: No such file or directory`; MinIO and
  the backup pipeline broke (see the top entry).
- **Root cause:** the tank pool's datasets are encrypted and nothing
  auto-imported, auto-key-loaded, or auto-mounted on boot; NFS needed
  `exportfs -ra` after the mounts came back.
- **Fix (manual, now automated):** `zpool import tank`, `zfs load-key tank`,
  `zfs mount -a`, `exportfs -ra`. `zfs-load-key.service` now runs
  `load-key -a` + `mount -a` between import and mount at every boot, and
  nfs-server orders after it.
- **Prevention:** still needs one controlled reboot to prove the chain
  end-to-end — tracked in the healing issue. Also found late: child
  dataset `tank/appdata/personal` stayed unmounted because `load-key tank`
  loads only the parent's key; `load-key -a` covers children.

## 2026-08-26 — Services "randomly" unreachable: duplicate ARP claim on .240

- **Symptom:** all twelve published services flapping; failing requests
  never reached the cluster's Traefik log; TLS fingerprint sometimes wrong.
- **Root cause:** a Raspberry Pi answered ARP for 192.168.1.240 (the
  MetalLB address) about 1 ms behind the cluster. `ip neigh` showed one
  clean MAC because it displays only the cached winner.
- **Fix:** powered the Pi off; verified one ARP responder across repeated
  probes.
- **Prevention:** MetalLB's pool (.240–.250) is reserved — nothing else may
  hold those addresses. To diagnose a repeat: capture the wire
  (`tcpdump`), never trust the neighbor cache.

## Recurring class — bare short hostnames in *arr and plugin configs

- **Symptom:** indexer/download-client failures that look like auth or
  network problems (`http://gluetun:50393`, `http://prowlarr:9696`,
  `http://flaresolverr:8191` — three separate instances in one day).
- **Root cause:** short names do not resolve across namespaces; only
  full `service.namespace.svc.cluster.local` names do.
- **Fix:** repoint to FQDNs; Lidarr validates on save.
- **Prevention:** any new cross-namespace URL gets the FQDN, always.

## Recurring class — over-tight readiness probes empty a Service

- **Symptom:** an endpoint that takes ~5 s (`/ping` on a 3.6 GB SQLite
  Lidarr) behind `timeoutSeconds: 1` marked the pod NotReady 119 times in
  53 minutes, emptied endpoints, and looked exactly like a networking
  fault for hours.
- **Fix:** generous timings, verified against the real endpoint with
  `kubectl exec` + curl before commit.
- **Prevention:** repo convention — new probes get measured, not guessed.

## 2026-08-29 — "Duplicate" Authentik providers that were not there

- **Symptom:** analysis reported six forward-auth providers existing twice;
  a handoff note claimed qui had a duplicate OIDC entry to remove.
- **Root cause:** a query bug, not reality: `ProxyProvider` subclasses
  `OAuth2Provider`, so unioning both querysets double-counts every proxy
  provider (25 rows, 17 distinct). qui's two entries are two different,
  live providers (forward-auth + native OIDC) exactly as its manifest
  documents.
- **Fix:** none needed — deleting the "duplicates" would have broken live
  SSO. The evidence gate (identical pks) stopped it.
- **Prevention:** when a parent/child ORM hierarchy exists, dedupe by pk
  before believing a count.

## 2026-08-31 — kubelet probes ghost's readiness with https despite an HTTP spec

- **Symptom:** ghost sat 0/1 Ready=False for 25h+; every readiness event read
  `Get "https://10.42.x.x:2368/": http: server gave HTTP response to HTTPS
  client` — while the pod spec said `scheme: HTTP` (the default), the
  kustomization has no patches, the live deployment matched git, and the
  liveness probe of the exact same shape succeeded as http every 60s
  (0 restarts in 25h). Reproduced on a brand-new pod (fresh IP, same event)
  to rule out stale state.
- **Root cause:** not fully pinned — the kubelet constructs an https probe
  for readiness only. Node runs k3s v1.31.5 on Debian 13; no manifest-level
  explanation exists.
- **Fix:** dropped the readiness probe, kept liveness (same call as the
  funkwhale worker/beat and the seedboxapi lesson: a probe that empties the
  Service for nothing is worse than no probe). Ghost either serves or the
  container dies and liveness restarts it.
- **Prevention:** when a probe misbehaves at the kubelet level, verify the
  pod spec, the rendered manifest, AND a fresh pod before trusting the
  event's story — then bias toward removing the probe over keeping it.

## 2026-08-31 — k8s `command:` replaces the image ENTRYPOINT (funkwhale api)

- **Symptom:** funkwhale api CrashLoopBackOff with gunicorn's
  `Error: No application module specified.` while worker and beat (same
  image) ran fine. The manifest comment claimed the image entrypoint
  dispatches on `command: ["gunicorn"]`.
- **Root cause:** Docker mental-model trap. In Kubernetes, `command` IS the
  new ENTRYPOINT — it is not an argument handed to the image's entrypoint.
  `command: ["gunicorn"]` therefore ran bare gunicorn with no WSGI module.
  worker/beat only worked because their `command` replaced the entrypoint
  with celery directly, which needs no dispatch.
- **Fix:** `command: ["/entrypoint.sh", "gunicorn"]` — invoke the image's
  own entrypoint explicitly; its gunicorn case execs
  `gunicorn config.asgi:application --worker-class
  uvicorn.workers.UvicornWorker --bind 0.0.0.0:${FUNKWHALE_API_PORT}`
  (verified by cat-ing the script out of the live worker container, same
  image digest). Same incident window: gluetun's resolv.conf rewrite broke
  cluster DNS for the pod (worker/beat could not resolve
  redis-master.redis.svc.cluster.local) — fixed with DNS_KEEP_NAMESERVER=on,
  same as remux.
- **Prevention:** `command` replaces ENTRYPOINT, `args` replaces CMD —
  always. To pass a subcommand THROUGH an image entrypoint, include the
  entrypoint path in `command`.
