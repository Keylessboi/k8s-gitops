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
| Every downstream *arr broken after a key change | Prowlarr API key rotation — 2026-08-29 |
| A CronJob that vanishes seconds after you create it | manual CronJob run — 2026-08-29 |
| Stale NFS handles, pods stuck ContainerCreating | closet move — 2026-08-28 |

### The traps that have bitten more than once

Each of these is now a check in `scripts/ci/check-invariants.py`, because the
prose version of the prevention failed:

- **kube-router race** (2×) — any Job whose first act is a network call needs a
  `wait-*` initContainer.
- **One-sided NetworkPolicy** (4×) — a cross-namespace flow needs egress in the
  source *and* ingress in the destination.
- **Duplicate YAML keys** (1×, but silent) — PyYAML accepts them, Go's yaml does
  not. Validate with the same parser as the consumer.

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
