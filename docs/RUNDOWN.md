# Running this cluster

Everything below is driven from this repo. ArgoCD watches `apps/*` and syncs
with prune and self-heal on, so a change made with `kubectl` gets reverted on
the next pass — change the file, push, and let it land.

## What's published

All of these sit behind Traefik with a Let's Encrypt certificate, and every one
of them is rate limited (50 req/s sustained, 100 burst, per source address).

| URL | What it is | Login |
|---|---|---|
| `authentik.sandstorm.chat` | SSO — the identity provider everything else defers to | `akadmin` |
| `vaultwarden.sandstorm.chat` | Password manager | Vaultwarden account, "Log in with SSO" available |
| `nextcloud.sandstorm.chat` | Files | Nextcloud account |
| `immich.sandstorm.chat` | Photos | Immich account |
| `navidrome.sandstorm.chat` | Music streaming | Navidrome account |
| `books.sandstorm.chat` | Calibre-Web Automated — read and manage the library | Authentik first, then CWA |
| `lidarr.sandstorm.chat` | Music acquisition | Authentik first, then Lidarr |
| `qui.sandstorm.chat` | Torrent management UI | Authentik first |
| `kiwix.sandstorm.chat` | Offline Wikipedia and other archives | none |
| `grafana.sandstorm.chat` | Dashboards and metrics | Grafana account |

Four of those — books, lidarr, qui, and anything else marked "Authentik first" —
are behind forward-auth: Traefik asks Authentik whether you're signed in before
the request ever reaches the application. That matters because Lidarr and qui
are admin interfaces with weak or no built-in auth of their own.

### Not published, deliberately

Prowlarr, FlareSolverr, Readarr, the book downloader, Beets, Octo-Fiesta and
qBittorrent's own WebUI have no Ingress. Neither does ArgoCD - it is the
control plane for everything else, so it stays off the public internet. All of
them are reachable over Tailscale or by port-forward:

```bash
kubectl port-forward -n prowlarr svc/prowlarr 9696:9696
kubectl port-forward -n music     svc/beets    8337:8337
kubectl port-forward -n argocd   svc/argocd-server 8080:443
```

Nothing is lost by this — Prowlarr feeds Lidarr and Readarr over cluster DNS,
and qBittorrent is driven through qui.

## Adding a person

Make the account once in Authentik (Directory → Users), then add them to the
groups for the applications they should reach. For the forward-auth
applications that is the whole job — access is granted or denied at the proxy.
For Vaultwarden, Nextcloud and Immich they also sign in through Authentik, but
the application keeps its own user record, created on first login.

## AirVPN and the torrent stack

**This is the one thing left to do, and it takes about a minute.**

qBittorrent shares a pod with gluetun, so the two run in one network namespace
and qBittorrent has no route to the internet except the VPN tunnel. If the
tunnel drops, gluetun's firewall drops the traffic — it cannot fall back to the
bare LAN connection. That design is why the stack ships at `replicas: 0`:
starting gluetun without credentials is the one path that could leak.

Set these four values in Doppler, project `kubernetes`, config `prd`:

| Doppler key | Where AirVPN gives it to you |
|---|---|
| `AIRVPN_PRIVATE_KEY` | WireGuard config, `PrivateKey` |
| `AIRVPN_PRESHARED_KEY` | WireGuard config, `PresharedKey` |
| `AIRVPN_ADDRESSES` | WireGuard config, `Address` (e.g. `10.x.x.x/32`) |
| `AIRVPN_SERVER_COUNTRIES` | Country you want to exit through, e.g. `Netherlands` |

Generate the config from AirVPN's **Client Area → Config Generator**, pick
WireGuard, and copy the fields across.

The Doppler operator syncs exactly those four keys — and nothing else from the
project — into the `airvpn` Secret in the `downloads` namespace within a minute.

Then flip the replica count in `apps/downloads/qbittorrent.yaml`:

```yaml
replicas: 1   # was 0
```

Commit, push. ArgoCD brings the pod up.

### Confirming the tunnel actually works

Before trusting it with anything:

```bash
kubectl -n downloads logs deploy/qbittorrent -c gluetun | tail -20
kubectl -n downloads exec deploy/qbittorrent -c qbittorrent -- \
  curl -s https://ipinfo.io/ip
```

The second command must print an AirVPN address. If it prints your home
address, stop and check the gluetun logs — but note that by construction it
should print nothing at all rather than leak, since qBittorrent has no
non-tunnel route.

