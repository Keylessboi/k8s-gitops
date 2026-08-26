# Outstanding work

Status as of 2026-08-26. Everything not listed here is done and verified.

## Mine — done

- [x] **Readarr download client.** qBittorrent added and tests valid, category
      `books` so downloads land in `/data/torrents/books` rather than the root.
      Its category field is confusingly named `musicCategory` - a leftover from
      the Lidarr fork - and defaulted to a category qBittorrent did not have.
- [x] **qui pointed at qBittorrent.** Account created (password in Doppler as
      `QUI_PASSWORD`), instance added, reports `connected: true`. It also shows
      `connectionStatus: firewalled`, which is qBittorrent saying it has not yet
      *observed* an incoming connection - expected with no active torrents,
      worth re-checking once something is downloading.
- [x] **`docs/RUNDOWN.md` brought up to date** with the `/data` layout, slskd,
      bgutil, the new hostnames and ArgoCD being LAN-only.

## Mine — in order

Closing the verified plan gaps from `docs/PLAN-GAPS.md`, largest first.

- [x] **1a. Nextcloud on S3 primary storage — DONE.** Verified end to end: a
      WebDAV PUT returns 201, the object appears in the `nextcloud-data` bucket
      as `urn:oid:85`, and a read returns the content. Credentials by secret
      reference, `autoCreate` off so a wrong endpoint cannot silently create a
      bucket and write there.
- [x] **1b. Immich on S3 — NOT DOING, and this reverses my earlier decision.**
      I had settled on JuiceFS with SQLite metadata. Checking the actual
      machines changed the answer:

      - Immich cannot speak S3 (it needs POSIX), so *some* gateway is mandatory.
      - JuiceFS stores data as opaque chunks; the filesystem exists only in the
        metadata database. Lose that file and the photo library is gone even
        though every chunk is still sitting in MinIO.
      - MinIO runs on the NAS at `/tank/minio`. The Immich library is on the
        same NAS at `/extra/nfs-csi`. Different ZFS pool, **same machine** - so
        moving gains nothing in failure domain.
      - The library is 13 GB and the `extra` pool has 3.5 TB free, so there is
        no capacity pressure either.

      That is a catastrophic-loss single point and a sidecar mount, bought for
      no durability and no space. The plan's own wording reserves "NFS fallback
      for media streaming", which is exactly what a photo and video library is.

      Nextcloud is the opposite case and is already done - it speaks S3 natively,
      so it needed no gateway and carries none of this risk. Say the word if you
      want it anyway and I will build it.
- [x] **2. Navidrome SQLite -> PostgreSQL — NOT POSSIBLE, closing.** Navidrome
      has no PostgreSQL support in any release: upstream PR #2821
      "feat(persistence): Postgres support" is still open (last updated
      2026-08-19). The plan assumed a capability that does not exist yet, so
      this is an upstream limitation rather than something left undone. Revisit
      if that PR merges; the pgloader step only becomes meaningful then.
- [x] **3. smartctl_exporter — DONE.** Running on the Proxmox host and the NAS
      as systemd units (`scripts/install-smartctl-exporter.sh`), not as a
      DaemonSet: LXC 200 has no block devices in `/dev` at all, and the disks
      that matter are the NAS pool disks, which no pod can see by any route.
      Prometheus scrapes both over the LAN; all 5 disks report healthy. Seven
      alerts cover SATA (reallocated/pending sectors), NVMe (media errors,
      spare ratio), temperature, the drive's own verdict, and the exporter
      going away - because a dead exporter looks exactly like healthy disks.
      Dashboard: **Disk Health (SMART)**.
- [x] **4. ArgoCD Image Updater — DEPLOYED, one step left for you.** Watching
      5 applications and 8 images, 0 errors, all currently at the newest tag
      allowed. Policy is in `apps/image-updater/imageupdaters.yaml`: every image
      is pinned to its major version (and its minor for 0.x, where semver still
      permits breaking changes), so an update can never cross a major.
      Write-back is git, so each bump arrives as a reviewable commit.

      **Needs you:** it cannot push yet. Run
      `./scripts/setup-image-updater-key.sh` - it mints a write-scoped deploy
      key for this repo only (not your personal credential), registers it, and
      puts the private half in Doppler. I was blocked from creating it.
- [x] **5. Per-app Grafana dashboards — DONE.** One templated **Application
      Detail** dashboard rather than a dashboard per service: every app is its
      own namespace, so a namespace variable scopes pods, restarts, OOMKills,
      PVC usage, Traefik request/error/latency and logs to one app - and a new
      app appears in the dropdown by itself.

      Two real faults turned up while building it:
      - Grafana had **no Loki datasource**. Loki was running and Alloy was
        shipping into it, but nothing could read it. Added.
      - Loki streams carried **no Kubernetes labels** - only instance, job and
        service_name. Alloy was never relabelling the `__meta_*` discovery
        labels, so logs were stored but could not be narrowed to an app by any
        query. Fixed; namespace/pod/container/app now present across all 24
        namespaces.
