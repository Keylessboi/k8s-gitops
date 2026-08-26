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

- [ ] **Remove the duplicate 80/443 port-forward pointing at the Raspberry Pi.**
      This is what makes services appear to "go down" at random.

      A device with MAC `e4:5f:01:83:1d:87` (Raspberry Pi) holds **two** LAN
      addresses, `192.168.1.39` and `192.168.1.199`, and runs its own Traefik on
      80 and 443. The router alternates between forwarding WAN traffic to it and
      to the cluster, so requests land on one or the other at random.

      Evidence: the certificate served externally during a failure fingerprints
      as `E2:63:9F:38:80:C8…`, which is the Pi's exactly; when it works it is
      `74:D1:38:52:41:4B…`, the cluster's. On port 80 the same split shows up as
      the Pi's Go-style "404 page not found" versus Traefik's 301. Requests that
      fail never appear in the cluster's Traefik access log at all.

      The cluster is not at fault: from the LAN, `192.168.1.240` consistently
      serves the correct Let's Encrypt certificate for every hostname, ARP for
      `.240` is stable, and Traefik has logged no reloads or TLS errors.

      Fix in the router: delete the stale 80/443 forward to the Pi, leaving only
      the one to `192.168.1.240`. Also worth asking why that Pi holds two DHCP
      leases.

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
