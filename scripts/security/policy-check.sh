#!/usr/bin/env bash
# Run the policy-as-code checks over rendered manifests.
#
#   scripts/security/policy-check.sh RENDERED_DIR
#
# RENDERED_DIR comes from scripts/security/render-all.sh. Uses $CONFTEST or
# conftest on PATH. Only approved, signed register entries reach the
# policies (scripts/security/registers.py data).
set -euo pipefail
rendered="${1:?usage: policy-check.sh RENDERED_DIR}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
python3 scripts/security/registers.py data "$work/registers.json"
"${CONFTEST:-conftest}" verify --policy policy --no-color
"${CONFTEST:-conftest}" test --combine --all-namespaces --no-color \
  --policy policy --data "$work/registers.json" "$rendered"/*.yaml
