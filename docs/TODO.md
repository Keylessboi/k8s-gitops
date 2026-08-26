# Outstanding work

Status as of 2026-08-26. Everything not listed here is done and verified.

## Mine — in progress

- [ ] **Readarr has no download client.** Confirmed: `downloadclient` returns 0.
      Books can be searched but nothing can actually be fetched over the P2P
      path until qBittorrent is added.
- [ ] **qui is not pointed at qBittorrent.** It is published and behind
      Authentik, but holds no instance, so it shows nothing.
- [ ] **`docs/RUNDOWN.md` is stale.** It predates the `/data` layout, slskd,
      bgutil, the bookdl and Prowlarr hostnames, and ArgoCD being LAN-only.

## Yours

- [ ] **Add indexers to Prowlarr.** Only CrackingPatching and Internet Archive
      exist. Which trackers, and any accounts, are your call.
      Tag anything Cloudflare-protected with `flaresolverr` — the proxy is
      configured but stays disabled until at least one indexer carries that tag.
- [ ] **Rotate the DAB account password** at dabmusic.xyz. It appeared in this
      session's log when I read the restored download clients. Note the service
      is currently down (HTTP 522 from outside the network), so this can wait.
      The qBittorrent password and slskd API key were already rotated.
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
