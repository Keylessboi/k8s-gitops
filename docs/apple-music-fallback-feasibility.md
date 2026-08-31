# Apple Music as a Streaming Fallback for Navidrome — Feasibility Report

*Research date: 2026-08-30. Read-only research; nothing was deployed or installed. Every external claim carries a source link. Cluster facts are from this repo (`apps/`, `docs/`).*

## The question

> "Can you stream Apple Music when Navidrome doesn't already have a song in the catalog?"

## Verdict up front

**No — Apple Music cannot be a streaming fallback for Navidrome, legally or technically.** Apple Music's full-track audio is FairPlay-encrypted, its public APIs expose only metadata + 30-second previews + opaque playback parameters, and both DMCA §1201 and Apple's own terms close the circumvention route. The one legitimate Apple Music pattern (MusicKit JS in a browser, with the listener's own subscription) cannot feed a Subsonic server.

The good news: this cluster already deploys the tool that does exactly "stream/browse a missing song from an external catalog through Subsonic" — **Octo-Fiesta** (`apps/music/octo-fiesta.yaml`) — and Apple Music is the one major service it *cannot* support, for exactly the reasons above ([maintainer, issue #80](https://github.com/V1ck3s/octo-fiesta/issues/80)). The recommended path is therefore **on-demand acquisition through the existing Lidarr stack** (build the library), with **Octo-Fiesta + one paid streaming provider** as the "hear it now" option, and a **MusicKit JS companion page** as the only legitimate way to touch Apple's catalog.

---

## 1. The hard technical reality of Apple Music

### 1.1 What Apple's public APIs actually provide

- The Apple Music API is a **metadata** API: "Use Apple Music API to access information about media in the Apple Music Catalog and a user's personal iCloud Music Library" — albums, songs, artists, playlists, ratings, charts, search. No audio-stream endpoints are documented. ([API overview](https://developer.apple.com/documentation/applemusicapi))
- The catalog-song response contains `previews` (a URL to a short preview `.m4a`) and opaque `playParams` — **no full-track stream URL exists in the API**. ([Get a Catalog Song](https://developer.apple.com/documentation/applemusicapi/get-a-catalog-song))
- Previews are 30-second clips per Apple's own documentation of its preview assets. ([iTunes Search API, `previewUrl`](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html))
- Playback happens only inside Apple's player components (MusicKit native players, MusicKit JS in a browser), gated on the **end user's** Apple ID + Apple Music subscription. ([MusicKit overview](https://developer.apple.com/musickit/), [User Authentication for MusicKit](https://developer.apple.com/documentation/applemusicapi/user-authentication-for-musickit))

### 1.2 FairPlay DRM

- Apple Music streams are protected by FairPlay: content encrypted with AES-128 keys, "the key handling and the content decryption occur on the kernel of the iOS device," delivered over HLS. ([FairPlay Streaming Overview PDF](https://developer.apple.com/streaming/fps/FairPlayStreamingOverview.pdf))
- FairPlay credentials are issued only to parties "provid[ing] a streaming service to consumers"; "requests for third-party accounts acting on behalf of content owners or licensees won't be approved." A homelab server can never get them. ([FPS program page](https://developer.apple.com/streaming/fps/))
- Apple's consumer terms confirm the content is DRM-protected ("DRM-protected Content can be used on up to five (5) computers…") and limit streaming to one device at a time on an individual membership. ([Apple Media Services Terms](https://www.apple.com/legal/internet-services/itunes/))

### 1.3 The legal wall

- **DMCA §1201**: "No person shall circumvent a technological measure that effectively controls access to a work"; trafficking in circumvention technology is separately prohibited; "circumvent" explicitly includes "to decrypt an encrypted work… without the authority of the copyright owner." ([17 U.S.C. §1201](https://www.copyright.gov/title17/92chap12.html), [Cornell LII](https://www.law.cornell.edu/uscode/text/17/1201))
- **No exemption applies to music.** The current triennial rule, 37 CFR §201.40 (last amended 2024-10-28), enumerates 22 exemption classes (motion pictures, literary works/TDM, device unlocking/jailbreaking, repair, security research, game preservation, …). Class (b)(6) — accessibility for works "fixed in the form of text or notation" — **explicitly excludes sound recordings**. None covers streaming-music DRM. ([eCFR 201.40](https://www.ecfr.gov/current/title-37/chapter-II/subchapter-A/part-201/section-201.40), [copyright.gov/1201](https://www.copyright.gov/1201/))
- **Apple Media Services Terms** (governs the subscription): "You may not use any software, device, automated process… to scrape, copy… any portion of the Content or Services"; "You may not tamper with or circumvent any security technology included with the Services or Content"; "You may access our Services only using Apple's software." ([terms](https://www.apple.com/legal/internet-services/itunes/))
- **Apple Developer Program License Agreement**, Schedule 1 §D "MusicKit": "You may not, and You may not permit Your end users to, download, upload, or modify any MusicKit Content"; "You may play MusicKit Content only as rendered by the MusicKit APIs or MusicKit JS"; MusicKit may be used only "for purposes unrelated to facilitating access to Your end users' Apple Music subscriptions" — negated. ([DPLA PDF](https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-English.pdf))

### 1.4 The tooling landscape (documented, not recommended)

| Project | What it technically is | DRM circumvention? | State (2026-08) | Subsonic fallback potential |
|---|---|---|---|---|
| [zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader) | CLI batch downloader; requires a running decryption daemon + subscription `media-user-token` | **Yes** | Active (push 2026-08-21; issue tracker disabled) | None — writes files, no streaming |
| [WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper) | Runs the Apple Music **Android app** in a privileged container and hooks its FairPlay library (`libCoreLSKD`) to extract per-track content keys | **Yes — the core violation** | Very active (push 2026-08-30) | None — key daemon |
| [WorldObservationLog/AppleMusicDecrypt](https://github.com/WorldObservationLog/AppleMusicDecrypt) | Python ripper; v2 can rip via public "wrapper-manager" instances **without any Apple account** | **Yes** | Active (push 2026-07-05) | None — batch CLI |
| [glomatico/gamdl](https://github.com/glomatico/gamdl) | Python downloader; web-player cookies for AAC, wrapper delegation for ALAC | Yes (for lossless) | Active (push 2026-08-03) | None — batch CLI |
| [am-dl](https://am-dl.pages.dev/) | Closed hosted web ripper (AAC/ALAC/Atmos output implies a DRM break; internals undocumented) | Almost certainly | Site live; unverifiable | None — web batch UI |
| [Musish](https://github.com/Musish/Musish) / [Sidra](https://github.com/wimpysworld/sidra) / [applemusic-tui](https://github.com/k1y0miiii/applemusic-tui) | Players wrapping MusicKit JS / music.apple.com with DRM intact ("No DRM hacks") | No | Musish stale (2025-03); Sidra/tui active | None — players, cannot export audio |
| [Lucida](https://lucida.to/) (already in this cluster via Tubifarry) | Multi-service downloader: **Qobuz, Tidal, SoundCloud, Deezer, Amazon Music, Yandex Music — no Apple Music** | n/a for Apple | Flaky availability (522/403 on fetch) | No Apple Music source at all |

Apple actively files GitHub DMCAs (its [2025-11-05 notice](https://github.com/github/dmca/blob/master/2025/11/2025-11-05-apple.md) disabled an 8,270-repo network of App Store scrapers); no takedown was found against the specific repos above, but the exposure is structural.

**Why this is off the table:** every tool that produces an Apple Music file does so by defeating FairPlay — §1201(a)/(b) liability plus direct violation of Apple's terms, with no exemption. They are also batch downloaders, not streamers, so they wouldn't even provide the "fallback streaming" behavior asked for. Not deployed, not recommended, documented for completeness.

---

## 2. Navidrome's extension model

**Premise correction first:** the task assumed Navidrome has no plugin system. That was true through the 0.55–0.58 era, but **Navidrome shipped a plugin system in mid-2026** (v0.61/0.62 line; docs last updated 2026-07-08; current stable v0.63.2). ([plugins docs](https://www.navidrome.org/docs/usage/features/plugins/))

However, it does not change the answer:

- Plugin capabilities are: **Metadata Agent, Scrobbler, Lifecycle, Scheduler Callback, WebSocket Callback** (plus lyrics, sonic-similarity, task-worker in code). There is **no media-source / streaming capability** — a plugin cannot serve or proxy audio for a missing track. ([capability list in source](https://github.com/navidrome/navidrome/tree/master/plugins/capabilities); open PRs [#5045 HTTP endpoint](https://github.com/navidrome/navidrome/pull/5045) and [#5148 PlaylistProvider](https://github.com/navidrome/navidrome/pull/5148) still don't add one)
- **This cluster runs `deluan/navidrome:0.58.0`** (`apps/navidrome/deployment.yaml`), which predates the plugin system entirely.
- A search miss is a silent empty result with no hooks: `Search3` queries only the local database and returns empty slices — no external calls, no events. ([`server/subsonic/searching.go`](https://github.com/navidrome/navidrome/blob/a2de8e61efe82ec1d81d67d985026c083ad541fd/server/subsonic/searching.go#L132-L152))
- "External integrations" in Navidrome means metadata agents (bios, images, similar artists) only. ([docs](https://www.navidrome.org/docs/usage/integration/external-services/))
- The published roadmap is "New UI" and "Plugins" — nothing about external media sources. ([overview](https://www.navidrome.org/docs/overview/))

**Conclusion:** Navidrome will never itself proxy a missing track. Any fallback must live *outside* Navidrome — in front of it (proxy), beside it (companion app), or behind it (fill the library).

---

## 3. The legitimate alternatives for THIS cluster

### 3a. On-demand acquisition via the existing Lidarr stack — **recommended**

**Lidarr API reality (premise correction):** the task suggested `/api/v1/search` supports track-level queries. **It does not.** The search controller maps only `Artist` and `Album` results and throws `NotImplementedException` for anything else; there is no track-search command; `AlbumSearch` takes `albumIds` only. ([SearchController.cs](https://github.com/Lidarr/Lidarr/blob/350860e524029b7fb4165ed14fbcabb11217ada2/src/Lidarr.Api.V1/Search/SearchController.cs#L26-L73), [AlbumSearchCommand.cs](https://github.com/Lidarr/Lidarr/blob/350860e524029b7fb4165ed14fbcabb11217ada2/src/NzbDrone.Core/IndexerSearch/AlbumSearchCommand.cs#L6-L19)) Single-track requests are explicitly **NOT_PLANNED** ([#5658](https://github.com/Lidarr/Lidarr/issues/5658), closed Dec 2025); "Song Mode" has been open since 2022 ([#3047](https://github.com/Lidarr/Lidarr/issues/3047)). Interactive per-release search/grab exists (`GET/POST /api/v1/release`) but is album-scoped. ([ReleaseController.cs](https://github.com/Lidarr/Lidarr/blob/350860e524029b7fb4165ed14fbcabb11217ada2/src/Lidarr.Api.V1/Indexers/ReleaseController.cs#L141-L146)) Lidarr itself is healthy again: v3.1.4.5029, 2026-08-23 ([release](https://github.com/Lidarr/Lidarr/releases/tag/v3.1.4.5029)); the 2025 stall was the hosted metadata server, fixed by the community [blampe/hearring-aid](https://github.com/blampe/hearring-aid) alternative; a fork exists ([Melodarr](https://github.com/melodarr/melodarr)).

**So the unit of acquisition is the album, not the track.** A missing *song* resolves to: look up the track on MusicBrainz → find its release/album → ensure the artist/album is monitored in Lidarr → `AlbumSearch` → Tubifarry's slskd/Lucida/DAB/YouTube sources grab it → Lidarr imports → Navidrome's watcher picks it up.

**Existing bridge tooling (the pattern exists, nothing polished):**

| Project | Pattern | Note |
|---|---|---|
| [Soularr](https://github.com/mrusse/soularr) (964★) | Polls Lidarr "wanted" → downloads via slskd → tells Lidarr to import | Album-level, poll-based |
| [Lidify](https://github.com/fjordnode/lidify) | Overseerr-style request UI over Lidarr + Subsonic playback | Album-level |
| [naviseerr](https://github.com/Schaka/naviseerr) | "Seerr + Navidrome + Lidarr + Soulseek"; roadmap is exactly this pattern | Pre-1.0, self-admittedly not usable yet |
| [DroppedNeedle](https://github.com/DroppedNeedle/DroppedNeedle/releases/tag/v2.0.0) | v2.0 (2026-07) **dropped Lidarr** for native slskd per-album **or per-track** downloads | The ecosystem's answer to track-level: bypass Lidarr |
| [navidrome-lidarr-bridge](https://github.com/danielbanariba/navidrome-lidarr-bridge) | Star in Navidrome → Lidarr monitors | Artist-level, tiny |

**Latency reality:** Soulseek transfers are peer-limited and highly variable (same file measured ~150 KB/s vs ~3 MB/s depending on buffering — [Soulseek.NET #428](https://github.com/jpdillingham/Soulseek.NET/issues/428)); peers serve one file at a time ([slskd #1317](https://github.com/slskd/slskd/discussions/1317)). A 3–5 min track is ~7–12 MB (320 kbps) or ~25–45 MB (FLAC). Navidrome's folder watcher scans ~5 s after a change ([Scanner.WatcherWait](https://www.navidrome.org/docs/usage/configuration/options/)). Realistic end-to-end: **~1–15 minutes in good conditions, unbounded when the peer queue is busy** — asynchronous by nature, not "instant streaming."

**Fit with this cluster:** excellent. The repo already contains the exact pattern to copy: `apps/lidarr/mass-search-job.yaml` drives `POST /api/v1/command {"name":"AlbumSearch"}` from Python with pacing, retries, and a persisted cursor, and the `lidarr-api` secret already exists. Tubifarry already provides slskd + Lucida + DAB + YouTube as sources. A bridge is one small Python service/CronJob: poll a request queue (or expose a tiny endpoint) → MusicBrainz track lookup → Lidarr add + AlbumSearch → done; Navidrome auto-scans.

**Verdict: feasible, medium effort (~1–2 days), album-granularity caveat, fully consistent with how this cluster already builds its library.** The track ends up *owned* in `/data/media/music` — which matches the owner's Lidarr/Soulseek catalog-building ethos.

### 3b. Apple Music web embed (MusicKit JS) — legitimate, but a separate surface

- Embedding MusicKit JS requires a developer token: an ES256 JWT signed with a MusicKit private key that only exists in Certificates, Identifiers & Profiles — **paid Apple Developer Program only, USD 99/year**. ([Generating Developer Tokens](https://developer.apple.com/documentation/applemusicapi/generating-developer-tokens), [media identifier help](https://developer.apple.com/help/account/capabilities/create-a-media-identifier-and-private-key/), [account feature table](https://developer.apple.com/help/account/basics/about-your-developer-account), [enrollment fee](https://developer.apple.com/support/enrollment/)) There is no free path.
- Full-track playback requires **each listener** to sign in with an Apple ID holding an Apple Music subscription; otherwise only 30-second previews play. ([MusicKit JS user authorization](https://js-cdn.music.apple.com/musickit/v3/docs/index.html?path=/story/user-authorization--page))
- Zero-code variant: Apple's [Marketing Tools iframe embed](https://artists.apple.com/support/1117-apple-music-marketing-tools) per song — 30-second clip for anonymous visitors, full tracks once the listener signs in inside the iframe.
- UX: a "listen on Apple Music" button per missing track on a companion web page is realistic. It is **browser-only** — it cannot play inside Symfonium/Navidrome clients, autoplay requires a user gesture, and the audio never touches the server (which is precisely why it's legal).
- **Decision point:** does the owner have (a) an Apple Music subscription and (b) willingness to pay $99/yr for a developer account? Without both, this path is dead.

**Verdict: feasible as a companion page, low-medium effort, fully legitimate — but it is not Navidrome and not Subsonic.** Only worth it if Apple's catalog specifically matters.

### 3c. Funkwhale federation — not a fallback source in practice

- The mechanism is real: follow remote instances/libraries, federated search via pasting remote object URLs, auto-follow settings. ([federation settings docs](https://docs.funkwhale.audio/administrator/configuration/federation-settings.html), [developer federation docs](https://docs.funkwhale.audio/developer/federation/index.html))
- **But Funkwhale 2.0 (2026-03-20) removed libraries as the sharing unit** (replaced by playlists + playlist federation) and **v2 pods do not federate with v1 pods** — any integration written against the old library-follow model is throwaway. ([Funkwhale blog](https://blog.funkwhale.audio/2025-funkwhale-2-news.html), [changelog](https://docs.funkwhale.audio/changelog.html))
- The network is tiny: the official pod directory lists **~30 pods**, mostly with double- or triple-digit account counts, visibly skewed to Creative Commons/free music ("Musica e Podcast Creative Commons", "BuzzWorkers - Experimental Electronic Music", "Balfolk"). ([funkwhale.audio/join](https://www.funkwhale.audio/join)) Third-party review: federation "doesn't activate at small scale," Subsonic compatibility "inconsistent or untested." ([unsubbed.co](https://unsubbed.co/tools/funkwhale-2/))

**Verdict: not viable as a "stream anything missing" layer.** Mainstream-catalog coverage is effectively zero. Deploy Funkwhale (C1) for free-culture discovery if desired — not for backfill.

### 3d. The Remux media server's music pipeline (Jellyfin + Gelato + AIOStreams) — dead end for music

- The stack's remote-source machinery is Gelato pulling **Stremio** addon content. Stremio's addon protocol defines content types `movie`, `series`, `channel`, `tv` — **there is no music type**. ([Stremio addon SDK content types](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/content.types.md))
- Gelato's code is video-shaped end to end: `StremioMediaType` has no music member; item creation handles Series/Movie/Episode and logs "unsupported type" for everything else; stream sync requires a `Video` item; config exposes only `MovieFolder` and `SeriesFolder`. ([enum](https://github.com/lostb1t/Gelato/blob/db72b969cd2d9d3d62630e794eb53a4f529dff43/GelatoStremioProvider.cs#L896-L906), [IntoBaseItem](https://github.com/lostb1t/Gelato/blob/db72b969cd2d9d3d62630e794eb53a4f529dff43/GelatoManager.cs#L1367-L1383), [config](https://github.com/lostb1t/Gelato/blob/db72b969cd2d9d3d62630e794eb53a4f529dff43/Config/PluginConfiguration.cs#L53-L57)) Its README requires AIOStreams + TMDB — film/TV infrastructure. Community "music addons" exist only as hacks that type music catalogs as `movie`.
- This cluster's Jellyfin `Music` library is the local `/data/media/music` mount only ([docs/jellyfin-gelato.md](jellyfin-gelato.md)); the AIOStreams manifest is movie+series.

**Verdict: cannot serve as the "stream anything" layer for music.** No code path from a Stremio music-ish addon to a Jellyfin `Audio` item exists.

---

## 4. Recommendation

Ordered by legitimacy, integration fit, then effort:

**1. On-demand acquisition bridge over the existing Lidarr stack (primary).**
A small Python service/CronJob in the `lidarr` namespace, modeled on `apps/lidarr/mass-search-job.yaml`: accept a track request (artist + title, or MusicBrainz ID) → resolve track → release via MusicBrainz → add/monitor in Lidarr → `POST /api/v1/command {"name":"AlbumSearch"}` → Tubifarry (slskd/Lucida/DAB/YouTube) acquires → Lidarr imports → Navidrome's 5-second watcher makes it playable. Effort: **~1–2 days**. Caveats: album-granularity (Lidarr will grab the release containing the track — usually desirable for a library builder), MusicBrainz coverage limits for obscure material, latency ~1–15 min (asynchronous). Outcome: the song is *owned*, tagged by Beets, shared back out via slskd — the same ethos as the rest of the stack. If per-track (not per-album) acquisition ever becomes a hard requirement, the ecosystem's answer is [DroppedNeedle](https://github.com/DroppedNeedle/DroppedNeedle/releases/tag/v2.0.0)-style native slskd downloads that bypass Lidarr — new infrastructure, not recommended first.

**2. Octo-Fiesta + one paid streaming provider (the "hear it now" option).**
Already deployed in `apps/music/octo-fiesta.yaml` (PLAN-GAPS C6). Point a Subsonic client at Octo-Fiesta instead of Navidrome and it merges the local library with Deezer/Qobuz/Tidal/Yandex catalogs; missing tracks are fetched on demand and cached into the library. Requires paid credentials for the provider (free accounts get search but nothing to stream) and is a personal-use ToS gray zone — keep it behind Authentik as it is. Effort: **hours** (config only) plus the subscription. Note it is download-and-cache, not live proxying: first play has acquisition latency. Apple Music is excluded by design — its maintainer calls the missing streamable API a blocker ([issue #80](https://github.com/V1ck3s/octo-fiesta/issues/80)). Also fix the drift-audit item: pin the image to `v0.10` instead of `:latest`.

**3. MusicKit JS companion page (only if Apple's catalog specifically matters).**
A single web page listing search-miss results with per-track Apple Music embeds (Marketing Tools iframes need zero MusicKit code; a MusicKit JS page needs the $99/yr developer account). Full playback requires each listener's own Apple Music subscription; browser-only. Effort: **low–medium** + $99/yr + subscription. This is the *only* legitimate way to hear Apple Music in this stack, and it will never be inside Symfonium.

**Not recommended / off the table:**
- **Any Apple Music downloader/ripper** (zhaarey, wrapper, AppleMusicDecrypt, gamdl, am-dl): FairPlay circumvention — §1201 exposure, Apple ToS violation, no exemption exists, and they don't stream anyway. Documented in §1.4; do not deploy.
- **Funkwhale as a fallback source**: network too small and CC-skewed; 2.0 broke the federation model you'd build against.
- **Gelato/Stremio for music**: protocol and plugin have no music concept.

**Direct answer to the owner:** Apple Music itself — no. The closest legitimate equivalents are: keep requesting through Lidarr and own the track in ~minutes (recommended), or add a Deezer/Qobuz/Tidal subscription behind the already-deployed Octo-Fiesta proxy for a unified local+streaming catalog, or use Apple's own web player/embed with your Apple Music subscription in a browser tab.

---

## Source index

**Apple:** [Apple Music API](https://developer.apple.com/documentation/applemusicapi) · [Get a Catalog Song](https://developer.apple.com/documentation/applemusicapi/get-a-catalog-song) · [iTunes Search API previews](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html) · [MusicKit](https://developer.apple.com/musickit/) · [MusicKit JS user authorization](https://js-cdn.music.apple.com/musickit/v3/docs/index.html?path=/story/user-authorization--page) · [Developer tokens](https://developer.apple.com/documentation/applemusicapi/generating-developer-tokens) · [User authentication](https://developer.apple.com/documentation/applemusicapi/user-authentication-for-musickit) · [FPS program](https://developer.apple.com/streaming/fps/) · [FPS overview PDF](https://developer.apple.com/streaming/fps/FairPlayStreamingOverview.pdf) · [Media identifier/key](https://developer.apple.com/help/account/capabilities/create-a-media-identifier-and-private-key/) · [Account feature table](https://developer.apple.com/help/account/basics/about-your-developer-account) · [Enrollment fee](https://developer.apple.com/support/enrollment/) · [Apple Media Services Terms](https://www.apple.com/legal/internet-services/itunes/) · [DPLA (Schedule 1 §D)](https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-English.pdf) · [Marketing Tools embeds](https://artists.apple.com/support/1117-apple-music-marketing-tools)

**Law:** [17 U.S.C. §1201](https://www.copyright.gov/title17/92chap12.html) · [37 CFR 201.40](https://www.ecfr.gov/current/title-37/chapter-II/subchapter-A/part-201/section-201.40) · [copyright.gov/1201](https://www.copyright.gov/1201/)

**Navidrome:** [overview/roadmap](https://www.navidrome.org/docs/overview/) · [plugins](https://www.navidrome.org/docs/usage/features/plugins/) · [external services](https://www.navidrome.org/docs/usage/integration/external-services/) · [searching.go](https://github.com/navidrome/navidrome/blob/a2de8e61efe82ec1d81d67d985026c083ad541fd/server/subsonic/searching.go#L132-L152) · [plugin capabilities](https://github.com/navidrome/navidrome/tree/master/plugins/capabilities) · [Scanner options](https://www.navidrome.org/docs/usage/configuration/options/)

**Lidarr:** [SearchController.cs](https://github.com/Lidarr/Lidarr/blob/350860e524029b7fb4165ed14fbcabb11217ada2/src/Lidarr.Api.V1/Search/SearchController.cs#L26-L73) · [AlbumSearchCommand.cs](https://github.com/Lidarr/Lidarr/blob/350860e524029b7fb4165ed14fbcabb11217ada2/src/NzbDrone.Core/IndexerSearch/AlbumSearchCommand.cs#L6-L19) · [ReleaseController.cs](https://github.com/Lidarr/Lidarr/blob/350860e524029b7fb4165ed14fbcabb11217ada2/src/Lidarr.Api.V1/Indexers/ReleaseController.cs#L141-L146) · [#5658 NOT_PLANNED](https://github.com/Lidarr/Lidarr/issues/5658) · [#3047 Song Mode](https://github.com/Lidarr/Lidarr/issues/3047) · [v3.1.4.5029](https://github.com/Lidarr/Lidarr/releases/tag/v3.1.4.5029) · [FAQ](https://wiki.servarr.com/lidarr/faq) · [plugins](https://wiki.servarr.com/lidarr/plugins)

**Bridges/sources:** [Soularr](https://github.com/mrusse/soularr) · [Lidify](https://github.com/fjordnode/lidify) · [naviseerr](https://github.com/Schaka/naviseerr) · [DroppedNeedle v2](https://github.com/DroppedNeedle/DroppedNeedle/releases/tag/v2.0.0) · [navidrome-lidarr-bridge](https://github.com/danielbanariba/navidrome-lidarr-bridge) · [Tubifarry](https://github.com/TypNull/Tubifarry) · [hearring-aid](https://github.com/blampe/hearring-aid) · [Melodarr](https://github.com/melodarr/melodarr) · [Soulseek.NET #428](https://github.com/jpdillingham/Soulseek.NET/issues/428) · [slskd #1317](https://github.com/slskd/slskd/discussions/1317)

**Octo-Fiesta:** [repo](https://github.com/V1ck3s/octo-fiesta) · [providers wiki](https://github.com/V1ck3s/octo-fiesta/wiki/Supported-Music-Providers) · [API wiki](https://github.com/V1ck3s/octo-fiesta/wiki/API-Endpoints) · [issue #80 (Apple Music)](https://github.com/V1ck3s/octo-fiesta/issues/80) · [releases](https://github.com/V1ck3s/octo-fiesta/releases)

**Funkwhale:** [federation settings](https://docs.funkwhale.audio/administrator/configuration/federation-settings.html) · [federation dev docs](https://docs.funkwhale.audio/developer/federation/index.html) · [2.0 blog](https://blog.funkwhale.audio/2025-funkwhale-2-news.html) · [changelog](https://docs.funkwhale.audio/changelog.html) · [pod directory](https://www.funkwhale.audio/join) · [unsubbed.co review](https://unsubbed.co/tools/funkwhale-2/)

**Gelato/Stremio:** [Gelato](https://github.com/lostb1t/Gelato) · [StremioMediaType enum](https://github.com/lostb1t/Gelato/blob/db72b969cd2d9d3d62630e794eb53a4f529dff43/GelatoStremioProvider.cs#L896-L906) · [IntoBaseItem](https://github.com/lostb1t/Gelato/blob/db72b969cd2d9d3d62630e794eb53a4f529dff43/GelatoManager.cs#L1367-L1383) · [plugin config](https://github.com/lostb1t/Gelato/blob/db72b969cd2d9d3d62630e794eb53a4f529dff43/Config/PluginConfiguration.cs#L53-L57) · [Stremio content types](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/content.types.md) · [setup discussion](https://github.com/lostb1t/Gelato/discussions/40)

**Ripper landscape:** [zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader) · [wrapper](https://github.com/WorldObservationLog/wrapper) · [AppleMusicDecrypt](https://github.com/WorldObservationLog/AppleMusicDecrypt) · [gamdl](https://github.com/glomatico/gamdl) · [am-dl](https://am-dl.pages.dev/) · [Musish](https://github.com/Musish/Musish) · [Sidra](https://github.com/wimpysworld/sidra) · [applemusic-tui](https://github.com/k1y0miiii/applemusic-tui) · [Lucida](https://lucida.to/) · [Apple DMCA 2025-11-05](https://github.com/github/dmca/blob/master/2025/11/2025-11-05-apple.md)
