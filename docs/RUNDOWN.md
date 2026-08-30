# Running This Cluster

Everything below is driven from this repo. ArgoCD watches `apps/*` and syncs with prune and self-heal on, so a change made with `kubectl` gets reverted on the next pass — change the file, push, and let it land.

## What's Published

All of these sit behind Traefik with a Let's Encrypt certificate, and every one of them is rate limited (50 req/s sustained, 100 burst, per source address).

| URL | What it is | Login |
|---|---|---|
| `authentik.sandstorm.chat` | SSO — the identity provider everything else defers to | `akadmin` |
| `vaultwarden.sandstorm.chat` | Password manager | Vaultwarden account, or the SSO button |
| `nextcloud.sandstorm.chat` | Files | Nextcloud account, or "Log in with authentik" |
| `immich.sandstorm.chat` | Photos | Immich account, or "Sign in with Authentik" |
| `navidrome.sandstorm.chat` | Music streaming | Navidrome account |
| `kiwix.sandstorm.chat` | Offline Wikipedia and other archives | none |
| `grafana.sandstorm.chat` | Dashboards and metrics | Grafana account |
| `books.sandstorm.chat` | Calibre-Web Automated — read and manage the library | Authentik, then CWA |
| `bookdl.sandstorm.chat` | Anna's Archive downloader — the non-P2P book path | Authentik |
| `lidarr.sandstorm.chat` | Music acquisition | Authentik, then Lidarr |
| `prowlarr.sandstorm.chat` | Indexer management | Authentik, then Prowlarr |
| `bitmagnet.sandstorm.chat` | DHT torrent indexer — crawls the BitTorrent DHT and serves the results as a Torznab indexer to Prowlarr | Authentik |
| `qui.sandstorm.chat` | Torrent management | Authentik, then qui |
| `convertx.sandstorm.chat` | File converter — 1000+ formats via ffmpeg, LibreOffice, ImageMagick and friends | Authentik, then ConvertX |
| `blog.sandstorm.chat` | Blog (Ghost) — public site, no forward-auth by design; admin panel at `/ghost` | Ghost staff account (created once at `/ghost/setup`) |
| `argocd.sandstorm.chat` | GitOps control plane — **LAN and Tailscale only** | ArgoCD admin |

Everything above sits behind Authentik forward-auth except Authentik itself and the three that keep their own accounts (Vaultwarden, Nextcloud, Immich, which use Authentik as an SSO option instead).

ArgoCD is the exception to public reachability: an IP allowlist runs ahead of everything else, so a request from the internet is refused with 403 before Authentik, CrowdSec or ArgoCD ever see it. It can deploy anything to the cluster, so it stays on the LAN and Tailscale only.

### A Thing to Watch After Adding an Authentik Provider

Authentik's embedded outpost has a Kubernetes integration that creates its *own* Ingress for every proxy provider with an external host. Left on, it published `prowlarr.sandstorm.chat` — which has no Ingress in this repo and was never meant to be public — and claimed `books`, `qui` and `lidarr` on a second router with none of the CrowdSec or rate-limit middlewares attached.

It is now disabled (`kubernetes_disabled_components: ["ingress"]` on the embedded outpost). Forward-auth does not need it: Traefik calls the outpost through the middleware, not through an Ingress. If you ever add a proxy provider and a stray `ak-outpost-*` Ingress appears, that setting got reset.

```bash
kubectl get ingress -A    # should be exactly the ten in the table above
```

### Not Published

FlareSolverr, the bgutil POT provider, slskd's web UI and qBittorrent's own WebUI have no Ingress. Nothing is lost by that: slskd and qBittorrent are driven through Lidarr and qui, and the other two are called by other services rather than people. Reach them over Tailscale or by port-forward if needed:

```bash
kubectl port-forward -n downloads svc/slskd 5030:5030
kubectl port-forward -n downloads svc/qbittorrent 8080:8080
```

qBittorrent's WebUI deliberately stays unpublished — it is an admin interface for a client running untrusted peer traffic.

## Adding a Person

Make the account once in Authentik (Directory → Users), then add them to the groups for the applications they should reach. For the forward-auth applications that is the whole job — access is granted or denied at the proxy. For Vaultwarden, Nextcloud and Immich they also sign in through Authentik, but the application keeps its own user record, created on first login.

## AirVPN and the Torrent Stack

