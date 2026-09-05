# Cluster Access Procedures

> Day-to-day usage lives in [RUNDOWN.md](RUNDOWN.md). This file covers access paths only.

## Service URLs

| Service | URL | Notes |
|---|---|---|
| Authentik | https://authentik.sandstorm.chat | SSO/Identity Provider |
| Vaultwarden | https://vaultwarden.sandstorm.chat | Password Manager |
| Nextcloud | https://nextcloud.sandstorm.chat | File Storage |
| Immich | https://immich.sandstorm.chat | Photo Management |
| Navidrome | https://navidrome.sandstorm.chat | Music Streaming (Authentik forward-auth; `/rest` + `/share` exempt for Subsonic clients) |
| Lidarr | https://lidarr.sandstorm.chat | Music acquisition (Authentik forward-auth) |
| Kiwix | https://kiwix.sandstorm.chat | Offline Content |
| Calibre-Web Automated | https://books.sandstorm.chat | Ebooks (Authentik forward-auth) |
| qui | https://qui.sandstorm.chat | Torrent management (Authentik forward-auth) |
| Grafana | https://grafana.sandstorm.chat | Monitoring Dashboards |

**Alternative Access**: If DNS is not configured, use kubectl port-forward:
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## Cluster Access

### Infrastructure

| Component | LAN | Tailscale | Details |
|---|---|---|---|
| k3s Server | 192.168.1.172 | — | LXC CT 200 on Proxmox |
| Proxmox Host | 192.168.1.153 | 100.125.108.56 | Dell Vostro 3681, **no IPMI** |
| NAS | 192.168.1.67 | 100.69.240.8 | Arch. ZFS, NFS, MinIO. AMD RX 5500 |
| travisbackupserver | *(other site)* | 100.81.123.74 | Debian 13, Long Island. ntfy + edge probe. NVIDIA GTX 1050 Ti |

### SSH Access

**`~/.ssh/worker_key` is the only key any of these accept.** `id_ed25519`,
`id_rsa` and `eni_agent` are refused everywhere — if a host says
"Permission denied (publickey)", the key is the first thing to check, not the
host. **The NAS logs in as `travis`, not `root`.**

```bash
ssh -i ~/.ssh/worker_key root@100.125.108.56    # Proxmox host   (alias: pve)
ssh -i ~/.ssh/worker_key travis@100.69.240.8    # NAS            (alias: nas)
ssh -i ~/.ssh/worker_key root@100.81.123.74     # backup server  (alias: backup)
```

Reach the k3s container through Proxmox rather than directly:

```bash
ssh pve 'pct exec 200 -- kubectl get nodes'
```

### Privilege escalation differs per host

| Host | Root | Note |
|---|---|---|
| pve, backup | already root | — |
| **NAS** | **`doas`, not `sudo`** | `sudo` is not installed. `doas <cmd>`; it prompts for a password. |

### Notes

- The laptop is **not** on the cluster's LAN. It sits on the backup server's
  separate `192.168.1.0/24` — same numbering, different L2 — so `192.168.1.153`
  from the laptop is a *different machine* than pve. Never diagnose cluster
  reachability from the laptop; use the NAS, which is on the cluster's segment.
- The backup server runs fail2ban. Guessing usernames will get the IP banned for
  a while; use the table above.

### Kubeconfig

Location on k3s server: `/etc/rancher/k3s/k3s.yaml`

To copy to local machine:
```bash
scp root@192.168.1.172:/etc/rancher/k3s/k3s.yaml ~/.kube/config
```

Verify cluster access:
```bash
kubectl get nodes
kubectl get applications -n argocd
```

## Credential Locations

### Secrets Management (Doppler)

| Secret | Doppler Project | Usage |
|---|---|---|
| ZFS key | proxmox | Disk encryption |
| MinIO root | proxmox | S3 storage access |
| Borg passphrase | proxmox | Backup encryption |
| k3s secrets | kubernetes | Cluster encryption |

### Manual Credential Locations

| Secret | Location | Fallback |
|---|---|---|
| ZFS key | /etc/zfs/keys/tank.key (NAS) | Doppler (proxmox) |
| Borg passphrase | /etc/borgmatic/passphrase (NAS) | Doppler (proxmox) |
| ArgoCD admin | kubectl -n argocd get secret argocd-initial-admin-secret | - |
| Doppler tokens | Stored on each host | Manual setup required |

