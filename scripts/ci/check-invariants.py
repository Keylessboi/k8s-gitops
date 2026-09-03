#!/usr/bin/env python3
"""Repo invariants that YAML parsing and `kustomize build` cannot express.

Both checks here exist because docs/doctor-log.md records the same mistake
happening twice. The log's own header says a repeat means the prevention
failed - and in both cases the prevention was a sentence in a markdown file,
which only protects whoever reads it at the right moment. Written as a check,
it protects always.

    scripts/ci/check-invariants.py          # check the whole repo
    scripts/ci/check-invariants.py --list   # show what passed, too

Exit 0 clean, 1 on any finding.

CHECK 1 - wait-init on Jobs and CronJobs
    kube-router needs ~1-2s after a pod starts to program its per-pod policy
    chains. Until then, egress the NetworkPolicy explicitly ALLOWS is REJECTed,
    which surfaces as "connection refused" rather than a timeout. Any pod whose
    first real action is a network call loses that race.

    It hit lidarr's maintenance CronJob on 2026-08-29. The entry ended "any Job
    that connects immediately needs the same treatment." Nobody applied it to
    pg_dump, which then failed three consecutive backup runs five days later.

CHECK 2 - NetworkPolicy declared on both sides
    A cross-namespace flow needs an egress rule in the source namespace AND an
    ingress rule in the destination. Declaring one side yields a policy that
    reads correct and drops traffic. This has bitten three times: the remux
    outpost, octo's egress to vpn:8888 (where the VPN side had always allowed
    the port and the downloads side never opened it), and the monitoring
    namespace's probes.
"""
from __future__ import annotations

import argparse
import pathlib
import sys

import yaml

REPO = pathlib.Path(__file__).resolve().parents[2]
APPS = REPO / "apps"

# Opt out with this annotation plus a reason. Fail-by-default with a documented
# escape hatch beats a check people delete the first time it is inconvenient.
SKIP_ANNOTATION = "homelab/no-wait-init"

NS_LABEL = "kubernetes.io/metadata.name"

BASELINE = pathlib.Path(__file__).resolve().parent / "wait-init-baseline.txt"


def load_baseline() -> set[str]:
    """Names exempted because they predate this check. See the file's header."""
    if not BASELINE.exists():
        return set()
    out = set()
    for line in BASELINE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line)
    return out


class DuplicateKeyLoader(yaml.SafeLoader):
    """SafeLoader that REJECTS duplicate mapping keys.

    PyYAML accepts them silently and keeps the last value. Go's yaml - which is
    what kustomize, ArgoCD and the API server all use - refuses outright with
    `mapping key "x" already defined at line N`.

    That difference is not academic. On 2026-09-03 a duplicated `protocol: TCP`
    in apps/lidarr/networkpolicy.yaml passed a local
    `yaml.safe_load_all` check, was pushed, and parked the lidarr Application
    at ComparisonError - which does not fail loudly: auto-sync keeps reporting
    the last good state, so the app simply stops updating until somebody
    notices. Validating with the same strictness as the consumer is the whole
    point.
    """


def _no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping", node.start_mark,
                f"found duplicate key {key!r}", key_node.start_mark)
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates)


def check_duplicate_keys(findings: list[str], passes: list[str]) -> None:
    import subprocess
    try:
        tracked = subprocess.run(
            ["git", "ls-files", "*.yaml", "*.yml"],
            cwd=REPO, capture_output=True, text=True, check=True).stdout.split()
    except Exception:
        tracked = [str(p.relative_to(REPO)) for p in REPO.rglob("*.yaml")
                   if "/charts/" not in str(p) and "/.git/" not in str(p)]

    for rel in sorted(tracked):
        path = REPO / rel
        if not path.exists() or "/charts/" in rel:
            continue
        try:
            with path.open(encoding="utf-8") as fh:
                list(yaml.load_all(fh, Loader=DuplicateKeyLoader))
            passes.append(f"{rel} has no duplicate keys")
        except yaml.constructor.ConstructorError as exc:
            findings.append(
                f"{rel}: {exc.problem} at {exc.problem_mark}\n"
                f"    PyYAML accepts this and keeps the last value; Go's yaml -\n"
                f"    kustomize, ArgoCD and the API server - refuses it. The\n"
                f"    Application parks at ComparisonError and silently stops\n"
                f"    syncing while still reporting the last good state."
            )
        except Exception:
            # Anything else is the yaml-parse job's business, not this check's.
            pass


def load_docs(path: pathlib.Path):
    try:
        with path.open(encoding="utf-8") as fh:
            return [d for d in yaml.safe_load_all(fh) if isinstance(d, dict)]
    except Exception as exc:  # noqa: BLE001 - a parse error is the other job's
        print(f"  (skipped unparseable {path.relative_to(REPO)}: {exc})")
        return []


def app_namespace(app_dir: pathlib.Path) -> str | None:
    """The namespace an app's resources land in.

    Resources usually omit `namespace:` and inherit it from the app's
    namespace.yaml, so reading only the resource is not enough.
    """
    for path in sorted(app_dir.glob("*.yaml")):
        for doc in load_docs(path):
            if doc.get("kind") == "Namespace":
                return (doc.get("metadata") or {}).get("name")
    kz = app_dir / "kustomization.yaml"
    if kz.exists():
        for doc in load_docs(kz):
            if doc.get("namespace"):
                return doc["namespace"]
    return None