### Then wire it up

1. Open `qui.sandstorm.chat`, sign in through Authentik, and add an instance:
   host `http://qbittorrent.downloads.svc.cluster.local:8080`. qBittorrent's
   default credentials are printed in its own log on first start —
   `kubectl -n downloads logs deploy/qbittorrent -c qbittorrent | grep -i password`.
   Change them immediately.
2. In Prowlarr, add your indexers, then add Lidarr and Readarr as applications
   so Prowlarr pushes indexer config to them automatically.
3. In Lidarr and Readarr, add qBittorrent as the download client at that same
   cluster address.

## Books

Two independent acquisition paths, on purpose:

- **Anna's Archive**, no P2P — the book downloader queries it through
  FlareSolverr and drops results into Calibre-Web Automated's ingest folder.
  CWA picks them up and files them. Nothing touches a torrent.
- **Readarr**, via Prowlarr and qBittorrent — the P2P path, which needs the
  AirVPN step above.

Read at `books.sandstorm.chat`.

## Music

The chain is: Lidarr acquires → Beets tags and organises → Navidrome serves.

Beets and Navidrome mount the *same* NFS directory, through a static PV pinned
to Navidrome's library path, so a file Beets tags appears in Navidrome without
copying. Octo-Fiesta sits alongside for Deezer-sourced material.

One caveat worth knowing: that static PV is pinned to
`pvc-9ea2b827-163b-4545-9224-cc13c2594ad9`. If `navidrome-music` is ever
deleted and recreated it gets a new UUID and
`apps/music/music-library-pv.yaml` must be updated to match, or Beets will
silently tag into a directory nothing reads.

## Backups

Four layers, each covering the previous one's failure mode:

| What | Where | Cadence |
|---|---|---|
| Postgres WAL + base backups | MinIO, `s3://cnpg-backups/app-databases` | continuous WAL, scheduled base |
| Logical `pg_dump` of every database | MinIO, restic repo, deduplicated and encrypted | daily, kept 8 latest / 7 daily / 4 weekly / 6 monthly |
| ZFS snapshots of `tank` | On the NAS | sanoid schedule |
| Off-site | borgmatic over Tailscale | nightly, rate limited to 1 MB/s so it can't saturate the uplink |

Vaultwarden's actual vault lives in Postgres, so it's inside the first two
layers rather than depending on a single PVC.

Restoring is not theoretical — `apps/databases/restore-verify-job.yaml.example`
restores a dump into a scratch database and counts what came back. It's an
example file rather than a CronJob so it never runs unattended.

```bash
kubectl create -f apps/databases/restore-verify-job.yaml.example
```

## Security at the edge

**Rate limiting** is on every published route: 50 req/s sustained, 100 burst,
keyed on the forwarded client address rather than the router's, so one abusive
client is throttled instead of the whole internet being treated as one.

**CrowdSec** reads Traefik's access logs, recognises attack patterns, and its
bouncer blocks the source on the next request. It also pulls the community
blocklist, so addresses already caught attacking other CrowdSec users never get
a first try here. This is not hypothetical: Traefik's log picks up automated
probing for WordPress paths and `.env` files within minutes of exposure.

The bouncer runs in `stream` mode, holding a cached copy of the decision list
rather than calling CrowdSec per request — so if CrowdSec goes down, protection
degrades instead of taking every service offline with it.

**Geo-blocking is deliberately not enabled.**

Useful commands:

```bash
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli decisions list
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli alerts list
kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli decisions delete --ip <address>
```

That last one is what to reach for if you ever lock yourself out. Cluster and
LAN ranges are already trusted and cannot be bounced.

## When something breaks

```bash
# What does ArgoCD think is wrong
kubectl get applications -n argocd

# Force a re-read of git
kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Traefik rejecting a route
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50 | grep -i error
```

Two failure modes have bitten this cluster repeatedly and are worth checking
first:

1. **A NetworkPolicy that allows the apiserver only at `10.43.0.1:443`.** k3s
   translates that to the node's own address on port 6443 *before* NetworkPolicy
   egress is evaluated, so the rule matches nothing and API calls fail — often
   silently, as a controller that never wins leader election. Every policy needs
   both rules.
2. **A Traefik middleware that fails to build takes its entire router down.**
   Attach a new middleware to one low-stakes route first, confirm, then roll out.
