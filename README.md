# k8s-gitops

Every manifest for a single-node homelab Kubernetes cluster. ArgoCD watches this repository and reconciles the cluster to match it. The cluster is a rendering of this repo, not a thing that is administered directly.

| | |
|---|---|
| Cluster | k3s, one node, `k3s-server` |
| Where it runs | Proxmox LXC container 200 (`192.168.1.172`) on the Vostro host |
| Domain | `sandstorm.chat`, TLS from Let's Encrypt via cert-manager |
| Reconciled by | ArgoCD, auto-sync with `prune: true` and `selfHeal: true` |
| Identity | Authentik at `authentik.sandstorm.chat` |
| Secrets | Doppler, synced into the cluster by the Doppler operator |

## The One Rule

**`kubectl edit` does not stick.** Auto-sync runs with `selfHeal: true`. ArgoCD reverts any live change on its next pass. The only durable way to change anything is to edit a file here, commit, and push.

```
edit apps/<app>/…  →  git commit  →  git push  →  ArgoCD syncs  →  cluster changes
```

`kubectl` is still the right tool for *looking* — logs, events, `exec`, a throwaway test pod. It is never the tool for changing.

The single exception is `apps/argocd/`, which is excluded from the ApplicationSet: ArgoCD cannot reconcile its own definition. Those files are applied by hand with `scripts/bootstrap-argocd.sh`, and nothing applies them for you. Run it after any change under `apps/argocd/`.

## Layout

```
apps/                one directory per application, each a kustomization
  argocd/            bootstrap manifests — NOT managed by ArgoCD, see above
  <app>/
    kustomization.yaml   resource list, common labels, sync-wave
    namespace.yaml       namespace + Pod Security Admission labels
    networkpolicy.yaml   `app-isolation`: default-deny ingress and egress
    deployment.yaml      … plus service, ingress, pvc as needed
ansible/             one-time host provisioning: Proxmox LXC, k3s, platform
docs/                how to run, access and recover the cluster
scripts/             the few things that cannot be GitOps
```

### How an App Becomes an Application

`apps/argocd/root-applicationset.yaml` holds an ApplicationSet with a git directory generator pointed at `apps/*`. Every directory under `apps/` becomes one ArgoCD Application named after the directory, in the `homelab` AppProject, with auto-sync on. There is no per-app Application file to write and no list to keep in step — creating `apps/<name>/` with a `kustomization.yaml` is the whole onboarding step.

`apps/argocd` itself is excluded by the generator.

Ordering between apps comes from `argocd.argoproj.io/sync-wave` on each `kustomization.yaml`: infrastructure runs first (metallb `-10`, traefik `-6`, cert-manager / coredns / nfs-csi `-5`, crowdsec `-4`, cnpg and doppler `0`, databases and image-updater `5`, authentik and monitoring `10`) and every user-facing app is wave `20`.

Upstream Helm charts are referenced from `kustomization.yaml` and pulled by ArgoCD at render time. `apps/*/charts/` is gitignored — those are local artefacts from `kustomize build --enable-helm` during testing and must never be committed.

## Making a Change

1. Edit the manifest under `apps/<app>/`.
2. Validate it. A YAML parse error is not a small mistake: it surfaces as an ArgoCD `ComparisonError` that fails the *entire* Application, not just the bad file.
   ```bash
   python3 -c "import yaml, sys; list(yaml.safe_load_all(open(sys.argv[1])))" apps/<app>/<file>.yaml
   ```
3. Commit and push to `main`.
4. Watch it land:
   ```bash
   kubectl get applications -n argocd            # want Synced / Healthy
   kubectl -n argocd annotate app <app> argocd.argoproj.io/refresh=hard --overwrite
   ```

Conventions worth keeping to, because the existing files do:

- **Non-obvious settings carry a comment saying why.** Most of the odd-looking lines in this repo are scar tissue from a specific failure, and the comment is the only record of it.
- **Pin image tags.** `:latest` leaves no way to reason about what is running.
- Use `labels:` with `includeSelectors: false` in a kustomization, never `commonLabels` — that rewrites Deployment selectors, which are immutable.
- Every app ships its own `namespace.yaml`. `CreateNamespace` is deliberately off in the ApplicationSet.

## Secrets

Nothing sensitive is in this repository, and nothing sensitive should ever be added to it.

