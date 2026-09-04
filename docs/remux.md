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

## Headless bootstrap

**This is now automated** by `apps/remux/admin-job.yaml`, an idempotent ArgoCD
PostSync hook that performs the steps below from the Doppler secret. It exits
early when `GET /Startup/Configuration` returns 403 (wizard already complete),
so it is safe on every sync. The manual procedure is kept here because it is
what the Job does and what you would do by hand if it ever failed.

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
   git): ProxyProvider `remux` (**mode `forward_single`** — it was created as
   `proxy`, which is what broke the login on 2026-09-03: proxy mode expects the
   outpost to receive and forward the request itself, while this app's Ingress
   is wired for forward-auth. Every other provider here is `forward_single`.
   external_host
   `https://remux.sandstorm.chat`, internal_host
   `http://remux.remux.svc.cluster.local:3000`) + Application slug `remux`.
   Recreate after a cluster rebuild with the same two objects.
4. **AND assign the provider to the Embedded Outpost** — the non-obvious step
   that cost an hour: the embedded outpost serves an EXPLICIT provider list
   (Lidarr, Prowlarr, Books, qui, Book Downloader, Navidrome, ConvertX,
   bitmagnet, Alertmanager), not "all providers". A provider that exists but
   is not in that list makes the outpost's `/outpost.goauthentik.io/auth/traefik`
   return 404 for its domain — Traefik then 404s the whole route. The fix:
   ```python
   from authentik.outposts.models import Outpost
   o = Outpost.objects.get(name="authentik Embedded Outpost")
   o.providers.add(ProxyProvider.objects.get(name="remux"))
   ```
   The outpost re-syncs within ~60s (watch for
   `GET /api/v3/outposts/proxy/ 200` from user `ak-outpost-*` in the
   authentik-server log).

## Verification evidence (2026-08-30, 21:00-23:00 EDT)

- **Pod Ready, health 200** in-cluster; gluetun tunnel up.
- **AIOStreams addon wired**: `POST /addons` returned 201 (Remux validates the
  manifest live at create time — the cross-namespace Service path works);
  `GET /addons/{id}/catalogs` lists 8 catalogs, all enabled.
- **Real search through the Jellyfin-compatible API**: with the system TMDB
  addon disabled, `GET /Items?searchTerm=Inception` returned **17 results**
  (Inception 2010 first) — pure AIOStreams path. Re-enabled after.
- **Killswitch test 1 — exit IP ≠ home WAN**: PASS. `curl ip4.me` from the
  remux container returned AirVPN exits across pod rolls (`62.102.148.182`,
  `130.195.210.114`, `68.235.36.19`), never `74.101.53.75`.
- **Killswitch test 2 — tunnel down = no egress**: PASS. With `tun0` down
  inside gluetun, both a DNS-resolved fetch (ip4.me) and a raw-IP fetch
  (1.1.1.1) timed out (curl rc=28) — fail-closed, no leak.
- **Killswitch test 3 — edge survives tunnel-down**: PASS. With `tun0` down:
  `https://remux.sandstorm.chat` still answered **302 → the Authentik login
  flow** (`/outpost.goauthentik.io/start?rd=...`), and the backend stayed
  healthy (health 200) — the edge path rides the pod-CIDR bypass and does not
  traverse the tunnel. After `tun0 up`, egress returned on the VPN exit
  (`68.235.36.19`).
- **Edge gate enforced**: unauthenticated request → 302 to the Authentik
  login flow, identical in kind to the lidarr forward-auth control captured
  side by side. Testing note for anyone re-verifying through a port-forward:
  the outpost matches providers by exact forwarded host, so a non-standard
  port in the Host header (`host:18443`) 404s EVERY app including known-good
  ones — send a clean `Host:` header or test on 443.

## Known issues at deploy time (pre-existing, not remux's)

- **Node disk-pressure storm**: the k3s node's 67 GB disk hovers at the
  kubelet eviction threshold; the CNPG Postgres pod's write churn (measured
  517 GiB/24h through the postgres container) cycles the node between
  taint-on and taint-off, evicting everything periodically. Remux has
  resource requests, so it is not first in eviction order, but it flaps with
  the storm like every other app.
- **Torrentio 403s (transient, recovered)**: during the deploy evening,
  AIOStreams' upstream Torrentio fetches were 403'd (Cloudflare vs the AirVPN
  exit), which dropped the `stream` resource from the AIOStreams manifest —
  search/catalogs kept working, stream results were degraded for BOTH
  Jellyfin/Gelato and Remux equally (same shared instance). By end of session
  the 403s cleared and the `stream` resource returned. This comes and goes
  with VPN exits; nothing in the remux deployment influences it.

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

## AIOStreams wiring — read this before debugging playback (2026-09-04)

