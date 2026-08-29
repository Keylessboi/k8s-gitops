# Outstanding Work

Status as of 2026-08-26. Everything not listed here is done and verified.

## Mine — Done

- [x] **Readarr download client.** qBittorrent added and tests valid, category `books` so downloads land in `/data/torrents/books` rather than the root. Its category field is confusingly named `musicCategory` — a leftover from the Lidarr fork — and defaulted to a category qBittorrent did not have.
- [x] **qui pointed at qBittorrent.** Account created (password in Doppler as `QUI_PASSWORD`), instance added, reports `connected: true`. It also shows `connectionStatus: firewalled`, which is qBittorrent saying it has not yet *observed* an incoming connection — expected with no active torrents, worth re-checking once something is downloading.
- [x] **`docs/RUNDOWN.md` brought up to date** with the `/data` layout, slskd, bgutil, the new hostnames and ArgoCD being LAN-only.

## Mine — In Order

Closing the verified plan gaps from `docs/PLAN-GAPS.md`, largest first.

- [x] **1a. Nextcloud on S3 primary storage — DONE.** Verified end to end: a WebDAV PUT returns 201, the object appears in the `nextcloud-data` bucket as `urn:oid:85`, and a read returns the content. Credentials by secret reference, `autoCreate` off so a wrong endpoint cannot silently create a bucket and write there.
- [x] **1b. Immich on S3 — NOT DOING, and this reverses my earlier decision.** I had settled on JuiceFS with SQLite metadata. Checking the actual machines changed the answer:

      - Immich cannot speak S3 (it needs POSIX), so *some* gateway is mandatory.
      - JuiceFS stores data as opaque chunks; the filesystem exists only in the metadata database. Lose that file and the photo library is gone even though every chunk is still sitting in MinIO.
      - MinIO runs on the NAS at `/tank/minio`. The Immich library is on the same NAS at `/extra/nfs-csi`. Different ZFS pool, **same machine** — so moving gains nothing in failure domain.
      - The library is 13 GB and the `extra` pool has 3.5 TB free, so there is no capacity pressure either.

      That is a catastrophic-loss single point and a sidecar mount, bought for no durability and no space. The plan's own wording reserves "NFS fallback for media streaming", which is exactly what a photo and video library is.

      Nextcloud is the opposite case and is already done — it speaks S3 natively, so it needed no gateway and carries none of this risk. Say the word if you want it anyway and I will build it.
- [x] **2. Navidrome SQLite -> PostgreSQL — NOT POSSIBLE, closing.** Navidrome has no PostgreSQL support in any release: upstream PR #2821 "feat(persistence): Postgres support" is still open (last updated 2026-08-19). The plan assumed a capability that does not exist yet, so this is an upstream limitation rather than something left undone. Revisit if that PR merges; the pgloader step only becomes meaningful then.
- [x] **3. smartctl_exporter — DONE.** Running on the Proxmox host and the NAS as systemd units (`scripts/install-smartctl-exporter.sh`), not as a DaemonSet: LXC 200 has no block devices in `/dev` at all, and the disks that matter are the NAS pool disks, which no pod can see by any route. Prometheus scrapes both over the LAN; all 5 disks report healthy. Seven alerts cover SATA (reallocated/pending sectors), NVMe (media errors, spare ratio), temperature, the drive's own verdict, and the exporter going away — because a dead exporter looks exactly like healthy disks. Dashboard: **Disk Health (SMART)**.
- [x] **4. ArgoCD Image Updater — DEPLOYED, one step left for you.** Watching 5 applications and 8 images, 0 errors, all currently at the newest tag allowed. Policy is in `apps/image-updater/imageupdaters.yaml`: every image is pinned to its major version (and its minor for 0.x, where semver still permits breaking changes), so an update can never cross a major. Write-back is git, so each bump arrives as a reviewable commit.

      **Needs you:** it cannot push yet. Run `./scripts/setup-image-updater-key.sh` — it mints a write-scoped deploy key for this repo only (not your personal credential), registers it, and puts the private half in Doppler. I was blocked from creating it.
- [x] **5. Per-app Grafana dashboards — DONE.** One templated **Application Detail** dashboard rather than a dashboard per service: every app is its own namespace, so a namespace variable scopes pods, restarts, OOMKills, PVC usage, Traefik request/error/latency and logs to one app — and a new app appears in the dropdown by itself.

      Two real faults turned up while building it:
      - Grafana had **no Loki datasource**. Loki was running and Alloy was shipping into it, but nothing could read it. Added.
      - Loki streams carried **no Kubernetes labels** — only instance, job and service_name. Alloy was never relabelling the `__meta_*` discovery labels, so logs were stored but could not be narrowed to an app by any query. Fixed; namespace/pod/container/app now present across all 24 namespaces.
