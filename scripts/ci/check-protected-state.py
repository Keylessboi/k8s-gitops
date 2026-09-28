#!/usr/bin/env python3
"""Fail if a rendered app would let ArgoCD delete state on its own.

    kustomize build --enable-helm apps/<app> | scripts/ci/check-protected-state.py <app>

Every PersistentVolumeClaim, PersistentVolume, Namespace and CNPG Cluster in
the render must carry `argocd.argoproj.io/sync-options` containing both
Prune=false and Delete=false. components/protect-state adds them; this catches
an app that stops including it, or a Helm chart whose own annotation replaces
it. See ADR-0012.

Exit 0 when clean, 1 with one ::error line per unprotected object.
"""
import sys

import yaml

PROTECTED = {
    ("", "PersistentVolumeClaim"),
    ("", "PersistentVolume"),
    ("", "Namespace"),
    ("postgresql.cnpg.io", "Cluster"),
}
REQUIRED = {"Prune=false", "Delete=false"}


class Loader(yaml.SafeLoader):
    """SafeLoader that reads a bare `=` as the string it is.

    YAML 1.1 tags an unquoted `=` as tag:yaml.org,2002:value, which SafeLoader
    cannot construct, and at least one chart here renders one in its args.
    """


Loader.add_constructor("tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node))


def group_of(api_version: str) -> str:
    return api_version.split("/")[0] if "/" in api_version else ""


def main() -> int:
    app = sys.argv[1] if len(sys.argv) > 1 else "?"
    bad = 0
    for doc in yaml.load_all(sys.stdin, Loader=Loader):
        if not isinstance(doc, dict):
            continue
        key = (group_of(doc.get("apiVersion", "")), doc.get("kind", ""))
        if key not in PROTECTED:
            continue
        meta = doc.get("metadata") or {}
        options = (meta.get("annotations") or {}).get("argocd.argoproj.io/sync-options", "")
        missing = REQUIRED - {o.strip() for o in options.split(",")}
        if missing:
            bad += 1
            print(
                f"::error::{app}: {key[1]} {meta.get('namespace', '')}/{meta.get('name')} "
                f"lacks {', '.join(sorted(missing))} - include components/protect-state"
            )
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
