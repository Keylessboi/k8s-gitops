# Doctor's log

One entry per incident: symptom first, then root cause, then the fix that
solved it, then what prevents a repeat. Newest first. If an incident
repeats, link the entries — a repeated incident means the prevention
failed and the entry needs revisiting.

New entries should also carry a **confidence** line — CONFIRMED, PROBABLE or
PROVISIONAL. The 2026-08-31 ghost entry said "root cause not fully pinned" and
everything downstream still treated it as settled, including a patch built on a
diagnosis that turned out to be wrong.

## Symptom index

**This index is the point of the file.** `scripts/doctor.sh <app>` greps here
by app name, and a model handed a symptom will grep for the error text. Search
the literal string you are seeing, then read the entry.

| If you are seeing… | Start at |
|---|---|
| `connection refused` from a pod that just started, where the NetworkPolicy allows it | kube-router race — 2026-08-29 (lidarr), 2026-09-03 (pg_dump) |
| `connection refused` between two namespaces, at any time | one-sided NetworkPolicy — 2026-09-03 (hermes → lidarr) |
| `ComparisonError`, `mapping key … already defined` | duplicate YAML key — 2026-09-03 |
| A pod Running and Healthy but doing nothing | one-sided NetworkPolicy — 2026-09-03; Obsidian never initialised — 2026-09-03 |
| Endless restarts behind a green dashboard | ghost probe redirect — 2026-09-03 |
| `Liveness probe failed: Get "https://…"` on a plaintext port | ghost probe redirect — 2026-09-03 |
| A Service with no endpoints after an edit | named-port contract — 2026-09-01; over-tight readiness probes — recurring |
| `[Unknown Album]` / `[Unknown Artist]` | Navidrome tags — 2026-08-29 |
| Backups "succeeding" with nothing stored | MinIO zero drives — 2026-08-29 |
| Everything on the host slow, API server 503 | swap thrash — 2026-08-31 |
| Disk full, or pods evicted for ephemeral storage | disk-pressure churn — 2026-08-31; ganesha.log 26 GB — 2026-08-31; Wings pulls — 2026-08-29 |
| A host unreachable at `192.168.1.240` intermittently | duplicate ARP claim — 2026-08-26 |
| `CrashLoopBackOff` immediately after adding `command:` | `command:` replaces ENTRYPOINT — 2026-08-31 |
| An *arr app that cannot reach another service by name | bare short hostnames — recurring class |
| ArgoCD says Synced but the object is stale | ServerSideDiff bug — 2026-08-31 |
| Everything on NFS slow, but disks and network test fine | pool IOPS saturated by seeding — 2026-09-12 |
| A database is slow but sequential file reads are fine | storage, not the app — 2026-09-12 |
| `Unrecognized host/PassKey` or `ASN mismatch` from MAM | session locked to the wrong ASN — 2026-09-12 |
| Moving big data off the NAS takes hours | stream over ssh, do not read via NFS — 2026-09-12 |
| Blocked from every published host, including Authentik itself | CrowdSec LAPI dead, frozen blocklist — 2026-09-11 |
| `403` in 0ms with no backend in the Traefik log | bouncer failing closed, restart Traefik — 2026-09-11 |
| "Broken for me, works for you" on a published host | you are probably in clientTrustedIPs — 2026-09-11 |
| A pod hung forever on a tiny read from an NFS volume, no error | stale NFSv4 delegation — 2026-09-11 |
| `(deleted)` in /proc/PID/fd for a file that plainly exists | stale NFS dentry cache — 2026-09-11 |
| A local `cp` on the NAS taking minutes for a few MB | delegation recall stalling local I/O — 2026-09-11 |
| ArgoCD `Synced` at the new revision but the change is not live | silent no-op sync — 2026-09-11 |
| A PostSync hook that never runs, with the manifest obviously correct | hooks create no diff — 2026-09-11 |
| `HTTP 401` on a call made AFTER authentication succeeded | remux auth headers are exclusive — 2026-09-11 |
| A CronJob failing every tick while the app it calls is merely busy | fatal transient — 2026-09-11 |
| Every downstream *arr broken after a key change | Prowlarr API key rotation — 2026-08-29 |
| A CronJob that vanishes seconds after you create it | manual CronJob run — 2026-08-29 |
| Stale NFS handles, pods stuck ContainerCreating | closet move — 2026-08-28 |
| SQLite slow to the point of unusable; `PRAGMA wal_checkpoint` taking seconds | SQLite on NFS — 2026-09-10 (remux) |
| `database disk image is malformed` after a migration | copied while the writer was running; `kubectl scale` loses to selfHeal — 2026-09-10 |
| Deployment 0/1 with NO pod and nothing to `kubectl logs` | PodSecurity rejection — read the ReplicaFailure condition — 2026-09-10 |
| `no successful lookups` from a torrent client, forever | DHT is UDP and the egress path is a TCP-only SOCKS5 proxy — 2026-09-10 |
| High load average but `ps` shows few blocked tasks, disk barely busy | you are counting processes, not threads — 2026-09-10 (`ps -eLo`) |
| A pod running with no limits although the chart declares them | Helm values at a path the chart does not read — 2026-09-10 (immich), 2026-09-09 (monitoring) |
| Pod stuck ContainerCreating, no events, `unmounted volumes=[…]: context deadline exceeded`, but the volume IS mounted | fsGroup chowning a huge NFS volume — 2026-09-09 (**check `fsGroupChangePolicy`**) |
| A pod recreated every couple of minutes, Deployment revision in the dozens | ArgoCD vs image-updater — 2026-09-05 (gluetun), 2026-09-09 (navidrome) |
| An alert that has been firing for days and never clears | scraping something k3s does not expose / probes for deleted apps — 2026-09-09 |

### The traps that have bitten more than once

Each of these is now a check in `scripts/ci/check-invariants.py`, because the
prose version of the prevention failed:

- **kube-router race** (2×) — any Job whose first act is a network call needs a
  `wait-*` initContainer.
- **One-sided NetworkPolicy** (4×) — a cross-namespace flow needs egress in the
  source *and* ingress in the destination.
- **Duplicate YAML keys** (1×, but silent) — PyYAML accepts them, Go's yaml does
  not. Validate with the same parser as the consumer.

## 2026-09-12 — the NAS was never slow; a thousand seeding torrents owned the disks

- **Confidence:** CONFIRMED (every layer measured independently).
- **Symptom:** everything touching NFS was slow, for weeks, in ways that each
  looked like a different application bug - Lidarr's API over 180s, Navidrome
  search failing while playback worked, remux lookups at 21s, crowdsec's
  bouncer failing closed, a 3.9 GB copy running at 0.79 MB/s, and a `chmod` on
  an empty directory taking five minutes to start.
- **The wrong answer I published first:** "this NFS mount is broken", on the
  strength of 111 MB/s raw TCP against 3 MB/s over NFS. **That test sent a
  memory buffer and never touched a disk.** It measured the network. Reading
  the same data locally on the NAS, cold, gives ~1.7-3 MB/s - so NFS was
  delivering essentially everything the pool could produce, and the 35x loss I
  reported did not exist.
- **Root cause:** the pool is IOPS-saturated. `zpool iostat -v` shows

      tank   211 read ops/s   3.71 MB/s     <- ~18 KB per read

  211 IOPS is the ceiling for a two-disk HDD mirror and it is fully consumed by
  small scattered reads. The consumer is **qBittorrent: 2,234 torrents, ~959
  seeding**, serving ~1.19 MB/s spread across a thousand torrents on a 4.4 TB
  pool, which is nearly pure seek. Everything else queues behind it.
- **Ruled out, each with a measurement, so nobody re-tests them:**
  - packet loss - `retrans 0` across 1.4 billion RPC calls
  - `nconnect=8` - remounted with it, 3.1 MB/s, unchanged
  - nfs-ganesha - it is kernel `nfsd` with 16 threads
  - a Proxmox rate limit - `pct config 200` has no `rate=`
  - file fragmentation - a file written in ONE pass reads at 2.9 MB/s against
    3.0 MB/s for one grown over months
  - failing disks - `smartctl -H` OK on both, pool ONLINE, resilvered clean
- **Fix:** queueing in qBittorrent (3 down / 8 up / 12 active) to cap the seek
  storm, plus moving every latency-sensitive workload off the pool (ADR-0009).
- **THE TRANSFER TRICK, which is the reusable part.** To move data off this
  pool, do NOT read it over NFS. The NAS reads its own disk at 121 MB/s, so
  stream it:

      ssh NAS 'doas cat /extra/nfs-csi/.../file' \
        | ssh pve "pct exec 200 -- sh -c 'cat > /var/lib/rancher/k3s/storage/<pv>/file'"

  Lidarr's 3.94 GB database: **2m22s at 27.6 MB/s**, against ~80 minutes over
  NFS. qBittorrent's 5,070-file config, as a streamed `tar`: **61 seconds**.
  And use `cp`, never `tar`, for any copy that does go over NFS - tar's 10 KiB
  blocks measured 0.42 MB/s against cp's 3.7 MB/s.
- **Prevention:** the tell is an application whose DATABASE or metadata
  operations are slow while sequential file reads are fine. That asymmetry is
  storage, not the app. Check the PVC's storage class before debugging the
  application.

## 2026-09-12 — MAM "Unrecognized host/PassKey" is an ASN lock, not a bad key

- **Confidence:** CONFIRMED (fixed and verified).
- **Symptom:** MyAnonamouse reporting `Unrecognized host/PassKey
  (23.130.104.134)`, and separately "no torrent clients active".
- **Root cause:** the seedboxapi log says it exactly, and is the only place it
  is said plainly:

      {"Success":false,"msg":"Invalid session - ASN mismatch",
       "ip":"23.130.104.134","ASN":62744,"AS":"Quintex Alliance Consulting"}

  The exit IP had NOT changed - `SERVER_NAMES: Aquila` pins it precisely so it
  will not. A MAM seedbox session is locked to the **ASN of the connection that
  created it**. A session created from a home browser locks to the home ISP's
  ASN, which will never match the VPN exit's ASN 62744, and MAM rejects it
  forever.
- **Fix:** create the session on MAM (Preferences → Security) with **"Switch to
  ASN locked session"** and **"Allow session to set dynamic seedbox IP"**,
  **while browsing through the same AirVPN exit** so MAM sees ASN 62744. Put
  the new value in Doppler as `MAM_ID`, then move the stale cookie aside -
  `/extra/nfs-csi/downloads/seedboxapi-config/MAM.cookies` - because
  seedboxapi prefers an existing cookie over the env var and will keep failing
  with a valid MAM_ID sitting right there. It then logs
  `New session created.`
- **`MAM_ID_PROWLARR` is a SEPARATE session and must stay separate:** Prowlarr
  egresses over the house WAN, a different ASN, so one session cannot satisfy
  both.
- **"No torrent clients active" is downstream, not a second fault.** MAM only
  knows what has announced to it; qBittorrent had been down or stuck in
  start-up across several restarts. It clears when the client announces again.
- **Prevention:** alert on seedboxapi exiting non-zero. It failed, logged the
  exact cause, and retried hourly for as long as nobody read the log.

## 2026-09-11 — locked out of everything, and CrowdSec had been dead since the 10th

- **Confidence:** CONFIRMED for the failure and the recovery. PROBABLE for
  which of the two repair steps was the one that mattered — see the caveat.
- **Symptom:** reported as "I think I'm blocked from octo.sandstorm.chat",
  then navidrome, then "and authentik, so that's its own thing". Being blocked
  from Authentik ITSELF is the tell: not an app problem, but the middleware
  chain in front of every published host. The same hosts answered normally
  from a different IP (302), so the edge, Traefik and the certs were all fine.
- **What was actually broken:** `crowdsec-lapi` had been crashlooping on a
  5-minute cycle since **2026-09-10 00:14**, killed each time by its startup
  probe (failureThreshold 30 x 10s). It never reached the API: it hung inside
  the entrypoint on

      cscli -c /etc/crowdsec/config.yaml machines list -o json

  which feeds a `yq` that checks whether this pod's machine is registered.
  Sampled every 15s, the SAME pid sat there past 2m22s and never returned —
  hung, not slow, on a 24-row table.
- **The dead ends, recorded because they were expensive:**
  - *"The SQLite database is corrupt."* It is not. Copied off, it reports
    `integrity_check: ok` with 5135 decisions, and opens in milliseconds even
    with its stale `-journal` present.
  - *"SQLite on NFS is too slow, move it to local-path"* — the conclusion
    every other app this week earned. Measured instead of assumed: a copy of
    the same database, opened read-write on the SAME NFS export, connected in
    1.77s and committed a write in 7.52s. Slow, but nowhere near a hang. The
    planned local-path migration was dropped on that evidence.