- [x] **6. Leftover `juicefs` database and role — DONE.** Removed through git, staged in two commits: the Database CR defaults to `databaseReclaimPolicy: retain`, so deleting it outright would have left the database behind and merely stopped tracking it. Set to `delete` first, then removed. The role is `ensure: absent` for the same reason — CNPG only drops a role it is still told about.
- [x] **7. Music sources — reworked around free frontends only.** SquidWTF is gone (uninstalled: its upstream Qobuz service no longer exists, and it collided with a working plugin by registering the same `Qobuz` implementation name). Tubifarry upgraded 2.0.4.1 -> 2.1.0.0.

      Verified live by testing every indexer and client through Lidarr's own test endpoint:

      | Source | State | Note |
      |---|---|---|
      | Soulseek (slskd) | **working** | free, lossless. Indexer was pointing at `http://gluetun:50393` and holding a pre-rotation API key — both fixed |
      | Lucida | **working** | free frontend for Qobuz/Tidal/Deezer/SoundCloud. Was 403 behind Cloudflare |
      | qBittorrent + Prowlarr | **working** | BT.etree and Internet Archive both pass |
      | YouTube / Tubifarry | needs cookies | the `cookies.txt` you said to skip |
      | DABMusic | **disabled** | no usable instance - see below |
      | TripleTriple / T2Tunes | dead | `t2tunes.site` redirects to `/unavailable` |
      | arcod.xyz | alive, unusable | see below |

      **Why Lucida was broken:** Tubifarry's FlareSolverr integration was configured with `http://flaresolverr:8191/` — a bare hostname that cannot resolve across namespaces. FlareSolverr itself was fine the whole time (it solves lucida.to's challenge on demand). This is the third instance of the same short-hostname defect today, after the Slskd indexer and the 15 Prowlarr ones.

      **Why DAB is disabled:** `dabmusic.xyz` returns 522 (origin down). `dab.yeet.su` — the instance the plugin itself lists as its placeholder — serves a chain rooted at **ISRG Root YE**, a new Let's Encrypt ECDSA root that is not yet in the container's CA bundle, so TLS verification fails before authentication is even attempted. Not worth working around by disabling certificate validation; it will likely fix itself when the base image ships a newer CA bundle. Re-enable both entries then.

      **arcod.xyz** is alive and is a genuinely free Qobuz frontend, but no installed plugin speaks its API. It is Qobuz-DL family — `/api/get-music` returning Qobuz-native JSON (`data.albums.items[]`) — whereas the DAB plugin parses a flat `albums[]`, so it cannot be used as a DAB base URL. It would need its own plugin written.

      Also installed but **not configured**, and left in place only in case you ever subscribe: TrevTV's Qobuz, Deezer and Tidal plugins. All three need paid accounts, so none of them are in use. Say the word and I will remove them.
- [x] **8. Lidarr maintenance script + Hermes — BOTH RUNNING.**
      Your `lidarr-maintenance-script` runs nightly at 02:00 as a CronJob and is verified end to end against Lidarr (all four phases). It is pure standard library, so it needs no build step, and it clones fresh each run — push to main and the next run picks it up, same as your `run_maintenance.sh`.

      Two things had to be fixed to get there: installing git needs apt, whose dependency downloads all failed because cluster DNS answers with AAAA records this node has no IPv6 route for (now fetched with urllib); and the NetworkPolicy allowed ingress from this namespace but not egress, so nothing in it could call Lidarr's own API.

      **Hermes is now deployed** (`apps/hermes`) from the official image, `nousresearch/hermes-agent:v2026.8.19` — upstream is `NousResearch/hermes-agent`, and although their compose builds locally, their CI publishes to Docker Hub, so there is a real image to pin and no dependency on any workstation.

      It is running with its state on a persistent volume, egress to Lidarr's API, and the private ranges excluded so a prompt cannot turn it into a LAN scanner. The dashboard is on container loopback because a non-loopback bind fails closed without an auth provider — upstream made that mandatory after unauthenticated dashboards were used to plant SSH backdoors in June 2026. It speaks self-hosted OIDC, so it can move behind Authentik.

      **Needs you:** one interactive setup to add an LLM provider key, which only you can choose:

          kubectl exec -it -n hermes deploy/hermes -- hermes setup

      It writes to the mounted volume, so it survives restarts and upgrades. After that, `hermes cron add` schedules the review of the maintenance script's `[AGENT_OVERSIGHT_NEEDED]` items.
- [ ] **9. Vaultwarden push notifications** — optional; needs a free install id and key from bitwarden.com/host for mobile push.

## Fixed Along the Way

- **Slskd indexer and download client in Lidarr were both dead.** The indexer pointed at `http://gluetun:50393`, which does not resolve, and both it and the `Slskd2` download client still held the slskd API key from before I rotated it — so both failed authentication. Repointed at `slskd.downloads.svc.cluster.local:5030` and re-keyed from slskd's running config; Lidarr validates on save, and both saved clean.

## Blocked on You

