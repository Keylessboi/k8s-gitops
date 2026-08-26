#!/usr/bin/env bash
# Apply the ArgoCD bootstrap manifests.
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
# Run this after ANY change under apps/argocd/.
set -euo pipefail

cd "$(dirname "$0")/.."

kubectl apply -f apps/argocd/app-project.yaml
kubectl apply -f apps/argocd/argocd-cm.yaml
kubectl apply -f apps/argocd/argocd-cmd-params-cm.yaml
kubectl apply -f apps/argocd/root-applicationset.yaml
kubectl apply -f apps/argocd/ingress.yaml

# argocd-cm is read at startup by the components that consume it:
# kustomize.buildOptions by the repo-server, diff settings by the controller.
# A registry outage must not be able to take down the control plane.
#
# ArgoCD ships with imagePullPolicy: Always, so kubelet contacts the registry on
# every pod start even when the image is already in containerd's store. During a
# quay.io outage (HTTP 504 on the manifest) that meant restarting ArgoCD left
# the application controller, server and repo-server all stuck in
# ImagePullBackOff - GitOps halted - despite the exact image being local.
# IfNotPresent uses the cached copy. The tag is pinned, so this does not risk
# running a stale image.
for r in statefulset/argocd-application-controller deployment/argocd-server deployment/argocd-repo-server; do
  kubectl patch "$r" -n argocd --type json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' >/dev/null
done

# argocd-server reads server.insecure at startup, so it needs restarting too.
kubectl rollout restart deploy/argocd-server -n argocd
kubectl rollout restart deploy/argocd-repo-server -n argocd
kubectl rollout restart sts/argocd-application-controller -n argocd

kubectl rollout status deploy/argocd-repo-server -n argocd --timeout=180s
kubectl rollout status sts/argocd-application-controller -n argocd --timeout=180s

echo "bootstrap applied"