### ArgoCD Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## Emergency Bypass

### ArgoCD Down

If ArgoCD is unresponsive and you need to remove an application:

```bash
kubectl delete application -n argocd <app-name> --cascade=background
```

### k3s Down

```bash
ssh root@192.168.1.172 'systemctl restart k3s'
```

### NFS Down

1. Check NAS NFS exports: `showmount -e 192.168.1.67`
2. Restart ganesha on NAS: `systemctl restart nfs-ganesha`
3. Verify PVC mounts: `kubectl get pvc -A`

### DNS Issues

If services are unreachable via domain:
1. Check Cloudflare DNS records
2. Verify MetalLB load balancer IPs: `kubectl get svc -n metallb-system`
3. Use direct IP access as temporary workaround

## Restore Procedure

For full cluster restore, see [scripts/restore.sh](../scripts/restore.sh).

**Quick Reference**:
```bash
# On k3s server (192.168.1.172)
# 1. Stop k3s
systemctl stop k3s

# 2. Reset etcd with snapshot
k3s server --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-name>

# 3. Start k3s
systemctl start k3s

# 4. Re-apply ArgoCD
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Maintenance Windows

- **Scheduled maintenance**: Sundays 02:00-06:00 UTC
- **Notification**: Send message to #ops-alerts channel
- **Rollback plan**: Keep previous ArgoCD sync revision

## Contacts

This is a single-operator homelab: every role below is the same person. The table is kept because the escalation *paths* differ even when the contact does not — knowing which layer a fault belongs to is the useful part.

| Role | Contact | When to Escalate |
|---|---|---|
| Infrastructure | Travis (owner) | Proxmox host or NAS: disks, ZFS pools, NFS exports, LXC 200 itself |
| Kubernetes | Travis (owner) | Cluster, pods, ArgoCD sync failures, PVC/CSI problems |
| Networking | Travis (owner) | DNS, Traefik/Ingress, MetalLB, Authentik forward-auth, CrowdSec bans |

If a second operator is ever added, replace the relevant row rather than adding a column — the escalation path should stay unambiguous.

## Not Published


```bash
kubectl port-forward -n prowlarr svc/prowlarr 9696:9696
```

Pangolin was removed — its routing lived in its own database rather than in this repo, and Traefik middlewares cover the same ground declaratively. Prometheus is reached through Grafana rather than published directly.

ArgoCD has no Ingress either — it is the control plane for everything else, so it stays off the public internet:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## GPU on travisbackupserver

NVIDIA GTX 1050 Ti (GP107, 4 GB), driver **550.163.01** via Debian DKMS.

Two things to know if this ever needs redoing:

**The apt sources were missing `main`.** Only `trixie-security` and
`trixie-updates` were configured, with no `contrib`/`non-free`, so
`nvidia-driver` was not installable at all. Fixed by adding
`/etc/apt/sources.list.d/debian-main.list`.

**`linux-headers-amd64` pulls a newer kernel than the running one.** DKMS then
builds only for that newer kernel, so the driver cannot load until a reboot —
and headers for the older running kernel are already gone from the archive, so
building for it is not an option.

### The reboot is the risky part, so it has a fallback

This host is at another site with no remote hands and carries ntfy plus the
edge probe — the external alerting path. A kernel that fails to boot would take
that out with no way back. So GRUB is configured to make that survivable:

- `GRUB_DEFAULT=saved`, `GRUB_SAVEDEFAULT=false` — a successful boot does not
  silently rewrite the fallback.
- `panic=30` on the kernel cmdline, so a panic **reboots** rather than hanging
  forever on an unreachable machine.
- `grub-set-default` pins the known-good kernel; `grub-reboot` arms the new one
  as a **one-shot**. GRUB consumes `next_entry` at boot regardless of outcome,
  so a failed boot falls back automatically.

After confirming the new kernel is good, promote it:

```sh
SUB=gnulinux-advanced-<uuid>
grub-set-default "$SUB>gnulinux-<version>-advanced-<uuid>"
```

Skipping that last step leaves the fallback pointing at a kernel with no NVIDIA
module, so the next routine reboot would silently lose the GPU.

Verified after reboot: `nvidia-smi` reports the card, `nouveau` is gone, and
ntfy, tailscaled, ssh and `homelab-watch.timer` all came back.
