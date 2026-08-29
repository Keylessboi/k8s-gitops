# ADR-0005: Do not deploy Pterodactyl until a MySQL host and a KVM node exist

**Status:** Accepted
**Date:** 2026-08-28

## Context

Phase 2 items 20 and 21 call for Pterodactyl Panel on k3s with Wings on a compute node. Three of the four things the deployment was specified to do turn out to be impossible on this cluster as it stands. Each was verified against the version that would actually be deployed — `v1.15.1`, released 2026-08-14 — not against a summary.

### 1. The Panel cannot use PostgreSQL. Not "unsupported" — it cannot connect.

The brief for this work asserted "Pterodactyl supports PostgreSQL". It does not, and there are two independent reasons, either of which is fatal.

`config/database.php` at tag `v1.15.1` defines exactly two connections, `mysql` and `mariadb`. There is no `pgsql` key. Upstream's own requirements read "MySQL `5.7.22` and higher (MySQL `8` recommended) **or** MariaDB `10.2` and higher."

The official image goes further and settles it. Running `ghcr.io/pterodactyl/panel:v1.15.1` in this cluster and pointing it at the CNPG cluster:

```
$ php -m | grep -i pdo
PDO
pdo_mysql
pdo_sqlite

$ DB_CONNECTION=pgsql DB_HOST=app-databases-rw.databases.svc.cluster.local \
  DB_PORT=5432 php artisan migrate --force
In Connection.php line 838:
  could not find driver (Connection: pgsql, Host: app-databases-rw.databases.
  svc.cluster.local, Port: 5432, ...)
In Connector.php line 66:
  could not find driver
```

`pdo_pgsql` is not compiled into the image. Postgres support was merged upstream in PR #4486 (Nov 2022) but into the `develop` branch of the *next* major version; it has never shipped in the 1.x line, which is what issue #4968 ("PostgreSQL not present in releases") is about.

So the only way to run Pterodactyl here is MySQL or MariaDB. That collides head on with this cluster's standing rule of **one Postgres and no second database engine**. It is not a rule Pterodactyl can be talked out of, and it is not a gap a sidecar or a proxy closes — the migrations are MySQL-dialect.

Worth knowing separately: Pterodactyl also *provisions* databases for game servers, and that feature is MySQL-only too. Even a Panel on Postgres, if it existed, would still want a MySQL host to hand out.

### 2. The Panel has no OIDC. None.

The owner asked for OIDC rather than edge forward-auth. Pterodactyl `v1.15.1` has no OIDC, no OAuth2, and no SAML. `routes/auth.php` exposes only local login, the 2FA checkpoint, forgot-password and reset. `composer.json` pulls no `socialite`, no OIDC library. Nothing in the `v1.12`–`v1.15` changelogs adds SSO. This is the same shape as ADR-0003 (Navidrome): the app simply has no external identity path.

Forward-auth at the Ingress is therefore the only option that exists — and it is *not* OIDC. It authenticates at the edge and leaves the Panel's own user model unaware of who logged in, so a Panel account must still be created and maintained separately, and revoking someone in Authentik does not revoke their Panel account. That is a real trade-off, not a substitution, and it is why this was not silently done and declared finished.

### 3. Wings cannot run on this node, and would endanger the cluster if it did.

The owner explicitly overrode the plan's "do not run Wings on k3s control plane nodes" on **2026-08-28** with "just set it up on the control plane node with S3 and OIDC auth". That override is recorded here deliberately so nobody later "fixes" the absence of Wings by re-reading the plan. The override was accepted; the install still did not happen, for reasons the override does not resolve.

**The node is an LXC container, which Wings does not support.** `k3s-server` is Proxmox LXC 200 (`unprivileged: 0`, `features: mount=1,nesting=1,fuse=1`). Upstream's install guide states that OpenVZ, LXC and Virtuozzo "will most likely prevent Wings from functioning" and that KVM is the guaranteed-to-work virtualisation. The plan's "use a compute node" constraint and this are the same constraint wearing different clothes.

**There is no Docker here, and Wings cannot use containerd.** Wings drives the Docker Engine API directly. This node runs k3s on containerd (`containerd://1.7.23-k3s2`) and has no `docker` or `dockerd` binary. Running Wings would mean either a second container runtime installed alongside k3s on the control-plane node, or a privileged Docker-in-Docker pod — and a privileged pod contradicts the `pod-security.kubernetes.io/enforce: baseline` label every namespace in this repo carries, and cannot run under `seccompProfile: RuntimeDefault`.

**Capacity makes it dangerous rather than merely untidy.** Measured on the node:

```
capacity            13824Mi
memory requests      8429Mi (60%)
memory limits       35554Mi (257% overcommitted)
cpu limits          33050m  (300% overcommitted)
free -m available    4739Mi
```

Roughly 4.7 GiB is actually free, and a single modded Minecraft server routinely asks for 4–8 GiB. The decisive part is not the headroom, it is the accounting: game servers started by Wings are Docker containers, *outside* Kubernetes. The kubelet cannot see them, cannot count them against the node, and cannot evict them under pressure. The first server that overshoots takes the node's memory with it — and this node is the sole control plane and the sole etcd member, so that is not a lost game server, it is a lost cluster.

## Decision

**Do not deploy Pterodactyl Panel or Wings on this cluster in its current shape.** No MariaDB, no second Postgres, no privileged Docker-in-Docker on the control plane. Items 20 and 21 stay open pending an owner decision between:

1. **A KVM compute node.** Resolves items 20 and 21 as originally written: Wings on the KVM host with Docker, Panel on k3s, and MySQL/MariaDB living on that same host rather than in the cluster — which keeps the "one Postgres in k3s" rule intact because the second engine is never in k3s. This is the only option that matches the plan.
2. **Accept MariaDB in-cluster** for the Panel only, and still leave Wings until a non-LXC host exists. A Panel with no Wings manages nothing, so this buys a login page and little else.
3. **Pelican Panel instead of Pterodactyl.** The fork by former Pterodactyl maintainers supports PostgreSQL 14+ natively (the CNPG cluster is 16) and has Socialite-based OIDC, so it would clear blockers 1 and 2 outright. It does not clear blocker 3 — Pelican's own Wings carries the identical Docker and LXC requirements. It is also a different product from the one the plan names, so it is the owner's call, not an implementation detail.

What *was* done, because it is engine-independent and required by F5: the MinIO bucket and a scoped credential for it now exist (see `docs/pterodactyl-wings.md`).

## Consequences

**Good:** the cluster keeps one database engine and one control plane that is not sharing a node with unaccounted Docker workloads. Nothing was deployed that would have crash-looped on a database it cannot speak to, and no privileged pod was added to a control-plane node running etcd.

**Bad:** phase 2 items 20 and 21 are not done, and success criterion 16 ("Pterodactyl can create game servers") is unmet. There is a provisioned, paid-for-in-attention MinIO bucket sitting empty until one of the three options above is chosen.

**Tripwire:** if a `mariadb` or `mysql` Deployment/StatefulSet ever appears in `apps/`, or a pod anywhere gains `privileged: true` outside `monitoring`, this decision has been reversed — check that it was reversed deliberately and that the node in question is no longer the only control plane. Equally, if Wings ever appears on `k3s-server` while `pct config 200` still reports an LXC, expect intermittent container failures that will look like Wings bugs and are not.
