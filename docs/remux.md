# Remux — Jellyfin-compatible media server (parallel deployment)

Remux (ghcr.io/lostb1t/remux, by the Gelato author) is deployed in the `remux`
namespace **in parallel** with the existing Jellyfin stack while the owner
validates it. Jellyfin keeps running untouched; nothing here decommissions it.

## Design

- **Airtight egress** — Remux shares a pod with a gluetun sidecar (AirVPN
  WireGuard, creds from Doppler `AIRVPN_*` synced namespace-locally), the same
  containment pattern as the qBittorrent and Jellyfin pods and the standard
  from the Funkwhale VPN design block in issue #2. All public egress — AIOStreams
  addon fetches, TMDB, RemuxDB, the built-in torrent client (librqbit peers,
  DHT, trackers) — exits the tunnel; tunnel down = zero egress. The LAN is
  deliberately NOT in `FIREWALL_OUTBOUND_SUBNETS` (unlike Jellyfin, Remux does
  no in-pod OIDC).
- **Split access** — users come IN via the edge (Traefik → pod CIDR, bypassed
  in gluetun's firewall); replies ride the established connection. The NFS
  library is a node-level mount and never touches the pod's netns.
- **Local files** — the same media-data NFS library as Jellyfin, static PV
  `media-data-remux` → subDir `data`, mounted read-only at `/data/media`
  (music now; movies/tv when a video *arr populates them). Remux's own state
  (SQLite db, logs, torrent sessions) is on the private `remux-config` PVC.
- **Image** — `ghcr.io/lostb1t/remux:0.27.0`, the newest stable release tag at
  deploy time (ghcr drops the `v` prefix; `:latest`/`:nightly` are moving tags).

## The AIOStreams addon wiring

Remux consumes the **same** self-hosted AIOStreams instance the Jellyfin stack
uses — same encrypted manifest URL, same 1080p Direct-Play config (user
`883deab4-c172-44fe-80f5-33c0c7042e9b`, see docs/jellyfin-gelato.md).

- The manifest URL is **portable**: the trailing blob is ciphertext under
  AIOStreams' `SECRET_KEY`, so it resolves from any caller that can reach the
  instance. What the Jellyfin pod reaches over localhost, Remux reaches through
  the new `aiostreams` Service in the jellyfin namespace (added to
  apps/jellyfin/deployment.yaml — the only change the Jellyfin stack took;
  additive, no Ingress, and the jellyfin NetworkPolicy gates it to the remux
  namespace on port 3000 only).
- Remux derives stream endpoints from the manifest URL's origin (not from
  AIOStreams' `BASE_URL`), and explicitly rewrites AIOStreams' placeholder
  `aiostreams` host to that origin (upstream `rewrite_aio_url`), so the
  cross-namespace origin is correct end to end. Without a debrid service the
  streams are infoHash-based and Remux's built-in torrent client fetches them
  through the tunnel.
- The addon was created headlessly: `POST /addons` with
  `{"preset":{"kind":"stremio","config":{"manifest_url":"http://aiostreams.jellyfin.svc.cluster.local:3000/stremio/<user>/<blob>/manifest.json"}},"name":"AIOStreams"}`
  (Remux validates the manifest live at create time, so a 201 is itself proof
  the cross-namespace path works).

## Auth decision (the trade-off)

Remux has **no native OIDC** — its auth surface is its own Jellyfin-style
login plus the first-run startup wizard. An open media server on the public
edge is unacceptable, so the whole route sits behind **Authentik
forward-auth** (`kube-system-authentik-forward-auth@kubernetescrd`, provider +
application `remux` created via `ak shell`).

**Trade-off, stated plainly:** native Jellyfin clients (Infuse, Swiftfin,
Jellyfin for Android) authenticate against Remux's own API and cannot follow
an OAuth redirect — pointed at `remux.sandstorm.chat` they will break behind
forward-auth. Chosen anyway for now: validation is browser-based and an
unauthenticated media server on the public internet is the worse failure
mode. If native clients are wanted later, carve the API paths out of
forward-auth (Remux's own login becomes the gate — the Jellyfin arrangement)
or front clients individually.

## Headless bootstrap (already done)

1. Startup wizard via the API: `POST /startup/configuration`,
   `POST /startup/user` (admin, password from Doppler `REMUX_ADMIN_PASSWORD`),
   `POST /startup/complete`. The wizard endpoints lock themselves after
   completion.
2. AIOStreams addon created via `POST /addons` (above).
3. Verified: search through Remux's Jellyfin-compatible API returns AIOStreams
   results; killswitch 3-test passed (see git history / session log for the
   evidence captures).

## Owner click-list

1. Open `https://remux.sandstorm.chat` in a browser — Authentik login first
   (forward-auth), then Remux's own login: username `admin`, password in
   Doppler (`kubernetes/prd` → `REMUX_ADMIN_PASSWORD`).
2. Import users/data from the existing Jellyfin (Remux's user management has a
   Jellyfin import; the Jellyfin server is reachable in-cluster at
   `http://jellyfin.jellyfin.svc.cluster.local:8096`).
3. Point ONE Jellyfin client at `remux.sandstorm.chat` to test — **expect
   native clients to fail behind forward-auth** (see the trade-off above);
   validate catalogs/playback in the browser or via a client that can follow
   the Authentik login.
4. If Remux wins: decommission plan for apps/jellyfin is a separate decision —
   nothing here has touched it.