**Done.** Kept as reference for when a port or key changes.

AirVPN forwards **6877** for qBittorrent and **6874** for slskd. Those numbers have to agree in three places or inbound peers silently never arrive: the AirVPN reservation, gluetun's `FIREWALL_VPN_INPUT_PORTS`, and each client's own listen port.

qBittorrent shares a pod with gluetun, so the two run in one network namespace and qBittorrent has no route to the internet except the VPN tunnel. If the tunnel drops, gluetun's firewall drops the traffic — it cannot fall back to the bare LAN connection. That design is why the stack ships at `replicas: 0`: starting gluetun without credentials is the one path that could leak.

Set these four values in Doppler, project `kubernetes`, config `prd`:

| Doppler key | Where AirVPN gives it to you |
|---|---|
| `AIRVPN_PRIVATE_KEY` | WireGuard config, `PrivateKey` |
| `AIRVPN_PRESHARED_KEY` | WireGuard config, `PresharedKey` |
| `AIRVPN_ADDRESSES` | WireGuard config, `Address` (e.g. `10.x.x.x/32`) |
| `AIRVPN_SERVER_COUNTRIES` | Country you want to exit through, e.g. `Netherlands` |

Generate the config from AirVPN's **Client Area → Config Generator**, pick WireGuard, and copy the fields across.

The Doppler operator syncs exactly those four keys — and nothing else from the project — into the `airvpn` Secret in the `downloads` namespace within a minute.

Then flip the replica count in `apps/downloads/qbittorrent.yaml`:

```yaml
replicas: 1   # was 0
```

Commit, push. ArgoCD brings the pod up.

### Confirming the Tunnel Actually Works

Before trusting it with anything:

```bash
kubectl -n downloads logs deploy/qbittorrent -c gluetun | tail -20
kubectl -n downloads exec deploy/qbittorrent -c qbittorrent -- \
  curl -s https://ipinfo.io/ip
```

The second command must print an AirVPN address. If it prints your home address, stop and check the gluetun logs — but note that by construction it should print nothing at all rather than leak, since qBittorrent has no non-tunnel route.

### Then Wire It Up

1. Open `qui.sandstorm.chat`, sign in through Authentik, and add an instance: host `http://qbittorrent.downloads.svc.cluster.local:8080`. qBittorrent's default credentials are printed in its own log on first start — `kubectl -n downloads logs deploy/qbittorrent -c qbittorrent | grep -i password`. Change them immediately.
2. In Prowlarr, add your indexers, then add Lidarr and Readarr as applications so Prowlarr pushes indexer config to them automatically.
3. In Lidarr and Readarr, add qBittorrent as the download client at that same cluster address.

## Books

Two independent acquisition paths, on purpose:

- **Anna's Archive**, no P2P — the book downloader queries it through FlareSolverr and drops results into Calibre-Web Automated's ingest folder. CWA picks them up and files them. Nothing touches a torrent.
- **Readarr**, via Prowlarr and qBittorrent — the P2P path, which needs the AirVPN step above.

Read at `books.sandstorm.chat`.

## Storage Layout

Everything media-related lives under one NFS directory mounted at `/data`:

```
/data/
├── media/music        ← Lidarr's root folder; Navidrome serves it; slskd shares it
├── media/books
├── ingest/books       ← Readarr imports here; CWA processes and files it
├── torrents/{music,books,soulseek,youtube,dab,lucida}
└── cookies/           ← youtube.txt goes here if you ever add it
```

One mount, deliberately. Hardlinks cannot cross filesystems, so with separate volumes every import becomes copy-then-delete: double the disk, slow imports, and the torrent unseedable afterwards because the file it was seeding is gone. Verified by hardlinking a file from `torrents/music` into `media/music`.

These paths match the ones already inside the restored Lidarr database, so the restore needed no remapping.

## Music

Lidarr acquires → Beets tags → Navidrome serves, all against `/data/media/music`.

Download clients on Lidarr: qBittorrent (torrents), slskd (Soulseek), and Tubifarry's YouTube, Lucida and DABmusic. YouTube also uses a `bgutil` POT provider in the lidarr namespace — without it YouTube either refuses or serves only low-quality audio. Cookies are the other half of that recommendation and must come from a logged-in browser session.

slskd shares `/data/media/music`, so Soulseek uploads come from the tagged library rather than the download directory.