def pod_spec_of(doc: dict) -> dict | None:
    kind = doc.get("kind")
    spec = doc.get("spec") or {}
    if kind == "Job":
        return ((spec.get("template") or {}).get("spec")) or None
    if kind == "CronJob":
        job = (spec.get("jobTemplate") or {}).get("spec") or {}
        return ((job.get("template") or {}).get("spec")) or None
    return None


def check_wait_init(findings: list[str], passes: list[str]) -> None:
    baseline = load_baseline()
    seen_in_baseline: set[str] = set()
    for path in sorted(APPS.rglob("*.yaml")):
        if "/charts/" in str(path):
            continue
        for doc in load_docs(path):
            if doc.get("kind") not in ("Job", "CronJob"):
                continue
            meta = doc.get("metadata") or {}
            name = meta.get("name", "<unnamed>")
            rel = path.relative_to(REPO)

            # The annotation may sit on the object or on the pod template.
            anns = dict(meta.get("annotations") or {})
            pod = pod_spec_of(doc) or {}
            tmpl_meta = {}
            if doc.get("kind") == "Job":
                tmpl_meta = ((doc.get("spec") or {}).get("template") or {}).get("metadata") or {}
            else:
                jt = ((doc.get("spec") or {}).get("jobTemplate") or {}).get("spec") or {}
                tmpl_meta = (jt.get("template") or {}).get("metadata") or {}
            anns.update(dict(tmpl_meta.get("annotations") or {}))

            if SKIP_ANNOTATION in anns:
                passes.append(f"{rel}:{name} opted out ({anns[SKIP_ANNOTATION]})")
                continue

            inits = pod.get("initContainers") or []
            if any(str(c.get("name", "")).startswith("wait-") for c in inits):
                passes.append(f"{rel}:{name} has a wait-* init")
                continue

            if name in baseline:
                seen_in_baseline.add(name)
                passes.append(f"{rel}:{name} baselined (pre-existing debt)")
                continue

            findings.append(
                f"{rel}: {doc['kind']}/{name} has no wait-* initContainer.\n"
                f"    kube-router programs per-pod policy ~1-2s after start; until then\n"
                f"    allowed egress is REJECTed as 'connection refused'. This cost three\n"
                f"    consecutive pg_dump runs on 2026-09-03.\n"
                f"    Add a wait-* initContainer, or annotate with\n"
                f"      {SKIP_ANNOTATION}: \"why this pod makes no early network call\""
            )

    # A baseline entry with nothing to exempt is stale - the job was fixed or
    # deleted. Failing on it is what stops the baseline silently growing into a
    # permanent amnesty.
    for stale in sorted(baseline - seen_in_baseline):
        findings.append(
            f"scripts/ci/wait-init-baseline.txt lists '{stale}', but no Job or\n"
            f"    CronJob by that name is missing a wait-* init any more.\n"
            f"    Delete that line - the debt is paid."
        )


def check_netpol_pairs(findings: list[str], passes: list[str]) -> None:
    # namespace -> {"egress_to": {ns...}, "ingress_from": {ns...}}
    graph: dict[str, dict[str, set]] = {}

    def peers(rule_list, key):
        out = set()
        for rule in rule_list or []:
            for peer in rule.get(key) or []:
                sel = (peer.get("namespaceSelector") or {}).get("matchLabels") or {}
                if NS_LABEL in sel:
                    out.add(sel[NS_LABEL])
        return out

    for app_dir in sorted(p for p in APPS.iterdir() if p.is_dir()):
        own_ns = app_namespace(app_dir)
        for path in sorted(app_dir.glob("*.yaml")):
            for doc in load_docs(path):
                if doc.get("kind") != "NetworkPolicy":
                    continue
                ns = (doc.get("metadata") or {}).get("namespace") or own_ns
                if not ns:
                    continue
                spec = doc.get("spec") or {}
                entry = graph.setdefault(ns, {"egress_to": set(), "ingress_from": set()})
                entry["egress_to"] |= peers(spec.get("egress"), "to")
                entry["ingress_from"] |= peers(spec.get("ingress"), "from")

    for src, data in sorted(graph.items()):
        for dst in sorted(data["egress_to"]):
            if dst == src:
                continue
            if dst not in graph:
                # No policy at all in the destination means nothing is denied
                # there, so the flow works. Worth knowing, not worth failing.
                passes.append(f"{src} -> {dst}: destination has no NetworkPolicy (open)")
                continue
            if src in graph[dst]["ingress_from"]:
                passes.append(f"{src} -> {dst}: declared on both sides")
            else:
                findings.append(
                    f"{src} declares egress to '{dst}', but '{dst}' has no matching\n"
                    f"    ingress rule allowing '{src}'. A cross-namespace flow needs BOTH\n"
                    f"    sides; one side alone reads correct and drops traffic.\n"
                    f"    Fix: add a namespaceSelector for '{src}' to the ingress rules in\n"
                    f"    apps/{dst}/networkpolicy.yaml"
                )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true", help="also print what passed")
    args = ap.parse_args()

    findings: list[str] = []
    passes: list[str] = []

    check_duplicate_keys(findings, passes)
    check_wait_init(findings, passes)
    check_netpol_pairs(findings, passes)

    if args.list:
        print(f"--- {len(passes)} checks passed ---")
        for p in passes:
            print(f"  ok  {p}")
        print()

    if not findings:
        print(f"invariants: OK ({len(passes)} checks passed)")
        return 0

    print(f"invariants: {len(findings)} finding(s)\n")
    for f in findings:
        print(f"::error::{f.splitlines()[0]}")
        print(f"  {f}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
