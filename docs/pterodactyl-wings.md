# Pterodactyl: Panel and Wings setup

Phase 2 items 20 and 21. **Nothing is deployed yet** — read
[ADR-0005](adr/0005-pterodactyl-needs-mysql-and-kvm.md) first for why, and for
the three options between which the owner has to choose. This file is the
build sheet for when that choice is made: what the host needs, how the Panel and
Wings find each other, and what already exists.

## Already provisioned (2026-08-28)

This part is independent of which panel and which database engine win, so it was
done and verified rather than left for later. It satisfies F5's "verify MinIO
buckets exist for new services".

| Thing | Value |
|---|---|
| Bucket | `s3://pterodactyl-backups` on the NAS MinIO, `http://192.168.1.67:9000` |
| Region / addressing | `us-east-1`, path-style (`AWS_USE_PATH_STYLE_ENDPOINT=true`) |
| Credential | MinIO service account, access key `pterodactyl-backup` |
| Where the credential lives | Doppler `kubernetes/prd`, as `MINIO_PTERODACTYL_ACCESS_KEY` / `MINIO_PTERODACTYL_SECRET_KEY`. Not in git, not only in the cluster. |

Unlike `cnpg-backup` — which reports `Policy: implied`, i.e. it inherits the
MinIO root user's full rights despite the comment in `apps/databases/cluster.yaml`
claiming otherwise — this service account carries an explicit policy scoped to
the one bucket. Verified both ways: it can put, list, get and delete inside
`pterodactyl-backups`, and `mc ls` against `cnpg-backups` returns
`Access Denied`. Egress from the cluster to `192.168.1.67:9000` was confirmed
reachable from a pod.

When the Panel is eventually deployed it consumes these as a Doppler-synced
namespace-local Secret, following `apps/doppler/dopplersecrets.yaml`; the Panel
env keys are `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_BACKUPS_BUCKET=pterodactyl-backups`, `AWS_ENDPOINT=http://192.168.1.67:9000`,
`AWS_DEFAULT_REGION=us-east-1`, `AWS_USE_PATH_STYLE_ENDPOINT=true` and
`APP_BACKUP_DRIVER=s3`.

Note how Pterodactyl's S3 backups actually work, because it changes who needs
network access: the **Panel** signs a presigned URL, and **Wings** does the
upload. The bytes never pass through the Panel. So the Wings host — not just the
cluster — needs a route to `192.168.1.67:9000`.

## What the Wings host must be

Wings is the piece with real requirements. It is not fussy about much, but the
things it is fussy about are not negotiable.

- **KVM, or bare metal. Not LXC.** Upstream states OpenVZ, LXC and Virtuozzo
  "will most likely prevent Wings from functioning"; KVM is the guaranteed
  option. This rules out `k3s-server`, which is Proxmox LXC 200.
- **Docker CE.** Wings speaks the Docker Engine API directly and cannot drive
  containerd, so a k3s node's runtime is no help. Docker must be installed on
  the host in the ordinary way.
- **Linux, x86_64, stock kernel.** Avoid the modified kernels ending
  `-xxxx-grs-ipv6-64` or `-xxxx-mod-std-ipv6-64`.
- **Memory sized for the games, plus headroom.** Whatever the servers are
  allocated in the Panel is what Docker will let them take. Size the host so the
  sum of allocations leaves the host itself room; do not rely on overcommit.
- **Disk** on something that tolerates many small writes — game servers are
  chatty. Not the NFS media pool.

### Ports

| Port | Protocol | Purpose |
|---|---|---|
| 8080 | TCP | Wings API, the Panel↔Wings channel (`api.port`, default 8080). Behind TLS in any real setup. |
| 2022 | TCP | SFTP server built into Wings (`system.sftp.bind_port`, default 2022) — how users get file access to their servers. |
| 25565+ | TCP/UDP | Game server allocations. Minecraft starts at 25565; allocate a contiguous block per node and register it in the Panel under the node's Allocations tab. |

Allocations are declared in the Panel, not in Wings' config, and Wings will only
bind what the Panel told it about. Both TCP and UDP matter — some games (Source
engine, most voice servers) are UDP-only, and a TCP-only firewall rule looks
like a working server that nobody can join.

