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

- [ ] **1. S3 primary storage.** The plan calls for MinIO S3 primary with NFS
      fallback for media streaming only; today that is inverted. Nextcloud and
      Immich both speak S3 natively - no gateway needed, which is what sank
      JuiceFS. Start with Nextcloud (`objectstore` is unset), then Immich.
- [ ] **2. Navidrome SQLite -> PostgreSQL** via pgloader, per the plan.
- [ ] **3. smartctl_exporter** so a failing disk is visible.
- [ ] **4. ArgoCD Image Updater** so image bumps are not manual.
- [ ] **5. Per-app Grafana dashboards** - currently only the stack's generic set
      plus one overview.
- [ ] **6. Drop the leftover `juicefs` database and role** from CNPG.
- [ ] **7. SquidWTF (Qobuz proxy) client + indexer** - plugin installed, needs
      configuring.
- [ ] **8. Hermes agent for the Lidarr maintenance script** - blocked on the
      repo URL.
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
