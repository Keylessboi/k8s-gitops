#!/usr/bin/env python3
"""Check the SSP against the MODERATE baseline and regenerate its indexes.

  ssp-index.py check     every baseline control has exactly one complete section,
                         and every gap is traced to a POA&M item
  ssp-index.py write     also rewrite the generated blocks in 02-tailoring.md
  ssp-index.py gaps      print every gap definition as TSV (id, control, text)

Run from the repository root. Exits 1 if the check fails.
"""
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path("docs/security")
SSP = ROOT / "ssp"
TAILORING = ROOT / "02-tailoring.md"
POAM = ROOT / "04-poam.md"

DISPOSITIONS = [
    "Implemented",
    "Partially implemented",
    "Planned",
    "Inherited",
    "Alternative implementation",
    "Not applicable",
]
PARTS = ["**Implementation.**", "**Evidence.**", "**Gaps.**", "**Related.**"]
FAMILIES = {
    "AC": "Access Control", "AT": "Awareness and Training",
    "AU": "Audit and Accountability", "CA": "Assessment, Authorization, and Monitoring",
    "CM": "Configuration Management", "CP": "Contingency Planning",
    "IA": "Identification and Authentication", "IR": "Incident Response",
    "MA": "Maintenance", "MP": "Media Protection",
    "PE": "Physical and Environmental Protection", "PL": "Planning",
    "PS": "Personnel Security", "RA": "Risk Assessment",
    "SA": "System and Services Acquisition", "SC": "System and Communications Protection",
    "SI": "System and Information Integrity", "SR": "Supply Chain Risk Management",
}
HEAD = re.compile(r"^### ([A-Z]{2}-\d+(?:\(\d+\))?) (.+)$")
GAP = re.compile(r"^\s*[-*] (?:`(G-[A-Z]{2}-\d+)`|\*\*(G-[A-Z]{2}-\d+)\.?\*\*):?\s*(.*)$")


def baseline():
    rows = []
    for line in (SSP / "baseline-moderate.tsv").read_text().splitlines():
        if line and not line.startswith("#"):
            cid, title, base = line.split("\t")
            rows.append((cid, title, base))
    return rows


def sections():
    out = []
    for path in sorted(SSP.glob("*.md")):
        if path.name == "README.md":
            continue
        cur = None
        for line in path.read_text().splitlines():
            m = HEAD.match(line)
            if m:
                cur = {"id": m[1], "title": m[2], "file": path.name, "body": []}
                out.append(cur)
            elif cur is not None:
                if line.startswith(("# ", "## ", "### ")):
                    cur = None
                else:
                    cur["body"].append(line)
    for s in out:
        body = "\n".join(s["body"])
        m = re.search(r"^\| \*\*Disposition\*\* \| (.+?) \|\s*$", body, re.M)
        s["disposition"] = m[1].strip() if m else ""
        s["kind"] = next((d for d in DISPOSITIONS if s["disposition"].startswith(d)), "")
        s["missing"] = [p.strip("*.") for p in PARTS if p not in body]
        s["gaps"] = [(g[1] or g[2], g[3]) for g in map(GAP.match, s["body"]) if g]
        impl = body.split("**Implementation.**", 1)[-1].split("**Evidence.**", 1)[0]
        s["implementation"] = " ".join(impl.split())
    return out


def check(base, secs):
    problems = []
    want = {cid for cid, _, _ in base}
    seen = collections.Counter(s["id"] for s in secs)
    for cid, _, _ in base:
        if seen[cid] == 0:
            problems.append(f"{cid}: no section")
        elif seen[cid] > 1:
            problems.append(f"{cid}: {seen[cid]} sections")
    for s in secs:
        where = f"{s['file']} {s['id']}"
        if s["id"] not in want:
            problems.append(f"{where}: not in the MODERATE baseline")
        if not s["kind"]:
            problems.append(f"{where}: disposition {s['disposition']!r} is not one of {DISPOSITIONS}")
        if s["missing"]:
            problems.append(f"{where}: missing {', '.join(s['missing'])}")
    gap_ids = collections.Counter(g for s in secs for g, _ in s["gaps"])
    problems += [f"{g}: defined {n} times" for g, n in gap_ids.items() if n > 1]
    if POAM.exists():
        traced = set(re.findall(r"G-[A-Z]{2}-\d+", POAM.read_text()))
        problems += [f"{g}: not traced to an item in {POAM}" for g in gap_ids if g not in traced]
    return problems


