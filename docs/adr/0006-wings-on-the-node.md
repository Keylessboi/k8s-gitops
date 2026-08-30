# ADR-0006: Run Wings on the k3s-server node itself

**Status:** Accepted
**Date:** 2026-08-29

## Context

ADR-0005 blocked Wings on this cluster for three reasons: the node is an LXC
container (upstream says Wings "will most likely not function" there), there was
no Docker for Wings to drive, and game-server memory is invisible to the
kubelet on a node that is the sole control plane and sole etcd member. The
owner's 2026-08-29 update (issue #2) removed the first blocker and dropped the
phone plan that Wings was waiting for:

- **CT 200 is privileged** (`unprivileged: 0`, `features: mount=1,nesting=1,fuse=1`),
  so Docker runs inside the LXC next to k3s's containerd. Verified by
  installing docker-ce 29.7.2 on the node and running Wings against it —
  both work, and the two runtimes do not touch each other's storage.
- **The phones are dropped.** The aarch64 constraint (Minecraft-only, 3.5 GB)
  is gone; the amd64 node can run the x86-only games (CS2, Valheim, Rust) that
  were the original motivation.
- Wings v1.0.0-beta29 installed from the upstream release binary, registered to
  the Pelican panel, and reports healthy — the LXC warning is empirically stale
  for this kernel (host 7.0.2-6-pve) and this workload.

What the owner's update did **not** remove is the accounting argument from
ADR-0005: containers started by Wings are Docker containers outside Kubernetes.
The kubelet cannot see them, count them, or evict them under pressure. The
node's measured headroom at deploy time: 13.8 GiB RAM with ~3.1 GiB available
at idle (cluster limits are 257% overcommitted), and a 63 GB rootfs shared by
k3s (40 GB of containerd images), Docker, and the game servers themselves.

Disk turned out to be the sharpest edge. During this deploy, pulling the yolk
images pushed the rootfs to 93% and the kubelet tripped its eviction threshold
(k3s defaults: nodefs/imagefs < 5% free) — the DiskPressure taint evicted the
CNPG primary mid-deploy. The incident is in `docs/doctor-log.md`. A governor is
not optional.

TLS was the last design question. Let's Encrypt cannot issue for the node's LAN
IP, `sandstorm.chat` is on Porkbun with no API credential in Doppler (DNS
changes are manual), and the panel verifies daemon TLS in production
(`AppServiceProvider`: `verify => environment('production')`). So a
panel-reachable HTTPS endpoint needs a private CA whose cert the panel
container trusts.

## Decision

**Wings runs on the k3s-server node itself (CT 200), as a systemd service with
its own docker-ce, registered to the Pelican panel — governed, not free-range.**

- **RAM governor:** the panel node is allocated 6144 MiB with 0% overallocate.
  One modded Minecraft server (4–6 GiB) fits; a second small server only fits
  if the sum stays under the cap. This is the operating rule: one game server
  at a time, two only by conscious decision.
- **Disk governor:** the panel node is allocated 10240 MiB with 0%
  overallocate, and the node rootfs must stay above 10% free — the kubelet
  starts evicting cluster workloads at 5%. Check `df -h /` before any large
  image pull or server install.
- **TLS:** a private CA on the node (`/etc/pelican/ca.key`, mode 600) signs the
  Wings certificate (SAN: `IP:192.168.1.172`, `DNS:wings.sandstorm.chat`), and
  the panel trusts it via the `ca-bundle` initContainer that appends the CA to
  the image's CA bundle on every pod start. The node FQDN in the panel is the
  LAN IP `192.168.1.172` until the owner adds a `wings.sandstorm.chat` A record
  at Porkbun; the cert already carries the DNS SAN, so switching is: add the
  record, patch the node FQDN, update the cert paths in the wings config.
- **Security posture:** Wings runs as root with access to the Docker socket —
  root-equivalent on the node. Accepted for a single-admin homelab where the
  owner already holds Proxmox root. The daemon token lives in Doppler
  (`WINGS_DAEMON_TOKEN`, kubernetes/prd), never in git.

## Consequences

**Good:** x86 game servers are possible on hardware that already exists, the
node is panel-visible and the owner deploys servers from the panel UI, the
yolk images are pre-pulled, and the RAM/disk caps mean the panel itself
enforces most of the governor.

**Bad:** the sole control plane now shares its node with Docker workloads the
kubelet cannot see — the exact risk ADR-0005 identified, reduced by the
governor but not eliminated. Disk, not RAM, is the resource that bites first:
the rootfs is 85%+ used at idle with the yolks cached. The browser console
connects to a private-CA cert, so the owner's browser shows a warning until
the CA is imported or the domain is switched. `nodejs_20` was dropped from the
pre-pull list: it is 2.06 GB and would have re-tripped DiskPressure for no
queued workload.

**Tripwire:** if a second game server runs while the first is up and the sum
exceeds 6144 MiB, the governor is being violated — check the panel's node page.
If the node rootfs drops below 10% free, expect the kubelet to evict cluster
workloads (measured 2026-08-29: the CNPG primary was evicted at 93% full) —
free space before installing anything. If the panel Deployment is ever
"simplified" by removing the `ca-bundle` initContainer, the node goes offline
in the panel with a TLS verification error. And if `APP_KEY` is ever rotated,
every node re-registers (unchanged from `docs/pelican.md`).
