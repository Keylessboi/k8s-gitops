# Jellyfin + Gelato + AIOStreams — server-side state and the browser click-list

The stack: Jellyfin (local library, Direct Play only) + the Gelato plugin (pulls
Stremio/torrentio content through Jellyfin itself) + self-hosted AIOStreams, all
three containers in one pod whose only internet path is the gluetun/AirVPN
tunnel. See `apps/jellyfin/deployment.yaml` for the why-comments.

## Already done server-side (no browser needed)

- **Tunnel + killswitch proven** (2026-08-29): Jellyfin container egress IP was
  the AirVPN exit (109.248.148.247), never the home WAN (74.101.53.75); with
  `tun0` down inside gluetun, public egress from Jellyfin timed out (raw IP) and
  DNS died (gluetun's netns-wide forwarder), while the WebUI stayed reachable
  via the Service (200 from the node network) and via
  `https://jellyfin.sandstorm.chat` (200) — management access does not depend
  on the VPN.
- **Authentik OIDC provider** "jellyfin" (application slug `jellyfin`) exists,
  created via `ak shell`. Client id/secret match the `jellyfin-oidc` Doppler
  Secret exactly. Redirect URIs are STRICT
  `https://jellyfin.sandstorm.chat/sso/OID/redirect/authentik` and
  `/sso/OID/r/authentik`; scopes `openid email profile`; sub_mode
  `hashed_user_id`; self-signed signing cert. The authorize endpoint was
  verified to accept this client (302 to the login flow, no client error).
- **AIOStreams v2.33.2** with the 1080p-only Direct-Play config already created
  (user `883deab4-c172-44fe-80f5-33c0c7042e9b`). Verified live: a movie stream
  query returned 15 results, all 1080p/720p WEB-DL or BluRay, h264/HEVC, zero
  4k/REMUX/HDR/DV/10-bit/3D/CAM/Screener results. Excluded: 2160p/1440p,
  BluRay/DVD REMUX, HDRip, HC HD-Rip, DVDRip, HDTV, CAM, TS, TC, SCR, Unknown,
  HDR/HDR10/HDR10+/HLG/DV/10bit/3D/H-OU/H-SBS/AI/Upscaled, AV1/VC-1/XviD/DivX,
  TrueHD/DTS-HD MA/DTS:X/FLAC/OPUS (lossless audio always transcodes on this
  CPU-only node). Sort: cached, then WEB-DL > WEBRip > BluRay, 1080p > 720p,
  AVC > HEVC, bigger first. The v2 image bump was required because Gelato needs
  search-capable catalogs in the manifest and v1.x hardcodes `catalogs: []`.
- **No hardware acceleration**: `encoding.xml` on the PVC has
  `HardwareAccelerationType=none` (the CPU-only default; it regenerates as none
  if the config volume is ever wiped).
- **Plugins installed server-side** (2026-08-29): `SSO-Auth 4.0.0.3` and
  `Gelato 0.26.16.0` DLLs (+ `meta.json`) placed into `/config/plugins/<Name>/`
  on the config PVC from their official releases (9p4/jellyfin-plugin-sso,
  lostb1t/Gelato gh-pages `repository.json`; both targetAbi 10.11.x, server is
  10.11.11), then the deployment was rolled. Both show in `GET /Plugins`.
  Note: plugin configs live in `/config/plugins/configurations/` (verified
  against Jellyfin 10.11 `BaseApplicationPaths.PluginConfigurationsPath`), NOT
  `/config/config/plugins/` as an earlier draft of this doc assumed.
- **SSO pre-configured against Authentik** (2026-08-29):
  `/config/plugins/configurations/SSO-Auth.xml` seeds an `authentik` OpenID
  provider — issuer `https://authentik.sandstorm.chat/application/o/jellyfin/`
  (the plugin appends `.well-known/openid-configuration` itself), client
  id/secret from the live `jellyfin-oidc` secret, scopes `openid profile
  email`, `SchemeOverride=https` (Traefik terminates TLS; without this the
  plugin builds the redirect_uri from the plain-http request), username claim
  `email`, and a pre-seeded `CanonicalLinks` entry mapping
  `travis.fiorito@tuta.com` → the `akadmin` user id, so the first Authentik
  login lands on the admin account instead of creating a new user. Verified:
  `GET /sso/OID/start/authentik` returns 302 to Authentik's `/authorize` with
  `scope=openid profile email` and an https redirect_uri; the callback
  `/sso/OID/redirect/authentik` answers 400 (not 500) without a state param.
  The 4.x plugin always uses authorization-code flow (PKCE S256 is sent;
  Authentik accepts it on confidential clients) — there is no separate
  "enable code flow" switch anymore.
- **Admin account recovered headlessly** (2026-08-29): `akadmin`'s unknown
  password was replaced using Jellyfin's own forgot-password PIN flow
  (`POST /Users/ForgotPassword` → read the PIN file it writes to
  `/config/data/` → `POST /Users/ForgotPassword/Pin`, which sets the password
  to the redeemed PIN → `POST /Users/{id}/Password` to swap it for a strong
  one). No DB surgery; `jellyfin.db.bak-20260829-182342` sits on the PVC as a
  pre-change backup anyway. The new password is in Doppler
  (`kubernetes/prd` → `JELLYFIN_AKADMIN_PASSWORD`), never in git.
- **Transcode forbidden via user policy** (2026-08-29): akadmin's policy has
  `EnableAudioPlaybackTranscoding=false`, `EnableVideoPlaybackTranscoding=false`,
  `EnablePlaybackRemuxing=false` (verified via `GET /Users/{id}` after a pod
  roll). Per-user, so repeat for any future user — or let them log in via SSO
  and tighten there.
- **Libraries created** (2026-08-29): `Music` → `/data/media/music` (real
  content, scanning), `Movies` → `/config/gelato/movies`, `Shows` →
  `/config/gelato/series` (Gelato populates these). The Shows library has the
  Gelato metadata fetcher ordered first for Series/Season/Episode. There are
  no `/data/media/movies|tv` folders yet (no video *arr stack), so the Gelato
  paths are the movie/series libraries.
- **Gelato wired to AIOStreams** (2026-08-29):
  `/config/plugins/configurations/Gelato.xml` sets `Url` to the manifest URL
  below plus `MoviePath=/config/gelato/movies`, `SeriesPath=/config/gelato/series`
  (Gelato created both folders itself). The manifest resolves in-pod: 200,
  10 search-capable catalogs, types movie+series.
- **API key for automation** (2026-08-29): Jellyfin API key
  `headless-automation` created; stored in Doppler (`kubernetes/prd` →
  `JELLYFIN_API_KEY`). Verified with `GET /System/Info` → 200.
- **Persistence proven** (2026-08-29): after a full
  `rollout restart deploy/jellyfin`, plugins, both plugin configs, libraries,
  the transcode policy, the minted password, and the API key all survived
  (PVC-backed, as intended).

## The AIOStreams manifest URL (already wired into Gelato)

```
http://localhost:3000/stremio/883deab4-c172-44fe-80f5-33c0c7042e9b/eyJpIjoiYVY5NEo5ZnhBdzZBbHRlTHQ5R3RuZz09IiwiZSI6Ikk5NTlQSSs4S1NYa0pkYzdRV083enJqVnpqZklOTUlWSW5pOVJzUzdMcnRKak5vZXRZdVNUd1lhZEpwb3FkNWsiLCJ0IjoiYSJ9/manifest.json
```

Gelato's config already points at this URL. The section stays because the URL
is what you re-paste after changing the AIOStreams config. Not a secret in the
Doppler sense: the trailing blob is ciphertext under the server-side
`SECRET_KEY` (Doppler `AIOSTREAMS_SECRET_KEY`), and the URL only resolves
inside the pod's own network namespace — AIOStreams is deliberately not
exposed through Traefik. Anyone who can reach it already controls the cluster.
To edit the AIOStreams config later:

```
kubectl port-forward -n jellyfin pod/$(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') 3000:3000
# open http://localhost:3000/stremio/<uuid>/<blob>/configure  (same URL, /configure at the end)
```

If a debrid service is ever wanted, enable it under Services in that page
(credentials go there, never in git), then re-save and update the URL in
Gelato's settings. Restart Jellyfin after changing the AIOStreams config
(Gelato caches the manifest).

## Owner click-list (shrunk 2026-08-29 — everything else is done server-side)

Everything plugin-, config-, policy-, and library-shaped is now pre-seeded on
the PVC and survives restarts. What genuinely remains needs a real browser and
a real client, which is the point of the remaining list:

### 1. The real-client OIDC login test (the one thing that cannot be faked)

1. Open `https://jellyfin.sandstorm.chat` in a browser (logged out).
2. The login page shows an **SSO** button (the SSO plugin adds it once a
   provider is configured). Click it, sign in with Authentik as
   `travis.fiorito@tuta.com`.
3. Expected: you land in Jellyfin **as `akadmin`** (the email → admin link was
   pre-seeded). If Authentik errors with an invalid-redirect message, check
   that the browser URL is exactly `jellyfin.sandstorm.chat` (the registered
   redirect URIs are strict).
4. Native mobile/TV clients keep using username/password against Jellyfin
   itself (`akadmin` + the Doppler password); SSO is a browser convenience
   layer, which is why there is no forward-auth on the Ingress.

### 2. Watch something through Gelato and confirm Direct Play

5. Search for a movie (Gelato replaces Jellyfin search with Stremio results —
   this exercises the AIOStreams manifest end-to-end) and start playback.
6. Dashboard → **Activity**: the playing session shows **Direct** (not
   Transcoding). With the transcode flags off, a client that cannot Direct
   Play gets an error instead of silently melting the CPU-only node — that is
   the intended failure mode.
7. `kubectl -n jellyfin logs deploy/jellyfin -c jellyfin --tail=50` shows no
   ffmpeg transcode spawns during playback.
8. Tracker/egress check while streaming: the stream bytes leave through the
   tunnel — `kubectl -n jellyfin exec deploy/jellyfin -c jellyfin -- curl -4 -s
   https://ip4.me/api/` still returns an AirVPN IP, never `74.101.53.75`.

### 3. Only if something is borked

- Gelato search returns nothing: restart Jellyfin after any AIOStreams config
  change (Gelato caches the manifest), or Scheduled Tasks → the Gelato purge
  task, then re-scan.
- Want a debrid service: enable it under Services in the AIOStreams configure
  page (credentials go there, never in git), re-save, update the URL in
  Gelato's settings if it changed, restart Jellyfin.