def first_sentence(text, limit=220):
    text = re.sub(r"\*\*[a-z0-9.()]+\*\*\s*", "", text).strip()
    m = re.match(r"(.+?[.;])(\s|$)", text)
    s = m[1] if m else text
    return s if len(s) <= limit else s[: limit - 1].rstrip() + "…"


def link(s):
    return f"[{s['id']}](ssp/{s['file']}#{anchor(s)})"


def anchor(s):
    a = f"{s['id']} {s['title']}".lower()
    a = re.sub(r"[^\w\- ]", "", a)
    return a.replace(" ", "-")


def blocks(base, secs):
    by_id = {s["id"]: s for s in secs}
    order = [by_id[c] for c, _, _ in base if c in by_id]

    fam = collections.OrderedDict((f, collections.Counter()) for f in FAMILIES)
    for s in order:
        fam[s["id"][:2]][s["kind"]] += 1
    short = ["Implemented", "Partially implemented", "Planned", "Inherited",
             "Alternative implementation", "Not applicable"]
    rows = ["| Family | Controls | Impl. | Partial | Planned | Inherited | Alt. | N/A |",
            "|---|---|---|---|---|---|---|---|"]
    tot = collections.Counter()
    for f, c in fam.items():
        n = sum(c.values())
        rows.append(f"| [{f}](ssp/{f.lower()}.md) {FAMILIES[f]} | {n} | "
                    + " | ".join(str(c[k] or "—") for k in short) + " |")
        tot.update(c)
    rows.append(f"| **Total** | **{sum(tot.values())}** | "
                + " | ".join(f"**{tot[k]}**" for k in short) + " |")
    summary = "\n".join(rows)

    na = ["| Control | Title | Why it does not apply here |", "|---|---|---|"]
    na += [f"| {link(s)} | {s['title']} | {first_sentence(s['implementation'])} |"
           for s in order if s["kind"] == "Not applicable"]

    inh = ["| Control | Title | Disposition |", "|---|---|---|"]
    inh += [f"| {link(s)} | {s['title']} | {s['disposition']} |"
            for s in order if s["kind"] == "Inherited"]

    alt = ["| Control | Title | How the intent is met instead |", "|---|---|---|"]
    alt += [f"| {link(s)} | {s['title']} | {first_sentence(s['implementation'])} |"
            for s in order if s["kind"] == "Alternative implementation"]

    full = ["| Control | Title | Baseline | Disposition | Gaps |", "|---|---|---|---|---|"]
    bases = {c: b for c, _, b in base}
    full += [f"| {link(s)} | {s['title']} | {bases[s['id']]} | {s['disposition']} | "
             f"{', '.join(g for g, _ in s['gaps']) or '—'} |" for s in order]

    return {"summary": summary, "not-applicable": "\n".join(na),
            "inherited": "\n".join(inh), "alternative": "\n".join(alt),
            "full": "\n".join(full)}


def write(gen):
    text = TAILORING.read_text()
    for name, body in gen.items():
        pat = re.compile(rf"(<!-- BEGIN generated: {name} -->\n).*?(<!-- END generated: {name} -->)", re.S)
        if not pat.search(text):
            sys.exit(f"{TAILORING}: no generated block named {name!r}")
        text = pat.sub(lambda m: m[1] + body + "\n" + m[2], text)
    TAILORING.write_text(text)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    base, secs = baseline(), sections()
    if mode == "gaps":
        for s in secs:
            for g, text in s["gaps"]:
                print(f"{g}\t{s['id']}\t{text}")
        return
    problems = check(base, secs)
    for p in problems:
        print(p)
    done = len({s["id"] for s in secs} & {c for c, _, _ in base})
    print(f"{done}/{len(base)} baseline controls have a section; {len(problems)} problem(s)")
    if mode == "write":
        write(blocks(base, secs))
        print(f"rewrote the generated blocks in {TAILORING}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
