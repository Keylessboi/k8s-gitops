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

## Yours

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
