#!/usr/bin/env python3
"""List the container images in rendered manifests, one per line.

  images.py RENDERED_DIR [--published]

--published limits the list to namespaces that have an Ingress, the
internet-facing images that policy §17 gives the shortest patch time.
Helm test hooks are skipped: the reconciler never deploys them.
"""
import pathlib
import sys

import yaml

yaml.SafeLoader.add_constructor("tag:yaml.org,2002:value", yaml.SafeLoader.construct_yaml_str)


def pod_spec(o):
    k, s = o.get("kind"), o.get("spec") or {}
    if k == "Pod":
        return s
    if k in ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"):
        return (s.get("template") or {}).get("spec")
    if k == "CronJob":
        return (((s.get("jobTemplate") or {}).get("spec") or {}).get("template") or {}).get("spec")
    return None


def main():
    root = pathlib.Path(sys.argv[1])
    published_only = "--published" in sys.argv
    images, published = {}, set()
    for f in sorted(root.glob("*.yaml")):
        for o in yaml.safe_load_all(f.read_text()):
            if not isinstance(o, dict):
                continue
            md = o.get("metadata") or {}
            if "test" in (md.get("annotations") or {}).get("helm.sh/hook", ""):
                continue
            if o.get("kind") == "Ingress":
                published.add(md.get("namespace"))
            spec = pod_spec(o)
            for c in (spec or {}).get("containers", []) + (spec or {}).get("initContainers", []):
                images.setdefault(c["image"], set()).add(md.get("namespace"))
    for img in sorted(images):
        if not published_only or images[img] & published:
            print(img)


if __name__ == "__main__":
    main()
