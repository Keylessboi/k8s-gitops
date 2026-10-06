#!/usr/bin/env bash
# Install pinned security tools into a directory, verifying each sha256.
#
#   scripts/security/install-tools.sh DIR TOOL...
#
# TOOL is kustomize, helm, conftest, polaris or trivy. Versions and
# checksums come from the environment (.github/workflows/security.yaml).
# A checksum mismatch stops the run.
set -euo pipefail
dir="${1:?usage: install-tools.sh DIR TOOL...}"
shift
mkdir -p "$dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { # url sha256 member
  curl -fsSL --retry 3 -o "$tmp/a.tgz" "$1"
  echo "$2  $tmp/a.tgz" | sha256sum -c --quiet
  tar -xzf "$tmp/a.tgz" -C "$tmp" "$3"
  install -m 0755 "$tmp/$3" "$dir/$(basename "$3")"
}

for tool in "$@"; do
  case "$tool" in
    kustomize) fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" "$KUSTOMIZE_SHA256" kustomize ;;
    helm) fetch "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" "$HELM_SHA256" linux-amd64/helm ;;
    conftest) fetch "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" "$CONFTEST_SHA256" conftest ;;
    polaris) fetch "https://github.com/FairwindsOps/polaris/releases/download/v${POLARIS_VERSION}/polaris_${POLARIS_VERSION}_linux_amd64.tar.gz" "$POLARIS_SHA256" polaris ;;
    trivy) fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" "$TRIVY_SHA256" trivy ;;
    *) echo "unknown tool: $tool" >&2; exit 1 ;;
  esac
  echo "installed $tool"
done