Secrets live in Doppler. The Doppler Kubernetes operator (`apps/doppler/`) reads them and writes namespace-local Kubernetes `Secret`s that workloads consume through `secretKeyRef` / `envFrom`. Every `DopplerSecret` in the cluster is declared in `apps/doppler/dopplersecrets.yaml`, next to the operator rather than next to the app that consumes it — the operator refuses to reconcile a `DopplerSecret` that lives outside its own namespace, so the target is carried in `managedSecret.namespace` instead. Each one pins an explicit `secrets:` list, so a namespace receives only the keys it needs rather than a mirror of the whole Doppler config.

Setting a value in Doppler is therefore the entire deployment step for a credential; there is no `kubectl create secret` anywhere in the workflow. The bootstrap credential the operator itself needs (`doppler-token-secret`) is the one thing applied by hand.

Deployments that reference a secret that may not exist yet use `optional: true`, so the pod still starts and can be debugged.

## Getting In

Public services sit behind Traefik with a Let's Encrypt certificate, CrowdSec, and a per-source rate limit. Most also sit behind Authentik forward-auth — the `kube-system-authentik-forward-auth@kubernetescrd` middleware in `apps/traefik/forward-auth-middleware.yaml`, attached in each Ingress's `traefik.ingress.kubernetes.io/router.middlewares` annotation. Authentik itself, and the apps that use Authentik as an SSO *option* on top of their own accounts (Vaultwarden, Nextcloud, Immich), are the exceptions.

ArgoCD at `argocd.sandstorm.chat` is additionally behind the `lan-only` middleware: it can deploy anything to the cluster, so it is reachable from the LAN and Tailscale only and returns 403 to the internet before any other middleware runs.

The full published-URL table, logins and port-forward recipes are in [docs/RUNDOWN.md](docs/RUNDOWN.md) and [docs/access-procedures.md](docs/access-procedures.md).

## Docs

| File | What it covers |
|---|---|
| [docs/RUNDOWN.md](docs/RUNDOWN.md) | Day-to-day cluster operation: published services, adding a person, the torrent stack and VPN, `/data` layout, books, music, backups, edge security, breakage response |
| [docs/access-procedures.md](docs/access-procedures.md) | Access paths only: service URLs, SSH, kubeconfig, credential locations, emergency bypasses, restore procedure |
| [docs/kindle-koreader-setup.md](docs/kindle-koreader-setup.md) | Jailbroken Kindle + KOReader against Calibre-Web-Automated |
| [docs/doctor-log.md](docs/doctor-log.md) | Incident journal: symptom, root cause, fix, prevention — for every failure the cluster has seen |
| [docs/adr/](docs/adr/) | Architecture decision records — why a thing was decided, kept next to the decision rather than in a commit message |
| [docs/recovery/](docs/recovery/) | Exported Navidrome favourites and the script that restores them |
| [docs/agents/](docs/agents/) | Conventions for agents working in this repo — issue tracker, triage labels, domain docs. See also [AGENTS.md](AGENTS.md) |

## Scripts

These exist because they cannot be GitOps.

| Script | Why it is not a manifest |
|---|---|
| `scripts/bootstrap-argocd.sh` | Applies `apps/argocd/`, which ArgoCD does not manage. Run after any change there |
| `scripts/setup-image-updater-key.sh` | Mints the deploy key ArgoCD Image Updater uses to push tag bumps back here |
| `scripts/install-smartctl-exporter.sh` | Installs an exporter on the Proxmox host and the NAS — LXC 200 has no block devices, so no pod can read the disks |
| `scripts/restore.sh` | Disaster recovery: etcd snapshot, Postgres dumps, Borg. Destroys current state; read it before running it |

## Two Failure Modes That Keep Coming Back

Both are documented at length in [docs/RUNDOWN.md](docs/RUNDOWN.md), and both have cost hours:

- **NetworkPolicy egress to the API server.** k3s DNATs `10.43.0.1:443` to the node's own address *before* egress policy is evaluated, so a rule written against the Service CIDR matches nothing. Namespaces that need the API server also need an egress rule for `192.168.1.0/24:6443`.
- **Over-tight readiness probes.** A one-second timeout against a path that took five seconds emptied a Service's endpoints and looked like a networking fault for hours. Probes here use generous timings on purpose, and a new probe gets verified against the real endpoint — `kubectl exec` in and `curl` it — before it is committed.
