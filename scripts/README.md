# scripts/

Four scripts. None of them run automatically — everything here is either a
bootstrap step that must precede ArgoCD, or a break-glass procedure. Each file
carries a full explanation in its own header comment; this is the index.

| Script | When you run it | Destructive? |
|---|---|---|
| [`bootstrap-argocd.sh`](bootstrap-argocd.sh) | Standing up the cluster, and after **any** edit under `apps/argocd/` | No |
| [`install-smartctl-exporter.sh`](install-smartctl-exporter.sh) | Once per bare-metal host (Proxmox, NAS) | No |
| [`setup-image-updater-key.sh`](setup-image-updater-key.sh) | Once, to give ArgoCD Image Updater push access | No |
| [`restore.sh`](restore.sh) | Disaster recovery only | **Yes — paths 1 and 2 destroy cluster state** |

## bootstrap-argocd.sh

Applies the ArgoCD bootstrap manifests by hand.

`apps/argocd` is deliberately excluded from the ApplicationSet's git generator,
because ArgoCD cannot be the thing that reconciles the definition of ArgoCD.
The consequence is the part people forget: **nothing applies `apps/argocd/`
automatically.** Committing a change there does nothing to the cluster until
this script runs. The repo has already been bitten by this — the cluster ran a
stale ApplicationSet for a full day after a change was merged.

If you edit anything under `apps/argocd/`, run this.

## install-smartctl-exporter.sh

Installs `smartctl_exporter` as a systemd unit on a bare-metal host.

This is the one piece of monitoring that cannot be a DaemonSet: the disks belong
to the Proxmox host and the NAS, not to the k3s LXC, which has no block devices
in `/dev` at all. Prometheus scrapes the exporter over the LAN on `:9633`
(see the `smartctl` job in `apps/monitoring/`).

Run it on each host that has disks worth watching — currently the Proxmox host
and the NAS.

## setup-image-updater-key.sh

Mints a dedicated ed25519 **deploy key** so ArgoCD Image Updater can push tag
bumps back to this repository, registers the public half with GitHub, and puts
the private half in Doppler.

Deliberately a per-repo deploy key rather than a personal access token: if it
leaks, the blast radius is this one repo and revoking it is a single click.

## restore.sh

**Emergency use only.** Three independent restore paths:

1. **etcd restore** — cluster state and all Kubernetes resources
2. **PostgreSQL restore** — individual database dumps from NFS
3. **Borg restore** — NAS filesystem data from the offsite repo

Paths 1 and 2 **will destroy current cluster state**. Read the header in the
script before running any of it, and be sure you actually want a restore rather
than a targeted fix. Run on the k3s server unless a path says otherwise.

## Conventions

- Scripts are idempotent where they can be, and say so when they are not.
- Anything that touches a secret reads it from Doppler or writes it there —
  no credentials are committed to this repo.
- If a script needs to run somewhere other than your workstation, its header
  says which host.
