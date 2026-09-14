# ADR-0011: Run Wings on the NAS, not the k3s-server node

**Status:** Accepted, supersedes [ADR-0006](0006-wings-on-the-node.md)
**Date:** 2026-09-13

## Context

ADR-0006 put Wings on CT 200 because it was the only amd64 host with room, and
accepted the cost it named: the sole control plane shared its node with Docker
containers the kubelet cannot see. It governed that with a 6144 MiB / 10240 MiB
panel allocation and a rule to keep the rootfs above 10% free.

Two things changed on 2026-09-13:

- **The NAS went from 8 GB to 24 GB of RAM** (two spare DDR4 sticks; a third
  slot is blocked by the cooler). It sat at 5-7% memory afterwards, while
  k3s-server stayed at 72-73%.
- **CT 200's rootfs is the resource that bites.** 112 GB, 82% used, 20 GB free.
  The pre-pulled yolks alone are 2.35 GB, ADR-0006 already recorded a
  DiskPressure eviction of the CNPG primary during a yolk pull, and task #45
  (Prometheus off NFS) is blocked on exactly this disk.

The NAS has what Wings needs and CT 200 lacks: bare metal rather than LXC (the
upstream requirement ADR-0006 had to argue around), Docker 29.7.2 already
installed, and an NVMe root with 810 GB free for server data. The HDD pool is
still wrong for live worlds (`docs/wings.md`), and that does not change: Wings
data lives on the NVMe at `/var/lib/pelican`, not on `tank`.

Checked before moving:

- **Docker next to k3s-agent on the NAS.** Starting Docker left the FORWARD
  policy at ACCEPT, and Traefik on k3s-server still reached a pod on the NAS
  afterwards. CT 200 has run the same pairing since ADR-0006.
- **Stale Docker networks on the NAS.** An old Compose install left
  `projects_internal` on 172.18.0.0/16, the subnet Wings' config asks for.
  There were no containers. Wings logged "network created successfully with
  Docker auto-assigned subnet" and came up anyway.
- **TLS.** The panel trusts the private CA from ADR-0006 through its
  `ca-bundle` initContainer. The CA moved with Wings, and a new leaf cert for
  `IP:192.168.1.67, DNS:wings.sandstorm.chat` was signed with it, so the panel
  needed no change. From the panel pod: `https://192.168.1.67:8443/api/system`
  returned 401 with `ssl_verify_result=0`, i.e. TLS verified and the token is
  required.

## Decision

**Wings runs on the NAS as a systemd service against the NAS's Docker, with
server data on the NVMe root.** CT 200's install is stopped and disabled, not
removed, until the NAS node has run a server.

- Moved verbatim (sha256 over every file matched): `/etc/pelican` including
  the CA and node token, `/var/lib/pelican` (162 MB, one server: Minecraft),
  `/usr/local/bin/wings`, the unit file. Staging copy at `/root/wings-import`
  on the NAS.
- `config.yml` changed in exactly two places: cert paths now point at
  `/etc/letsencrypt/live/192.168.1.67/`, and `system.user` uid/gid are the
  NAS's `pelican` system user (964/964, not CT 200's 999/988 - gid 988 is
  `optical` on the NAS).
- The panel's NetworkPolicy allows `192.168.1.67:8443` alongside `.172`
  (commit 3927563). `.172` comes out when CT 200's install is deleted.
- The panel's node record and its 68 allocations must say `192.168.1.67`.
  Allocations are what Docker binds game ports to, and `.172` does not exist
  on the NAS, so a server started against the old rows fails to bind.

The RAM and disk governors from ADR-0006 carry over unchanged (6144 MiB /
10240 MiB, 0% overallocate). They can be raised now, but that is a separate
decision to take with the NAS's ZFS ARC, which also wants that memory.

## Consequences

**Good:** the control plane no longer shares its node with invisible Docker
workloads, which was ADR-0006's main cost. CT 200 can reclaim 2.35 GB of yolk
images once the old install is removed. Game servers get a 12-thread Ryzen and
an NVMe instead of an overcommitted LXC.

**Bad:** the NAS is now three things at once: storage, a k3s worker and a game
host. A runaway server competes with nfsd and ZFS for memory, and the kubelet
still cannot see Docker's usage. Any router port-forwards for game ports that
pointed at `.172` must be re-pointed at `.67` by hand. That is not visible from
the cluster.

**Tripwire:** the panel shows the node offline, or a server fails with a
port-bind error, means the node FQDN or allocation IPs still say `.172`. If
the NAS's `free -h` shows available memory below ~4 GB with a server running,
the governor is too loose for a host that also runs ZFS; lower the node's
panel allocation before raising the ARC.

**Completed 2026-09-14:** the owner updated the node FQDN and all 68
allocations to `192.168.1.67` (`UPDATE 1`, `UPDATE 68`). The panel's
`systemInformation()` call then returned the NAS (12 CPUs, kernel
7.1.8-arch1-3, wings 1.0.0-beta29). `.172` was dropped from the panel's
egress policy, and Docker, Wings and the yolk images were removed from CT 200.

`pelican-portmap` (UPnP port leases, `docs/pelican.md`) was missed in the first
pass: it reads Docker on the Wings host, so it spent a morning logging "docker
unavailable" on CT 200. It now runs on the NAS with `INTERNAL_IP` set to `.67`,
with `miniupnpc` installed there. `pelican-dns` stays on CT 200, because it
needs the server node's kubectl and never touches Docker.

**Rollback:** the full pre-move copy is on the NAS at `/root/wings-import`
(`etc/pelican` with the CA and token, `var/lib/pelican`, the binary and the
unit). Reinstalling on CT 200 means docker-ce again plus that copy, and
setting the node FQDN/allocations back to `192.168.1.172`.