- **Root cause:** stale NFSv4 state on the client. `/proc/locks` on the NAS
  showed an ACTIVE WRITE **delegation** pinned to the database's inode:

      5253: DELEG  ACTIVE    WRITE 2398 00:2f:40268    <- inode of crowdsec.db

  Every new opener blocked waiting on a delegation recall that never
  completed. Two things confirm it was the delegation and not the data: a
  server-side `cp` of that 7 MB file, on local ZFS, took **2m17s** (the local
  read triggers the same recall), and the hung process's fd read
  `/var/lib/crowdsec/data/crowdsec.db (deleted)` — the client still resolving
  the cached name to the old filehandle. All three NFS clients were confirmed
  and renewing, so this was not an expired client record.
- **Fix, in the order it was done:**
  1. Server-side on the NAS: copied the database to a fresh inode, verified
     it (`integrity_check: ok`), then atomically swapped it in, keeping the
     originals as `crowdsec.db.stale-20260911` and
     `crowdsec.db-journal.stale-20260911`. **This alone did NOT fix it** — the
     next pod hung in exactly the same place.
  2. Dropped dentry/inode caches on BOTH the k3s CT and the Proxmox host
     (`sync; echo 2 > /proc/sys/vm/drop_caches`), then deleted the pod.
     It came Ready in 89s: `CrowdSec Local API listening on 0.0.0.0:8080`,
     health 200, community-blocklist update running. `cscli` answers
     instantly again.
- **CAVEAT, stated rather than glossed:** because step 2 followed step 1,
  this does not prove step 1 was necessary. The cache drop is what immediately
  preceded recovery, and the "(deleted)" fd points at client-side caching
  rather than at the file. If this recurs, **try the cache drop first** and
  leave the database alone.
- **Who was actually blocked:** nobody, by decision. Every one of the 5135
  decisions had `origin = CAPI`, the community blocklist; there were ZERO
  locally-issued bans. What blocked people was the Traefik bouncer, which
  caches the decision list and — with LAPI dead since the 10th — could never
  refresh it. Its last successful pull was `2026-09-10T00:09`, minutes before
  LAPI died. The list was frozen, so nothing expired and nothing could be
  deleted. After the fix the list drains to **0 active decisions**.
- **Latent issue found alongside:** `machines` had grown to 24 rows and
  `bouncers` to 19, for one agent and one bouncer. The entrypoint registers by
  POD NAME, which changes on every restart, so each restart leaves another
  dead registration behind.
- **Prevention:** a security component that fails by FREEZING its own
  allow/deny list needs an alert on the COMPONENT, not on its decisions. This
  ran dead for a day and a half and the only signal was a Degraded dot in
  ArgoCD that nothing was watching. A bouncer whose `last_pull` is hours stale
  is the specific thing to alert on.

### The part that actually restored access: restart Traefik

Fixing LAPI did NOT unblock anyone, and the entry above would have left the
next reader believing it did. The report came back: "still blocked from
authentik".

- **What was really rejecting people:** the Traefik CrowdSec bouncer plugin,
  failing CLOSED. Traefik's access log shows `403` in **0ms with no backend**
  (`"-"` where the upstream URL goes) - a middleware verdict, reached before
  routing. One IP took 403 on authentik, immich and ghost in the same second,
  which is the signature of a global middleware rather than any one app.
- **Why it did not heal itself:** the plugin runs `crowdsecMode: stream`. It
  lost its stream when LAPI died on the 10th and stayed in that state. The
  Traefik pod was 3d4h old, so a healthy LAPI underneath changed nothing -
  `cscli decisions list --ip <addr>` returned `[]` for every blocked address,
  proving CrowdSec had decided nothing about them.
- **Fix:** `kubectl rollout restart deploy/traefik -n kube-system`. Access was
  restored immediately, and no 403 has appeared since.
- **THE METHODOLOGICAL TRAP, which cost most of the time here.** The middleware
  carries an allowlist:

      clientTrustedIPs: [10.42.0.0/16, 10.43.0.0/16, 192.168.1.0/24,
                         74.101.53.75/32, 144.62.224.77/32]

  The workstation used for testing is **74.101.53.75** - on that list. So every
  "I verified the edge, it returns 302" check was run from an address exempt
  from the middleware doing the blocking. It could never have reproduced the
  bug, and it was used as evidence the edge was fine. **A reachability test
  from a trusted IP proves nothing about untrusted clients.** When a report is
  "it's broken for me, fine for you", check the allowlist BEFORE trusting any
  of your own probes, and read the access log for the reporter's address
  instead - that is what finally identified both the IP and the verdict.

## 2026-09-11 — ArgoCD said Synced, twice, and had applied nothing

- **Confidence:** CONFIRMED (two different causes, each reproduced).
- **Symptom:** a commit was pushed, ArgoCD reported `Synced / Healthy`
  against the NEW revision, and the change was simply not live. No
  ComparisonError, no Degraded, nothing red anywhere. For prowlarr the
  Deployment ran without the initContainer the commit added; for remux a
  PostSync hook never ran.
- **How it was caught:** `.status.sync.revision` and
  `.status.operationState.finishedAt` disagree. The first is the revision
  ArgoCD last COMPARED; the second is when it last APPLIED. prowlarr
  reported revision `0159339` while its last sync operation had finished
  at 11:57 that morning, hours and several commits earlier. The audit is:

      kubectl get app -n argocd -o json | ... .status.operationState.finishedAt

  A long `finishedAt` age is normal for an app nobody has changed — that is
  GitOps working. It is only a signal when the app's files DID change.
- **Root cause — two of them, which is why it looked so confusing:**
  1. **prowlarr: the ServerSideDiff bug class** (see 2026-08-31, "the
     ServerSideDiff bug is a class, not an app"). The earlier entries all
     describe it surfacing as a loud `omits key field name`
     ComparisonError. This time it was SILENT: the diff simply failed to
     see an added initContainer and concluded the app was in sync. The
     appset carries a documented opt-out list for exactly this, and
     prowlarr was not in it.
  2. **remux: not a bug at all.** The only thing that commit added was a
     PostSync hook Job. Hooks are not tracked resources and are not part
     of desired state, so adding one creates NO DIFF. No diff means no
     sync operation, and a PostSync hook only runs as part of a sync
     operation. A hook added on its own therefore never runs until
     something else changes — the manifest is correct and inert.
- **Fix:** added `prowlarr` to the `ServerSideDiff=false` list in
  apps/argocd/root-applicationset.yaml. For both apps, an explicit sync
  operation applied everything correctly:

      kubectl patch app -n argocd <app> --type merge \
        -p '{"operation":{"initiatedBy":{"username":"you"},
             "sync":{"revision":"HEAD","prune":true}}}'

  Note `argocd.argoproj.io/refresh=hard` is NOT enough. It re-compares and
  advances `.status.sync.revision`, which makes the app look freshly
  handled while still applying nothing. It was tried first and wasted
  several minutes for exactly that reason.
- **Prevention:** after pushing a change, verify the OBJECT, not the
  Application status. `Synced/Healthy` is not evidence that a specific
  commit was applied. When a commit only adds a hook, trigger a sync
  explicitly or expect it to fire on the next unrelated change.

## 2026-09-11 — remux 401s on a request that had already authenticated

- **Confidence:** CONFIRMED (measured all three header combinations).
- **Symptom:** the addon-bootstrap hook failed every attempt with
  `HTTPError: 401 Unauthorized`, which reads as a wrong admin password.
  It was not: the traceback pointed at `GET /Addons`, one call AFTER
  `POST /Users/AuthenticateByName` had returned a valid AccessToken.
- **Root cause:** remux treats the two Jellyfin auth headers as mutually
  exclusive, and sending both is worse than sending either. Measured:

      X-Emby-Token + X-Emby-Authorization -> HTTP 401
      X-Emby-Token alone                  -> 200, 7 addons
      X-Emby-Authorization with Token=""  -> 200, 7 addons

  It reads `X-Emby-Authorization` first; present but carrying no `Token=`
  field means unauthenticated, whatever `X-Emby-Token` says. The job built
  ONE header dict for every request and always included the login header,
  so every authenticated call sabotaged itself.
- **Fix:** send `X-Emby-Authorization` only on the login call.
  apps/remux/user-sync-cronjob.yaml had always been correct here by
  accident — it happens to build a fresh header dict for its authenticated
  calls instead of reusing the login one.
- **Prevention:** when a 401 appears, check WHICH call raised it before
  suspecting the credential. A 401 after a successful authentication is
  almost never the password.

## 2026-09-11 — a reconciler that failed four times an hour over a slow upstream

- **Confidence:** CONFIRMED (reproduced, and the fix verified by a manual run).
- **Symptom:** "still getting octo errors" — octo-artist-on-heart failing
  every 15 minutes, with a notification each time.
- **Root cause:** `GET /api/v1/artist` against Lidarr exceeded its 180s
  timeout. Lidarr was saturated by the two mass-search jobs (node load
  28.7, memory 88%) and does not answer a full artist listing under that
  load. Nothing was wrong with Octo, the shim, or the credentials — the
  job got as far as `starred artists: 96` every time.
- **The actual defect** was not the timeout value. Every network call in a
  RECONCILER was treated as fatal. This job re-derives its work from
  scratch each run and adds at most one artist, so a timeout means "ask
  again later", not "something is broken".
- **Fix:** transient transport errors (timeouts, refused, resets, 429,
  5xx) now end the run at exit 0 with a line saying why; real errors — a
  401, a bad profile id, a malformed response — still fail loudly.
  `HTTPError` must be tested BEFORE `URLError` since it is a subclass;
  without that ordering a 401 is silently swallowed as transient.
  Verified by a manual run: `lidarr did not answer in time (TimeoutError);
  nothing added this run, retrying on the next schedule`, Job Complete.
- **Prevention:** any job on a short schedule that reconciles from scratch
  should treat upstream slowness as a skip, not a failure. Alert on a
  condition persisting, not on one tick of it.

## 2026-09-10 — Remux: one slow disk, and everything that fell out of fixing it

This is one causal chain, recorded together because each step was caused by the
previous one and two of the steps were self-inflicted.

**1. The UI took tens of seconds per action.** Not CPU: measured during a page
load, remux never exceeded 2m CPU and aiostreams never moved off 1m. Its own
log named it — single-row primary-key lookups against SQLite taking **17-21
seconds**, `PRAGMA wal_checkpoint` taking 12.9s, and a connection pool
exhausted behind them. The database was a 324 MB SQLite file on **nfs-csi**.
SQLite on NFS is the worst case, not merely suboptimal: it coordinates through
POSIX byte-range locks that become network round trips, every commit fsyncs,
and in WAL mode the `-shm` file is a shared mmap NFS cannot properly provide.
Moved to local-path. Postgres was never an option — remux compiles only the
SQLite driver (`sqlx` features `sqlite`, no `postgres`).

**2. I corrupted the copy.** The migration used `kubectl scale` to stop remux.
ArgoCD selfHeal put the replica back part-way through, so remux wrote to
`db.sqlite` while `cp` was still reading it, and SQLite rejected the result:
`database disk image is malformed`. **`kubectl scale` is not a lock on a
selfHeal cluster; it is a suggestion.** Stopping a workload for a data
migration has to be done in git, or not at all.

**3. Wiping and rebuilding lost more than expected.** With the owner's
agreement the database was rebuilt from empty, on the basis that this repo is
built to reconstruct it — `admin-job.yaml` seeds the admin account
idempotently and says so, and `user-sync-cronjob.yaml` recreates an account per
authentik user. Both worked. What nobody had written down is that **addon
registrations live only in that database**: the rebuilt instance came up with
the 5 built-in defaults and without AIOStreams (`stremio`) or Prowlarr
(`torznab`), which are the two that supply streams. TMDB survived, so titles
and artwork looked correct and the loss was invisible until playback produced
`streams synced streams=0 sources=[]` and a black screen. Recovered by reading
the addon rows out of the pre-wipe database — which passes
`PRAGMA integrity_check` — and POSTing them back through `/Addons`.
**Before wiping any app's state, enumerate what is ONLY there.**

**4. Then it still took a minute to start a stream, and that was a third,
separate cause.** remux ran as a single container reaching the internet through
the shared gateway's SOCKS5 proxy. SOCKS5 is TCP-only, so DHT (UDP) could never
work — the log said `no successful lookups` every ~30 seconds, permanently —
and nothing could connect in. Fixed by giving remux its own gluetun sidecar:
containers in a pod share a network namespace, so its traffic now leaves on
tun0 with UDP and an AirVPN forwarded port. Afterwards: **0 DHT errors**.

