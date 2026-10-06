#!/usr/bin/env bash
# Scan every deployed image for known vulnerabilities (policy §17; HS-SUP-04).
#
#   scripts/security/scan-images.sh RENDERED_DIR OUT_DIR
#
# Reports HIGH and CRITICAL vulnerabilities that have a fixed version.
# Exits 1 if an internet-facing image has a fixable CRITICAL, the class that
# policy §17 gives 14 days. Uses $TRIVY or trivy on PATH. Writes
# OUT_DIR/summary.md and one JSON report per image.
set -uo pipefail
rendered="${1:?usage: scan-images.sh RENDERED_DIR OUT_DIR}"
out="${2:?usage: scan-images.sh RENDERED_DIR OUT_DIR}"
mkdir -p "$out"
python3 scripts/security/images.py "$rendered" > "$out/images.txt"
python3 scripts/security/images.py "$rendered" --published > "$out/published.txt"
i=0
while read -r img; do
  i=$((i + 1))
  "${TRIVY:-trivy}" image --quiet --scanners vuln --severity HIGH,CRITICAL \
    --ignore-unfixed --format json --output "$out/$i.json" "$img" \
    || echo "{\"ArtifactName\": \"$img\", \"ScanError\": true}" > "$out/$i.json"
done < "$out/images.txt"
python3 - "$out" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
published = set(out.joinpath("published.txt").read_text().split())
rows, fail = [], False
for f in sorted(out.glob("*.json"), key=lambda p: int(p.stem)):
    r = json.loads(f.read_text())
    img = r.get("ArtifactName", "?")
    if r.get("ScanError"):
        rows.append((img, "scan failed", "", ""))
        continue
    sev = {"CRITICAL": set(), "HIGH": set()}
    for res in r.get("Results") or []:
        for v in res.get("Vulnerabilities") or []:
            sev.setdefault(v["Severity"], set()).add(v["VulnerabilityID"])
    crit, high = len(sev["CRITICAL"]), len(sev["HIGH"])
    if crit or high:
        rows.append((img, crit, high, "yes" if img in published else ""))
    if crit and img in published:
        fail = True
rows.sort(key=lambda x: (str(x[1]) != "scan failed", -(x[1] if isinstance(x[1], int) else 0)))
lines = ["# Image vulnerability scan", "",
         "HIGH and CRITICAL vulnerabilities that have a fixed version (Trivy).", "",
         "| Image | Critical | High | Internet-facing |", "|---|---|---|---|"]
lines += [f"| `{a}` | {b} | {c} | {d} |" for a, b, c, d in rows]
lines += ["", f"{len(rows)} of {len(list(out.glob('*.json')))} images have findings."]
out.joinpath("summary.md").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(1 if fail else 0)
PY
