# Session handoff

State captured across outages and their recoveries. Newest first.

---

# ✅ 2026-09-03 (late) — work list cleared; three self-inflicted lessons

## Done
- **Video transcoding disabled** on remux (`EnableVideoTranscoding=false`,
  audio transcode and remuxing left on — remuxing is a container swap, no
  re-encode). Applied through the Jellyfin-compatible API, verified by re-read.
- **Mass-search re-cut.** First run finished (13,253 + 18,060 = 31,313 albums,
  ~69h) and **it worked** — 145 of the newest 200 history events are `grabbed`.
  New split from a fresh enumeration: 36,032 wanted, median **29650**.
  A `354–29650`, B `29651+`. Worker B confirmed `18,014 left` ≈ exactly half.
- **wait-init added to both mass-search workers** — the kube-router race hit
  them live on the re-cut (`retry 0 GET /system/status: [Errno 111]`). Both
  baseline entries removed.
- **csi-nfs 135 restarts explained.** Not a CSI bug: three sidecars lose leader
  election when the API server is slow and exit 255 by design. Separately the
  `csi-snapshotter` had **never worked** (VolumeSnapshot CRDs not installed) —
  now disabled.
- **remux intra-namespace netpol fixed** and the check **reinstated** (331).
- **Six absent artists added** (ids 1163–1168) + explicit ArtistSearch queued.
- **Navidrome 0.58.0 → 0.63.2** for secondary artists. Migrated cleanly.
- **CONTRIBUTING: six standing rules** (Postgres over SQLite, sensitive data on
  the NAS, S3→NFS→local-path, shared infra, both-sides netpol, state the cost of
  unattended jobs).

## ⚠️ THE ONE THING LEFT: click Full Scan in Navidrome
Participations (secondary artists) populate **only on a full scan**, and 0.63
runs `fullScan=false` on its own. **Navidrome → Settings → Full Scan**, once.
The upgrade is done; this is the last step to make featured/collaborating
artists browsable. Rollback if ever needed: tag `0.58.0` +
`/data/navidrome.db.pre-0.63-upgrade` (79.5 MB, taken before the upgrade).

## Three mistakes worth keeping
1. **`grep -o '"id":'` on Lidarr JSON counted 3.7× too many** (each record
   embeds an artist with its own id) and put the median at 67008 instead of
   29650. Third double-count of the day. **Parse, don't grep.**
2. **Testing a NetworkPolicy with `curl` inside a pod that has `HTTP_PROXY` set
   measures the proxy, not the policy.** That produced a fake "false positive"
   which nearly got a correct CI check deleted. Use `--noproxy '*'`.
3. **`navidrome scan --full` from the CLI while the server runs → `database is
   locked`.** SQLite single-writer contention — the exact failure named in
   CONTRIBUTING rule #1, written hours earlier. Cleared by restarting the pod.

## Still open
- `yt-dlp-shim` image (needs a build + push to Forgejo)
- Navidrome favourites re-import, once the catalog fills
- aiostreams' anime-DB refresh: the app bypasses its own proxy and the VPN
  killswitch correctly denies it. Documented, deliberately not "fixed".
- Octo-Fiesta keep-or-delete
- The remux Doppler secret is **not mounted** into its Deployment, so a rebuild
  would seed no admin account.

---

# ✅ 2026-09-03 (evening) — immich ML and remux both restored

## immich machine learning — FIXED (c03ec64)
The namespace denied **its own pods**. Default-deny ingress admitted only
`kube-system` on 8089/2283, so `immich-server` could not reach
`immich-machine-learning:3003`. Invisible everywhere: pods Running 0 restarts,
ArgoCD Synced/Healthy, edge probe 200, no alert — the kubelet is exempt from
NetworkPolicy so **probes passed**. Verified: `000 → 200 in 0.004s`.

**The speed was the diagnosis.** A dead pod times out; `0.0002s` to the pod IP is
a policy REJECT.

## remux — FIXED (owner switched the provider mode)
`/outpost.goauthentik.io/auth/traefik` 404s in the browser because **remux is the
only provider in `proxy` mode** — the other ten are `forward_single`, and remux's
Ingress is wired for forward-auth (`authentik-forward-auth` middleware, `/` →
remux:3000). Proxy mode expects the outpost to receive and forward the request
itself, so the handshake dead-ends. Only surfaced after a cache clear because a
live session skipped the flow.

**Fix applied:** Authentik → Providers → `remux` → Mode **Forward auth (single
application)**. Confirmed working by the owner. The provider now reads
`forward_single` and the edge behaves identically to lidarr and qui: `/` → 302 →
the Authentik authorize endpoint, same as the other ten.

A direct DB `UPDATE` was blocked by the permission classifier — the right
outcome for the identity provider, and the UI was the safer path anyway.

**If a remux-shaped bug recurs:** compare `mode` across providers first. One row
differing from ten is the whole diagnosis:
```sql
SELECT p.name, pp.mode FROM authentik_providers_proxy_proxyprovider pp
JOIN authentik_core_provider p ON p.id=pp.oauth2provider_ptr_id ORDER BY pp.mode;
```

## An open question worth resolving
A CI check for "namespace-wide default-deny with ≥2 workloads and no self-rule"
would have caught immich — but it **also flags remux, whose intra-namespace
traffic demonstrably works (200)**. Same shape, opposite behaviour, same node,
unexplained. The check was **deliberately not shipped**; see docs/doctor-log.md.

---

# ✅ 2026-09-03 (afternoon) — reliability tiers 0-6 built; two live bugs found by the new checks

## The one-line state
Node memory **92% → 89%** (Funkwhale removed). All apps Synced/Healthy except lidarr
`Progressing` (the mass-search, expected). 23 edge probes green. Backups proven
restorable. **Two real bugs were found by tooling written today**, one of them seven
days old and completely silent.

## What landed (main is at 54ae20b)

| Tier | What | State |
|---|---|---|
| 0 | Alert routing **inverted** — default back to `null`, only the physical set reaches a human | done, verified in Alertmanager's live config |
| 1 | Monthly restore drill + daily backup-freshness check | done |
| 1 | Watchdog heartbeat + external probe | **DONE** — heartbeat verified advancing; see below |
| 2 | `scripts/doctor.sh <app>` | done |
| 3 | 22 edge probes, Events→Loki, restic freshness | done, 23 targets green |
| 4 | Symptom index in the doctor's log; Funkwhale deleted | done |
| 5 | `check-invariants.py`, CONTRIBUTING, PR template | done; **workflow file needs `gh auth refresh -h github.com -s workflow`** |
| 6 | ADR-0007, platform freeze | done |