DABmusic currently fails its connection test because dabmusic.xyz is down (HTTP 522 from outside the network entirely), not because of anything here.

## Backups

Four layers, each covering the previous one's failure mode:

| What | Where | Cadence |
|---|---|---|
| Postgres WAL + base backups | MinIO, `s3://cnpg-backups/app-databases` | continuous WAL, scheduled base |
| Logical `pg_dump` of every database | MinIO, restic repo, deduplicated and encrypted | daily, kept 8 latest / 7 daily / 4 weekly / 6 monthly |
| ZFS snapshots of `tank` | On the NAS | sanoid schedule |
| Off-site | borgmatic over Tailscale | nightly, rate limited to 1 MB/s so it can't saturate the uplink |

Vaultwarden's actual vault lives in Postgres, so it is inside the first two layers rather than depending on a single PVC.

The pipeline fails loudly: `BackupTooOld`, `WALArchiverFailing` and a MinIO cluster-health probe alert by email, and the **Backups** Grafana dashboard shows last-backup age, WAL archive state and probe status. The 2026-08-29 outage — MinIO serving from a shadowed boot-disk path with zero drives for ~20 h — and every other failure the cluster has seen is documented in [docs/doctor-log.md](doctor-log.md).

Restoring is not theoretical — `apps/databases/restore-verify-job.yaml.example` restores a dump into a scratch database and counts what came back. It is an example file rather than a CronJob so it never runs unattended.

```bash
kubectl create -f apps/databases/restore-verify-job.yaml.example
```

## Security at the Edge

**Rate limiting** is on every published route: 50 req/s sustained, 100 burst, keyed on the forwarded client address rather than the router's, so one abusive client is throttled instead of the whole internet being treated as one.

**CrowdSec** reads Traefik's access logs, recognises attack patterns, and its bouncer blocks the source on the next request. It also pulls the community blocklist, so addresses already caught attacking other CrowdSec users never get a first try here. This is not hypothetical: Traefik's log picks up automated probing for WordPress paths and `.env` files within minutes of exposure.

The bouncer runs in `stream` mode, holding a cached copy of the decision list rather than calling CrowdSec per request — so if CrowdSec goes down, protection degrades instead of taking every service offline with it.

**Geo-blocking is deliberately not enabled.**

Useful commands:

```bash
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli decisions list
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli alerts list
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli decisions delete --ip <address>
```

That last one is what to reach for if you ever lock yourself out. Cluster and LAN ranges are already trusted and cannot be bounced.

## When Something Breaks

```bash
# What does ArgoCD think is wrong
kubectl get applications -n argocd

# Force a re-read of git
kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Traefik rejecting a route
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50 | grep -i error
```

### One Thing ArgoCD Will Not Do for You

`apps/argocd/` is excluded from the ApplicationSet — ArgoCD cannot reconcile its own definition. So a change to the ApplicationSet, the AppProject or `argocd-cm` sits in git doing nothing until you apply it:

```bash
./scripts/bootstrap-argocd.sh
```

The cluster ran a stale ApplicationSet for a full day this way. If ArgoCD's behaviour does not match what the repo says it should be, run that first.

### Two Failure Modes Have Bitten This Cluster Repeatedly

**A NetworkPolicy that allows the apiserver only at `10.43.0.1:443`.** k3s translates that to the node's own address on port 6443 *before* NetworkPolicy egress is evaluated, so the rule matches nothing and API calls fail — often silently, as a controller that never wins leader election. Every policy needs both rules.

**A Traefik middleware that fails to build takes its entire router down.** Not just the middleware — the whole route. Attach a new one to a single low-stakes route first, confirm, then roll out.

## Vaultwarden SSO from the Apps and Browser Extension

The server side is complete and verified live. What follows is the part that is not obvious from the Vaultwarden side at all.

**The clients ask for an "SSO organization identifier". Type `Vaultwarden`.** Bitwarden's clients were built for Bitwarden's hosted SSO, where that string selects your organisation. Vaultwarden's SSO fork has no organisations to select, so it accepts any identifier and answers `/identity/account/prevalidate` for all of them — the constant in its source is literally `FAKE_IDENTIFIER = "Vaultwarden"`. Verified: that endpoint returns a JWT.

Login flow per client:

| Client | Works | Note |
|---|---|---|
| Web vault | yes | "Log in with SSO" is on the login page |
| Browser extension | yes | opens a tab for Authentik, then returns |
| Mobile apps | yes | same tab hand-off |
| Desktop app (Chrome-based) | **no** | upstream bug bitwarden/clients#2606, not ours - the browser cannot hand the redirect back to the app on Linux or Windows |
| Desktop app via Firefox on Linux | fiddly | needs `network.protocol-handler.expose.bitwarden=false` and `network.protocol-handler.external.bitwarden=true` in `about:config`, and the handler only registers on a real click |

**The one Authentik setting to check.** Its default access token lifetime is 5 minutes, and Bitwarden's front-end also treats 5 minutes as its refresh threshold — the two collide and sessions drop immediately. Set it longer in Authentik under *Applications -> Providers -> vaultwarden -> Advanced protocol settings -> Access token validity* (an hour is fine). This is the single most likely cause if SSO logs in and then logs straight back out.

If sessions still will not hold, `SSO_AUTH_ONLY_NOT_SESSION=true` makes Hermes use SSO for authentication only and falls back to Vaultwarden's own session handling (2h access token, 7-day idle refresh). It is the documented escape hatch, not a workaround.

Verified already correct, so do not go changing these:

- `SSO_SCOPES` includes `offline_access` — required from Authentik 2024.2 for a refresh token, and Authentik advertises it (`scopes_supported` includes `offline_access`, `grant_types_supported` includes `refresh_token`).
- `SSO_AUTHORITY` keeps its trailing `/`. The generic docs say to omit it; the Authentik-specific section says it is required, and Authentik's discovery document confirms the issuer carries it.
- The callback `https://vaultwarden.sandstorm.chat/identity/connect/oidc-signin` is registered — an authorize probe returns 302 into the login flow rather than an invalid-redirect error.
- `SSO_ONLY=false` stays false, so an Authentik outage cannot lock you out.

### Troubleshooting Vaultwarden SSO

Read the server log first — it distinguishes the two failure halves immediately:

```
kubectl logs -n vaultwarden deploy/vaultwarden --tail=200 | grep -iE "sso|oidc|token|error"
```

A **working** SSO handshake looks like this, and this is what was in the log the whole time the apps appeared broken:

```
GET  /identity/sso/prevalidate?domainHint=... => 200 OK
GET  /identity/connect/oidc-signin?<code>&<state> => 307 Temporary Redirect
POST /identity/connect/token => 200 OK
```

So if you see those three, **SSO is not your problem**. Two things fail *after* that point and both look like "SSO is broken":

1. `Error sending new device email: Connection error: Network unreachable` — Bitwarden's apps and extension demand a new-device verification email on first login. This was the actual fault: the NetworkPolicy opened 443 but not 587, so the mail never left. The web vault kept working because it was an already-known device, which is exactly what made it look like an app-side SSO bug. Fixed.

2. `Unable to refresh login credentials: Impossible to read refresh_token: Error decoding JWT: Error(InvalidSignature)` — a token signed with a different key than the one now loaded. `/data/rsa_key.pem` is on the persistent volume, so this is not a per-restart problem; it means the client is holding a token from before that key was created. Log out fully in the client and log back in. If it recurs *after* a fresh login, that is when to suspect the key.

3. `POST /identity/accounts/prelogin/password => 404 Not Found` — this one presents as **"an unexpected error has occurred"** on a plain email+password login, while SSO keeps working, because the SSO path never calls that route. It meant the server was the old `timshel/vaultwarden` fork, which never implemented it. Fixed by moving to **OIDCWarden**, the renamed and actively maintained continuation of that fork.

`SSO_DEBUG_TOKENS=true` with `LOG_LEVEL=debug` dumps the tokens if you need to inspect claims — turn it off again afterwards, it logs credentials.

### The Two Accounts

There are two Vaultwarden users, both holding 319 items, with **different master passwords and different vault keys** (verified: neither `password_hash` nor `akey` match):

- `root@example.com` — created first, under the placeholder email that was in place before Authentik's admin identity was corrected.
- `travis@sandstorm.chat` — created later; this is the only one SSO can ever reach, because Authentik's provider uses `sub_mode = user_email` and its only user carries that address.

Bitwarden derives the vault key client-side using **the email as KDF salt**, so the right password for the wrong account fails locally, inside the client, with no server round-trip. That is why the log shows every `connect/token` returning 200 while the client still says the master password is wrong. Resolving this means deciding which account survives — see issue #2.
