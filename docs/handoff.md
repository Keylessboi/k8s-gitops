# Handoff — 2026-09-08

## Access
```bash
ssh -i ~/.ssh/worker_key root@100.125.108.56          # Proxmox host (pve)
ssh ... root@100.125.108.56 'pct exec 200 -- kubectl get pods -A'   # cluster
```
`worker_key` is the only key that works. CT 200 is the k3s node, now a **static
192.168.1.172** (was DHCP — a lease change to .198 broke etcd during the outage).

## What just happened
Cluster went down: `/var/log/ganesha/ganesha.log` hit **72.8 GB**, filled CT 200's
root disk, took the k3s API server with it. Recovered. Root cause was that the
earlier `Enable_UDP = false` fix sat in a **duplicate `NFS_CORE_PARAM` block**,
which ganesha ignores — it had never taken effect. Now merged into the first
block (`scripts/host/ganesha/`), plus a **1-minute logrotate timer**
(`ganesha-logrotate.timer`) because the `maxsize 200M` rule only ran daily.
Verify with `ss -lunp` (no UDP listener) and two `stat` calls on the log.

Also fixed during recovery: Redis AOF corruption (`redis-check-aof --fix`),
Traefik 404ing all 35 Ingresses (it started before the API server — deleted the
pod), CoreDNS holding a stale Tailscale resolver, and 257 stale
`oc_file_locks` rows causing HTTP 423 on every upload.

## In flight
- **Elden Ring 50 GB upload.** Check:
  `kubectl exec -n downloads <qbit-pod> -c qbittorrent -- cat /config/elden-upload.out`
  Nextcloud's PHP scratch is now a 300Gi NFS PVC at `/scratch`
  (`apps/nextcloud/pvc-scratch.yaml`) — PHP buffers the whole PUT body to disk,
  and it used to buffer onto the cluster's root disk. Do **not** raise
  `post_max_size` without checking where `sys_temp_dir` points.
- Nextcloud backfill otherwise **done**: Bodycam, Red Dead, Dirty Business, PEAK
  all byte-exact. Baldur's Gate still downloading (3 `.!qB` files); the AutoRun
  hook will upload it automatically.

## Open issues
1. **Remux QuickConnect authorize button does nothing.** NOT an auth/ingress
   problem — `remux-api` Ingress works (`/System/Info/Public` and
   `/QuickConnect/Enabled` both 200, no OIDC on those paths). The cause is in
   the remux logs: `pool timed out while waiting for an open connection`,
   sqlx acquire times of **20+ seconds**, and 500s on API calls. Remux's
   Postgres pool is exhausted. Fix the pool size / DB contention, not the
   ingress. **This is where to start.**
2. **Lidarr mass search: ~49 days at current rate.** 25 albums/hour, 29,578
   left. Also `MultipleArtistsFoundException: Expected one artist, but found 2`
   blocks imports for at least one album, the Lucida indexer is permanently
   "No services available" (many searches run with 0–1 indexers), and one
   command has been stuck in `started` since 15:13.
3. `octo-yt-dlp-shim` ImagePullBackOff — local image `octo-yt-dlp-shim:2026.09.03`
   was never built/pushed. Pre-existing.
4. **Rotate two MinIO keys** leaked into the transcript: `etcd-s3-secret-key`
   and the `nextcloud-svc` key.
5. Task #35: CT 200 is RAM-tight; LVM thin pool has only ~41 GB free and the VG
   has 4 MB, so the disk cannot be meaningfully grown.

## Rules that cost real outages
- ArgoCD auto-syncs `main` with prune+selfHeal. **Pushing is deploying.**
- Config that parses is not config that runs. Three separate bugs this week were
  valid settings nothing read (`AutoRun/Enabled` vs `enabled`, a duplicate
  ganesha block, a NetworkPolicy naming the Service port instead of the pod
  port). Verify against the **observable**, not the file.
- Verify a hook by watching it fire, not by calling it yourself. qBittorrent
  passes `%L` and `%F` as ONE argument; the line is now `"%L|%F"`.
- Full history and lessons: `docs/doctor-log.md`.
