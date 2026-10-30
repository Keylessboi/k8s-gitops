# Host OS updates

Container images update through Renovate (`renovate.json`, ADR-0013). This page
covers the machines underneath them. Policy and the risk accepted: ADR-0014.

## Update posture (read-only audit, 2026-10-30)

| Host class | OS | Mechanism before this change | Evidence on 2026-10-30 |
|---|---|---|---|
| pve (`vostro`, Dell Vostro) | Proxmox VE 9.2.2 / Debian 13 | `unattended-upgrades`, Debian + Tailscale origins only; Proxmox excluded | Up 6w 4d, running `7.0.2-6-pve`, `7.0.14-26` available; 82 packages pending (qemu `11.0.0`->`11.0.3`, pve-manager, ceph, corosync); no reboot-required flag; last auto upgrade 10-28 (tailscale). Repos: `pve-no-subscription` plus an `pve-enterprise`/`ceph` source with no subscription key |
| CT 200 `k3s-server` | Debian 13 (shares the pve kernel) | `unattended-upgrades`, same origins | 6 pending, all Docker/containerd (excluded origin); last auto upgrade 10-28; runs pve's `7.0.2-6-pve` |
| k3s on CT 200 and `nas` | v1.31.5+k3s1 | none (binary in `/usr/local/bin`) | Both nodes v1.31.5+k3s1, 66 / 54 days old; 1.31 is EOL, current is 1.37 |
| NAS | Arch | `nas-auto-update.timer`, Sunday 05:30 | Up 3w 3d; **running `7.2.8-arch1-2`, whose `/usr/lib/modules` dir pacman already deleted; installed `7.2.11-arch1-1` and `linux-lts 6.18.58-1`**; last run 10-25; `checkupdates` empty; ZFS present for both installed kernels; 3 stale module dirs |
| travisbackupserver | Debian 13 | `unattended-upgrades` | Up 7w 5d, **running `6.12.107`, installed `6.12.113`, `/run/reboot-required` set; GRUB saved default still `6.12.107`**; 5 pending (nvidia-container-toolkit, tzdata) |
| vmhub-1 (DL360p) | Proxmox VE 9.2.2 | `unattended-upgrades`, **stock Debian-Security-only policy** (not the homelab file) | Up 4d, `7.0.2-6-pve`, 84 pending incl. pve-manager `9.2.2`->`9.2.24`, `7.0.14-26` kernel; UU ran 10-30 (imagemagick) |
| vmhub CTs 3000 `llm`, 3010 `llm-next` | Debian 13 | **none** (no `unattended-upgrades`) | 22 and 38 packages pending; last upgrade by hand 10-12 (openssl) on 3010; share vmhub-1's kernel |
| vmhub CT 3020 `dsh-agent` | Debian 13 | none | Stopped; not inspectable read-only |
| vmhub VM templates (18, e.g. `debian-13-golden`, `x11-2404`, `windows-11-24h2`) and pve VMs 101/102/2120 | various | none | All stopped. Disk images are frozen at their last boot; not audited |
| Container images | many | Renovate (ADR-0013) | PR #162 merged 10-30 06:00; digest pinning incomplete (AGENTS.md) |

Everything above updated its **packages** on its own; none updated its
**running code**, because nothing reboots on its own.

What stays manual, on purpose:

- **ZFS on the NAS** (`zfs-dkms-git`, `zfs-utils-git`, AUR) and other AUR
  packages (`minio`). Rebuild both when a kernel outgrows the current build.
  Never a release build: the pool has master-only features enabled
  (doctor-log 2026-10-04).

  **The AUR `zfs-dkms-git` PKGBUILD needs a one-line fix** (as of
  2.4.99.r1185, 2026-10-04): OpenZFS master's Makefile runs
  `scripts/make_gitrev.sh`, but the package only copies `dkms.postbuild` and
  `objtool-wrapper.in` from `scripts/`. The module compiles, `make` exits 2 on
  the missing script, and DKMS throws the build away ("Bad return status";
  `make.log` shows `make_gitrev.sh: No such file or directory`). Build it by
  hand with the fix, keeping both packages on the same commit:

  ```
  cd ~/build && paru -G zfs-utils-git zfs-dkms-git
  sed -i 's#scripts/objtool-wrapper.in "${dkmsdir}"/scripts/#scripts/objtool-wrapper.in scripts/make_gitrev.sh "${dkmsdir}"/scripts/#' zfs-dkms-git/PKGBUILD
  export PACMAN_AUTH=doas   # makepkg defaults to sudo; the NAS has doas
  (cd zfs-dkms-git && makepkg -s) && (cd zfs-utils-git && makepkg -s)
  # pkgver of the two must match (zfs-dkms-git depends on the exact utils version)
  doas pacman -U zfs-utils-git/zfs-utils-git-2:*-x86_64.pkg.tar.zst zfs-dkms-git/zfs-dkms-git-2:*-any.pkg.tar.zst
  doas dkms status   # every installed kernel: "installed"
  ```
- **Proxmox, Docker and NVIDIA toolkit packages** were manual until ADR-0014;
  they now auto-install (`52unattended-upgrades-homelab`). To hold one back,
  `apt-mark hold <pkg>` on that host and say why in this file.
- **Major OS upgrades** (Debian 13 -> 14, PVE 9 -> 10, Arch is rolling) stay
  manual. So do the NAS's AUR packages above.

## Update schedule