- [x] **6. Leftover `juicefs` database and role — DONE.** Removed through git,
      staged in two commits: the Database CR defaults to
      `databaseReclaimPolicy: retain`, so deleting it outright would have left
      the database behind and merely stopped tracking it. Set to `delete` first,
      then removed. The role is `ensure: absent` for the same reason - CNPG only
      drops a role it is still told about.
- [ ] **7. SquidWTF (Qobuz proxy) client + indexer** - plugin installed, needs
      configuring.
- [x] **8. Lidarr maintenance script — RUNNING; the Hermes half is blocked.**
      Your `lidarr-maintenance-script` runs nightly at 02:00 as a CronJob and is
      verified end to end against Lidarr (all four phases). It is pure standard
      library, so it needs no build step, and it clones fresh each run - push to
      main and the next run picks it up, same as your `run_maintenance.sh`.

      Two things had to be fixed to get there: installing git needs apt, whose
      dependency downloads all failed because cluster DNS answers with AAAA
      records this node has no IPv6 route for (now fetched with urllib); and the
      NetworkPolicy allowed ingress from this namespace but not egress, so
      nothing in it could call Lidarr's own API.

      **Blocked:** the Hermes agent-oversight layer. Hermes Agent is a
      third-party product - there is no `hermes` binary on your machine, no
      `~/.hermes`, and nothing matching in your 32 repos - so I cannot
      containerise it without knowing which distribution you run. The mechanical
      cleanup is fully delivered without it; items the script refuses to judge
      print as `[AGENT_OVERSIGHT_NEEDED]` and surface in the job log.
- [ ] **9. Vaultwarden push notifications** - optional; needs a free install id
      and key from bitwarden.com/host for mobile push.

## Yours

- [x] **RESOLVED: IP conflict on 192.168.1.240.** This was the cause of services
      appearing to drop at random, and it was never the cluster.

      A Raspberry Pi (MAC `e4:5f:01:83:1d:87`, holding both `192.168.1.39` and
      `192.168.1.199`) was **also answering ARP for 192.168.1.240** - the
      MetalLB address the router forwards 80/443 to. Both machines replied to
      every ARP request, the Pi about 1ms behind, so whichever reply the router
      cached last won. Traffic landed on the cluster or on the Pi's Traefik at
      random.

      Proof: `tcpdump` showed two replies per probe -
      `192.168.1.240 is-at bc:24:11:16:58:4e` (k3s node) and
      `is-at e4:5f:01:83:1d:87` (Pi). The certificate served externally during a
      failure fingerprinted as the Pi's exactly; when it worked, the cluster's.
      Failing requests never appeared in the cluster's Traefik access log.

      Note the earlier entry here blamed a duplicate port-forward rule. That was
      wrong - the forwards were correct all along, a single rule per port
      pointing at `.240`. `ip neigh` had shown a single clean MAC because it
      displays only the cached winner, not every responder; only a packet
      capture revealed the second. Worth remembering: to find a duplicate ARP
      claim you must watch the wire, not the cache.

      Resolved by powering the Pi off. Verified afterwards: one ARP responder
      for `.240` across repeated probes, and all twelve public services
      returning correct status with verified TLS from outside the network,
      eight consecutive attempts with no failures.

      If that Pi is ever wanted again, it must not carry `192.168.1.240` -
      MetalLB's pool is `192.168.1.240-250`, so nothing else may use that range.

- [ ] **Review the cluster against best practice, the docs, and the plan.**
      Requested as standing work: after changes, verify the running cluster
      still matches `docs/RUNDOWN.md`, the phase goals, and sane defaults -
      rather than assuming a green sync means correct.

- [ ] **Add indexers to Prowlarr.** Only CrackingPatching and Internet Archive
      exist. Which trackers, and any accounts, are your call.
      Tag anything Cloudflare-protected with `flaresolverr` — the proxy is
      configured but stays disabled until at least one indexer carries that tag.
- [x] **DAB account password — deliberately not rotated.** It appeared in this
      session's log when the restored download clients were read. Owner's
      decision to leave it; noted here so it is not raised again. The
      qBittorrent password and slskd API key *were* rotated.

- [ ] **YouTube `cookies.txt`** — skipped per your instruction. If you ever want
      it, drop the file at `/data/cookies/youtube.txt`; the path and the bgutil
      POT provider are already in place.

## Done this session

Core: split-horizon DNS, real client addresses at the edge, CrowdSec + rate
limiting actually keyed correctly, Doppler operator working for the first time,
server-side diff, ArgoCD bootstrap scripted.

Media: `/data` layout with verified hardlinks, Lidarr restored (498 artists),
gluetun + qBittorrent + slskd on the AirVPN forwarded ports with a passing leak
test, Soulseek sharing the tagged library, bgutil for YouTube, Prowlarr wired to
Lidarr and Readarr, FlareSolverr given internet access, Internet Archive fixed.

Auth: Vaultwarden SSO, Nextcloud SSO, Immich SSO, Authentik icons and launch
URLs, outpost callback routes, ArgoCD restricted to LAN/Tailscale.
