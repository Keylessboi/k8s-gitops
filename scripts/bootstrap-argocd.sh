#!/usr/bin/env bash
# Install or upgrade ArgoCD, then apply the bootstrap manifests.
#
# apps/argocd is deliberately EXCLUDED from the ApplicationSet's git generator -
# ArgoCD cannot be the thing that reconciles the definition of ArgoCD. The
# consequence is that nothing applies these files automatically: edit them,
# commit them, and the cluster keeps running whatever was applied last.
#
# That is not theoretical. The cluster ran a stale ApplicationSet for a full day
# after CreateNamespace=true was removed from it in git, and argocd-cm changes
# take effect only after the components that read them are restarted.
#
# Run this after ANY change under apps/argocd/, and to apply a new
# ARGOCD_VERSION. Renovate opens a PR when ArgoCD releases; merging it deploys
# nothing until someone runs this script.
set -euo pipefail

cd "$(dirname "$0")/.."

# Bump together with KUSTOMIZE_VERSION / HELM_VERSION in
# .github/workflows/validate.yaml (hack/tool-versions.sh at this tag).
# renovate: datasource=github-releases depName=argoproj/argo-cd
ARGOCD_VERSION=v3.5.4
# Rollback: ARGOCD_VERSION_OVERRIDE=v2.12.3 ./scripts/bootstrap-argocd.sh
ARGOCD_VERSION="${ARGOCD_VERSION_OVERRIDE:-$ARGOCD_VERSION}"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Everything is applied server-side under two dedicated field managers, never
# kubectl's default. A server-side apply takes over fields owned by
# kubectl-client-side-apply and then DELETES whatever its manifest omits: run
# install.yaml first and it wipes kustomize.buildOptions (every helm app goes
# to ComparisonError), the batch_Job health check, server.insecure,
# controller.diff.server.side and every notification trigger. So the overlays
# are applied first, to be owned by homelab-bootstrap before install.yaml runs.
# Never put a key in the overlays that install.yaml also sets: the two managers
# would flip it on every run.
#
# Server-side is required anyway: v3's ApplicationSet CRD is larger than the
# 256 KiB last-applied annotation that client-side apply writes.
ssa() { kubectl apply --server-side --force-conflicts "$@"; }
CMS=(-f apps/argocd/argocd-cm.yaml
     -f apps/argocd/argocd-cmd-params-cm.yaml
     -f apps/argocd/argocd-notifications-cm.yaml)
CRS=(-f apps/argocd/app-project.yaml
     -f apps/argocd/root-applicationset.yaml
     -f apps/argocd/ingress.yaml)
# Not apps/argocd/networkpolicy.yaml: it carries no namespace.

kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
ssa --field-manager=homelab-bootstrap "${CMS[@]}"

# A registry outage must not be able to take down the control plane.
# install.yaml ships imagePullPolicy: Always, so kubelet contacts the registry
# on every pod start even when the image is already in containerd's store.
# During a quay.io outage (HTTP 504) that left the controller, server and
# repo-server in ImagePullBackOff - GitOps halted - with the image local.
# The tag is pinned, so IfNotPresent cannot run a stale image.
curl -fsSL "$INSTALL_URL" \
  | sed 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/' \
  | ssa -n argocd --field-manager=argocd-install -f -
kubectl wait --for=condition=Established --timeout=120s \
  crd/applications.argoproj.io crd/applicationsets.argoproj.io crd/appprojects.argoproj.io

ssa --field-manager=homelab-bootstrap "${CMS[@]}" "${CRS[@]}"

# Config is read at startup, and a config-only run changes no pod spec.
kubectl -n argocd rollout restart \
  deploy/argocd-server deploy/argocd-repo-server \
  deploy/argocd-applicationset-controller deploy/argocd-notifications-controller \
  sts/argocd-application-controller
for r in deploy/argocd-redis deploy/argocd-dex-server deploy/argocd-repo-server \
         deploy/argocd-server deploy/argocd-applicationset-controller \
         deploy/argocd-notifications-controller sts/argocd-application-controller; do
  kubectl -n argocd rollout status "$r" --timeout=300s
done

echo "bootstrap applied (${ARGOCD_VERSION})"
