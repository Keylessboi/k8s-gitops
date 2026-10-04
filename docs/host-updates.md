# Host OS updates

Container images update through Renovate (`renovate.json`). This page covers
the machines underneath them. Every host updates itself; **none reboots on its
own** - a pending reboot arrives as a low-priority ntfy on `homelab-alerts`.

| Host | OS | Mechanism | Schedule |
|---|---|---|---|
| NAS (`nas`) | Arch | `nas-auto-update.timer` → `pacman -Syu` + ZFS guard | Sun 05:30 local |
| k3s node (CT 200 on pve) | Debian 13 | `unattended-upgrades` | daily (`apt-daily-upgrade.timer`) |
| pve | Proxmox VE 9 / Debian 13 | `unattended-upgrades`, Debian origins only | daily |
| travisbackupserver (`backup`) | Debian 13 | `unattended-upgrades` | daily |

What stays manual, on purpose:

- **ZFS on the NAS** (`zfs-dkms-git`, `zfs-utils-git`, AUR) and other AUR
  packages (`minio`). Rebuild with `paru -S zfs-utils-git zfs-dkms-git` when a
  kernel outgrows the current build. Never a release build: the pool has
  master-only features enabled (doctor-log 2026-10-04).
- **Proxmox packages** (pve-manager, the pve kernel, qemu, lxc): Proxmox
  advises against unattended upgrades. `apt full-upgrade` on pve, then a
  planned reboot (`docs/recovery/cluster-down.md` covers getting CT 200 back).
- **Docker and the NVIDIA container toolkit**: an upgrade restarts dockerd and
  every container on the host.
- **k3s** is a binary in `/usr/local/bin`, not a package. Upgrade it one minor
  at a time, server (CT 200) first, then the NAS agent.

## The NAS guard

`scripts/host/nas-auto-update` exists because a kernel upgrade on the NAS can
leave the next boot without `tank` (doctor-log 2026-10-04). After each
upgrade it checks every installed kernel for `zfs.ko`. If one has none it
retries `dkms autoinstall`, then reinstalls that kernel's previous version
from `/var/cache/pacman/pkg` and sends an **urgent** ntfy. "DO NOT REBOOT" in
that message means the rollback failed too.

It skips the week (low ntfy) if pacman is locked or borgmatic is mid-backup.

Manual check before rebooting the NAS, any time:

```
for k in /usr/lib/modules/*/vmlinuz; do d=${k%/vmlinuz}; printf '%s ' "${d##*/}"; find "$d" -name 'zfs.ko*' | grep -q . && echo ok || echo NO-ZFS; done
```

## Install

NAS (as root):

```
install -m755 scripts/host/nas-auto-update /usr/local/bin/
install -m644 scripts/host/nas-auto-update.{service,timer} /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now nas-auto-update.timer
```

Debian hosts (pve, CT 200 via `pct exec 200 --`, backup):

```
apt-get install -y unattended-upgrades
install -m644 scripts/host/apt/52unattended-upgrades-homelab scripts/host/apt/20auto-upgrades-homelab /etc/apt/apt.conf.d/
unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins|Packages that will be upgraded'
```

pve and backup only (CT 200 cannot reach ntfy and has no kernel to reboot):

```
install -m755 scripts/host/homelab-reboot-notify /usr/local/bin/
install -Dm644 scripts/host/apt/apt-daily-upgrade.service.d/homelab-reboot-notify.conf \
  /etc/systemd/system/apt-daily-upgrade.service.d/homelab-reboot-notify.conf
systemctl daemon-reload
```
