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

## The AIOStreams manifest URL (paste into Gelato in step 9)

```
http://localhost:3000/stremio/883deab4-c172-44fe-80f5-33c0c7042e9b/eyJpIjoiYVY5NEo5ZnhBdzZBbHRlTHQ5R3RuZz09IiwiZSI6Ikk5NTlQSSs4S1NYa0pkYzdRV083enJqVnpqZklOTUlWSW5pOVJzUzdMcnRKak5vZXRZdVNUd1lhZEpwb3FkNWsiLCJ0IjoiYSJ9/manifest.json
```

Not a secret in the Doppler sense: the trailing blob is ciphertext under the
server-side `SECRET_KEY` (Doppler `AIOSTREAMS_SECRET_KEY`), and the URL only
resolves inside the pod's own network namespace — AIOStreams is deliberately
not exposed through Traefik. Anyone who can reach it already controls the
cluster. To edit the AIOStreams config later:

```
kubectl port-forward -n jellyfin pod/$(kubectl get pod -n jellyfin -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}') 3000:3000
# open http://localhost:3000/stremio/<uuid>/<blob>/configure  (same URL, /configure at the end)
```

If a debrid service is ever wanted, enable it under Services in that page
(credentials go there, never in git), then re-save and update the URL in
Gelato's settings. Restart Jellyfin after changing the AIOStreams config
(Gelato caches the manifest).

## Browser click-list (owner-only steps)

### 1. Sign into Jellyfin and lock down the admin account

1. Open `https://jellyfin.sandstorm.chat`.
2. Sign in as the existing admin (`akadmin`).
3. Dashboard (hamburger menu → Dashboard) → **Users** → click `akadmin`.
4. Scroll to **Features** / playback permissions and UNTICK:
   - "Allow audio playback that requires transcoding"
   - "Allow video playback that requires transcoding"
   - "Allow playback that requires remuxing"
5. Click **Save**. Repeat for every user you create later — this is per-user,
   there is no global switch. With these off, a client that cannot Direct Play
   gets an error instead of silently melting the CPU-only node.
6. Dashboard → **Playback** (Transcoding section): confirm "Hardware
   acceleration" is **None** (it already is; this is the visual check).

### 2. Install the plugins

7. Dashboard → **Plugins** → **Repositories** → **Add**:
   - Repository Name: `Gelato`
   - Repository URL: `https://raw.githubusercontent.com/lostb1t/Gelato/refs/heads/gh-pages/repository.json`
   - Save.
8. Dashboard → **Plugins** → **Catalog**:
   - Install **Gelato** (from the new repo; needs Jellyfin 10.11+ — this
     server is 10.11.11).
   - Install **SSO Auth** (in the default Jellyfin catalog; the plugin package
     name is "SSO-Auth", listed as SSO).
9. When both show "Installed", Dashboard → **Restart** (Plugins → the Restart
   button, or restart the pod: `kubectl -n jellyfin delete pod -l app.kubernetes.io/name=jellyfin`).
   Jellyfin will be back in ~1 minute.

### 3. Configure SSO (Sign in with Authentik)

10. Dashboard → **Plugins** → **SSO Auth** → **Add OpenID Provider**.
11. Fill EXACTLY (the provider name is part of the callback URL and must be
    lowercase `authentik` to match the redirect URIs registered in Authentik):
    - OID Provider Name: `authentik`
    - OID Endpoint: `https://authentik.sandstorm.chat/application/o/jellyfin/.well-known/openid-configuration`
    - OID Client ID: `BYD5PS0JqZY7KBeUEBIeZhkcnBOwZKkFt7QTu5TD`
    - OID Secret: run this and paste the output:
      `kubectl -n jellyfin get secret jellyfin-oidc -o jsonpath='{.data.client-secret}' | base64 -d`
    - OID Scope: `openid profile email`
    - Enabled: **yes**
    - Enable Authorization Code Flow: **yes** (leave PKCE off — this is a
      confidential client)
    - Enable All Folders: **yes** (admin account; tighten per-user later)
12. Save. Log out. The login page now shows an **SSO** button — sign in with
    Authentik. First login links to the Jellyfin account with the same verified
    email (or creates one). Native mobile/TV clients keep using
    username/password against Jellyfin itself; SSO is a browser convenience
    layer, which is why there is no forward-auth on the Ingress.

### 4. Configure Gelato

13. Dashboard → **Plugins** → **Gelato**:
    - AIOStreams URL (manifest or base): paste the manifest URL from the
      section above.
    - Movies path: `/config/gelato/movies`
    - Series path: `/config/gelato/series`
      (Gelato creates these folders itself; `/config` is the writable config
      PVC. The media library mount `/data/media` is read-only on purpose.)
    - Save.
14. Dashboard → **Library** → add the two paths above to your movie/series
    libraries (or create new libraries for them), then **Scan Library**.
15. Dashboard → **Scheduled Tasks**: run **Scan Library**; Gelato's catalog
    import task can populate the library from the TMDB catalogs. For shows,
    Library settings → metadata downloaders: enable the "Gelato missing
    season/episode fetcher" and drag it to the top.
16. Search for a movie (Gelato replaces Jellyfin search with Stremio results)
    and start playback. If something is borked: Scheduled Tasks → the Gelato
    purge task, then re-scan.

### 5. Verify

- Play something: Dashboard → **Activity** → the playing session shows
  **Direct** (not Transcoding) as the play method.
- `kubectl -n jellyfin logs deploy/jellyfin -c jellyfin --tail=50` shows no
  ffmpeg transcode spawns during playback.
- Tracker/egress check while streaming: the stream bytes leave through the
  tunnel — `kubectl -n jellyfin exec deploy/jellyfin -c jellyfin -- curl -4 -s
  https://ip4.me/api/` still returns an AirVPN IP, never `74.101.53.75`.