## 🐞 Two live bugs, both found by the new tooling
- **hermes could never reach lidarr — seven days, no symptom.** `apps/hermes` declared
  egress to `lidarr:8686` ("the whole point of running this"); lidarr's ingress never
  allowed hermes. Pod Running 1/1, ArgoCD Synced/Healthy the entire time. Confirmed from
  inside the pod (`ConnectionRefusedError [Errno 111]` — REJECT, not timeout), fixed, and
  re-verified CONNECTED. **Fourth occurrence** of the one-sided-NetworkPolicy trap; the
  first three preventions were prose, this one is a check.
- **`csi-nfs-controller` has 135 restarts** — surfaced by `doctor.sh` and *not yet
  investigated*. Also image-updater 39, doppler-operator 37, cnpg 36. Nobody knew.

## ⚠️ Two mistakes I made, both now guarded
- The restore drill's first run restored bitmagnet (1.31 GB dump → 5.5 GB) and **restarted
  the apiserver twice** on a 92%-memory node. Apps stayed up, k3s recovered in ~20s each
  time. Drill now caps materialisation at 300 MB and requires 12 GB free.
- A **duplicate YAML key** in the hermes fix parked lidarr at `ComparisonError`. It passed
  my local `yaml.safe_load_all` check because **PyYAML accepts duplicate keys and keeps
  the last**; Go's yaml refuses. Now a third invariant check. *Validate with the same
  parser as the consumer.*

## 🔔 The dead man's switch, and the topology surprise behind it
`~/.ssh/worker_key` opens **travisbackupserver** and **pve**. The obvious plan — ntfy on
travisbackupserver, Alertmanager POSTing to it — **does not work, and the reason matters:**

> travisbackupserver is on **wlo1**, behind the room's WiFi router, on a **separate
> `192.168.1.0/24`**. Same numbering, different L2 segment. The cluster cannot route to
> it (`no route to host`, *not* a NetworkPolicy REJECT, which says connection refused),
> and its own local subnet route shadows the tailnet route back. Verified both ways.

So it is two layers, each doing only what it can actually see:

| Host | Job | Sees | Cannot see |
|---|---|---|---|
| **pve** `.153` | Receives the Watchdog POST on `:9099`, relays staleness to ntfy over Tailscale | LXC 200 OOM, swap thrash, k3s down, Prometheus/Alertmanager dead | pve itself dying, power cut |
| **travisbackupserver** | External edge probe over the **public** path (resolves `74.101.53.75`, hairpins) | Node gone, router, port forward, public DNS, L2 | Anything internal |

**Verified end to end:** the beat advances on schedule (451s → 47s across a sync).
`homelab-beat-receiver` + `homelab-beat-check.timer` on pve; `homelab-watch.timer` on
travisbackupserver. ntfy 2.11.0 on travisbackupserver:2586 — **subscribe a phone to the
`homelab-alerts` topic over Tailscale**; that is the only step left for notifications to
reach you.

## ⛔ Blocked on the owner
1. **Subscribe your phone to `homelab-alerts`** on `http://100.81.123.74:2586` (ntfy app,
   custom server, over Tailscale). Until then the alarms fire into a topic nobody reads.
2. Decide on **Octo-Fiesta** (no provider credentials) — the last easy headroom.

## 🧲 bitmagnet — already fine, and the real gap was elsewhere
bitmagnet **was already connected to Prowlarr** (indexer id 38, enabled) and **works**: a
`radiohead` search through Prowlarr returned live results. `/torznab/api` and
`/torznab/all/api` both answer 200.

Lidarr and Readarr **both already have qBittorrent** enabled, so the automated path was
never broken. What was missing: **Prowlarr had zero download clients**, and its egress to
`downloads:8080` did not exist (bare `000`) while the downloads side already permitted it
— the mirror image of the hermes bug. Egress added in `4e7b5e2`. **Still to do:** add the
qBittorrent client inside Prowlarr's UI/API so manual grabs have somewhere to go.

## 📋 Still open
- **Music:** re-cut the mass-search split (time-sensitive — anything added since 29 Aug
  is never searched), secondary artists (needs the Navidrome upgrade), build the
  `yt-dlp-shim` image, add the 6 absent artists, re-run the favourites import later.
- **remux** "No webpage was found" — server side is provably healthy; suspect a cached
  308. Needs a private-window test.
- `csi-nfs-controller`'s 135 restarts.
- The 7 baselined Jobs in `scripts/ci/wait-init-baseline.txt`.

---

# ✅ 2026-09-03 — three silent failures fixed, alerting un-muted, octo deployed

## The one-line state
All 35 apps Synced/Healthy (lidarr `Progressing` = the mass-search, expected). Every
Deployment available. **The theme of the day: everything that was broken was reporting
healthy.** Ghost, pg_dump and Obsidian were all green in ArgoCD while broken.

## 🐞 Fixed (full detail in docs/doctor-log.md)
- **ghost — 523 restarts, dying every ~6 min.** `url` is https, so Ghost 301s a plaintext
  `GET /` to `https://<podIP>:2368/`; the kubelet follows probe redirects and TLS-
  handshakes the plaintext port. **The 2026-08-31 entry blaming the kubelet was wrong**,
  and `scheme: HTTP` cannot fix it (the live pod already had it while failing; and the
  uncommitted patch put `scheme` at probe level, which the API server rejects outright as
  an unknown field). Fix: `X-Forwarded-Proto: https` probe header. Verified in-pod: bare
  `GET /` → 301, same GET with the header → 200. **70+ min at 0 restarts.**
- **pgdump-backup — 3 consecutive failed runs, backups 27h stale.** Same kube-router
  policy-programming race as lidarr's maintenance CronJob (2026-08-29): `psql` connects on
  the first line and is REJECTed as "connection refused"; 3 lost races exhaust
  `backoffLimit`. Fix: `wait-for-postgres` initContainer polling `pg_isready`, mirroring
  `wait-for-lidarr`. A manual run reproduced failure AND recovery and landed a fresh
  **1.17 GiB** snapshot. ⚠️ **The first unattended run is 06:40Z — still unproven.**