| Host | Packages | Reboot window (only if needed, after checks) |
|---|---|---|
| NAS | daily 05:30 `nas-auto-update` | Sun 06:45 |
| vmhub-1 (and its CTs) | 02:00 and 14:00 | Tue 04:00 |
| travisbackupserver | 02:00 and 14:00 | Wed 04:00 (GRUB one-shot, promoted on health) |
| pve (and CT 200, which has no reboot of its own) | 02:00 and 14:00 | Thu 04:00 |
| k3s (both nodes) | system-upgrade-controller Plans in `apps/system-upgrade/plans.yaml` | Tue/Wed 03:00-05:00, one minor at a time |

All times are the host's local time (America/New_York except CT 200, UTC).
`homelab-reboot-window --dry-run` shows what a host would do tonight.

Reboots are skipped (low-priority ntfy on `homelab-alerts`) when: uptime is
under 12 h, a package manager is running, or the role check fails (NAS: no
`zfs.ko` for the next kernel, pool not healthy, borg or a scrub running; pve:
pool not healthy).

## CVE-critical fast path

1. **A package on a host**: `unattended-upgrade -v` on the host (Debian) or
   `doas systemctl start nas-auto-update.service` (NAS), then
   `homelab-reboot-window --dry-run`, and `systemctl start
   homelab-reboot-window.service` if the reasons are right. That skips the weekly wait.
2. **An image or chart**: Renovate `vulnerabilityAlerts` and OSV open the PR at
   any hour and merge it when `validate` is green, ignoring the 3-day delay.
   Renovate has no vulnerability feed for plain Docker tags, so for a CVE it
   does not know about, edit the tag (and digest) in a PR and merge it yourself,
   or tick the update's box on the Dependency Dashboard to skip the schedule.
3. **k3s**: merge the Renovate PR; the Plans act at the next 03:00 Tue/Wed
   window. For an emergency, edit the Plans' `window:` to cover now, push, and
   put it back.
4. **ArgoCD** is pinned in `scripts/bootstrap-argocd.sh`; merging deploys
   nothing. Bump it, then run the script.

## Not covered

Stopped VM and CT images (vmhub templates, pve VMs 101/102/2120, CT 3020) do not
patch until booted; the phones and Pi in the Ansible inventory are offline
(pixel-3a-1/2, raspberrypi last seen 88-122 days ago); firmware and BIOS
(DL360p iLO, Vostro); `minio` and `zfs-*-git` on the NAS; Home Assistant (offline
121 days); container images with no `# renovate:` comment inside Helm values;
images not yet pinned by digest; and anything on the laptop.

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

Nothing below is applied by CI or ArgoCD (only `apps/system-upgrade` is). Run
each block by hand, one host at a time, and check `--dry-run` output first.
Reboot-window files live in `scripts/host/reboot-window/`.

Every host (`ROLE` = `nas`, `pve`, `vmhub` or `backup`; not CT 200 or CTs):

```
install -m755 scripts/host/reboot-window/homelab-reboot-window /usr/local/bin/
install -m644 scripts/host/reboot-window/homelab-reboot-window.{service,timer} /etc/systemd/system/
install -D -m644 scripts/host/reboot-window/$ROLE.timer.conf /etc/systemd/system/homelab-reboot-window.timer.d/schedule.conf
install -m644 scripts/host/reboot-window/$ROLE.env /etc/default/homelab-reboot-window
systemctl daemon-reload && homelab-reboot-window --dry-run && systemctl enable --now homelab-reboot-window.timer
```

NAS (as root, `doas`): also reinstall the changed daily timer.

```
install -m644 scripts/host/nas-auto-update.{service,timer} /etc/systemd/system/
systemctl daemon-reload && systemctl restart nas-auto-update.timer
```

Debian hosts (pve, vmhub-1, backup, CT 200, vmhub CTs 3000 and 3010; the CTs
via `pct exec <id> --`):

```
apt-get install -y unattended-upgrades
install -m644 scripts/host/apt/52unattended-upgrades-homelab scripts/host/apt/20auto-upgrades-homelab /etc/apt/apt.conf.d/
install -D -m644 scripts/host/apt/apt-daily.timer.d/homelab-window.conf /etc/systemd/system/apt-daily.timer.d/homelab-window.conf
install -D -m644 scripts/host/apt/apt-daily-upgrade.timer.d/homelab-window.conf /etc/systemd/system/apt-daily-upgrade.timer.d/homelab-window.conf
systemctl daemon-reload && systemctl restart apt-daily.timer apt-daily-upgrade.timer
unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins|Packages that will be upgraded'
```

pve, vmhub-1 and backup only (CT 200 and the CTs cannot reach ntfy and have no kernel):

```
install -m755 scripts/host/homelab-reboot-notify /usr/local/bin/
install -Dm644 scripts/host/apt/apt-daily-upgrade.service.d/homelab-reboot-notify.conf \
  /etc/systemd/system/apt-daily-upgrade.service.d/homelab-reboot-notify.conf
systemctl daemon-reload
```

backup only, once, before its first window:

```
install -m755 scripts/host/reboot-window/homelab-grub-promote /usr/local/bin/
install -m644 scripts/host/reboot-window/homelab-grub-promote.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable homelab-grub-promote.service
```

Then, to pick up the 6.12.113 kernel that is already waiting, let the first
window do it, or run `systemctl start homelab-reboot-window.service` yourself
while watching `ntfy`.

k3s: merging this PR syncs `apps/system-upgrade` through ArgoCD. The Plans start
at the version already installed on the nodes' minor (`v1.31.14+k3s1`); the
first window upgrades both nodes 1.31.5 -> 1.31.14. Take a snapshot first:
`ssh pve 'pct exec 200 -- /usr/local/bin/k3s etcd-snapshot save'`.
