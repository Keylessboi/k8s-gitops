# Session handoff — 2026-08-29

State at the point a weekly rate limit was about to interrupt work, so the next
session (or the owner) can pick up without losing context. Newest concern first.

## ⚠️ ACTIVE: NAS is down after a physical move

The owner moved the whole server into a closet. As of ~00:06 on 2026-08-29:

- **`192.168.1.67` (the NAS) does not respond to ping.** It holds *every* NFS
  PVC in the cluster, so all stateful pods lose their storage until it returns.
- The Proxmox host rebooted (`uptime` showed ~8 min). Load was 6.19 and rising
  — **this is pods retrying against dead NFS mounts plus post-boot
  reconciliation, not heat.** Host temps were fine (max ~55°C, threshold 60°C).

**First thing to check next session:** is the NAS powered on and cabled? Once
`ping 192.168.1.67` succeeds and its NFS exports are back
(`showmount -e 192.168.1.67` should list `/extra/nfs-csi` and `/tank/media`),
the stateful pods recover on their own. If a pod is wedged `Terminating` or
`ContainerCreating` on a stale mount, force-delete it — that pattern recurred
all session (see the fsGroup / stale-NFS notes below).

Storage lives on the `tank` mirror now (ADR-0001); `df /extra/nfs-csi` must
report `tank/extra`.

## Background tasks that were running

- **Temp monitor** (Monitor task): watches Proxmox host CPU/NVMe/dell_smm and
  NAS disk temps via the smartctl exporter. Silent unless host ≥60°C or a NAS
  disk ≥50°C; heartbeat ~every 30 min. Filters out the phantom
  `dell_smm/temp8: 126°C` (unused Dell sensor slot). It will report the NAS
  temps as empty while the NAS is down.
