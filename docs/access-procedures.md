# Cluster Access Procedures

> Day-to-day usage lives in [RUNDOWN.md](RUNDOWN.md). This file covers access paths only.

## Service URLs

| Service | URL | Notes |
|---------|-----|-------|
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

| Component | Location | Details |
|-----------|----------|---------|
| k3s Server | 192.168.1.172 | LXC CT 200 on Proxmox |
| Proxmox Host | 192.168.1.153 | Vostro server |
| NAS | 192.168.1.67 | ZFS storage, NFS, MinIO |

### SSH Access

```bash
# k3s server
ssh root@192.168.1.172

# Proxmox host
ssh root@192.168.1.153

# NAS
ssh root@192.168.1.67
```

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
|--------|-----------------|-------|
| ZFS key | proxmox | Disk encryption |
| MinIO root | proxmox | S3 storage access |
| Borg passphrase | proxmox | Backup encryption |
| k3s secrets | kubernetes | Cluster encryption |

### Manual Credential Locations

| Secret | Location | Fallback |
|--------|----------|----------|
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

| Role | Contact | When to Escalate |
|------|---------|------------------|
| Infrastructure | - | Proxmox/NAS issues |
| Kubernetes | - | Cluster/pod issues |
| Networking | - | DNS/Ingress issues |

## Not published

Prowlarr, FlareSolverr, Readarr, the book downloader, Beets, Octo-Fiesta and
qBittorrent's WebUI have no Ingress by design. Reach them over Tailscale or
port-forward, e.g.:

```bash
kubectl port-forward -n prowlarr svc/prowlarr 9696:9696
```

Pangolin was removed - its routing lived in its own database rather than in
this repo, and Traefik middlewares cover the same ground declaratively.
Prometheus is reached through Grafana rather than published directly.

ArgoCD has no Ingress either - it is the control plane for everything else,
so it stays off the public internet:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```
