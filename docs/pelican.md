# Pelican Panel: deployment and the Wings/aarch64 question

Pelican Panel is deployed in `apps/pelican/`. It is the successor to Pterodactyl
and was chosen because Pterodactyl v1.15.1 cannot run on this cluster at all
(no `pdo_pgsql`, no OIDC — see [ADR-0005](adr/0005-pterodactyl-needs-mysql-and-kvm.md)).
This doc is the Pelican-specific companion to [pterodactyl-wings.md](pterodactyl-wings.md),
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

Wings is deliberately **not** installed here (it cannot run on the k3s LXC node —
ADR-0005). The owner intends to run it on Pixel 3a phones (aarch64, 3.5 GB RAM)
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
  token handshake are unchanged from [pterodactyl-wings.md](pterodactyl-wings.md).
  The node token is a standing credential and belongs in Doppler when a phone is
  actually enrolled.
