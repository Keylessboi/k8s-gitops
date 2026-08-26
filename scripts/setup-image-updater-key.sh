#!/usr/bin/env bash
# Create the write credential ArgoCD Image Updater needs, and nothing more.
#
# Image Updater commits tag bumps back to this repo, so it needs push access.
# This mints a dedicated ed25519 deploy key scoped to this one repository
# rather than reusing a personal access token - if it ever leaks, the blast
# radius is this repo and nothing else, and revoking it is one click.
#
# Three steps: generate the pair, register the public half with GitHub as a
# write-enabled deploy key, and put the private half in Doppler, from where
# apps/doppler/dopplersecrets.yaml syncs it into the argocd namespace as
# `image-updater-git`.
#
# Requires `gh` already authenticated (it is) and `doppler` on PATH. The private
# key is written to a temp file and shredded on exit; it is never committed.
#
# Usage:  ./scripts/setup-image-updater-key.sh
set -euo pipefail

REPO="Keylessboi/k8s-gitops"
TITLE="argocd-image-updater (write)"
DOPPLER_PROJECT="kubernetes"
DOPPLER_CONFIG="prd"
DOPPLER_NAME="IMAGE_UPDATER_SSH_KEY"

command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
command -v doppler >/dev/null || { echo "doppler not found" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'find "$tmp" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$tmp"' EXIT

ssh-keygen -t ed25519 -N "" -C "argocd-image-updater@sandstorm.chat" -f "$tmp/key" >/dev/null

# Replace rather than duplicate, so re-running this rotates the key cleanly
# instead of leaving a trail of stale ones with push access.
old_id="$(gh api "repos/${REPO}/keys" --jq ".[] | select(.title == \"${TITLE}\") | .id" 2>/dev/null || true)"
if [ -n "$old_id" ]; then
  echo "Removing previous deploy key ${old_id}"
  gh api -X DELETE "repos/${REPO}/keys/${old_id}"
fi

gh api "repos/${REPO}/keys" \
  -f title="${TITLE}" \
  -f key="$(cat "$tmp/key.pub")" \
  -F read_only=false \
  --jq '"Deploy key added: id=\(.id) read_only=\(.read_only)"'

doppler secrets set "${DOPPLER_NAME}" \
  --project "${DOPPLER_PROJECT}" --config "${DOPPLER_CONFIG}" \
  --silent < "$tmp/key"

echo "Private key stored in Doppler as ${DOPPLER_NAME} (${DOPPLER_PROJECT}/${DOPPLER_CONFIG})."
echo "The Doppler operator syncs it to secret image-updater-git in the argocd namespace within ~5 minutes."
