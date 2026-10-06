#!/usr/bin/env bash
# Render every apps/* kustomization into one file per app, for policy checks.
#
#   scripts/security/render-all.sh OUTDIR
#
# Uses whatever kustomize and helm are on PATH. CI puts the pinned versions
# there (validate.yaml, KUSTOMIZE_VERSION / HELM_VERSION); use the same ones
# locally, or a rendered chart can differ from what ArgoCD applies.
set -uo pipefail
out="${1:?usage: render-all.sh OUTDIR}"
mkdir -p "$out"
rc=0
for dir in apps/*/; do
  name="$(basename "$dir")"
  [ -f "${dir}kustomization.yaml" ] || continue
  for attempt in 1 2 3; do
    if "${KUSTOMIZE:-kustomize}" build --enable-helm --helm-command "${HELM:-helm}" "$dir" >"$out/$name.yaml" 2>"$out/$name.err"; then
      rm -f "$out/$name.err"
      break
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "render failed: $name (see $out/$name.err)" >&2
      rm -f "$out/$name.yaml"
      rc=1
      break
    fi
    rm -rf "${dir}charts"
    sleep $((attempt * 5))
  done
done
exit "$rc"
