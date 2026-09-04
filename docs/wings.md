# Wings: the game-server daemon

**Wings is what actually runs game servers.** The Pelican panel is only the web
UI and the database; it places servers onto a *node*, and a node is a host
running Wings. With no Wings registered, the panel is correct but empty and the
UI says you own no servers.

This file was `pterodactyl-wings.md`, which was confusing for a good reason:
**Pterodactyl was rejected** (see [ADR-0005](adr/0005-pterodactyl-needs-mysql-and-kvm.md)
— no `pdo_pgsql`, no OIDC) and [Pelican](pelican.md) was deployed instead. But
Pelican is a Pterodactyl fork and runs **the same Wings daemon**, so everything
here about the host, the ports and the panel↔Wings handshake applies unchanged.
Only the panel half was Pterodactyl-specific, and that has been removed — see
[pelican.md](pelican.md) for the panel.

Where Wings runs, and under what governors, is decided in
[ADR-0006](adr/0006-wings-on-the-node.md): a systemd service on CT 200 with its
own docker-ce, 6144 MiB RAM and 10240 MiB disk allocated, 0% overallocate.

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
  chatty. **Not the NFS media pool**, and this is not a preference: Minecraft
  rewrites region files constantly, and a world living on NFS produces lag
  spikes and save timeouts rather than a slow-but-working server.

  **Decided 2026-09-04:** active server data stays on the node's local disk;
  **backups go to the NAS**, via Wings' own backup mechanism into
  `s3://pterodactyl-backups` on the NAS MinIO (the bucket and credential in
  "Already provisioned" above). That is the arrangement that satisfies both
  requirements — fast where writes happen, durable where it matters — rather
  than putting the live world on NFS and losing both.

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

## The panel

Pelican, not Pterodactyl. See [pelican.md](pelican.md) — it uses the shared
CNPG Postgres and Authentik OIDC, which is precisely what Pterodactyl could not
do and why it was rejected. The MySQL requirement, the `p:user:make` CLI and the
"no OIDC" workaround that used to be documented here were Pterodactyl-only and
no longer apply.

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