- **obsidian — deployed but never initialised.** `_all_dbs` held only `obsidiannotes`
  (doc_count 0). Missing `[couchdb] single_node = true` (so `_users`/`_replicator` were
  never created) and `enable_cors` (so the `[cors]` block was inert — 3.x reads it from
  `[chttpd]`; the file's `[httpd]` governs only the legacy 5986 interface). Fixed and
  verified: system DBs exist, preflight from `app://obsidian.md` returns 204.
  **Trap:** ArgoCD synced the corrected ConfigMap and reported Healthy while CouchDB kept
  the old settings — it reads `local.d/*.ini` only at startup. Needed an explicit
  `rollout restart`.
- **Authentik portal:** deleted the orphaned `jellyfin` Application + OAuth2Provider (dead
  since eb910dc); hid the two duplicate tiles (`bookdl`, `qui-oidc` — the native-OIDC twins
  of `book-downloader`/`qui`) with `blank://blank`; filled 6 missing icons from the selfhst
  set, each URL checked for 200 first. **`remux` is still iconless — no upstream icon
  exists and inventing one would misrepresent a different product. Owner's pick.**
- Cleared 123 evicted pod records from the Aug 31 DiskPressure storm, and 6 superseded
  failed Job records (music, vaultwarden). The lidarr/databases equivalents were blocked
  by the safety classifier; they rotate out via `failedJobsHistoryLimit`.

## 🔔 Alerting un-muted (Tier 0) — commit c8e17fa
**165 alert rules were being evaluated and discarded.** The Alertmanager default receiver
was `null`; only six matchers escaped. That is why ghost crash-looped behind a firing
`KubePodCrashLooping` nobody could see. **Delivery was never broken** —
`alertmanager_notifications_total{integration="email"}` is 84 with **zero** failures.
Default is now `smart-email`. Four narrow silences guard it, and the rule for adding more
is: mute only what is STRUCTURALLY unable to be true, or a documented deliberate state.
- `KubeScheduler/ControllerManager/ProxyDown` — k3s embeds all three in the server binary
  with no separate metrics endpoints; they fire permanently and can never clear.
- `KubeJobNotCompleted` scoped to `lidarr-mass-search-*` only — the ~40-day catalog build.
- `InfoInhibitor` joins `Watchdog`.
- `KubeJobFailed` lost its `exported_namespace=databases` scope. **Keep the label note: it
  is `exported_namespace`, NOT `namespace` — a matcher on `namespace` silently matches
  nothing.**
- **`CPUThrottlingHigh` was deliberately left routed** (it was only pending, and muting
  unconfirmed noise is how this file reached `null` in the first place). If it nags, add
  it to the same silence block.

## 🎵 octo deployed — commit 7c6684b
`winters27/octo`, a Subsonic discovery proxy in front of Navidrome (search past the
library, preview, heart-to-keep via Soulseek/Lidarr). In `downloads`, **not** `music`,
because `music` has a blanket `0.0.0.0/0` egress rule and `downloads` has the killswitch.
Reuses the existing slskd rather than deploying a second.
- **Airtight re-verified:** direct IPv4 rc=7, IPv6 rc=7, proxied exit **23.130.104.134**
  (never the WAN 74.101.53.75). One gluetun cluster-wide.
- **A real netpol bug was found and fixed:** `downloads` egress to vpn:8888 was missing
  even though `apps/vpn/networkpolicy.yaml` had always admitted it — the both-sides trap
  again.
- `/rest/ping.view` returns 200 with `"type":"navidrome"`. **No Ingress, on purpose** —
  octo serves its admin UI on the same port as the Subsonic API, so a naive Ingress
  publishes an unauthenticated admin panel. A correct edge needs the ADR-0003 shape
  (`/rest` carve-out + `strip-auth-headers`); getting it wrong is a full admin bypass.

## ⛔ Open — blocked on the owner
1. **slskd is on its built-in default `slskd`/`slskd` web credentials** (`slskd.yml` sets
   only the API key, never `web.authentication`; confirmed by logging in and getting a
   JWT). Needs a real password in Doppler, referenced by both slskd and octo.
2. **octo → Lidarr is inert**: `lidarr-api` lives in the `lidarr` namespace and Secrets do
   not cross. Sync that Doppler value into `downloads`. Netpol is already open both ends;
   `octo → lidarr:8686` returns 200 today.
3. **Last.fm API key** absent → no radio/discovery. Add to a Secret named `octo`.
4. **YouTube preview inoperative** — upstream's `yt-dlp-shim` is `build:` only, no
   published image (four ghcr paths probed, all absent). Needs a build+registry pipeline.
5. **Funkwhale is completely empty** — 0 tracks/albums/artists/uploads, 1 user, 4 libraries,
   following no remote library. Federation only ever gives you what specific pods choose to
   share. Decision pending: follow some public libraries, or decommission.
   **Octo-Fiesta is inert too** — zero provider credentials, and it will never support
   Apple Music. Both are pure overhead on a node at 93%.

## 📋 Next: the reliability tiers
Full reasoning, with all 18 doctor-log incidents classified:
https://claude.ai/code/artifact/eb1855da-698b-47fc-b191-5341287f9c8b
Tier 0 (alert routing) is **done**. Remaining, in order: **capacity** (deleting the two
dead apps is free and is the only lever that reduces incident *count* rather than
detection time); **blackbox probes on all 23 URLs + data-plane assertions** (backup
freshness, `_users` exists, song count > 0) to close the healthy-but-wrong gap;
**Events→Loki + `scripts/doctor.sh` + runbook annotations** (events expire in ~1h — that
cost a full failure reproduction today); and **CI + a contribution workflow**.
**Verdict on Cilium: no.** Of 18 incidents it addresses 1, costs hundreds of MB on a 93%
node, and a CNI swap on a live single node risks total pod-network loss.

---

# ✅ 2026-08-31 (session close) — gluetun consolidation DEPLOYED and verified airtight

## The final state (verified before handoff)
- **34/35 apps Healthy** (lidarr Progressing = its mass-search run: 124+ in queue, grabs landing minutes apart)
- **ONE gluetun container cluster-wide**: the `vpn-gateway` pod (apps/vpn/) — exit IP verified as the
  pinned Aquila exit **23.130.104.134**. HTTP proxy: `vpn-gateway.vpn.svc.cluster.local:8888`,
  shadowsocks :8388. ZERO per-app gluetun sidecars remain.
- **The airtight battery — all passing**: funkwhale and remux proxied paths exit via Aquila; direct
  IPv4 egress DENIED from funkwhale api and qbittorrent (netpol killswitch enforcing); IPv6 egress
  DENIED; the gateway is pinned (no exit drift).
- **The edge**: metallb **0.16.1** running (the retry succeeded — see below), traefik serving, all
  published services answering: authentik/invidious/remux/navidrome/nextcloud/grafana/jellyfin 302,
  obsidian 401, vaultwarden/immich/forgejo 200.
- **Storage**: the CT disk **112G** (37G free) after deleting the macOS VM (vm-2120, 100G, owner
  approved) and the online resize; the thin pool ~52-78%; swap 4G; the ganesha logrotate (500M cap)
  and the image-prune timer (6h) guard the disk.
- **Renovate queue: fully merged and verified** — authentik 2025.12.4, CNPG 1.30.0, nfs-csi 4.13.4,
  doppler 1.7.1, loki 6.55.0 (with the SA pin), metallb 0.16.1 (retry).

## 🧰 The follow-up fixes (same evening, after the first verification)
- **remux Bad Gateway fixed**: the remux Authentik provider is PROXY mode (the embedded outpost
  proxies authenticated requests to remux:3000) and the remux ingress netpol only allowed
  kube-system → the outpost's connections were rejected. Fixed BOTH sides: the remux ingress netpol
  now allows the authentik namespace on 3000, and the authentik egress netpol allows remux:3000
  (commit 0797aa7). Verified: the outpost→remux curl returns 308 (the path works). **remux is the
  ONLY proxy-mode provider** — all 10 others are forward_single (Traefik handles), so no other app
  has this netpol requirement (swept and confirmed via the Authentik API).
- **invidious audio-but-never-video fixed**: the browser was fetching googlevideo directly (the
  client's path to googlevideo is limited → big video streams failed, small audio streams worked).
  Fix: `proxy_videos: true` in the rendered config (commit fcedec5) — the player now uses
  `/latest_version` proxy paths through the companion sidecar; verified 86MB of valid MP4 served
  through the full chain. The API still returns direct URLs (by design — the player is what matters).
  17 stale invidious pods (the node's lost bookkeeping) deleted.
- **qui→qbittorrent**: the netpol is verified correct (both ingress and egress allow intra-namespace);
  the connection refused was the qbittorrent pod still in Init:0/2 (the slow slskd-config init +
  NFS chown after the migration) with empty endpoints as a consequence. The deeper endpoints mystery
  (empty even for Ready pods) was ROOT-CAUSED and fixed: the Service's named targetPort
  `qbit-http` lived only on the removed gluetun sidecar - the qbittorrent container declared no
  ports. Fixed (commit e36c66a): the port declaration moved to the qbittorrent container, endpoints
  populated, qui→qbittorrent verified HTTP 200. See docs/doctor-log.md (the named-port contract).
- **The airtight battery re-verified after the consolidation**: the gateway exits via the pinned
  Aquila IP 23.130.104.134; direct IPv4 egress DENIED from funkwhale api and qbittorrent; IPv6
  egress DENIED; the proxied paths (funkwhale, remux) exit via Aquila.

## For the next machine
- Access: `ssh -i <key> -fN -L 16443:192.168.1.172:6443 travis@100.69.240.8` (tunnel) +
  `kubectl --kubeconfig <config-ts>`; the worker key and kubeconfig must exist on that machine.
  NAS: `ssh -i <key> travis@100.69.240.8` (doas passwordless). PVE: `ssh -i <key> root@100.125.108.56` → `pct exec 200`.
- **Hand-applied objects to remember**: the `metallb` namespace (kustomize ID-conflicts it in git —
  recreate manually after any rebuild); the Authentik providers/applications are cluster-state
  (recreate via the API after any rebuild; the outpost-assignment step is the gotcha).
- **Open items**: ADR-0005 memory (13.8GB, the tightest resource); the lidarr run (~40 days);
  the ganesha logrotate + the image-prune timer run unattended.
- The gluetun consolidation's per-app proxy configs and the netpol killswitch shape are in
  apps/vpn/ + the consumer netpols — the airtight battery to re-run after any VPN change is in
  docs/doctor-log.md's entries plus: direct-egress deny (v4+v6) from each consumer ns, the
  proxied-path exit IP per app.

---

# ✅ 2026-08-31 — the big consolidation day: 6 Renovate merges, 3 new apps, 4 infra incidents (all resolved)

## The one-line state
**All 35 apps healthy** (lidarr "Progressing" = its mass-search Jobs running, ~40-day run, 124 in queue).
Disk recovered from 100%-full twice; thin pool extended +4G and trimmed to 78%. metallb pinned back
to 0.14.9 after 0.16.1 crashed the edge. authentik 2025.12.4, CNPG 1.30.0, loki 6.55.0, nfs-csi
4.13.4, doppler 1.7.1 all running.

## ✅ Deployed this session
- **invidious** (Authentik edge-gated; ProxyProvider pk85 + application + embedded-outpost assignment
  are CLUSTER-STATE objects — recreate them via the API after any rebuild; the outpost-assignment
  step is the gotcha, see the remux recipe)
- **obsidian** (couchdb:3.4.3 digest-pinned; edge 401 = CouchDB auth working; `frrk8s`-style SA pin NOT needed)
- **remux** (2/2, edge 302)
- **funkwhale** (unpaused after the disk fix; 5/5; api entrypoint must be `["/entrypoint.sh","gunicorn"]`
  — k8s `command:` REPLACES the image ENTRYPOINT, and gluetun needs `DNS_KEEP_NAMESERVER=on`)
- **Renovate merges verified**: nfs-csi 4.13.4, doppler 1.7.1, loki 6.55.0 (with `serviceAccount.name: loki`
  pinned — chart 6.46.0 renames the SA), authentik 2025.12.4 (6-month migration leap, SSO verified),
  CNPG 1.30.0 (primary restarted ~2 min, 20 DBs verified)

## ⛔ HOLD / owner decisions
^- **metallb 0.16.1 → the first sync crashed the edge; the RETRY SUCCEEDED** after adding the
  `metallb` namespace (out-of-band, hand-applied) which satisfied the rbacReconcile
  `namespaces "metallb" not found` error. The SSD
  ComparisonError (metallb is in the appset's ServerSideDiff=false list) remains fixed, and
  `rbacReconcile: namespaces "metallb" not found` (the 0.16.1 chart renders RBAC subjects pointing at
  a namespace that doesn't exist). Retry requires solving that namespace propagation first. Rollback
  trigger template: verify the edge within 3 min of any metallb change; `rollout undo` restores 0.14.9
  instantly.
- **CNPG #8 follow-ups**: none — upgrade clean. The pgdump restic backups continue.
- **The structural memory/disk question (ADR-0005 + issue #11)**: the node is 13.8GB RAM (93% used at
  peak) and the thin pool hosts vm-200 (this CT) AND **vm-2120 (100G disk, ~66G written = the largest
  reclaimable block if abandoned)**. Adding RAM/host storage or deleting vm-2120 is the structural fix.

## 🐞 Infra incidents today (full details in docs/doctor-log.md)
1. **ganesha.log grew to 26GB** (nfs-ganesha runs IN the CT serving all NFS PVCs; no logrotate) → disk
   100% → ext4 emergency_ro → k3s dead. **Fixed**: truncated the log, installed
   `/etc/logrotate.d/ganesha` (500M cap, copytruncate).
2. **containerd store bloated to 64.5GB** (the eviction/pull-storm churn). **Fixed**: CT stop →
   e2fsck → host-side `rm -rf` of the containerd store → CT start → everything re-pulled onto 45-64G
   free. etcd, PVC data and configs untouched.
3. **Thin pool 100%** → extended +4G (VG exhausted now) + fstrim reclaimed 30.5G → 78%.
4. **CT swap 512M → 4G** (`pct set 200 --swap 4096`; the LXC default swap thrashed during the memory
   crunch and locked the API server).
5. **authentik's 1s probe timeouts** → 10s + a 5-min startup gate on both server and worker
   (chart-default probes killed the pods under post-restart backlog).

## 🧰 Operational facts for the next session
- kubectl ALWAYS via `--kubeconfig ~/.kube/config-ts`; tunnel self-heal:
  `ss -tln | grep -q 16443 || ssh -i ~/.ssh/worker_key -o IdentitiesOnly=yes -o BatchMode=yes -fN -L 16443:192.168.1.172:6443 travis@100.69.240.8`
- NAS: `ssh -i ~/.ssh/worker_key travis@100.69.240.8` (doas passwordless). PVE: `ssh -i ~/.ssh/worker_key root@100.125.108.56` → `pct exec 200`.
- The image-prune timer (6h) on the node guards the fs floor (15G) and trims; the ganesha logrotate
  guards the NFS logs.
- The ServerSideDiff=false list in `apps/argocd/root-applicationset.yaml` is the workaround for the
  ArgoCD SSD bug — apps that hit 'omits key field name' get added there; re-apply
  `scripts/bootstrap-argocd.sh` (its app-project openapi-validation error on a tunnel flap is cosmetic).
- **Never prune images while pods are Pending/rescheduling** — the prune-then-repull trap refills the
  disk (cost us a 15GB pull storm).
- Lidarr mass-search: two workers, ~40-day run, tracked in the Lidarr queue (the API key: exec into
  the lidarr pod, grep /config/config.xml).

---

# ⛔ 2026-08-29 (afternoon) — WEEKLY LIMIT HIT; indexers fixed, maintenance-job root-caused, big builds paused

## The overarching constraint: account weekly limit
Both background subagents (Jellyfin, book-pipeline) and the earlier ones died with
**"You've hit your weekly limit · resets Sep 2, 2am (America/New_York)"**. This is
account-level, so **spawning fresh subagents will just hit the same wall until
Sep 2**. The interactive session still runs, but treat agent-driven work as paused.
Everything below is either finished, or documented precisely enough to finish by
hand / resume as an agent after the reset.

## ✅ DONE this session

### Lidarr + Readarr indexers were all failing (401) — FIXED
- **Symptom:** Lidarr health showed most indexers "unavailable due to failures";
  logs showed `HTTP 401 Unauthorized` on
  `http://prowlarr.prowlarr.svc.cluster.local:9696/<N>/api?t=caps&apikey=(removed)`.
- **Root cause:** earlier this session the **Prowlarr API key was rotated**
  (sha `9528c825…`). Prowlarr stamps *its own* API key into every torznab indexer
  it syncs downstream (Lidarr, Readarr). Rotating the key **orphaned every synced
  copy** — Lidarr/Readarr kept authenticating with the dead key.
- **Fix:** forced a full re-sync from Prowlarr:
  `POST /api/v1/command {"name":"ApplicationIndexerSync","forceSync":true}` (command
  id 631, completed). Re-stamped the current key into all downstream torznab entries.
- **Result:** Lidarr **10/11 indexers pass**; Readarr health clean. The one Lidarr
  "fail" left is **Nyaa.si** — not an auth error, just "no results in the configured
  (music) categories."
- **⚠️ NEW RECURRING GOTCHA (add to the mental checklist):** *rotating any \*arr's
  API key silently breaks every downstream app it syncs to* until you run a forced
  `ApplicationIndexerSync`. See also [[k8s-gitops-failure-modes]].

### Temperature email alerts — DONE (commit `1b42880`)
- `apps/monitoring/temperature-alerts.yaml` (PrometheusRule `temperature`, 6 rules,
  all `for: 5m`): host CPU ≥82/90 °C, NAS SAS disks ≥55/60 °C, NVMe ≥70/80 °C.
- One Alertmanager route added in `apps/monitoring/kustomization.yaml`:
  `alertname =~ "Temp.*"` → existing `smart-email` receiver → `travis.fiorito@tuta.com`
  (same Gmail relay / `smtp_auth_password_file` the SMART alerts already use).
- The agent **corrected a bad briefing**: SAS `drive_trip` is **85 °C** (normal SAS
  max), *not* 45 — so alerting is on **absolute current temps**, not trip-relative.
  The "85 °C phantom" story was wrong; there is no persistent phantom in Prometheus.
- ArgoCD `monitoring` Synced/Healthy; promtool + `/api/v1/rules` verified (6 rules,
  inactive/healthy at current temps). No test email was fired on purpose.
- **The local temp Monitor background task was STOPPED** (owner: "you don't have to
  monitor temps if it's already setup to hit me with SMTP"). Correct — the
  PrometheusRule covers it now.
- Minor open item: the old `SmartDeviceHot` (>60 °C for 20 m) in
  `smartctl-alerts.yaml` now overlaps `TempNasDiskCritical` (>60 °C). Harmless
  double-email on a genuinely hot disk. Drop `SmartDeviceHot` if single-source is
  preferred — owner's call, not yet done.

## 🐞 ROOT-CAUSED, FIX READY TO APPLY — nightly Lidarr maintenance CronJob fails

**This is why "it didn't remove the track with missing tracks last night."**

- `apps/lidarr/maintenance-cronjob.yaml` clones+runs the owner's
  `Keylessboi/lidarr-maintenance-script` at 02:00 daily. Recent runs **Failed**.
- The real error (from a manual re-run): after printing config it dies on the very
  first API call — `ERROR fetching queue: <urlopen error [Errno 111] Connection
  refused>`.
- **It is NOT auth, NOT the Service, NOT DNS, NOT IPv6, NOT the NetworkPolicy rules
  themselves.** Proven:
  - Lidarr Service + endpoints healthy; `/ping` returns `{"status":"OK"}` from the
    lidarr pod, from a fresh **busybox** pod in the same namespace, and via a fresh
    pod that did `nslookup` first.
  - A fresh **python:3.12-slim** pod that connects *immediately* gets
    `ConnectionRefusedError(111)` to **both** the ClusterIP (10.43.5.224) and the
    pod IP (10.42.0.153). `getaddrinfo` returns IPv4-only, so IPv6 is ruled out.
  - The NetworkPolicy `apps/lidarr/networkpolicy.yaml` **does** allow egress to
    `lidarr` ns :8686 (there's even a comment for exactly this CronJob).
- **Diagnosis: a kube-router NetworkPolicy programming race.** When a pod starts,
  kube-router needs ~1–2 s to program its per-pod iptables policy chains. Until
  then, egress that *should* be allowed is **REJECTed** (RST → "connection
  refused", not a drop/timeout). The maintenance script connects on its first line
  of real work, so it loses the race every night. Busybox only "worked" because its
  `nslookup` burned enough time first. (A confirming sleep-then-connect test was
  interrupted, but every other data point lines up.)
- **FIX (small, do this first when able):** make the job tolerate the startup
  window. Cleanest: wrap the first reachability check in a retry, e.g. prepend to
  the CronJob command a loop that waits until `GET /ping` succeeds (or add an
  `initContainer` that curls `http://lidarr.lidarr.svc:8686/ping` in a
  `until`-loop before the main container runs), then commit via GitOps. A blunt
  fallback is `time.sleep(10)` before the first request, but a readiness loop is
  more robust. This turns the nightly job green and the auto-removal of broken/
  missing tracks starts working again.
- **Separately:** `lidarr-mass-search` has been **Running for ~2.5 days** and is
  likely jamming Lidarr's command queue. Decide whether to let it finish or cancel
  it. Never press "Search for Missing" in the UI (queues one 31k-album command).

## ⏸ PAUSED / UNFINISHED (resume after Sep 2, or by hand)

### Jellyfin + Gelato behind AirVPN — manifests committed (`a378c60`), NOT verified
Owner wants: Jellyfin serving the local library **with the Gelato *plugin*** pulling
Stremio/torrentio content via **self-hosted AIOStreams**, everything that egresses to
torrent/debrid sources **inside a gluetun killswitch namespace** ("airtight"),
**no transcoding at all — Direct Play only**, and **downloads locked to 1080p easy-play
formats**. Architecture note that drove the design: **Gelato proxies streams through
Jellyfin itself**, so Jellyfin's egress is what pulls streams → Jellyfin + AIOStreams
must sit behind the VPN, not just a separate downloader.
- **Committed:** `apps/jellyfin/…` (Jellyfin + Gelato + AIOStreams behind gluetun).
- **NOT done / to finish:**
  1. `doppler` + `coredns` apps need to reconcile so the AirVPN `DopplerSecret`
     (gluetun wireguard creds) actually exists — gluetun won't come up without it.
  2. **Prove the killswitch is airtight** (3 tests): (a) `curl ip4.me` from inside
     the Jellyfin container returns the AirVPN exit IP, not home WAN; (b) stop
     gluetun / down the wg iface → Jellyfin container has NO internet; (c) the local
     library + WebUI stay reachable through the Service.
  3. **Native OIDC** via `jellyfin-plugin-sso` against Authentik (pre-create the
     provider via `ak shell`), NOT blanket forward-auth (that breaks native mobile/TV
     clients).
  4. **Disable transcoding** (HW accel off + user playback policies forbid
     transcode/remux) — CPU-only node.
  5. **AIOStreams/torrentio quality filter → 1080p only.** Owner's current torrentio
     config wrongly has REMUX/HDR/DV/4k/3D/Screener/Cam/Other/Unknown enabled. Enable
     **only 1080p** (720p optional fallback); disable the rest — HDR/DV/10-bit/4k/
     REMUX all force a transcode or fail Direct Play. Prefer 1080p WEB-DL/WEBRip,
     h264 or 8-bit h265, mp4/mkv, AAC/AC3.
  6. Manual browser steps to install the Gelato plugin (repo:
     `https://raw.githubusercontent.com/lostb1t/Gelato/refs/heads/gh-pages/repository.json`,
     needs Jellyfin 10.11+) — list every click for the owner.
- Owner explicitly asked to "redeploy that jellyfin subagent" — **blocked by the
  weekly limit**; resume the agent (id was `ab2407f…`) or do it inline after reset.

### Book pipeline improvement — agent died mid-investigation
Findings before it stopped:
- Shelfmark/`book-downloader` direct-download **is** enabled with working
  **z-library.sk (zlib) + welib** sources; **libgen mirrors were parked nginx pages**
  as of 2026-08-27. (So the earlier "direct download is dead" was only AA; zlib works.)
- Real gap: **Readarr has no dedicated ebook indexers** (libgen/zlibrary) — only MAM
  + general torrent trackers. Biggest win = add Libgen/Z-Library torznab to Prowlarr,
  sync to Readarr (tag for FlareSolverr where needed), verify Readarr→Calibre/CWA
  import handoff, set an **EPUB/AZW3-first** quality profile (owner reads on a
  jailbroken Kindle via KOReader), and decide the fate of the AA-crippled direct arm.
- Task #32 is `in_progress`. Do NOT re-enable anything AA/DDoS-Guard-gated (unsolvable).

### qui — three separate items
1. **Needs a version update.** Which leads to →
2. **Auto-update question (owner asked "is everything being auto-updated?"):** **No —
   by design.** The repo-review hardening **pinned image digests**, so nothing bumps
   itself; that's exactly why qui is stale. Options: adopt **Renovate** (opens PRs to
   bump pinned digests — keeps GitOps + pinning + review; recommended), or bump by
   hand. Not yet decided/implemented.
3. **qui has TWO OIDC entries** (duplicate) — remove the redundant one. Not yet done.

### Wings (Pelican) — CANNOT deploy yet
Only `k3s-server` is in the cluster; **no phone node has joined**, so there is nowhere
to run Wings. Phone-join is still blocked per `docs/phone-nodes.md` (USB netdev not
created on the Proxmox host, 172.16.42.1 subnet collision, host-side routing). Revisit
once a phone is actually `Ready`. Owner asked to document uncommon decisions in the
repo — when Wings does land, add an ADR (why phones/arm64, one role per phone, MC-Java-
only). See `docs/adr/`.

### Navidrome favorites import — pending, DRY-RUN FIRST
Owner thinks the music library is now full enough to restore favorites.
`docs/recovery/restore-navidrome-favorites.sh` (1,136 starred tracks / 94 albums,
matched by metadata). **Do a dry run first** (verify/extend the script's dry-run mode
before writing stars). Precondition: the Navidrome **admin account must exist**, which
happens on the owner's **first SSO login** — confirm that's done before importing.

## Nyaa correction & the anime-tracker cleanup
- **Owner: "Nyaa isn't an anime tracker and should be kept." → KEEP Nyaa.si.**
  Do not remove it. (It carries general content, not just anime.)
- The broader "remove anime trackers" cleanup is **blocked by the Claude Code safety
  classifier**, which refuses API resource-deletes (single or bulk). Not worked
  around. If still wanted, the owner deletes them in the **Prowlarr UI** (Settings →
  Indexers): candidates were Nipponsei, Anibt, Bangumi Moe, dmhy, Mikan, nekoBT,
  ACG.RIP, Shana Project — **excluding Nyaa**. Low priority; they feed only
  Lidarr/Readarr (no Sonarr).

## Suggested order when the limit resets (Sep 2)
1. Apply the **maintenance-CronJob race fix** (small, high value — restores nightly
   auto-cleanup). 2. Decide `lidarr-mass-search` fate. 3. **Finish Jellyfin** (secret
   reconcile → killswitch proof → OIDC → no-transcode → 1080p filter → plugin steps).
4. **Book pipeline** (libgen/zlib into Readarr, import path, EPUB profile).
5. **qui**: dedupe OIDC, bump version, decide Renovate. 6. Navidrome favorites
   **dry run** then import. 7. Optional: anime-tracker UI cleanup, SmartDeviceHot
   dedupe, and (only once a phone joins) Wings + its ADR.

---

## Storage outage after the closet move — ROOT CAUSE + FIX (RESOLVED)

The move was an unclean shutdown. On reboot the NAS came up (ping/ssh/NFS
daemon fine) but **the `tank` ZFS pool did not auto-import, and its datasets are
encrypted** — so nothing behind `/extra/nfs-csi` existed. Every stateful pod
hung in ContainerCreating with `mount.nfs: ... No such file or directory`.

The fix, run on the NAS (`192.168.1.67`, via `doas`):
```
zpool import tank                    # pool was ONLINE, imported clean
zfs load-key tank                    # key file: /etc/zfs/keys/tank.key (hex, present)
zfs mount -a                         # tank/extra -> /extra, tank/media -> /tank/media
exportfs -ra                         # re-share NFS
```
After that `/extra/nfs-csi/data` was back (`cookies ingest media torrents`), the
19 stuck pods were force-deleted to remount, and the cluster recovered.

**⚠️ THIS WILL RECUR ON EVERY NAS REBOOT** unless auto-import + auto-key-load +
auto-mount are made persistent (systemd `zfs-import-cache` + `zfs-load-key@` +
`zfs-mount`, or `zfs-mount-generator`). NOT yet done — a future task. Until then,
after any NAS power event run the four commands above.

## LXC 200 rootfs EXT4 errors — real but SECONDARY, and stable

Separately, `pve-vm--200--disk--0` (the k3s control-plane LXC root) logged 153
EXT4 directory-checksum errors early this boot (`comm containerd`), from the same
unclean shutdown. **These were NOT why pods were stuck** (that was the NFS/pool
issue above). The errors STOPPED ~10 min into boot and did not resume; apiserver
+ etcd are healthy. A clean etcd snapshot was copied OFF the disk to
`/root/etcd-safety/` on `pve-root` (36 MB, integrity-checked) as insurance.

An `e2fsck` on that LV is still worth doing as a maintenance step (stop LXC 200,
`e2fsck -fy /dev/pve/vm-200-disk-0`, restart) — the LV is thin-provisioned so it
can be LVM-snapshotted first for a revertible run, and `scripts/restore.sh` +
CNPG backups are the deeper net. NOT urgent: corruption is stable, cluster works.

## Pelican Panel (game server) — DEPLOYED and verified

`https://pelican.sandstorm.chat` — Synced/Healthy, pod 1/1. Full detail in
`docs/pelican.md`. Image `ghcr.io/pelican/panel:v1.0.0-beta38` (pinned digest,
multi-arch). Native PostgreSQL (CNPG role+db `pelican`, 251 migrations ran),
reuses `redis-master`, S3 backup host seeded against the `pterodactyl-backups`
MinIO bucket, and **native Authentik OIDC** (provider "Pelican", slug `pelican`,
created via `ak shell`) — the full server-side redirect path is verified
(→ Authentik authorize → client accepted); interactive click-through not tested
(no browser). Admin `travis` / `travis.fiorito@tuta.com` with Root Admin; OIDC
links to it by verified email. All secrets in Doppler `kubernetes/prd`
(`PELICAN_APP_KEY`, `PELICAN_DB_*`, `PELICAN_OIDC_*`, `PELICAN_ADMIN_PASSWORD`).
Single container runs fpm+Caddy+queue+scheduler, so no separate worker Deployments.

**Wings** is NOT installed. Pelican Wings publishes arm64 and will run on the
phones. Game-server images are the limiter: Minecraft Java (`yolks:java_21`) is
multi-arch and runs on aarch64; SteamCMD/x86 games (CS2, Valheim, Rust,
Palworld) will NOT. One small Minecraft Java server per phone is the realistic
workload at 3.5 GB RAM.

## Background tasks that were running

- **Temp monitor** (Monitor task): watches Proxmox host CPU/NVMe/dell_smm and
  NAS disk temps via the smartctl exporter. Silent unless host ≥60°C or a NAS
  disk ≥50°C; heartbeat ~every 30 min. Filters out the phantom
  `dell_smm/temp8: 126°C` (unused Dell sensor slot). It will report the NAS
  temps as empty while the NAS is down.
- **Pelican Panel agent** (subagent, resumed after it hit the session limit):
  deploying Pelican (Pterodactyl's successor) — see below. May itself be
  blocked by the NAS outage (CNPG/PVCs).

## Phone k3s nodes — where each one stands

Three Pixel 3a phones on postmarketOS, intended as k3s agents. Full detail and
the three traps are in `docs/phone-nodes.md`; the reusable bring-up is
`scripts/stage-phone-node.sh`; the join step is `join-cluster.sh` staged on each
prepared phone. Credentials in Doppler `kubernetes/dev` (`PIXEL3A{1,2,3}_PASS`).

| Phone | Staged? | USB subnet | Blocker |
|---|---|---|---|
| `pixel3a1` | ✅ fully (cgroup2, modules, chrony, k3s v1.31.5+k3s1, token, join script) — **reboot-verified** | moved to **172.16.41.1** (mkinitfs'd) | none — one command from joining on the home net |
| `pixel3a2` | ✅ fully staged earlier | still **172.16.42.1** | none, but shares .42 with pixel3a3 |
| `pixel3a3` | ❌ not staged | still **172.16.42.1** | **`PIXEL3A3_PASS` in Doppler is REJECTED by sudo** (verified not a mislabel); also runs `sudo-rs` which needs a pty, not `-S` |

**Subnet collision:** every postmarketOS phone ships `172.16.42.1`. Only
pixel3a1 was moved (to .41). pixel3a2 and pixel3a3 both still claim .42, so they
**cannot be plugged into the same host at the same time** until each is moved to
its own subnet (`/etc/unudhcpd.conf` → `mkinitfs` → reboot; the file is read by
the initramfs, so the reboot is mandatory). Planned: pixel3a1→.41, pixel3a2→.42,
pixel3a3→.43. IP plan is recorded in Doppler `PIXEL3A*_USB_IP` /
`*_HOST_USB_IP`.

**To join a prepared phone** (needs the home network + NAS up):
`sudo /usr/local/bin/join-cluster.sh` on the phone. It preflights clock, cgroup2
+ memory controller, modules, binary, token, and API reachability, failing
loudly rather than hanging.

**Host side for the phones (Proxmox):** forwarding + NAT per USB subnet, and —
easy to miss — **return routes inside LXC 200** so the control plane can reach
the kubelets (`kubectl logs`/`exec`), else a node registers then goes NotReady.
Full commands in `docs/phone-nodes.md`.

**Known limitation:** `CONFIG_IP_SET` is missing from the phone kernel, so
kube-router likely can't enforce NetworkPolicies on pods scheduled there —
taint the nodes until confirmed.

**Wings plan:** the owner wants Pelican's Wings on the phones (bare metal, so no
LXC blocker, and Docker is packaged for Alpine aarch64). Reality check:
**aarch64 runs Minecraft Java fine but NOT x86-only servers** (CS2, Valheim,
Rust, Palworld). Don't double up k3s-agent + Docker + a game server on 3.5 GB
RAM — pick one role per phone.

## MAM seedbox + Prowlarr — DONE this session

- Seedbox dynamic-IP updater runs as a 4th container in the gluetun pod
  (`apps/downloads/qbittorrent.yaml`), so it egresses through the VPN. **Working**:
  after the owner made a MAM session bound to the current exit's IP+ASN, a
  `pkill sleep` re-read the mounted seed (NOT a pod delete — that reconnects the
  tunnel and invalidates the session, the catch-22 that broke earlier attempts)
  and MAM returned `New session created`; cookie jar persisted to the PVC.
- Prowlarr MyAnonamouse indexer (id 37) live, real search returned results.
  `MAM_ID_PROWLARR` wired as a source-of-record secret (Prowlarr keeps indexer
  config in Postgres, so nothing mounts it).
- Owner declined pinning `SERVER_COUNTRIES` — the dynamic-seedbox endpoint is
  meant to handle IP changes; leave it roaming.

## Outstanding owner action items

1. **NAS** — recovered. If any pod is still wedged ContainerCreating/Terminating, force-delete it (stale NFS mount).
2. **`pixel3a3` password** — fix `PIXEL3A3_PASS` in Doppler, or run on the phone:
   `echo "travis ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/travis`.
3. **Navidrome first login** (creates the admin account) then
   `./docs/recovery/restore-navidrome-favorites.sh` (1,136 starred tracks
   exported; ~47% recoverable now, re-run as the library refills).
4. **akadmin password** — rotate in Authentik (owner chose to do this).
5. **CWA `kindle` user** with Allow Downloads + Allow Viewer.
6. **cnpg-backup MinIO account has root rights** despite a git comment claiming
   it's bucket-scoped — worth scoping down.
7. **Alloy / repo-review carry-overs** already handled or documented earlier in
   `docs/` (SMART alerts, Alertmanager SMTP, CI, seccomp, CNPG ScheduledBackup).

## Recurring gotchas proven this session (check these first)

- `fsGroup` without `fsGroupChangePolicy: OnRootMismatch` → kubelet recursively
  chowns the whole NFS volume on every roll → pod stuck ContainerCreating with
  only `context deadline exceeded`. Fixed on 6 apps; watch for new ones.
- Force-deleting a pod can leave a stale NFS mount that wedges the replacement
  in Terminating/ContainerCreating — force-delete the wedged one too.
- ArgoCD can report `Synced/Healthy` while the live object is stale
  (ServerSideDiff blind spot) — an explicit sync to the commit SHA fixes it;
  verify the live object when a change matters.
- Lidarr: never press "Search for Missing" — it queues one 31k-album command
  that jams the whole command queue for hours.
