# ADR-0014: Patch every layer automatically, reboot in windows, accept the breakage

**Status:** Accepted
**Date:** 2026-10-30

## Context

The owner's instruction on 2026-10-30, during a wave of zero-days: patch fast,
automatically, and accept that something will occasionally break. ADR-0013
already did that for container images. Read against the hosts on 2026-10-30
(evidence in `docs/host-updates.md`, "Update posture"), the layers underneath
were the weak part, not because updates were off, but because three things were
left manual or never rebooted:

- **Nothing reboots on its own.** Packages install, the running kernel stays
  old. pve and CT 200 ran `7.0.2-6-pve` for 6 weeks with `7.0.14-26` available;
  the backup server ran `6.12.107` with `6.12.113` installed, **and** GRUB's
  saved default still pointed at `6.12.107`, so even a reboot would have gone
  back to the old kernel; the NAS ran `7.2.8` after pacman had already
  deleted `/usr/lib/modules/7.2.8-arch1-2` and installed `7.2.11`.
- **The excluded origins are the exposed ones.** Proxmox packages (qemu, lxc,
  the kernel, 80+ pending), Docker/containerd, and the NVIDIA toolkit were
  deliberately outside `unattended-upgrades`. They are the hypervisor and the
  container runtime.
- **Two classes had no patching at all.** The vmhub CTs (3000, 3010) have no
  `unattended-upgrades` (22 and 38 packages pending), and vmhub-1 runs the stock
  policy, not the homelab one. k3s itself (v1.31.5, EOL upstream) has no upgrade
  mechanism: it is a binary in `/usr/local/bin`.

## Decision

1. **Packages install twice a day** on every Debian host (apt timers moved to
   00:30/12:30 refresh, 02:00/14:00 install) and daily on the NAS, with the
   Proxmox, Docker and NVIDIA origins added to the allowed list.
2. **Reboots happen in one weekly window per host**, run by
   `homelab-reboot-window`, only when a reboot is needed and the role's checks
   pass (ZFS module present for the next kernel, pool healthy, no backup or
   scrub running, loop guard). Windows are staggered so the cluster, the alerting
   host and the storage host never go down together: vmhub Tue 04:00, backup Wed
   04:00, pve Thu 04:00, NAS Sun 06:45.
3. **The backup server boots new kernels as a GRUB one-shot** and promotes them
   only after a health check, because it is unreachable by hand and carries ntfy.
4. **k3s upgrades through system-upgrade-controller**, pinned to an exact version
   Renovate bumps, cordon-only (no drain on a one-server control plane), inside a
   Tue/Wed 03:00-05:00 window, one minor at a time.
5. **Renovate gets a security fast path**: `vulnerabilityAlerts` and OSV alerts
   bypass the 3-day wait and the merge window; patch/digest bumps wait 1 day.

### This adds an operator and a CRD, which ADR-0007 forbids by default

ADR-0007's tripwire says to walk the proposal against `docs/doctor-log.md` and
count the incidents it would have prevented; one or fewer means no. The count
for this change:

| Incident | Prevented? |
|---|---|
| 2026-10-04 kernel upgrade left the NAS with no ZFS | The reboot-window ZFS check and the daily guard make this a skipped night, not a dead pool |
| 2026-09-30 image wave took k3s down (etcd on the same disk) | Not prevented; the Plans' window and `concurrency: 1` avoid adding to it |
| 2026-09-30 ntfy died on a package upgrade, unnoticed 3 h | Not prevented; widening what auto-upgrades raises the odds of a repeat |
| 2026-09-30 nothing had updated in months | Yes, by the same logic as ADR-0013, for the layer below the images |

Two incidents, both prevented by the host-side pieces; the controller itself
prevents none of the logged ones. The exception for the controller is taken on
the owner's explicit instruction, and because the alternative for k3s (a hand-run
install script on two nodes, one of them the control plane) has no guard at all.
The controller is the smallest thing that can do it: one Deployment, no
network egress, idle between releases.

## Consequences

**Good:** a CVE in the kernel, qemu, containerd or k3s reaches every host within
about a day for packages and within a week for the reboot, with no human step.
Every pending reboot is either done or a visible ntfy saying why it was skipped.

**Bad:**
- An unattended Proxmox, Docker or k3s update can break the cluster, and it will
  usually do so at 02:00-04:00. Recovery is a human with a console; pve has
  no IPMI. This is the accepted risk.
- pve's reboot takes CT 200, hence every app, down for a few minutes weekly
  whenever a kernel or libc update landed.
- A Renovate k3s PR that automerges is a cluster upgrade. The 3 AM window gates
  *when*, not *whether*.
- Docker upgrades restart containers (immich-ml); the ntfy/edge-probe host is
  now exposed to the 2026-09-30 ntfy-style failure on any package upgrade.

**Tripwire:** `uname -r` differs from the newest `/usr/lib/modules/*` on any
host for more than 8 days; a `homelab-reboot-window` skip ntfy two weeks
running; or `kubectl get nodes` showing k3s versions that differ between nodes
outside a Tue/Wed window. Each means the automation is not doing its job:
read the ntfy, do not widen the window.