### Panel → Wings handshake

1. In the Panel, **Admin → Nodes → Create Node**: FQDN, ports above, memory and
   disk the node is allowed to hand out.
2. Open the new node's **Configuration** tab. It renders a complete
   `config.yml`, including the node's token and UUID.
3. Either paste that into `/etc/pterodactyl/config.yml` on the host, or use the
   **Generate Token** button and run the one-line `wings configure` command it
   gives you.
4. `systemctl enable --now wings`, then confirm the node goes green in the Panel.

The token in that file *is* the trust relationship — it is a standing
credential, so it belongs in Doppler (`WINGS_NODE_TOKEN`) rather than only on
the host's disk, the same as every other secret here.

The FQDN matters more than it looks: the Panel's browser console and file
manager connect to Wings **from the user's browser**, not server-side. So the
Wings FQDN has to be resolvable and TLS-valid from outside, not just from the
cluster, or the Panel loads and every server console sits blank.

## What the Panel needs

- **MySQL 8 or MariaDB 10.2+.** Not Postgres — see ADR-0005. If a KVM compute
  node is the chosen path, the cleanest placement is MariaDB on that host
  alongside Wings, which keeps a second engine out of k3s entirely.
- **Redis** for cache, session and queue. The existing `redis-master.redis.svc.cluster.local:6379`
  serves this; Pterodactyl reads `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD`
  and takes separate logical databases for default and sessions, so it does not
  collide with the other tenants.
- **`APP_KEY`**, a base64 32-byte Laravel key. Generate once, store in Doppler,
  and never rotate casually — it encrypts the Wings node tokens in the database,
  so changing it silently breaks every node.
- **A queue worker.** Pterodactyl needs `php artisan queue:work` running
  alongside the web container, or scheduled tasks and backups queue up forever
  and nothing tells you. This is a second container in the same pod, not an
  afterthought.
- **The scheduler**, `php artisan schedule:run` every minute.

### Admin account

There is no first-run web wizard — the first admin is made on the CLI:

```
php artisan p:user:make --email=<addr> --username=<name> \
  --name-first=<first> --name-last=<last> --admin=1 --password=<pw>
```

Run it as a Kubernetes Job (or `kubectl exec`) once the Panel is up. The
password belongs in Doppler as `PTERODACTYL_ADMIN_PASSWORD` before the Job runs,
read via `secretKeyRef` — never as a literal in the manifest, and never typed
interactively where it lands in shell history.

### Authentication

Pterodactyl `v1.15.1` has no OIDC, OAuth2 or SAML — verified against
`routes/auth.php` and `composer.json` at that tag. The realistic option is
Authentik **forward-auth** on the Ingress, exactly as
`apps/prowlarr/ingress.yaml` does it, combined with a Panel-local admin account.

Be clear about what that does and does not buy, because it is the same trade-off
ADR-0003 records for Navidrome: forward-auth authenticates at the edge, but the
Panel's own user model never learns who the visitor is. Panel accounts are
maintained separately, and removing someone from Authentik does not remove their
Panel account. It is a gate in front of the app, not single sign-on into it.

Two carve-outs will be needed and are easy to miss:

- `/api/*` — the Panel's client and application APIs use bearer tokens. Behind
  forward-auth they get an HTML login redirect instead of JSON.
- The Wings↔Panel callbacks. Wings is not a browser and cannot complete an
  Authentik redirect.

If native OIDC is a hard requirement rather than a preference, Pelican Panel is
the option that actually has it (Laravel Socialite, with Authentik among the
configurable providers) — see option 3 in ADR-0005.

## Game server creation, once it works

1. **Admin → Nests** — import or pick an egg (Minecraft, Source, etc.). Eggs are
   the per-game container image plus install script.
2. **Admin → Servers → Create** — pick owner, node, egg, and allocate CPU,
   memory, disk and a port from the node's allocation pool.
3. Wings pulls the egg's image and runs the install script; the server appears in
   the user's client area with console, file manager and SFTP.
4. **Backups** land in `s3://pterodactyl-backups` via the presigned-URL flow
   above. Set a backup limit per server, or one chatty server will fill the
   bucket.
