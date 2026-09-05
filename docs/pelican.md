# Pelican Panel: deployment and the Wings/aarch64 question

Pelican Panel is deployed in `apps/pelican/`. It is the successor to Pterodactyl
and was chosen because Pterodactyl v1.15.1 cannot run on this cluster at all
(no `pdo_pgsql`, no OIDC — see [ADR-0005](adr/0005-pterodactyl-needs-mysql-and-kvm.md)).
This doc is the Pelican-specific companion to [wings.md](wings.md),
much of which (S3 presigned-URL flow, node handshake, ports) applies unchanged.

## What is deployed

| Thing | Value |
|---|---|
| Panel image | `ghcr.io/pelican/panel:v1.0.0-beta38` pinned to digest `sha256:46f356f3fda423b1d43f0dc3c71efc056cd8b9bec365d1d7817306a17ee5694a` (multi-arch amd64+arm64) |
| Panel version | Laravel 13.25, PHP 8.5.9, released 2026-08-16 |
| URL | `https://pelican.sandstorm.chat` (Traefik + Let's Encrypt, CrowdSec + rate-limit middlewares) |
| Processes | ONE container. Its supervisord runs php-fpm + Caddy + `queue:work` + supercronic (`schedule:run`) together — no separate worker/scheduler Deployments needed (this is the Pterodactyl difference) |

## The two claims from ADR-0005, verified against the deployed image

Both were checked by running the real image in the cluster, not from docs:

- **`pdo_pgsql` is present and works.** `php -m` lists `pdo_pgsql`, and a PDO
  connect from the image to `app-databases-rw.databases.svc.cluster.local:5432`
  returned `PostgreSQL 16.9`. Pterodactyl at the same test returned
  `could not find driver`. `config/database.php` has a real `pgsql` connection
  block (Pterodactyl had only `mysql`/`mariadb`).
- **OIDC is native.** `composer.json` pulls `laravel/socialite` +
  `socialiteproviders/authentik`, and `app/Extensions/OAuth/Schemas/AuthentikSchema.php`
  is a first-class provider driven by `OAUTH_AUTHENTIK_*` env vars.

## How each dependency is wired

- **Database** — native PostgreSQL on the shared CNPG cluster. Role `pelican` +
  database `pelican` added to `apps/databases/cluster.yaml` and
  `databases.yaml`; password via Doppler `pelican-db-credentials` (basic-auth,
  in `databases`) and `pelican-app` (in `pelican`). No second engine, no MariaDB.
- **Redis** — the ONE shared `redis-master`, `predis` client (the image has no
  phpredis extension). `APP_NAME=Pelican` sets the Redis key prefix so cache,
  session and queue keys don't collide with the other tenants on that instance.
- **S3 backups** — reuses the pre-provisioned `pterodactyl-backups` bucket on
  `http://192.168.1.67:9000` (creds `MINIO_PTERODACTYL_*` from Doppler). The
  `create_backup_hosts` migration reads `AWS_*` env on first migrate and seeds a
  "Remote" S3 backup host row, so the backup target is declarative. As with
  Pterodactyl, the Panel signs presigned URLs and **Wings** uploads the bytes —
  so the Wings host (the phone) also needs a route to `192.168.1.67:9000`.
- **OIDC** — Authentik OAuth2 provider **"Pelican"** (application slug `pelican`),
  created via `ak shell`. Confidential client, `sub_mode=user_email`, self-signed
  signing cert, scopes `openid email profile goauthentik.io/api`, redirect URI
  `https://pelican.sandstorm.chat/auth/oauth/callback/authentik`. Client id/secret
  in Doppler (`PELICAN_OIDC_CLIENT_*`). The socialite authentik driver builds its
  authorize/token/userinfo URLs from `OAUTH_AUTHENTIK_BASE_URL` — there is no
  discovery-URL fetch.
- **APP_KEY** — generated once, stored in Doppler `PELICAN_APP_KEY`, never
  rotated. It encrypts Wings node tokens; rotating it re-registers every node.

## Admin account

Made by the `pelican-admin` Job (an ArgoCD PostSync hook, so it runs after the
schema exists): `php artisan p:user:make --admin=1` for `travis.fiorito@tuta.com`
(username `travis`). Password in Doppler `PELICAN_ADMIN_PASSWORD`. The email
matches the OIDC `sub_mode=user_email`, and the panel links an OIDC login to an
existing local account by verified email — so signing in through Authentik lands
on this admin account rather than making a second unprivileged one.

## Wings and aarch64 (Pixel 3a / postmarketOS) — the reality check

**Update 2026-08-29: Wings IS now deployed — on the k3s-server node itself, not
on phones.** The phones were dropped by the owner and CT 200 turned out to be
privileged with nesting, so Docker runs in the LXC. See
[ADR-0006](adr/0006-wings-on-the-node.md) for the decision, the RAM/disk
governors, and the TLS setup; the historical aarch64 analysis below is kept for
the record.

Wings was originally **not** installed here (it cannot run on the k3s LXC node —
ADR-0005). The owner intended to run it on Pixel 3a phones (aarch64, 3.5 GB RAM)
on postmarketOS. Findings:

- **Wings does publish arm64 builds.** Pelican Wings `v1.0.0-beta29` ships
  `wings_linux_arm64` (37 MB) alongside `wings_linux_amd64`. So the daemon itself
  will run on the phones — and a bare-metal aarch64 Linux host satisfies the
  "not LXC, real Docker" requirement that the k3s node fails.
- **The limiter is the game-server images, not Wings.** Pelican's generic and
  JVM yolk images are multi-arch: `ghcr.io/pelican-eggs/yolks:java_21` and
  `:debian` both publish `amd64` **and** `arm64`. But the SteamCMD image that
  every Source/Steam game builds on — `ghcr.io/pelican-eggs/games:steamcmd` — is
  **amd64-only**.
- **Therefore:** JVM-based servers (Minecraft Java) will run on the phones. The
  popular native servers — **CS2, Valheim, Rust, Palworld are x86-only and will
  not run on aarch64** (SteamCMD/native binaries, no arm64 image, emulation not
  practical). With 3.5 GB RAM per phone, a single small Minecraft Java server is
  the realistic workload per node.
- Node registration, ports (8080 API, 2022 SFTP, 25565+ allocations) and the
  token handshake are unchanged from [wings.md](wings.md).
  The node token is a standing credential and belongs in Doppler when a phone is
  actually enrolled.

## "You don't own any servers" — the first admin has no role (2026-09-04)

Two separate things look identical from the client dashboard, and both were
true here at once.

**1. Wings was never installed.** The panel is only the UI; Wings is the daemon
that runs the containers. `config.yml`, the node registration, the private CA
and its certs had all existed since 31 Aug — the `wings` binary simply was not
on CT 200. Installed, enabled and started; see [wings.md](wings.md). The panel
now reaches it (`panel → 192.168.1.172:8443` returns **401**, which is the
correct answer for an unauthenticated request: alive and enforcing auth).

**2. No account had a role.** This is the one that actually produced the
message. Pelican uses Filament Shield roles, not Pterodactyl's `root_admin`
column, and the check is an explicit row in `model_has_roles`:

```
travis   (id 1) -> NO ROLE
akadmin  (id 3) -> NO ROLE
role "Root Admin" existed, assigned to nobody
```

**Authentik OIDC provisions a Pelican user with no role**, which is the right
default — a new SSO user should not become an administrator by logging in — but
it means the *first* admin has to be assigned by hand, and nobody had. With no
role there is no admin area, so there is no way to create a server, and the
client dashboard correctly reports that you own none.

Fixed with the panel's own command rather than raw SQL:

```bash
php artisan permission:assign-role "Root Admin" 1
```

**Log out and back in afterwards** — the role is read into the session at login.

### State after this

`1 node, 0 servers, 2 eggs (Vanilla Minecraft, Paper), 6 allocations`. Nothing
is missing; a server just has to be created in the admin area.

### ⚠️ Before creating one, check memory

[ADR-0006](adr/0006-wings-on-the-node.md) allocates the node **6144 MiB**, but
that is a panel-side *cap*, not physical memory. On 2026-09-04 the node had
**~2.2 GB actually available**. A modded Minecraft server sized to the cap will
OOM the node and take cluster workloads with it. Allocate against what `free -m`
says, not against the governor.

## Creating servers: eggs, ports, and addresses

### Eggs

**313 eggs are installed** — effectively everything the `pelican-eggs` org
publishes: all of `minecraft`, `games-steamcmd`, `games-standalone`, `voice`,
`software`, `database`, `storage`, `monitoring`, `chatbots`, `generic`. So
Vanilla / Paper / Purpur / Spigot / Forge / NeoForge / Fabric / Bedrock, both
proxies (Velocity, BungeeCord), CS2 and CS:S, Rust, Valheim, Palworld, ARK,
Terraria, Project Zomboid and the rest are all pickable in the create-server
wizard. Version is a per-server startup variable, so switching Minecraft
versions never needs a new egg.

Beta38 has no `p:egg:import` CLI. Bulk import goes through the service the
panel's own importer uses:

```php
// php artisan tinker --execute="require '/tmp/import_all.php';"
$svc = app(App\Services\Eggs\Sharing\EggImporterService::class);
$egg = $svc->fromUrl('https://raw.githubusercontent.com/pelican-eggs/<repo>/main/<path>.json');
```

Two gotchas worth remembering. `php artisan tinker <file>` opens a REPL and
echoes the file instead of running it — it must be `--execute="require '…';"`.
And many directories carry both `egg-x.json` and `egg-pterodactyl-x.json` for
the same egg; dedupe per directory preferring the non-`pterodactyl` variant, or
the panel fills with pairs.

### Addresses

`*.sandstorm.chat` is a **wildcard A record → 74.101.53.75** (Porkbun NS), so
any hostname resolves with no DNS work. Each allocation therefore just needs a
name attached, which is what `allocations.ip_alias` is for — the panel then
shows players the hostname instead of `192.168.1.172`.

68 allocations exist on node 1, all named:

| Address | Port | For |
|---|---|---|
| `minecraft.sandstorm.chat` | 25565 | Minecraft Java (in use) |
| `papermc` / `forge` / `fabric` / `neoforge` / `purpur` / `spigot` / `vanilla` | 25566-25572 | Minecraft Java |
| `proxy.sandstorm.chat` | 25573 | Velocity / BungeeCord |
| `bedrock.sandstorm.chat` | 19132 | Minecraft Bedrock (UDP) |
| `cs` / `cs2` / `css` | 27015-27017 | Source engine |
| `terraria` `rust` `palworld` `valheim` `zomboid` | 7777 / 28015 / 8211 / 2456 / 16261 | standalone games |
| `game1…game50` | remainder | unassigned spares |

### Two things the cluster cannot do for itself

**Router port-forwards.** Web apps work because 80/443 already forward to
Traefik at `192.168.1.240`. Game traffic is raw TCP/UDP and must forward to the
Wings node, **`192.168.1.172`**, port-for-port. Until a port is forwarded, a
server is LAN-only. Forward both TCP and UDP.

**Dropping the port from the address.** Two ways, depending on the game:

- *Minecraft Java* reads SRV records, so one record per name removes the port:
  `_minecraft._tcp.papermc` → priority 0, weight 5, port 25566, target
  `papermc.sandstorm.chat`. Players then type `papermc.sandstorm.chat`.
- *Source games* ignore SRV, but clients default to **27015** — so
  `cs.sandstorm.chat` works portless as long as that server holds 27015.
  Anything on 27016+ must be given as `host:port`.

There is a better option for Minecraft specifically. The Java protocol sends
the hostname it dialed in its handshake, so a **Velocity proxy on 25565 with
forced-hosts** can route every subdomain to a different backend through a
**single forwarded port** — no SRV records, no extra forwards per server. If
more than two or three Minecraft servers are ever wanted, do that instead of
forwarding a port each.
