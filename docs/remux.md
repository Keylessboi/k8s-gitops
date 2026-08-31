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
   completion. NOTE: the payload fields are PascalCase (`{"Name":...,
   "Password":...}`) — lowercase keys deserialize as None and the endpoint
   silently no-ops with a 204 (this bit once; the wizard flag was reset via
   the `server_configuration` row in the settings table to redo it).
2. AIOStreams addon created via `POST /addons` (above). Catalogs enabled via
   `POST /addons/{id}/catalogs` (all 8 enabled).
3. Authentik forward-auth provider created via `ak shell` (cluster state, not
   git): ProxyProvider `remux` (mode proxy, external_host
   `https://remux.sandstorm.chat`, internal_host
   `http://remux.remux.svc.cluster.local:3000`) + Application slug `remux`.
   Recreate after a cluster rebuild with the same two objects.

## Verification evidence (2026-08-30 ~21:00-23:45 EDT)

- **Pod Ready, health 200** in-cluster; gluetun tunnel up.
- **AIOStreams addon wired**: `POST /addons` returned 201 (Remux validates the
  manifest live at create time — the cross-namespace Service path works);
  `GET /addons/{id}/catalogs` lists 8 catalogs, all enabled.
- **Real search through the Jellyfin-compatible API**: with the system TMDB
  addon disabled, `GET /Items?searchTerm=Inception` returned **17 results**
  (Inception 2010 first) — pure AIOStreams path. Re-enabled after.
- **Killswitch test 1 — exit IP ≠ home WAN**: PASS. `curl ip4.me` from the
  remux container returned `62.102.148.182` (AirVPN exit), never
  `74.101.53.75`.
- **Killswitch test 2 — tunnel down = no egress**: PASS. With `tun0` down
  inside gluetun, both a DNS-resolved fetch (ip4.me) and a raw-IP fetch
  (1.1.1.1) timed out (curl rc=28) — fail-closed, no leak.
- **Killswitch test 3 — edge survives tunnel-down**: PARTIAL. The Remux
  backend stayed reachable in-cluster during the tunnel-down window (health
  200). The full edge path (Traefik → forward-auth → browser) could not be
  validated end-to-end: the cluster spent the evening in a pre-existing
  node disk-pressure eviction storm (CNPG/Postgres churn, days old — see
  below), which took down Authentik's database and every pod repeatedly. The
  lidarr forward-auth control failed identically at the same moment, so the
  failure is infrastructure, not the remux route. To finish the check once
  the cluster is calm:
  ```bash
  curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' \
    https://remux.sandstorm.chat/   # expect 302 to Authentik login
  ```

## Known issues at deploy time (pre-existing, not remux's)

- **Node disk-pressure storm**: the k3s node's 67 GB disk hovers at the
  kubelet eviction threshold; the CNPG Postgres pod's write churn (measured
  517 GiB/24h through the postgres container) cycles the node between
  taint-on and taint-off, evicting everything periodically. Remux has
  resource requests, so it is not first in eviction order, but it flaps with
  the storm like every other app.
- **Torrentio 403s**: AIOStreams' upstream Torrentio fetches are being
  403'd (Cloudflare vs the AirVPN exit), so the AIOStreams manifest currently
  advertises no `stream` resource — search/catalogs work, stream results are
  degraded for BOTH Jellyfin/Gelato and Remux equally (same shared instance).
  This comes and goes with VPN exits; nothing in the remux deployment
  influences it.

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