**The addon had never worked, and not for the reason anyone was looking at.**
Remux's stored AIOStreams addon pointed at
`http://aiostreams.jellyfin.svc.cluster.local:3000/...` — the **decommissioned
jellyfin namespace**. AIOStreams moved to `remux` and the addon URL was never
updated.

It failed *silently* because `NO_PROXY` named only
`aiostreams.remux.svc.cluster.local`, so the stale `jellyfin` address was not
exempt and every call went **out through the VPN HTTP proxy**. gluetun has no
cluster DNS, so it answered `no such host`. Nothing was visible from remux's
side; the evidence was only in the gluetun log. `NO_PROXY` is now a suffix
match on `.svc` / `.svc.cluster.local` / `.cluster.local`.

### Current state
- AIOStreams runs on Postgres (25 tables), reachable in-cluster.
- A user config exists: uuid `10b1c3af-b372-4bff-98e3-3e4bbc138640`, password in
  Doppler `AIOSTREAMS_UI_PASSWORD`.
- Its manifest endpoint returns **200**, but `resources: []` and `types: []`
  because **no addons are selected yet**.

### To finish (UI, a few clicks)
1. Open AIOStreams, log in with the uuid + `AIOSTREAMS_UI_PASSWORD`.
2. Add public-tracker addons (Torrentio and similar). **Leave every debrid
   service empty.**
3. Copy the generated manifest URL and set it on Remux's AIOStreams addon,
   rewriting the host to `aiostreams.remux.svc.cluster.local:3000`.

### The constraint that decides whether playback can work at all
**Remux has no path to BitTorrent peers.** Its only egress is the gateway's
**HTTP** proxy on 8888, which cannot carry peer or DHT traffic. The gateway's
8388 is **Shadowsocks — an encrypted protocol, not plain SOCKS5** — and a
SOCKS5 client cannot speak it: verified, `curl --socks5-hostname` to 8388 times
out from **both** remux *and* qBittorrent.

That last point deserves attention on its own: `apps/downloads/qbittorrent.yaml`
configures `[Proxy] Type=5 Port=8388` with **no credentials**, against a
Shadowsocks server that has `SHADOWSOCKS_PASSWORD` set. That configuration is
very likely inert, meaning qBittorrent's peer and tracker connections are not
using it. The killswitch still holds (a direct request from the pod returns
nothing), so this is not a leak — but it is worth confirming what path its peer
traffic actually takes.

So, without a debrid provider, torrent streaming in Remux needs **real peer
connectivity**, which means a gluetun sidecar giving it its own tunnel — the
arrangement qBittorrent used to have. Cost: ~100 MB on a node at ~90 % memory
and a second AirVPN session. Debrid would work over the existing HTTP proxy
because those are plain HTTPS links, but that is explicitly not wanted.

## Stream filtering — keep the hard-to-play releases from being offered

Set 2026-09-04 on the AIOStreams config (uuid `10b1c3af-…`). This is the
equivalent of Torrentio's quality checkboxes, and it is **cluster state, not
git** — re-apply it if the AIOStreams database is ever reset.

The governing principle: **this server can only direct-play.**
`EnableVideoTranscoding=False` and `HardwareAccelerationType=none`, so a stream
the client cannot direct-play does not fall back to a transcode — it fails.
Filtering at the source means the client is never offered one.

| Field | Excluded | Why |
|---|---|---|
| `excludedResolutions` | `2160p`, `1440p` | 4K is almost always HEVC, and unplayable here for both reasons at once |
| `excludedQualities` | `BluRay REMUX`, `DVD REMUX`, `CAM`, `TS`, `TC`, `SCR` | REMUX is an untouched disc rip at 30–100 Mbps; the rest are junk tiers |
| `excludedEncodes` | `HEVC`, `AV1` | The codecs that force a transcode on most clients |
| `excludedVisualTags` | `HDR+DV`, `DV Only`, `HDR Only`, `HDR10+`, `HDR10`, `DV`, `HDR`, `HLG`, `3D`, `H-OU`, `H-SBS` | HDR/DV need tone-mapping, which *is* a transcode; on an SDR client they otherwise play washed-out. 3D half-OU/SBS is unplayable on a normal display |

**Plain `BluRay` is deliberately kept.** A 1080p BluRay encode is ~8–15 Mbps,
direct-plays fine, and excluding it would remove most good 1080p releases —
REMUX is the heavy one, not BluRay as such. Also kept: `AVC` (the one video
codec essentially everything direct-plays), `SDR`, `10bit`, `IMAX`.

What remains on offer is the universally direct-playable combination: **1080p
and below, AVC, SDR, WEB-DL/WEBRip/BluRay**.

`maxSize` also exists as a backstop if a size ceiling is ever wanted; it is not
set, because a cap tight enough to matter would also cut legitimate long films.

`excludedRegexPatterns` exists but is refused for this user — regex filters need
a permission this account does not have.