- **The trap that nearly took the download stack down with it.** The remux
  DopplerSecret synced the *same* AIRVPN_* values the downloads pod uses, and
  said so: "credentials are reused". AirVPN WireGuard is one session per key
  pair, so a second gluetun on that key would have made both tunnels flap,
  taking qBittorrent, slskd and the seedbox API with them. **Hash the keys and
  compare before wiring a second consumer.** The first `.conf` supplied was a
  config for the *existing* device on a different server — same private key,
  different filename and endpoint. A new .conf is not a new device.
- **Two comments were actively wrong and cost real time.** `qbittorrent.yaml`
  said "the gluetun sidecar has been removed" — untrue since commit 95397f6,
  and read as current during this diagnosis. `remux/deployment.yaml` said
  librqbit's raw TCP "egresses from the node's WAN, not the VPN tunnel" — it
  did not; the NetworkPolicy dropped it. Wrong in the reassuring direction.
- **PodSecurity failure has no pod to debug.** gluetun needs NET_ADMIN *and* a
  hostPath `/dev/net/tun`; `baseline` forbids both, and the ReplicaSet then
  cannot create a pod at all. `get pods` is empty and there is nothing to
  `logs`. The reason is on the Deployment's **ReplicaFailure** condition and in
  namespace events, nowhere else.
- **A stuck sync deadlocked the fix.** The operation sat at
  `waiting for healthy state of apps/Deployment/remux` while the Deployment
  waited on the namespace label in that same blocked sync. Broken by applying
  the label directly with `kubectl label` — identical to git, so no drift.
- **Confidence:** CONFIRMED throughout. Each step was verified by the number it
  was supposed to move: 21s queries → 394µs; `streams=0` → `streams=16`;
  constant DHT failures → zero; and qBittorrent's tunnel unchanged on its own
  exit IP the whole time.

## 2026-09-10 — The heartbeat receiver was emailing every five minutes

- **Symptom:** owner reported email "every 10 minutes", indefinitely.
- **Root cause:** the `heartbeat-ntfy` Alertmanager receiver carried an
  `email_configs` block alongside its webhook, and the route that feeds it
  matches `Watchdog` with `repeat_interval: 5m`. Both are correct alone.
  Watchdog is the dead-man's switch — it fires permanently by design, and the
  short repeat is the point, because it is the ABSENCE of beats that carries
  information. Aimed at an inbox that is a message every five minutes saying
  nothing is wrong.
- **Fix:** webhook only. The comment above the receiver already said "nothing
  reads the body - only the arrival time matters", so a human recipient was
  never intended. Verified after: 0 of 18 firing alerts route to email, and the
  beat still lands on pve.
- **The generalisable lesson:** a heartbeat is consumed by a machine. If a
  person should hear about it, the watcher says so when beats STOP.

## 2026-09-10 — A log line was failing the Vaultwarden backup

- **Symptom:** `vaultwarden-data-backup` failed three consecutive runs, firing
  KubeJobFailed each time, while the backup itself was fine.
- **Root cause:** `mc mirror` succeeded every run (0 B — already in sync), then
  the `mc du` on the next line exited 1 with "is not a folder", and `set -eu`
  failed the whole Job.
- **Why the shape was confusing, and what settled it:** the pods died in ~20
  seconds, far short of the 60s sleep in the retry loop above, so `mc mirror`
  had never returned non-zero and that loop had never engaged — which ruled out
  the connection-refused theory the file documented. **The fault was after the
  loop, in the reporting.** The size report is now best-effort.
- **How it was found at all:** the previous day's change to
  `restartPolicy: Never` was made specifically so a failed attempt would leave
  a pod behind to read, because every earlier attempt returned "You must
  provide one or more resources by argument". The next failure was legible in
  about a minute. **Diagnosability is worth committing before the diagnosis.**
- **Confidence:** CONFIRMED. Verified the bucket independently: 78 objects
  including `rsa_key.pem`.

## 2026-09-10 — Load 47 overnight with the disk 4.6% busy: counting processes instead of threads

- **Symptom:** everything degraded overnight and the phone filled with alerts.
  Load average **47** against a baseline of ~7, 50% iowait, sustained for twelve
  hours and still climbing when looked at.
- **The measurement that was wrong for an hour.** `ps -eo stat` showed only
  **6** tasks in R+D. Load 47 with 6 blocked tasks is a contradiction, and I
  spent real time chasing NFS server health, dmesg, mountstats and disk
  utilisation because of it. The NVMe was **4.6% utilised** at ~3 MB/s and the
  NAS was 97% idle at load 1.3, so nothing looked saturated anywhere.
  **`ps -eo stat` prints one line per PROCESS. Load average counts THREADS.**
  `ps -eLo stat` gave 44 blocked threads against a load of 44.13 - an exact
  match, and the whole picture resolved at once.
- **A second measurement that lied in the same hour:** `/proc/<pid>/io`
  `read_bytes` counts block-device I/O only and **excludes NFS entirely**, so
  the per-process totals came back at fractions of a MB/s while the machine was
  50% in iowait. On a node whose working set is NFS, that counter is close to
  meaningless.
- **Root cause: three library walkers over NFS at once**, none of them
  individually alarming, cumulatively fatal to latency -
  Lidarr ~12 blocked threads, Immich ~12, qBittorrent ~10.
  - **Lidarr had 216 commands stuck in "started"**, `ProcessMonitoredDownloads`
    wedged for 13.5 hours, fed by two `lidarr-mass-search` Jobs that have been
    running for six days. Restarting it took load **47 -> 26** on its own.
  - **Immich was running its nightly integrity check permanently.** 31
    consecutive batches of 10,000 files over 31 hours, every one reporting **0
    missing**. `missingFiles` and `untrackedFiles` default to `0 03 * * *` with
    no time limit; a pass over this library on NFS cannot finish inside a day,
    so each night's run starts while the last is still going and it never stops.
    Now weekly. (`checksumFiles` was left daily - it self-limits to one hour and
    1% per run, which is exactly the property the other two lack.)
  - qBittorrent is the largest remaining contributor and is untouched.
- **Immich also had no resource limits at all** - `BestEffort`, `resources: {}`,
  no nodeSelector - because the chart values were written as bare `resources:`
  and `nodeSelector:` keys under `server:`. immich 0.12.0 wraps bjw-s common,
  which reads `controllers.<n>.containers.<n>.resources` and
  `controllers.<n>.pod.nodeSelector`; a bare key at the top level is silently
  discarded. **This is the third instance of the same class in three days**
  (monitoring metricRelabelings, then this, plus the ML `tag:` indented as a
  sibling of `image:`), and the lesson has to stop being restated and start
  being checked: **after any Helm values change, read the running object, not
  the manifest.** Helm never errors on a key it does not recognise.
- **Confidence:** CONFIRMED. Thread counts match load exactly, and each
  intervention moved the number in the predicted direction.
- **The generalisable lesson:** when load average and your task count disagree
  by an order of magnitude, the counter is wrong before the kernel is. Check
  whether you are counting the same things the kernel counts.

## 2026-09-09 — beets-import sat in ContainerCreating for 9 hours: fsGroup was chowning a 2 TB NFS tree

- **Symptom:** the import pod never started. Nine hours in `ContainerCreating`,
  and because the CronJob is `concurrencyPolicy: Forbid`, every later run was
  blocked behind it — music imports were dead the whole time, reported only as
  one `KubeJobFailed` among eleven other alerts nobody could act on.
- **Root cause:** `fsGroup: 1000` with the policy left at its default of
  `Always`. That makes the kubelet **recursively chown every mounted volume
  before the container starts**, and this pod mounts `/extra/nfs-csi/data` — the
  entire music library plus the torrent trees, over NFS. The walk is O(files)
  and does not finish.
- **Fix:** `fsGroupChangePolicy: OnRootMismatch`. The volume root is already
  `gid 1000, mode 2775`, exactly what fsGroup wants, so the walk is skipped
  entirely. **Verified: 9 hours of ContainerCreating became Running in 20
  seconds.**
- **Why it was so hard to see, which is the transferable part.** Every signal
  pointed at storage and every one of them was a red herring:
  - The pod has **no events at all**. Not one.
  - kubelet says only `unmounted volumes=[data] ... context deadline exceeded`.
  - `/proc/mounts` shows the volume **mounted and responsive** — `stat -f`
    returns instantly.
  - The CSI driver logs the mount as **succeeded**, in milliseconds.
  All true simultaneously, because the mount *does* succeed immediately; it is
  the ownership pass afterwards that never returns, and kubelet reports a volume
  whose SetUp has not returned as "unmounted".
- **The evidence that settled it was not in Kubernetes.** On the NAS,
  `find /extra/nfs-csi/data/media/music -cmin -30 | wc -l` returned **12,448** —
  files marching alphabetically through the library having their ownership
  rewritten. Nothing in `kubectl` shows this. **When a pod is stuck on a volume
  and the cluster says nothing, go look at the filesystem.**
- **This repo already knew the rule and this file broke it.** navidrome, octo,
  lidarr and qbittorrent each carry `fsGroupChangePolicy: OnRootMismatch` with a
  comment describing this exact failure. beets-import was the only place that
  set `fsGroup` and left the policy default. Every other `fsGroup` in `apps/` was
  checked afterwards; all have a policy.
- **The clue I had from the first minute and misread for hours:** the beets
  *Deployment* sets no `fsGroup` at all. Same image, same two PVCs, same node —
  the web UI runs fine while the importer never starts. That difference was
  visible immediately and pointed straight at the pod spec. I read it as
  evidence about storage instead.
- **Wrong turns, and what they cost.** Two published conclusions before the right
  one: that the failure needed a *combination* of two PVCs, and that Navidrome's
  restart loop was starving the shared NFS export. Both were inferred from
  correlation between tests run minutes apart in a system I was changing
  underneath myself — my own force-deletes were creating and clearing orphaned
  mounts between measurements, so results flipped and each flip looked like a
  new signal. A `nas`-vs-`k3s-server` comparison seemed decisive and was not: the
  busybox probe I ran there had no `fsGroup`, so it was never running the same
  experiment. **A comparison only isolates a variable if the two sides differ in
  exactly that variable — mine differed in the one that mattered.**
- **A real, separate defect found on the way:** force-deleting a pod stuck on a
  CSI volume leaves an **orphaned kubelet pod directory still holding the NFS
  mount**. kubelet cleans up only orphans with no mounts; a mounted one blocks
  later pods wanting that volume. Remedy: `umount -l` the paths, then remove
  `/var/lib/kubelet/pods/<uid>`. So do not force-delete a pod stuck on a CSI
  volume without clearing up after it — and note that this defect is what made
  the headline symptom *look* intermittent.
- **Prevention:** the invariant is checkable and worth adding to
  `scripts/ci/check-invariants.py` — **any pod spec setting `fsGroup` must also
  set `fsGroupChangePolicy`**. Every manifest in this repo already satisfies it,
  so it would land green and stay that way. Not yet written.
- **Confidence:** CONFIRMED. The chown walk was observed directly on the NAS, the
  repo's own prior art describes the same mechanism, and the fix took the pod
  from nine hours to twenty seconds.

## 2026-09-09 — Navidrome restarted every 2m15s for 61 revisions: the image tag disagreed in two files

- **Symptom:** Navidrome pods were seconds old whenever looked at, Deployment
  revision **61**, replicasets alternating `0.58.0` / `0.63.2`. Nothing alerted;
  the app answered normally between restarts.
- **Root cause:** the tag in `imageName` in `apps/image-updater/imageupdaters.yaml`
  is a semver **constraint**, not a note about the current version. It pinned
  `deluan/navidrome:0.58.0` while `apps/navidrome/deployment.yaml` deployed
  `0.63.2` — commit `99e4fb0` bumped the Deployment and not the updater policy.
  Every 2m15s image-updater set the live Application back to 0.58.0 and ArgoCD
  selfHeal returned it to 0.63.2. Neither could win.