- [ ] **Hermes needs your local AI box powered on.** Hermes is deployed and Running, but the Tailscale node named `llm` (100.112.201.48) has been **offline for 8 days** — no ping, and 11434/8000/1234/5000/8080 all refused. I could not find the setup documented in any of your 15 GitHub repos either, so I cannot tell which engine or model it serves.

      Once it is on I need two things and can finish in one pass: its **LAN** address (not the Tailscale one — the pod would have to route 100.64/10 through the node, whereas a LAN IP is one NetworkPolicy rule) and which server it runs. Hermes takes an OpenAI-compatible endpoint with no real key, e.g. for Ollama:

      ```yaml
      providers:
        local:
          api: http://192.168.1.X:11434/v1
          api_key: "unused"     # local servers ignore it; the field must exist
      ```

      Its egress policy currently excludes the private ranges on purpose, so a prompt cannot turn the agent into a LAN scanner — that box gets one explicit allow rule, the same way the smartctl exporters did.

- [ ] **Lidarr plugin for arcod / the Qobuz frontends.** Parked at your request. Reference you sent: https://discord.com/channels/1347344910008979548/1423268870361190486/1533343627365974057 (I cannot read it — Discord needs an authenticated session — so paste anything relevant from it when we pick this up.)

      Not urgent: a real search now returns 16 releases, 13 of them from Lucida, which already fronts Qobuz/Tidal/Deezer/SoundCloud for free.

## Yours

- [ ] **15 dead indexers in Lidarr, left over from the backup restore.** They are named `... (Prowlarr)` and point at `http://prowlarr:9696/...` — a bare hostname, which cannot resolve from the lidarr namespace. Verified: that URL returns nothing from inside the Lidarr pod, while `prowlarr.prowlarr.svc.cluster.local:9696` returns 302.

      I did not delete them, because this is your area — you said you would set the Prowlarr trackers. Prowlarr will not repair them either: it currently has **zero** indexers configured, so it does not own these and a forced `ApplicationIndexerSync` leaves them alone.

      The fix is just to add your indexers in Prowlarr. Its Lidarr application is already correct (`prowlarrUrl = http://prowlarr.prowlarr.svc.cluster.local:9696`), so anything you add gets pushed to Lidarr with a working URL. Then delete the 15 stale ones, or say the word and I will. Until then every Lidarr search spends time failing against them.

- [x] **RESOLVED: IP conflict on 192.168.1.240.** This was the cause of services appearing to drop at random, and it was never the cluster.

      A Raspberry Pi (MAC `e4:5f:01:83:1d:87`, holding both `192.168.1.39` and `192.168.1.199`) was **also answering ARP for 192.168.1.240** — the MetalLB address the router forwards 80/443 to. Both machines replied to every ARP request, the Pi about 1ms behind, so whichever reply the router cached last won. Traffic landed on the cluster or on the Pi's Traefik at random.

      Proof: `tcpdump` showed two replies per probe — `192.168.1.240 is-at bc:24:11:16:58:4e` (k3s node) and `is-at e4:5f:01:83:1d:87` (Pi). The certificate served externally during a failure fingerprinted as the Pi's exactly; when it worked, the cluster's. Failing requests never appeared in the cluster's Traefik access log.

      Note the earlier entry here blamed a duplicate port-forward rule. That was wrong — the forwards were correct all along, a single rule per port pointing at `.240`. `ip neigh` had shown a single clean MAC because it displays only the cached winner, not every responder; only a packet capture revealed the second. Worth remembering: to find a duplicate ARP claim you must watch the wire, not the cache.

      Resolved by powering the Pi off. Verified afterwards: one ARP responder for `.240` across repeated probes, and all twelve public services returning correct status with verified TLS from outside the network, eight consecutive attempts with no failures.

      If that Pi is ever wanted again, it must not carry `192.168.1.240` — MetalLB's pool is `192.168.1.240-250`, so nothing else may use that range.

- [ ] **Review the cluster against best practice, the docs, and the plan.** Requested as standing work: after changes, verify the running cluster still matches `docs/RUNDOWN.md`, the phase goals, and sane defaults — rather than assuming a green sync means correct.

- [ ] **Add indexers to Prowlarr.** Only CrackingPatching and Internet Archive exist. Which trackers, and any accounts, are your call. Tag anything Cloudflare-protected with `flaresolverr` — the proxy is configured but stays disabled until at least one indexer carries that tag.
- [x] **DAB account password — deliberately not rotated.** It appeared in this session's log when the restored download clients were read. Owner's decision to leave it; noted here so it is not raised again. The qBittorrent password and slskd API key *were* rotated.

- [ ] **YouTube `cookies.txt`** — skipped per your instruction. If you ever want it, drop the file at `/data/cookies/youtube.txt`; the path and the bgutil POT provider are already in place.

## Done This Session

Core: split-horizon DNS, real client addresses at the edge, CrowdSec + rate limiting actually keyed correctly, Doppler operator working for the first time, server-side diff, ArgoCD bootstrap scripted.

Media: `/data` layout with verified hardlinks, Lidarr restored (498 artists), gluetun + qBittorrent + slskd on the AirVPN forwarded ports with a passing leak test, Soulseek sharing the tagged library, bgutil for YouTube, Prowlarr wired to Lidarr and Readarr, FlareSolverr given internet access, Internet Archive fixed.

Auth: Vaultwarden SSO, Nextcloud SSO, Immich SSO, Authentik icons and launch URLs, outpost callback routes, ArgoCD restricted to LAN/Tailscale.