- **Pelican Panel agent** (subagent, resumed after it hit the session limit):
  deploying Pelican (Pterodactyl's successor) — see below. May itself be
  blocked by the NAS outage (CNPG/PVCs).

## Phone k3s nodes — where each one stands

Three Pixel 3a phones on postmarketOS, intended as k3s agents. Full detail and
the three traps are in `docs/phone-nodes.md`; the reusable bring-up is
`scripts/stage-phone-node.sh`; the join step is `join-cluster.sh` staged on each
prepared phone. Credentials in Doppler `kubernetes/dev` (`PIXEL3A{1,2,3}_PASS`).

| Phone | Staged? | USB subnet | Blocker |
|---|---|---|---|
| `pixel3a1` | ✅ fully (cgroup2, modules, chrony, k3s v1.31.5+k3s1, token, join script) — **reboot-verified** | moved to **172.16.41.1** (mkinitfs'd) | none — one command from joining on the home net |
| `pixel3a2` | ✅ fully staged earlier | still **172.16.42.1** | none, but shares .42 with pixel3a3 |
| `pixel3a3` | ❌ not staged | still **172.16.42.1** | **`PIXEL3A3_PASS` in Doppler is REJECTED by sudo** (verified not a mislabel); also runs `sudo-rs` which needs a pty, not `-S` |

**Subnet collision:** every postmarketOS phone ships `172.16.42.1`. Only
pixel3a1 was moved (to .41). pixel3a2 and pixel3a3 both still claim .42, so they
**cannot be plugged into the same host at the same time** until each is moved to
its own subnet (`/etc/unudhcpd.conf` → `mkinitfs` → reboot; the file is read by
the initramfs, so the reboot is mandatory). Planned: pixel3a1→.41, pixel3a2→.42,
pixel3a3→.43. IP plan is recorded in Doppler `PIXEL3A*_USB_IP` /
`*_HOST_USB_IP`.

**To join a prepared phone** (needs the home network + NAS up):
`sudo /usr/local/bin/join-cluster.sh` on the phone. It preflights clock, cgroup2
+ memory controller, modules, binary, token, and API reachability, failing
loudly rather than hanging.

**Host side for the phones (Proxmox):** forwarding + NAT per USB subnet, and —
easy to miss — **return routes inside LXC 200** so the control plane can reach
the kubelets (`kubectl logs`/`exec`), else a node registers then goes NotReady.
Full commands in `docs/phone-nodes.md`.

**Known limitation:** `CONFIG_IP_SET` is missing from the phone kernel, so
kube-router likely can't enforce NetworkPolicies on pods scheduled there —
taint the nodes until confirmed.

**Wings plan:** the owner wants Pelican's Wings on the phones (bare metal, so no
LXC blocker, and Docker is packaged for Alpine aarch64). Reality check:
**aarch64 runs Minecraft Java fine but NOT x86-only servers** (CS2, Valheim,
Rust, Palworld). Don't double up k3s-agent + Docker + a game server on 3.5 GB
RAM — pick one role per phone.

## Pelican Panel (game server) — in progress

Chosen over Pterodactyl after a subagent proved (against the real `v1.15.1`
image) that Pterodactyl has no `pdo_pgsql` and no OIDC, and its Wings needs
Docker + KVM (this node is an unprivileged LXC with containerd only). Evidence:
`docs/adr/0005-pterodactyl-needs-mysql-and-kvm.md`; Wings build sheet:
`docs/pterodactyl-wings.md`.

- **Owner decisions:** deploy on the k3s node (explicit override of the plan's
  "no Wings on control plane" — recorded, dated); **OIDC auth required**; S3
  backups; Wings to run on the phones.
- **Already done:** S3 bucket `pterodactyl-backups` on MinIO
  `http://192.168.1.67:9000`, service account scoped to that bucket only
  (negative-tested), creds in Doppler `kubernetes/prd`
  (`MINIO_PTERODACTYL_ACCESS_KEY` / `_SECRET_KEY`). Satisfies plan item F5.
- **In flight:** the agent is deploying Pelican with CNPG Postgres, `redis-master`,
  the S3 bucket, and native Authentik OIDC (created via `ak shell`; the Authentik
  bootstrap API token returns 403). Verify web UI + OIDC redirect before calling
  it done. Blocked while the NAS/CNPG is down.

## MAM seedbox + Prowlarr — DONE this session

- Seedbox dynamic-IP updater runs as a 4th container in the gluetun pod
  (`apps/downloads/qbittorrent.yaml`), so it egresses through the VPN. **Working**:
  after the owner made a MAM session bound to the current exit's IP+ASN, a
  `pkill sleep` re-read the mounted seed (NOT a pod delete — that reconnects the
  tunnel and invalidates the session, the catch-22 that broke earlier attempts)
  and MAM returned `New session created`; cookie jar persisted to the PVC.
- Prowlarr MyAnonamouse indexer (id 37) live, real search returned results.
  `MAM_ID_PROWLARR` wired as a source-of-record secret (Prowlarr keeps indexer
  config in Postgres, so nothing mounts it).
- Owner declined pinning `SERVER_COUNTRIES` — the dynamic-seedbox endpoint is
  meant to handle IP changes; leave it roaming.

## Outstanding owner action items

1. **NAS** — confirm it's powered/cabled after the move (blocks everything).
2. **`pixel3a3` password** — fix `PIXEL3A3_PASS` in Doppler, or run on the phone:
   `echo "travis ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/travis`.
3. **Navidrome first login** (creates the admin account) then
   `./docs/recovery/restore-navidrome-favorites.sh` (1,136 starred tracks
   exported; ~47% recoverable now, re-run as the library refills).
4. **akadmin password** — rotate in Authentik (owner chose to do this).
5. **CWA `kindle` user** with Allow Downloads + Allow Viewer.
6. **cnpg-backup MinIO account has root rights** despite a git comment claiming
   it's bucket-scoped — worth scoping down.
7. **Alloy / repo-review carry-overs** already handled or documented earlier in
   `docs/` (SMART alerts, Alertmanager SMTP, CI, seccomp, CNPG ScheduledBackup).

## Recurring gotchas proven this session (check these first)

- `fsGroup` without `fsGroupChangePolicy: OnRootMismatch` → kubelet recursively
  chowns the whole NFS volume on every roll → pod stuck ContainerCreating with
  only `context deadline exceeded`. Fixed on 6 apps; watch for new ones.
- Force-deleting a pod can leave a stale NFS mount that wedges the replacement
  in Terminating/ContainerCreating — force-delete the wedged one too.
- ArgoCD can report `Synced/Healthy` while the live object is stale
  (ServerSideDiff blind spot) — an explicit sync to the commit SHA fixes it;
  verify the live object when a change matters.
- Lidarr: never press "Search for Missing" — it queues one 31k-album command
  that jams the whole command queue for hours.