- **This is the gluetun bug again** (task #37): two controllers with opposite
  opinions about one image and selfHeal on. There it was a digest, here a tag
  changed in one file of two — which is why the prevention from last time did
  not catch it.
- **Fix:** one line, `0.58.0` → `0.63.2`. Verified over 6 minutes: revision
  stable at 61, zero `Setting new image` log lines, pod age growing past 11
  minutes. The other seven managed images were checked at the same time and all
  agree with what git deploys.
- **Collateral worth noting:** the loop had the CSI node driver publishing and
  force-unmounting Navidrome's NFS media mount continuously. That is *not* what
  broke `beets-import` above — fixing this changed nothing there — but it is the
  noise the other diagnosis had to be separated from.
- **Confidence:** CONFIRMED, from image-updater's own log lines and a stable
  revision after the change.

## 2026-09-09 — Prometheus had no size ceiling at all, and 36% of the TSDB was control-plane histograms

- **Symptom:** none yet. Found by checking a change I had made earlier the same
  day rather than by anything failing.
- **Root cause:** `retention: 180d` was set on the assumption the 20Gi PVC bounded
  it. It does not — nfs-csi is a plain directory on an NFS export with no quota,
  and `df` inside the pod reports the whole 5.4T pool. Prometheus was free to
  grow for six months on the pool that also holds the music library. This is the
  disk-full outage of 2026-09-08 waiting to happen again, one pool over.
- **Fix:** `retentionSize: 45GB` — the only ceiling that exists here — sized from
  measurement (4.5G held ~14 days at 152k series). Plus `metricRelabelings`
  dropping eight control-plane histogram families, **55,228 series, 36% of the
  TSDB**, every one checked against `/api/v1/rules` first for zero dependants.
  `apiserver_request_sli_duration_seconds` was deliberately kept despite being
  the third largest: 23 rules depend on it.
- **Also, alerts that could never clear.** `KubeSchedulerDown`,
  `KubeControllerManagerDown` and `KubeProxyDown` had been firing continuously
  for 30+ hours because the chart assumes kubeadm and k3s exposes none of those
  ports — all four ServiceMonitors had `endpoints: NONE`. Four edge blackbox
  probes were the same story: grafana (deliberately disabled), forgejo,
  invidious and obsidian (apps deleted from this repo, probes left behind).
  Firing alerts went **28 → 15**.
- **The generalisable lesson, and it is the one this log keeps relearning:**
  a permanently-red alert is worse than no alert, because it teaches you to stop
  reading the list. The Vaultwarden backup that failed three consecutive runs the
  same day did fire `KubeJobFailed` — into a list that already had eleven rows
  nobody could act on.
- **Confidence:** CONFIRMED for the cardinality and the empty endpoints, both
  read from Prometheus and the API server. The retention projection is arithmetic
  from a 14-day sample, so treat the 45GB as sized, not measured to exhaustion.

## 2026-09-03 — csi-nfs-controller's 135 restarts are a symptom, plus a sidecar that never worked

- **Symptom:** `scripts/doctor.sh` surfaced `csi-nfs-controller` with **135
  restarts** — the largest unexplained number in the cluster. Also
  image-updater 39, doppler-operator 37, cnpg 36. Nobody had noticed any of them.
- **Root cause, part 1 — the restarts are not a CSI bug.** Only three of the five
  containers restart: `csi-provisioner` (48), `csi-resizer` (44),
  `csi-snapshotter` (43). The `nfs` driver itself and the liveness probe have
  **zero**. All three die the same way:
  `Failed to renew lease ... Put .../leases/...: context deadline exceeded` →
  `Stopped leading` → exit 255. CSI sidecars exit **by design** when they lose
  leader election, and the kubelet restarts them.
  So 135 restarts means 135 moments the API server was too slow to service a
  lease renewal. This is the resource-exhaustion class wearing a different hat,
  and the same count pattern across image-updater, doppler-operator and cnpg —
  all leader-electing controllers — is the corroboration. The 16:03–16:06Z
  terminations line up exactly with the restore drill that restarted the
  apiserver twice earlier the same day.
- **Root cause, part 2 — a sidecar that has never worked.** `csi-snapshotter`
  additionally logs, continuously:
  `failed to list *v1.VolumeSnapshotContent: the server could not find the
  requested resource`. The VolumeSnapshot CRDs are not installed —
  `kubectl get volumesnapshot` reports the resource type does not exist. The
  sidecar has therefore been erroring since the day it was deployed.
- **Fix:** `controller.enableSnapshotter: false`. Nothing here uses volume
  snapshots and nothing is planned to — point-in-time recovery comes from CNPG
  WAL archiving, file history from sanoid, off-site from restic and borgmatic.
  Installing the CRDs plus a snapshot-controller to satisfy a sidecar nobody
  uses would add moving parts to a cluster ADR-0007 froze.
- **Prevention:** none needed for part 2 — it is a one-time configuration
  correction. For part 1 the prevention is headroom, which is already ADR-0007's
  decision #1 and its stated tripwire.
- **Confidence:** CONFIRMED for both. The lease-renewal failures and the missing
  CRDs are both read directly from the containers' own logs and the API server.
- **The generalisable lesson:** a restart count is a *symptom*, and the useful
  question is which container and with what exit reason.
  `lastState.terminated` answered this in one field — the same field that
  contained the whole Ghost diagnosis. A high restart count on a multi-container
  pod says almost nothing until it is broken down per container.

## 2026-09-03 — Immich had no machine learning: the namespace denied its own pods

- **Symptom:** owner reported "immich machine learning isn't working". Smart
  search, face detection and CLIP jobs silently did nothing.
- **Root cause:** `apps/immich/networkpolicy.yaml` is a default-deny ingress
  policy (`podSelector: {}`, `policyTypes: [Ingress]`) whose only rules admit
  `kube-system` on 8089 and 2283. **Nothing allowed immich → immich.** A
  default-deny ingress policy denies POD-TO-POD traffic inside its own namespace
  too, which is easy to miss when every other rule in the file is about letting
  traffic in from outside. `immich-server` could not reach
  `immich-machine-learning:3003`.
- **How it was found:** `curl` from inside `immich-server` returned
  **`000` in 0.0058s to the Service and 0.0002s to the pod IP.** The *speed* is
  the diagnosis: a dead pod or missing route times out, an instant refusal is a
  policy REJECT. The ML pod was listening the whole time — `/proc/net/tcp6`
  showed `0BBB` (3003) in state `0A` — and its only established connections came
  from `10.42.0.1`, the node's kubelet. **Probes therefore passed**, so both pods
  were Running with 0 restarts, ArgoCD was Synced/Healthy, the edge probe
  returned 200, and no alert fired. Invisible from every direction that is
  normally checked.
- **Fix:** an ingress rule admitting the `immich` namespace to itself.
- **Prevention:** intended to be a check, and **the check was written and then
  deliberately dropped** — see below.
- **Confidence:** CONFIRMED for the diagnosis (reproduced twice, both by Service
  name and pod IP). See the open question before treating the general rule as
  settled.
- **RESOLVED, same day — the check was right and I was wrong to withdraw it.**
  The check was first withdrawn because it flagged **remux**, where
  `remux → aiostreams:3000` returns 200, which looked like a false positive.
  Testing the *other* direction settled it: `aiostreams → remux:3000` is
  REJECTed, and the live policy admits only `kube-system` and `authentik`. So
  remux genuinely was missing the rule; one direction happening to work does not
  make a missing rule correct, and "it works" is not the same claim as "it is
  allowed".
  Two measurement traps were burned through on the way, both worth remembering:
  the first remux test used `curl` inside a container with `HTTP_PROXY` set, so
  it silently traversed the VPN gateway instead of the direct path; and the pod
  that appeared to prove the point had an explicit `NO_PROXY` entry the other
  did not. **When testing a NetworkPolicy from inside a pod, pass
  `--noproxy '*'` or the measurement is not testing what you think.**
  The intra-namespace rule is now added to remux as well, and the check is
  shipped in `scripts/ci/check-invariants.py` (331 checks).

## 2026-09-03 — A duplicate YAML key parked lidarr at ComparisonError; the local check could not see it

- **Symptom:** `lidarr` showed sync status `Unknown`, health `Progressing`, and
  `Failed to load target state: ... kustomize build ... failed exit status 1:
  line 61: mapping key "protocol" already defined at line 60`. The app stopped
  picking up new commits and sat on the previous revision.
- **Root cause:** the fix for the hermes ingress appended
  `ports: [- port: 8686, protocol: TCP]` immediately before an existing
  `protocol: TCP`, producing the key twice in one mapping.
  It was pushed because the pre-push check could not detect it:
  **PyYAML's `safe_load_all` accepts duplicate keys silently and keeps the last
  value**, so `python3 -c "yaml.safe_load_all(...)"` returned clean. Go's yaml —
  which kustomize, ArgoCD and the API server all use — refuses outright.
  `.yamllint.yaml` has `key-duplicates: enable` and would have caught it, but
  yamllint was not installed locally and only runs in CI.
- **Fix:** removed the duplicate line. Verified with `kubectl kustomize
  apps/lidarr`, which is the parser that actually matters.
- **Prevention:** added a third check to `scripts/ci/check-invariants.py` that
  loads every tracked YAML file with a `SafeLoader` subclass whose mapping
  constructor raises on a repeated key — i.e. validating with the same
  strictness as the consumer rather than the most permissive parser to hand.
  It reproduces the failure when the duplicate is reintroduced and is clean
  otherwise. This closes the gap where a local check passes and CI is the first
  thing to notice.
- **Confidence:** CONFIRMED — reproduced both the ComparisonError and the
  check's detection of it.
- **The general lesson**, which is worth more than this bug: *validate with the
  same parser as the consumer.* A permissive local check that disagrees with
  the strict remote one is worse than no local check, because it grants
  confidence it has not earned. ComparisonError is especially unforgiving here
  because it fails the ENTIRE Application and does so quietly — auto-sync keeps
  reporting the last good state, so a broken push looks exactly like a
  successful one.

## 2026-09-03 — Hermes could never reach Lidarr; the NetworkPolicy was declared on one side only

- **Symptom:** none visible. `hermes` reported Running 1/1 for seven days,
  ArgoCD showed Synced/Healthy, and nothing alerted. It simply never did the
  job it exists for.
- **Root cause:** `apps/hermes/networkpolicy.yaml` declares egress to
  `lidarr:8686`, with the comment "Lidarr's API - the whole point of running
  this." `apps/lidarr/networkpolicy.yaml` allowed ingress from `kube-system`,
  `lidarr` and `prowlarr` — never from `hermes`. A cross-namespace flow needs
  the rule in BOTH namespaces; one side alone reads correct in review and drops
  the traffic. Confirmed from inside the pod rather than inferred: a Python
  `connect()` to `lidarr.lidarr.svc.cluster.local:8686` returned
  `ConnectionRefusedError [Errno 111]` — the REJECT signature this log already
  documents, not the timeout a missing route would give.
- **Fix:** added a `hermes` namespaceSelector on port 8686 to lidarr's ingress.
- **Prevention:** **written as a check this time.**
  `scripts/ci/check-invariants.py` builds a graph of every NetworkPolicy's
  cross-namespace peers and fails when an egress rule naming a namespace has no
  matching ingress rule at the other end. This bug is what it found on its
  first run — the trap's fourth occurrence, after the remux outpost, octo's
  egress to `vpn:8888`, and the monitoring namespace's probes. The three
  previous preventions were all written as prose in this file, and prose
  protects only whoever happens to read it at the right moment.
- **Confidence:** CONFIRMED — reproduced the block from the hermes pod and the
  checker reports the pairing clean after the fix.
- **Worth noting:** this is the failure mode with no symptom at all. Every
  health signal was green for a week because nothing was crashing; the app was
  simply inert. That is the same class as the sync server that had never
  synced, and it is why the data-plane assertions in Tier 3 matter more than
  another uptime check.

## 2026-09-03 — The new restore drill restarted the apiserver twice, then failed 13 good backups

- **Symptom:** two separate faults from one new job. (1) While the first run of
  `restore-drill` was materialising the bitmagnet dump, the k3s apiserver
  refused connections on :6443 twice, ~20 s each time. (2) Once it completed,
  it reported 13 of 17 databases as FAILED.
- **Root cause:** two unrelated mistakes, both mine, both in the checker rather
  than in anything it was checking.
  (1) `bitmagnet.dump` is **1.31 GB** and expands to **~5.5 GB** restored. The
  node idles at **92 % of 13.8 GB**, so restoring it pushed memory hard enough
  to knock over the apiserver. Applications never went down — containerd keeps
  pods running across an apiserver restart, and `authentik` served 302 in
  0.46 s throughout — and k3s recovered unaided both times, but the drill was
  the trigger.
  (2) The FAILures were an artefact of counting. `pg_restore --list` emits a
  `TABLE` entry **and** a `TABLE DATA` entry per table, and the string
  `TABLE DATA` contains the substring `TABLE `, so `grep -cE "TABLE "` counted
  every table exactly twice. The tell was in the output and unmissable once
  looked at: TOCTBL was **exactly 2× TABLES on all 13 rows** — 414/207,
  260/130, 58/29. Nothing was wrong with any backup.
- **Fix:** the drill is now two-staged. Stage 1 streams every archive through
  `pg_restore -f -` and discards the output, which walks every data block and
  so proves the bytes are readable end to end while touching neither Postgres
  nor the disk. Stage 2 materialises into a scratch database only when the dump
  is under `MAX_RESTORE_BYTES` (300 MB) and the data volume has more than
  `MIN_FREE_MB` (12 GB) free. Counting is now by TOC *field* — `awk '$4=="TABLE"
  && $5!="DATA"'` — compared against `table_type='BASE TABLE'` so views cannot
  inflate the other side. Re-run clean: 17 checked, 16 fully restored, bitmagnet
  integrity-verified, **0 failures**, every TOCTBL equal to its TABLES.
- **Prevention:** a diagnostic that destabilises what it diagnoses is a net
  negative, and this log already carries three outages caused by probes and
  none prevented by them — this job came within one run of being the fourth.
  Any new unattended job that touches the database must state its worst-case
  disk and memory cost *before* it is scheduled, and cap it. Raise the 300 MB
  cap only after the headroom work in ADR-0005, not before.
  On counting: never `grep -c` a substring that is a prefix of a longer tag in
  the same output. This is the second double-count in two days — the artist
  census read 1752 instead of 879 by grepping `"artistName"` across nested
  objects. Both were caught by the ratio being suspiciously round; when a count
  is exactly 2× or 3× what it should be, suspect the counter before the data.
  A drill killed mid-run leaks its scratch database (`drill_bitmagnet`, 5.5 GB,
  dropped by hand) — the `drill_` prefix guard is what made that safe to clean
  up, and the leftover check now fails the run if any survive.

## 2026-09-03 — Authentik's My Applications page: duplicate tiles, dead entry, 9 missing icons

- **Symptom:** the application library read as a "battle zone" — the same
  service appearing twice, an entry for a decommissioned app, and blank tiles.
- **Root cause:** three separate things. (1) The apps that carry a *native*
  OIDC provider alongside an existing forward-auth app — `bookdl` beside
  `book-downloader`, `qui-oidc` beside `qui` — each had an `https://` launch
  URL, and Authentik shows every app whose launch URL starts with http(s). Both
  pairs point at one host, so each rendered two tiles for one service. The
  pairing itself is deliberate (forward-auth gates the edge, native OIDC gives
  the app an identity); only the second *tile* was wrong. (2) `jellyfin` still
  had an Application and OAuth2Provider after the app was decommissioned in
  eb910dc, with redirect URIs at a host that no longer resolves. (3) Nine apps
  had `meta_icon` empty.
- **Fix:** deleted the orphaned jellyfin Application and OAuth2Provider; set
  the two native-OIDC twins' launch URL to `blank://blank`, the documented way
  to keep an app usable while hiding its tile; filled icons from the
  `cdn.jsdelivr.net/gh/selfhst/icons` set already used by the other apps, after
  confirming each URL returns 200 rather than assuming the name.
- **Prevention:** whenever a service gets a native OIDC provider *in addition
  to* forward-auth, set the new Application's launch URL to `blank://blank` at
  creation — the tile is otherwise duplicated. Decommissioning an app means
  deleting its Authentik Application and provider too; the git manifests going
  away does not touch cluster state. Check an icon URL resolves before saving
  it: a 404 icon renders as a blank tile and looks identical to no icon.
  `remux` is still iconless — the selfhst set has no Remux icon and inventing
  one (Jellyfin's, say) would misrepresent a different product.

## 2026-09-03 — Ghost restarted every 6 minutes for 523 restarts; the probe followed a redirect into TLS

- **Symptom:** `ghost` reported Running 1/1 and served the edge fine, but had
  accumulated **523 restarts**, the newest minutes old. Events showed
  `Liveness probe failed: Get "https://10.42.0.176:2368/": http: server gave
  HTTP response to HTTPS client`. The container exited 0/`Completed` every
  ~360s — exactly `initialDelaySeconds 60 + periodSeconds 60 × failureThreshold
  5` — i.e. liveness SIGTERMed it and Ghost shut down cleanly.
- **Root cause:** *not* the kubelet, which is what the manifest's own comment
  had concluded. `url` is `https://blog.sandstorm.chat`, so Ghost 301s any
  request it believes arrived over plaintext, and it builds that redirect from
  the request's own host — `Location: https://127.0.0.1:2368/`, verified
  in-pod. The kubelet follows probe redirects, so the second hop TLS-handshakes
  against the plaintext port and fails. The first GET does leave as http, so
  **`scheme: HTTP` cannot fix this** — the live pod already carried
  `scheme: HTTP` (the API server defaults it) while failing every cycle.
- **Fix:** send `X-Forwarded-Proto: https` as a probe header
  (`apps/ghost/deployment.yaml`). Ghost then treats the request as already
  secure and returns 200 with no redirect. Verified in-pod: bare `GET /` → 301;
  same GET with the header → `200 OK`.
- **Prevention:** when a probe error names a scheme the spec did not ask for,
  check for a redirect before blaming the kubelet — `wget -S --spider` from
  inside the pod shows it in one command. Any app configured with an external
  https `url` (Ghost, and anything else that force-redirects) needs either this
  header or a probe path that does not redirect. The stale readiness-probe
  story in that manifest came from the same misdiagnosis; a readiness probe of
  this shape is safe to reinstate now that the redirect is understood.

## 2026-09-03 — pg_dump backups failed 3 runs running; the dump lost the kube-router race

- **Symptom:** `pgdump-backup` showed `FailureTarget/BackoffLimitExceeded` for
  its last three scheduled runs. The newest good restic snapshot was
  **27h stale** — the job that protects the Vaultwarden vault.
- **Root cause:** the same kube-router NetworkPolicy programming race already
  documented for Lidarr's maintenance CronJob (2026-08-29 entry below). The
  `dump` initContainer opens its `psql` connection on its first line of real
  work; until kube-router has programmed the per-pod policy chains (~1–2s),
  allowed egress is **REJECTed**, surfacing as `connection refused` rather than
  a timeout. Captured verbatim from a manual run's previous attempt:
  `psql: error: connection to server at "app-databases-rw..." (10.43.96.131),
  port 5432 failed: Connection refused`. With `backoffLimit: 2`, three lost
  races in a row fail the whole run.
- **Fix:** a `wait-for-postgres` initContainer that polls `pg_isready` (30
  attempts, 2s apart) ahead of `dump`, mirroring lidarr's `wait-for-lidarr`.
  Same image as the dump, so no extra pull. A manual run reproduced both the
  failure and the recovery and landed a fresh **1.17 GiB** snapshot.
- **Prevention:** any Job or CronJob whose first action is a network call needs
  a wait-init. This race has now bitten two of them; treat "connection refused
  from a just-started pod, where the NetworkPolicy clearly allows it" as this
  cause until proven otherwise. Worth auditing new CronJobs for it.
- **Confirmed unattended 2026-09-03:** the manual run only proved the fix under
  supervision. Two scheduled runs have now completed on their own — 06:40Z in
  4m37s and 12:40Z in 4m39s — writing all 18 dumps plus `globals.sql`. The
  three failed job records from before the fix were deleted, so the namespace
  no longer carries a permanently-firing `KubeJobFailed`. The prevention was
  applied a third time in `restore-drill-cronjob.yaml`, which is the audit this
  entry asked for.

## 2026-09-03 — Obsidian LiveSync was never actually initialised

- **Symptom:** the endpoint answered 401 (CouchDB auth working) and ArgoCD
  called it Healthy, so it looked deployed — but no vault had ever synced.
  `_all_dbs` returned only `["obsidiannotes"]`, and that database held
  `doc_count: 0`.
- **Root cause:** two directives missing from `livesync.ini`. (1) No
  `[couchdb] single_node = true`, which is what makes CouchDB 3.x create
  `_users`, `_replicator` and `_global_changes` on startup — without `_users`
  the server cannot authenticate a non-admin. (2) No `enable_cors`, so the
  `[cors]` block (origins, credentials) was **inert**: CouchDB 3.x reads
  `enable_cors` from `[chttpd]` — default.ini says these options "moved from
  [httpd]" — and the file's `[httpd]` section only governs the legacy
  127.0.0.1:**5986** interface, not the 5984 port Obsidian talks to. The
  effective config confirmed it: `[chttpd]` had no `enable_cors` key at all.
- **Fix:** added `single_node = true`, `[chttpd] enable_cors = true`, and
  explicit CORS `headers`/`methods` (CouchDB's default method list stops at
  GET/HEAD/POST; replication also issues PUT and DELETE).
- **Prevention:** "Ingress answers 401" only proves a listener is up. For a
  sync backend, check the data plane — `_all_dbs` for the system databases and
  the effective `_node/_local/_config` — before calling it deployed. Verify a
  section's keys landed where the running version reads them, not where an
  older docs page put them.
- **Second trap, worth its own line:** ArgoCD synced the corrected ConfigMap
  and reported Synced/Healthy while CouchDB carried on with the old settings —
  it only reads `local.d/*.ini` at startup, and nothing rolls the pod when a
  mounted ConfigMap changes. The fix needed an explicit
  `kubectl rollout restart deploy/obsidian`. After any change to
  `livesync-config`, restart the deployment or the change is live in git,
  live in the API, and inert in the process.
- **Verified after the fix:** `_all_dbs` → `["_replicator","_users",
  "obsidiannotes"]`; `[chttpd] enable_cors: "true"`; and a preflight
  `OPTIONS /obsidiannotes` with `Origin: app://obsidian.md` returns 204 with
  `Access-Control-Allow-Origin: app://obsidian.md` and
  `Allow-Methods: GET, PUT, POST, HEAD, DELETE`.

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

## 2026-08-31 — disk-pressure churn loop: prune-then-repull feeds itself

- **Symptom:** the fourth ephemeral-storage eviction loop of the day. Each
  loop evicted authentik (SSO down cluster-wide), argocd-repo-server (no
  app could sync) and whatever else was running, and piled hundreds of
  Evicted pod records.
- **Root cause:** the CT 200 disk (63G) sits permanently at the kubelet's
  15% imagefs threshold (9.45G free); containerd holds 41.7G (27G
  snapshots + 9G content) and k3s local-path PVCs another 6.3G. Made
  worse by an operator error: `crictl rmi --prune` deletes images that
  PENDING pods still need, so each scheduling retry re-pulled ~1.5G and
  re-crossed the threshold. Prune only when nothing is Pending.
- **Fix (immediate):** sweep Failed pods, remove Exited containers
  (`crictl ps -aq --state Exited | xargs crictl rm`) before pruning,
  pause funkwhale at replicas: 0 until the capacity decision lands.
- **Prevention / decision:** tracked in issue #4 - the host thin pool is
  also at 92.78%, so this is a storage architecture decision, not a
  cleanup job.

## 2026-08-31 — node memory exhaustion: swap thrash → API 503s cluster-wide

- **Symptom:** kubectl returned ServiceUnavailable (503) on every read; etcd
  transactions took up to 77 seconds (warn logs: "apply request took too
  long"); kubelet proxy calls 502'd; probe timeouts across the cluster.
- **Root cause:** the 13.8GB node at 13GB used with an Immich video
  transcode (435% CPU, 1GB RSS) on top of the post-restart task backlog -
  and a **512MB swap limit** (the Proxmox LXC default) that hit 99.9%.
  Swap thrash turned memory pressure into a control-plane lockup.
- **Fix:** dropped the page cache (`echo 3 > /proc/sys/vm/drop_caches`,
  +1.6GB), reniced the ffmpeg transcode to 19 (Immich re-runs the job
  cleanly later), and raised the CT swap limit to 4G
  (`pct set 200 --swap 4096` - the host had 6.6G of its 8G swap unused).
  The API recovered within a minute.
- **Prevention:** the swap limit persists in the CT config; the
  image-prune timer guards disk. Memory remains the node's tightest
  resource (ADR-0005) - adding RAM or moving workloads is the structural
  fix.

## 2026-08-31 — the ServerSideDiff bug is a class, not an app

- **Symptom:** after the ghost fix, nfs-csi hit the identical
  ComparisonError ('element 0 omits key field name') the moment its helm
  bump synced, pinning the app at Unknown and nfsplugin at v4.9.0.
- **Root cause:** the same ArgoCD server-side-diff implementation bug; the
  appset's compare-options list is the mitigation point.
- **Fix:** added nfs-csi to the list and re-applied the ApplicationSet
  directly. For future fixers: the bootstrap script's app-project.yaml
  openapi-validation failure is cosmetic (tunnel flap) - the
  ApplicationSet applies first and that is the file that matters.
- **Prevention:** any app that hits 'omits key field name' gets added to
  the list; the list is the documented workaround, not a one-off.

## 2026-08-31 — metallb 0.16.1: edge down, rolled back to 0.14.9

- **Symptom:** the moment PR #13 (chart 0.14.9 → 0.16.1) synced, the
  controller AND speaker entered CrashLoopBackOff, the speaker stopped
  announcing 192.168.1.240, and every published service went dark
  (all edge curls → 000, the LB IP unpingable).
- **Root cause:** two stacked errors. (1) the known server-side-diff
  ComparisonError (fixed by adding metallb to the appset's
  ServerSideDiff=false list). (2) beneath it, the sync's rbacReconcile
  failed with `namespaces "metallb" not found` - the 0.16.1 chart renders
  ClusterRoleBinding subjects referencing a namespace `metallb` (release
  name) that does not exist in this cluster (only `metallb-system`).
  A k3s restart did not clear either state; the kubelet's CSI registration
  loss for nfs.csi.k8s.io and csi.juicefs.com in the same window is
  likely related to the same restart-time degradation.
- **Fix:** `kubectl -n metallb-system rollout undo` both controller and
  speaker (instant restore from the previous 0.14.9 ReplicaSets), then
  the git rollback commit so ArgoCD converges to the same state. The
  `frrk8s.enabled: false` values fix stays in git for the eventual retry.
- **Prevention:** a 0.16.x retry requires solving the rbacReconcile
  namespace propagation first (namespaceOverride in values, or render the
  chart locally with kustomize build --enable-helm and diff the subjects
  before ArgoCD touches it). The edge MUST be verified within 3 minutes
  of any metallb change - the rollback trigger that was set up for this
  merge is the template for future ones.

## 2026-08-31 — ganesha.log 26GB + containerd store 64.5GB: disk 100%, recovered by cache reset

- **Symptom:** the API refused connections (the edge dark, every curl 000);
  k3s in an activation loop dying with `mkdir etcd-tmp: read-only file
  system`; the root fs in ext4 emergency_ro.
- **Root cause:** TWO unbounded consumers filled the 84G disk: (1)
  /var/log/ganesha/ganesha.log grew to 26GB (nfs-ganesha runs IN the CT
  serving the cluster's NFS PVCs and logs every operation; logrotate had
  no ganesha config), and (2) the containerd store bloated to 64.5GB
  (the day's eviction/pull-storm churn - every prune was offset by
  rescheduling pods re-pulling). Beneath both: the thin pool hit 100%,
  which force-remounted the CT root read-only.
- **Fix:** truncated ganesha.log (+26GB instantly), then the decisive
  reset: CT stop → e2fsck -f → host-side rm -rf of
  /var/lib/rancher/k3s/agent/containerd (etcd, PVC data and configs
  untouched) → CT start → k3s re-initialized containerd empty and
  re-pulled everything onto a disk with 45-64G free.
- **Prevention:** /etc/logrotate.d/ganesha installed (500M cap, 3
  rotations, copytruncate); the image-prune timer guards the fs floor.
  The structural issue stands: the thin pool hosts this CT AND vm-2120
  (100G disk, ~66G written) - vm-2120 is the largest reclaimable block
  if abandoned (owner decision).

## 2026-08-31 — metallb 0.16.1 retry SUCCEEDED (the namespace fix)

- The retry after the rollback: created the `metallb` namespace
  out-of-band (kustomize's namespace transformer ID-conflicts an in-git
  Namespace resource with the real metallb-system one - the namespace
  is a hand-applied object, documented here), kept
  `frrk8s.enabled: false`, bumped to 0.16.1 - rbacReconcile passed,
  controller and speaker came up 1/1 on 0.16.1, the edge verified
  (302 through traefik). The metallb-ns.yaml file was removed from
  git; the namespace must be recreated manually after any cluster
  rebuild (noted in docs/SESSION-HANDOFF.md).

## 2026-09-01 — removing a sidecar silently emptied a Service's endpoints (named-port contract)

- **Symptom:** qui could not reach qbittorrent (connection refused via the
  Service IP); the qbittorrent pod was 3/3 Running+Ready with a matching
  Service selector, yet the Endpoints object was empty - and stayed empty
  through a k3s restart and an Endpoints deletion.
- **Root cause:** the Service's targetPort was the NAMED port `qbit-http`,
  which only the removed gluetun sidecar had declared. The qbittorrent
  container (which actually serves 8080) declared NO ports. The endpoints
  controller silently produces empty endpoints when a named targetPort
  matches no container port - no error, no event, nothing.
- **Fix:** declared `ports: [{name: qbit-http, containerPort: 8080}]` on
  the qbittorrent container (commit e36c66a). Endpoints populated
  (10.42.0.198:8080), qui connected, HTTP 200 from the WebUI.
- **Prevention:** when removing a sidecar, audit every Service whose
  targetPort is a NAMED port - the port name may live on the sidecar,
  not the main container. A named targetPort with empty endpoints and a
  Ready, label-matched pod = check the container port declarations first.
  Side note: the slskd-config-render init takes ~45 min per restart
  (chown -R over NFS on an already-owned tree) - an ownership check
  before recursing would cut pod-start time dramatically.

---

## 2026-09-05 — Four things that were configured, healthy, and doing nothing

Grouped because they are the same failure, four times: a component present and
reporting fine while delivering nothing. That shape is now most of this file.

### Alertmanager's `smart-email` receiver had no configs
**Symptom:** none. That is the entry.
**Found by:** reading the live generated config rather than the source, while
adding an ntfy path to it.
```
receivers: [ null -> nothing, smart-email -> nothing, heartbeat-ntfy -> ok ]
```
All seven "smart" routes — failing disks, disk temperature, degraded array,
node unreachable, filesystem filling, backup chain, MinIO — resolved to a
receiver declared as `- name: "smart-email"` with nothing under it.
Alertmanager accepts that and delivers nowhere.
**Lesson:** the routing inversion was verified by reading the routes. Nobody
checked that the receiver they pointed at could send. *A route is only as real
as its receiver.*

### slskd's proxy env vars were ignored, so Soulseek never once connected
**Symptom:** `Failed to connect to 208.76.170.59:2271: Connection refused`,
124 consecutive times, and every Octo search returning "currently:
Disconnected".
**Cause:** `SLSKD_SLSK_PROXY` / `_ADDRESS` / `_PORT` are silently ignored —
the same nested-path env-mapping trap already documented in this repo for
slskd's API key. So slskd dialled the Soulseek server *directly*, and the
namespace policy rejected it. kube-router REJECTs rather than drops, so a
policy denial reads as `Connection refused` **against the destination
address**, which is indistinguishable from the far end being down.
**Compounding:** the port was 8388 (Shadowsocks), which cannot answer a SOCKS5
greeting, so it would not have worked even had the env vars been read.
**Fix:** `soulseek.connection.proxy` in `slskd.yml`, port 1080.
**Lesson:** when an error names the *final* destination rather than the proxy,
the client is not using the proxy. That one line distinguishes "proxy broken"
from "proxy not configured" and is worth reading for every time.

### AIOStreams had proxy variables it structurally could not use
**Symptom:** `Failed to fetch manifest for Torrentio p2p: fetch failed`, and
a long-running `ECONNREFUSED 140.82.114.3:443 (github.com)` loop.
**Cause:** `HTTP_PROXY`/`HTTPS_PROXY` were set, but AIOStreams is Node and
its calls go through undici's `fetch()`, which does not read them — Node has
no implicit proxy support. Every request went direct; the killswitch denied it.
The previous comment in the manifest blamed "the app bypassing its own proxy
configuration". It had never been given one it could use.
**Fix:** `ADDON_PROXY` + `ADDON_PROXY_CONFIG`, which install an undici
ProxyAgent. Also `BASE_URL`, which was `http://localhost:3000` — not cosmetic,
since every URL it generated for remux resolved to remux's own pod.
**Lesson:** `HTTP_PROXY` is a convention, not a guarantee. Per-runtime: Go
honours it, .NET honours it, Node does not.

### ntfy died on a package upgrade and stayed dead for three hours
**Symptom:** `FATAL unable to open database file: permission denied`, five
restarts, then systemd's start limit — and silence, which is what a healthy
day also looks like.
**Cause:** the upgrade changed the packaged service user from `ntfy` (987) to
`_ntfy` (986). `/var/cache/ntfy` was still owned by the old account at 0700.
**Fix:** chown, plus a `CacheDirectory=` drop-in so systemd re-chowns to
whatever `User=` currently is on every start.
**Lesson:** the notification path needs its own liveness check. It failed in
the same window it was being extended, and only got noticed because it was
being extended.

### Also, not a silent failure but the same family
ArgoCD waits for a sync wave to report healthy, and a running Job never does.
The two lidarr mass-search Jobs run for days, so the whole `lidarr` Application
parked at `waiting for healthy state of batch/Job/lidarr-mass-search-a` and a
NetworkPolicy change would not apply. Moved to a later sync wave.

---

## 2026-09-04 — "Immich ML still isn't connected" — it is; the backlog is not

Reported as a broken connection. It is not one, and the distinction changes
what to do about it.

**Evidence, from the database rather than from a health check:**

```
asset                        9676
smart_search (CLIP)            72
asset_face                     13
person                          0

oldest asset WITH embedding      2026-09-04 18:02
newest asset WITHOUT embedding   2026-09-02 01:25
assets created since 2026-09-03    72
  of those, with an embedding      72     <-- 100%
```

Every asset added since the NetworkPolicy fix has an embedding. Not one added
before it does. So machine learning is wired correctly and is processing new
uploads; what is missing is the 9,604 photos imported while the namespace was
denying its own pods. **Immich never re-queues past assets** - Smart Search and
Face Detection have to be run for "Missing" from the Jobs page.

`machineLearning: {}` in the config file is fine, verified empirically rather
than assumed: the empty object inherits the defaults, whose URL
(`http://immich-machine-learning:3003`) happens to be exactly this Service's
name in this namespace.

**Do not run that backlog yet.** See below.

### The apiserver died in the middle of investigating it

Every `kubectl exec` and `kubectl logs` started failing mid-session, first as
`proxy error ... dialing 192.168.1.172:10250, code 502`, then as
`pod does not exist` for a pod `get pods` was still listing, then finally
`connection refused` on 6443. That last one is the honest signal: k3s had
restarted. It came back on its own in about 30 seconds.

```
NRestarts=9        ActiveEnterTimestamp=Fri 2026-09-04 18:09:25 UTC
Mem: 13824 total   12536 used   108 free   1322 swap used
```

**90.7% with 108 MB free and swapping.** ADR-0007's tripwire is 85%. The
biggest single consumer is Lidarr at 1.58 GB - the mass search, with ~100 hours
still to run - followed by the Immich ML model at ~1.0 GB resident even while
idle, Prometheus at 659 MB, and the two Immich processes at ~1.0 GB combined.

So the Immich backlog is 9,600 CLIP embeddings and face passes on a node that
is already restarting its control plane under the load it has. It would be one
of the heaviest things this cluster can be asked to do, and it should wait for
the mass search to finish - or for headroom, which is still decision #1.

**The lesson worth keeping:** "is it connected" and "has it done the work" are
different questions, and only the second one is answerable from the data. A
health check would have said Immich ML was fine, and it would have been right.

---

## 2026-09-04 (evening) — the Immich migration, and three things it exposed

### The migration itself
262 GB of originals plus 71 GB of encoded video, checksum-verified with **0
mismatches**, and a 2026-08-21 database restored with **0 errors**. Recovered
691 assets, 28 locked, 6 hidden, 5 albums and 273 people that a previous
"restore" had silently dropped.

**The finding that mattered most was one I nearly missed.** The restored
database already contained 10,318 CLIP embeddings, 47,082 OCR rows and 10,273
face-recognised assets. The "9,604-photo ML backlog" diagnosed earlier that day
was never a backlog in the library - it was an artefact of the broken restore.
Running it would have been hours of CLIP inference on a node that cannot afford
minutes of it, to recompute work that already existed. *Check whether the work
has already been done before scheduling it again.*

### A 1-second probe timeout is a load test, not a health check
The new Immich pod logged "Immich Server is listening on 2283" and "Machine
learning server became healthy", answered `/api/server/ping` with 200 over a
port-forward, and sat **0/1 for fifteen minutes**. The chart's probes use
`timeoutSeconds: 1`; under memory pressure three consecutive scheduling delays
marked it NotReady, so the rolling update never completed - which kept BOTH
ReplicaSets running, cost another ~500 MB, and worsened the pressure that
caused it. A probe that fails under load on the app it protects is a feedback
loop. Now 5s.

### Streaming a 500 MB restore through the apiserver is not a plan
The first restore attempt piped `zcat | kubectl exec psql` and died partway with
`websocket: close 1006`. The fix was to copy the 67 MB *compressed* dump into
the pod (checksum-verified, six attempts before one survived), then run the
restore **detached inside the pod** with `setsid nohup`. It finished in 70
seconds with zero errors. On an unstable control plane, move the small file and
run the big job locally - never stream the big job through the control plane.

### And on the NAS, two stacks nobody was watching
`immich_postgres` at **8,197 restarts** and `immich_server` at 7,952, pointed at
a path that stopped being a mountpoint on 2026-08-28 - and dangerous, because
they aimed at the exact data being migrated. Blinko was worse: its Postgres
container had been deleted, its healthcheck only fetched `/` so it reported
"healthy" for weeks, and **71 notes** sat in an orphaned data directory nothing
read, backed up or alerted on. Both are why ADR-0008 now exists.

### The cluster was down for 3h37m and every watcher was inside it

**Symptom:** owner opened a laptop at 22:05 to a dead cluster and said "the
whole cluster is down for whatever reason, THIS CANNOT HAPPEN AGAIN."

**Diagnosis.** pve (the Proxmox host, `192.168.1.153`) powered off at
**18:39:30**. From `awesomemediaserver`, which is on the cluster's own L2
segment, `.153` resolves `INCOMPLETE` — no ARP reply — so the NIC is dead and
the box is off or hung, not merely unroutable. LXC 200 and therefore k3s,
ArgoCD, all ~35 apps and the Wings game daemon went with it.

Probing from the laptop was worthless and nearly misleading: it sits on
travisbackupserver's **separate** `192.168.1.0/24`, where `.153` is a different
machine whose MAC (`60:69:44:...`) is not pve's (`b0:7b:25:...`, a Dell OUI).
Only a host on the cluster's segment can answer this question.

**Why nobody was told — three faults, compounding:**

1. **Every in-band watcher shares a fate with pve.** Prometheus and Alertmanager
   run in LXC 200; the ntfy relay `:9098` and beat receiver `:9099` run on pve.
   The dead man's switch is the worst offender because it looks like the control
   that covers exactly this — but `homelab-beat-check.timer` runs *on pve*, so
   pve's own death is the one failure it structurally cannot report. The normal
   alert path is `cluster → relay on pve → tailscale → ntfy`: **every alert
   about pve had to be forwarded by pve.**
2. **The one watcher that did see it spoke once.** `homelab-edge-probe` on
   travisbackupserver notified on `state != prev`, so it sent a single urgent
   push at 18:39 and then went quiet for 3h37m while faithfully logging
   `edge: FAIL` every 5 minutes to a journal nobody reads.
3. **That push was the fifth identical-looking message of the day.** The same
   `HOMELAB EDGE UNREACHABLE` title had fired and self-recovered at 14:53,
   15:13, 15:33 and 17:14, alongside ~14 flapping `TempNasDiskHigh` alerts,
   several delivered in triplicate. The real alert was indistinguishable from
   the noise that preceded it.

This is the same shape as the `smart-email` receiver and slskd's ignored env
vars: **a control that is present, configured, and reporting healthy while
delivering nothing.** SESSION-HANDOFF had already named "pve itself dying,
power cut" as the uncovered case. It was documented and not closed.

**Fix.**
- New `homelab-external-watchdog` on **awesomemediaserver** — different machine,
  different PSU, on the cluster's segment, and reaching ntfy over Tailscale
  *without* pve relaying. Probes pve by ICMP and k3s `:6443` by TCP every 60s,
  3 strikes before alerting, re-nags every 30 min, fires WoL while down, one
  quiet daily heartbeat so its own silence is noticeable.
- `homelab-edge-probe` re-nags every 30 min instead of once, using `edge.state`'s
  mtime as the outage start.

**Verified live against the real outage:** `DOWN: Proxmox host` and
`DOWN: k3s API` at 22:16, then `STILL DOWN: homelab edge (223m)` — 223 minutes
matching the 18:39 start exactly.

**Not fixed, needs hands on the machine:** the host is a Dell Vostro, so there
is **no IPMI**, it ignored ~25 WoL packets from its own segment, and a full LAN
sweep found no smart plug. Recovery required a physical power button press.
See `docs/recovery/cluster-down.md` for the BIOS settings and the one purchase
that would make this remotely recoverable.

### Signing in with Authentik silently created a second, empty Immich account

Immich's OAuth is `autoRegister: true`, and it matches an incoming login to an
existing account by **email**. The Authentik identity is `travis@sandstorm.chat`;
the Immich account holding the library was created with `travis.fiorito@tuta.com`.
No match, so the first Authentik sign-in did the only other thing it could —
provisioned a brand-new account.

| account | OAuth bound | admin | assets |
|---|---|---|---|
| `travis.fiorito@tuta.com` | no | yes | **10,367** |
| `travis@sandstorm.chat` (created 2026-09-05 17:58 UTC) | **yes** | no | **0** |

The library was never damaged or lost — the login just landed somewhere else.
Fixed by moving the OAuth binding onto the account that owns the photos, rather
than reassigning 10,367 rows: on-disk paths are keyed `upload/<ownerId>/…`, so
changing `ownerId` would have orphaned every file.

This is the same shape as the outage two entries up: **a control that is
present, configured, and reporting healthy while delivering nothing.** SSO was
"working" the whole time. It authenticated correctly, issued a valid session,
and showed an empty library — and an empty library is indistinguishable from
data loss at a glance. The failure wasn't in the auth path; it was in the
assumption that one person's two email addresses describe one identity.

Worth doing: set `autoRegister: false` in Immich's OAuth settings. With it off,
an unmatched login fails loudly instead of quietly inventing an account.

### `kubectl rollout restart` took the Pelican panel down under ArgoCD

Restarting an ArgoCD-managed Deployment with `selfHeal: true` is not a safe
no-op. `rollout restart` works by stamping a
`kubectl.kubernetes.io/restartedAt` annotation on the pod template, which
creates a new ReplicaSet. ArgoCD sees that annotation as drift from git and
strips it — orphaning the ReplicaSet it just caused.

The Deployment was then left in a state neither side would resolve:

```
spec.replicas = 1
pelican-54f9bcc485   0 desired
pelican-5c75cdd6     0 desired
pelican-68d4bc8fbc   0 desired
Available=False  MinimumReplicasUnavailable
```

Desired one pod, every ReplicaSet scaled to zero, nothing scheduling. The panel
served **503** until an explicit ArgoCD sync recreated a pod.

Restart such a Deployment by **deleting the pod** or syncing the app — never by
annotating the template that git owns.

The same session's Pelican work is the reason this matters twice over: plugins
install into `/var/www/html/plugins`, which is image filesystem. The PVC already
carried a `plugins/` directory, but it was never mounted where the panel reads
from. Every install would have disappeared on the next restart *while the panel
went on listing the plugins as enabled* — the same shape as the qBittorrent
category, the empty Immich library, and the watchers that were configured,
healthy, and reporting nothing. **Verify a thing survives the restart, not just
that it works once.**

### Two controllers fought over one image digest, and a torrent client paid for it

qBittorrent could not stay up. Every ~2.5 minutes the pod was replaced, and
because it takes about three minutes to load 2,228 torrents before it binds
`:8080`, it was killed before it ever finished starting. qui could never
connect, and Baldur's Gate re-checked from scratch on every cycle.

Nothing looked wrong. `restarts=0` on every pod, so no container was crashing.
No probes at all. No `activeDeadlineSeconds`. No evictions, no
Memory/Disk/PIDPressure. ArgoCD reported `Synced` with zero OutOfSync resources
and logged `Skipping auto-sync: application status is Synced`. Disabling
auto-sync on the app entirely did not stop it.

The only signal was the Deployment's `generation`: **59 in the afternoon, over
300 by night** — roughly one change a minute, while the ReplicaSet hash stayed
the same and a before/after diff showed *no* net change.

That last part was the tell. Generation only moves on a spec change, so a bump
with no net difference means something changed a field and something else
changed it back. Sampling the object every two seconds caught it:

```
gen 310 -> 311  image: qmcgaw/gluetun:v3.41.3@sha256:fa19cc...  ->  qmcgaw/gluetun:v3.41.3
gen 311 -> 312  image: qmcgaw/gluetun:v3.41.3                   ->  qmcgaw/gluetun:v3.41.3@sha256:fa19cc...
gen 312 -> 313  (strips it again)
gen 313 -> 314  (restores it again)
```

`argocd-image-updater` was rewriting gluetun's digest-pinned reference down to a
bare tag; ArgoCD restored the pin from git; repeat forever. Each flip changed
the pod template, and a changed pod template means a new pod.

Neither controller was misbehaving. Both were doing their job. The bug was that
they had been given contradictory instructions about the same field, and
**neither one reports a conflict** — image-updater logs a cheerful "Successfully
updated image", ArgoCD reports `Synced`. Both were telling the truth about
themselves and nothing was telling the truth about the system.

It had been latent for as long as the `gluetun` entry existed under the
`downloads` application. It only began firing when gluetun moved out of
`apps/vpn` and into the qBittorrent pod, so an unrelated change lit a fuse that
had been sitting there.

**The lesson, and it is the same one as the rest of this log:** when everything
reports healthy and something is still broken, stop reading status and start
watching a number change over time. `generation` climbing with no diff is a
fingerprint for two controllers fighting, and nothing else produces it.

Fixed by removing gluetun from `apps/image-updater/imageupdaters.yaml` — it is
pinned by digest deliberately, because v3.40.0 aborts at startup on this LXC's
IPv6 link-local address. An image it must never auto-update should not be listed
for auto-update. Pod then survived eight minutes with `generation` frozen.

### One log file took the cluster's storage down, and logrotate was working fine

Pods were being evicted every few minutes. The kubelet said so plainly once
someone read a *failed* pod rather than a running one:

```
phase=Failed reason=Evicted
msg=Pod was rejected: The node had condition: [DiskPressure]
```

The node's root filesystem was full. `/var/log` was **44 GB**, and effectively
all of it was one file: `/var/log/ganesha/ganesha.log`, at **43.6 GB**. Every
line was identical:

```
svc_dg_rendezvous: Bad message sa_family is 0xffff
```

nfs-ganesha's **UDP** RPC listener had received a malformed datagram and was
spinning on it. Measured growth: **~13 MB/s** — 854 MB to 986 MB in ten
seconds. That is 46 GB an hour, so the disk went from healthy to full inside a
single evening.

The trap: a logrotate rule for this exact file already existed (`size 500M`,
`rotate 3`, `copytruncate`), logrotate **was** enabled, and it **had** run that
morning at 00:04. None of that helps. `size` is only evaluated when logrotate
runs, and it runs daily. A daily job cannot contain a 13 MB/s writer — by the
time it next looked, 40+ GB had already landed.

Fixed with `Enable_UDP = false` in `/etc/ganesha/ganesha.conf`. Every export
there is already `Transports = TCP` and NFSv4 is TCP-only, so nothing needed the
datagram listener at all — and this ganesha has zero connected clients, because
the cluster's actual NFS comes from the NAS. Growth went from 13 MB/s to **0
bytes in 15 seconds**.

**The lesson:** "log rotation is configured" is not the same as "logs are
bounded". Rotation is a scheduled job; a runaway writer is a rate. When the rate
beats the schedule, the config is decoration. If a service can log unbounded,
either cap it at the source or rotate on a timer that matches how fast it can
write — and treat a service that logs the *same line* forever as a fault to fix,
not a volume to manage.

### Port forwarding was correct at every layer and still did nothing

qBittorrent reported connection status `firewalled` — no incoming peers, ever.
Every layer checked out:

- AirVPN forwards port 6877 for the account
- gluetun opens it: `-A INPUT -i tun0 -p tcp --dport 6877 -j ACCEPT`
- qBittorrent is configured for it: `Session\Port=6877`
- `Connection\UPnP=false`, correctly, since the forward comes from the VPN

Four layers agreeing, and inbound was still impossible. The listener sockets
showed why:

```
tcp ::1:6877                       LISTEN
tcp fe80::7c41:5ff:fe21:ddfd:6877  LISTEN
```

IPv6 loopback and link-local. With no `Session\Interface` set, qBittorrent had
chosen its own bind addresses, and neither is reachable from anywhere. AirVPN
was faithfully forwarding a port to a socket that could not be dialled.

Outbound was unaffected, which is exactly why it looked fine — downloads ran at
3.2 MB/s while inbound was structurally impossible. Binding to `tun0` moved the
listeners onto the tunnel address and the status flipped to `connected`, with
throughput going 24 KB/s -> 3.2 MB/s -> **18.7 MB/s**.

Bound by interface **name**, not address: `tun0`'s address changes on every
reconnect, so a pinned address is a slow-motion version of the same bug.

**The lesson:** checking that each layer is configured correctly is not the same
as checking that the path works. Every hop here was right in isolation. The only
question that would have found it in one step is "what address is the process
actually listening on" — `netstat -lntu` beat four correct config files.

---

## A hook that had never once run, and therefore had never once been tested

**2026-09-07.** Torrents in the `nextcloud` category were downloading to
`/data/torrents/nextcloud` and going no further. 188 GB sat there. The upload
path had been built days earlier and every visible part of it was right:

- `[AutoRun] Enabled=true` and a `Program=` line in `qBittorrent.conf`
- `qbit-upload.sh` mounted at `/scripts`, readable, executable
- the `nextcloud` category seeded, with the correct save path
- `NEXTCLOUD_WEBDAV_URL/USER/PASSWORD` all populated from the secret
- NetworkPolicies on both sides naming each other's namespace
- both ArgoCD apps `Synced`

Four independent faults, stacked. Any one of them alone would have produced the
identical symptom: nothing happens, silently.

**1. The hook was never invoked.** qBittorrent reads these through QSettings,
whose IniFormat keys are case-sensitive, and the keys it asks for are
`AutoRun/enabled` and `AutoRun/program` — lowercase. `Enabled=true` parsed
perfectly and answered a question nobody asks. The real key was absent, so it
defaulted to false. There is no warning for an ini key nobody reads.

The keys were not guessed. The binary stores its settings names as UTF-16
string literals, so `grep` finds nothing; `tr -d '\0' < qbittorrent-nox | grep
-i autorun` prints the table, and `AutoRun/OnTorrentAdded/Enabled` sits right
beside them, capitalised, which is why the wrong casing looked plausible.

**2. The path was blocked anyway.** Both NetworkPolicies named port **8080** —
the *Service* port. NetworkPolicy is evaluated after kube-proxy's DNAT, so the
number that has to appear is the destination **pod's** containerPort, which is
80. `curl` from the qBittorrent pod was REJECTed in 5 ms to the ClusterIP and
to the pod IP alike. The kube-system rule three lines above the broken one
already carried both numbers, with a comment explaining exactly this.

**3. The script had three bugs, because it had never run.** It never created
its own `/qbittorrent` base collection (first PUT: 409). It computed paths
relative to the torrent folder instead of its parent, so every torrent
flattened into one directory and two repacks shipping a `setup.exe` would
overwrite each other. And it issued `MKCOL` for a whole nested path at once,
which fails unless every parent already exists.

**4. And then a 413 after 0 bytes sent.** Apache in the Nextcloud image caps a
request at `APACHE_BODY_LIMIT=1073741824`. Raising it does not help: PHP's
`post_max_size` is 16G and the largest file here is **95 GB**. A single PUT
cannot carry it at any setting, so chunked upload
(`/remote.php/dav/uploads/...`, 256 MiB chunks, `MOVE .file` with
`OC-Total-Length`) is not an optimisation, it is the only implementation that
exists.

Then a fifth, found only by running it: `curl -T "Red Dead Redemption [DODI
Repack]/Setup.exe"` fails with `bad range in URL` before a byte moves. curl
applies its own `{a,b}` / `[1-3]` glob expansion to the **upload file name**,
not just the URL. Percent-encoding the destination protects the URL argument;
nothing was protecting `-T`. Scene names contain brackets constantly, so this
is the common case. `-g`.

**The lesson:** *code that has never executed is not working code, it is
unwritten code.* Every one of bugs 3, 4 and 5 was latent behind bug 1 — the
hook was disabled, so nothing downstream had ever been exercised, and the whole
chain read as "configured" while being untested end to end. A config file, a
mounted script and a green sync status describe intent, not behaviour.

The corollary is about evidence. The hook wrote to stdout, and qBittorrent
spawns it detached, so its output never reached `kubectl logs` — a component
that fails silently *and* logs nowhere cannot be debugged, only rediscovered.
It now writes one line per invocation to `/config/qbit-upload.log`, **before**
the category check, so the question "did it fire at all?" is answerable with a
`tail` instead of a five-hour excavation.

---

## Three layers of green over one short read

**2026-09-07, continued.** With the hook finally firing and the path finally
open, the backfill uploaded Red Dead Redemption's 7.2 GB `data1.doi` and
logged:

```
22:20:26  ok (7377 MiB chunked) .../Red Dead Redemption [DODI Repack]/data1.doi
```

Three minutes later a `HEAD` on that URL answered **404**, while the two files
uploaded immediately after it sat in the same directory perfectly happily.

Every layer had reported success. All 29 chunk PUTs returned 2xx. The final
`MOVE` returned 2xx and curl exited 0. The hook wrote `ok`. Nextcloud's own log
had the truth and had kept it to itself:

```
Stream from assembly node shorter than expected,
got 213364620 bytes, expected 268435456
```

One chunk was short. `dd` without `iflag=fullblock` counts a **short read as a
whole block** — a `read()` that returns less than `bs` still consumes one of
`count` — so `bs=1M count=256` produced 213 MB instead of 256 MB. Over NFS
under concurrent load that is routine. It does not reproduce on an idle
filesystem: three back-to-back runs of the exact same `dd` returned the full
268435456 bytes every time. The chunk that broke was the one written while
qBittorrent was saturating the same mount.

Nextcloud rejected the assembly and answered the client as if nothing had
happened, so the only place the truth existed was a log nobody was reading.

Two fixes, deliberately redundant: `iflag=fullblock`, and an explicit size
check on every chunk before it is uploaded. Those are different claims —
"dd's short-read behaviour is the known cause" and "a truncated chunk must
never be uploaded" — and only the second one is worth enforcing.

And separately, the hook now **asks the server** after every upload instead of
trusting its own exit code. An upload that reports success and delivers
nothing is worse than one that fails, because the retry never happens and the
log actively argues against looking.

**The lesson:** *a success report is a claim about a process, not about a
result.* Every exit code in that chain was honest about its own step and the
file still was not there. Where a component can confirm the outcome — a HEAD,
a size, a checksum — believing it over your own return value costs one round
trip and is the difference between "it worked" and "it says it worked".

The corollary, again: the failing component logged the exact answer, in
detail, immediately, to a file nobody had thought to read. Checking the
*destination's* logs, not just the sender's, would have turned five hours into
five minutes.

### Correction to the entry above

The `dd` short read was real and worth fixing, but it was **not** the cause of
the false success. With `iflag=fullblock` in place and every chunk verified
byte-correct before upload, the failure reproduced exactly.

The actual cause is Nextcloud's chunked upload against S3 primary storage. A
clean single-run probe (the two before it were contaminated by my own orphaned
processes — see below):

- 29 chunks uploaded, **0** local or PUT problems
- server-side sizes: 28 x 268435456 + 1 x 219640692, `.file` = 7735833460 — exact
- `MOVE` -> **201**, after 100s
- `HEAD` on the destination -> **404**

Nextcloud logged `Stream from assembly node shorter than expected` and answered
the client 201 regardless. Re-run at 64 MiB chunks: 116 chunks, all correct,
MOVE 201 in 105s, still 404 — so it is not chunk size, and the byte counts at
which it died (212574486, 213364620, 213978412, then 12980658 of a 64 MiB
chunk) were not a fixed quantity but wherever the read happened to be when the
assembly gave up.

The fix was to stop chunking. Apache's `LimitRequestBody` (1 GiB by default in
that image) was the only reason chunking was introduced; with
`APACHE_BODY_LIMIT=0` and PHP at 64G, files go up in a single PUT that streams
straight into the object store and never performs the server-side reassembly.
**The same 7.7 GB file that failed three times as chunks uploaded first try as
one PUT** — 201, 636s at 12.1 MB/s, HEAD confirming 7735833460 bytes.

**The lesson:** the workaround was the bug. Chunking was added to get around a
1 GiB request cap, and it introduced a failure mode far worse than the cap it
solved — a silent one. Removing the constraint was cheaper and safer than
engineering around it, and that option was available from the first 413.

**And a lesson about the debugging, not the system:** two of the three probes
that produced my early conclusions were contaminated by my own leftover
processes. A `kubectl exec` killed at the ssh layer leaves its script running
inside the pod as an orphan; two runs then shared `/tmp/ct`, and one's cleanup
deleted the other's working directory mid-run. Both runs looked like system
failures and neither was. Use a unique temp dir per run, and confirm the
previous run is actually dead — `ps` in the pod, not an assumption — before
believing anything a second run tells you.

---

## The same log file took the cluster down again, with the fix already in place

**2026-09-08.** `/var/log/ganesha/ganesha.log` reached **72.8 GB**, filled the
LXC root disk to 100%, and took the k3s API server down with it. Every service
went with it.

This is the *same file*, the *same message*, and the *same failure* as
"One log file took the cluster's storage down" above — written up a day
earlier, with a fix applied and a lesson recorded. Both defences were in place.
Both did nothing.

**The config fix parsed cleanly and was never read.** `Enable_UDP = false` had
been added as a **second** `NFS_CORE_PARAM` block at the end of
`ganesha.conf`. Ganesha keeps the first block of a given name and ignores
later duplicates. The setting was syntactically valid, visible in the file,
committed to git, and described in this log — and the UDP listener kept
running the whole time.

That is the identical shape as the qBittorrent AutoRun key from the same week:
`Enabled=true` where the program reads `enabled`. Both were *config that
parsed and nothing consumed*. Neither produced a warning, because there is no
warning to produce: a key nobody reads and a block nobody reaches both look
exactly like a key that works.

**The rotation fix was correct and ran on the wrong clock.** The logrotate rule
said `maxsize 200M` — and logrotate itself runs **daily**. The previous entry
here even records the lesson, "rotation is a scheduled job; a runaway writer is
a rate," and the remedy applied at the time was to fix the *writer* while
leaving the schedule alone. When the writer came back, the schedule was still
daily: at 13 MB/s, a daily check permits about a terabyte.

**What is different now:**

- `Enable_UDP = false` lives in the first `NFS_CORE_PARAM` block, and was
  verified by `ss -lunp` showing no UDP listener plus the log being
  byte-identical across repeated samples — not by reading the config back.
- `ganesha-logrotate.timer` runs the existing rule **every minute** against its
  own state file. Worst case goes from ~1 TB to ~800 MB.

Both live in `scripts/host/ganesha/` now, because nothing in this repo deployed
them and that is why the first fix could quietly rot.

**The lesson:** *a fix you have not observed working is a hypothesis.* Every
step of the first repair was reasonable — right diagnosis, right setting, right
file, committed, documented — and it never once ran. What was missing was the
five-second check that the thing had actually changed: `ss -lunp` for the
listener, two `stat` calls for the growth rate. Verifying the config is not
verifying the behaviour; the only evidence that counts comes from the running
system, not the file you edited.

The corollary, which cost the most time: **when a failure recurs, suspect your
own fix before you suspect a new cause.** Several hours went into Nextcloud
upload paths on the assumption that the uploads had filled the disk. They had
not. The disk was filled by the thing that had filled it before, whose fix I
had already written and never confirmed.

### Two other things this outage exposed

**CT 200 was on DHCP.** During the outage its lease moved from `.172` to
`.198`, and k3s then refused to start: `this server is a not a member of the
etcd cluster. Found [...192.168.1.172:2380], expect: [...192.168.1.198:2380]`.
etcd pins members by URL, so a DHCP lease change is a cluster-destroying event
for a single-node control plane. Now a static `192.168.1.172`. Note the
follow-on: switching off DHCP also dropped the DHCP-supplied nameserver, and
the container inherited the Proxmox host's Tailscale resolver
(`100.100.100.100`), which is unreachable from inside the CT — every image pull
failed with `lookup quay.io: Try again` until an explicit nameserver was set.

**Two services came back up but stayed broken, in ways nothing reported.**
Redis crashlooped on a truncated AOF (`Bad file format reading the append only
file`) — the disk filled mid-append; `redis-check-aof --fix` truncated 1.18 MB
of corrupt tail and kept the other 49.4 MB. And Traefik came up *healthy*
while serving **404 for all 35 Ingresses**, because it started before the API
server was available and never rebuilt its routes. A running, ready Traefik
answering 404 for the entire homelab is the same genre as everything else in
this log: green status, no function. Deleting the pod fixed it.
