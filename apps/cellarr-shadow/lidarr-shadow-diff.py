#!/usr/bin/env python3
"""Compare a live Lidarr with a shadow cellarr migrated from it: same data, by id.

    scripts/lidarr-shadow-diff LIDARR_URL CELLARR_URL [--lidarr-key K] [--cellarr-key K]
                               [--sample N] [--no-albums] [--max-shown N] [--report FILE]
                               [--known] [--show-expected]

Keys default to $LIDARR_API_KEY / $CELLARR_API_KEY. Only GET requests are made, to
both: it is safe to run against production. Compares what a cutover has to preserve:

  artists       id, MusicBrainz id, name, path, monitoring, profiles
  albums        id, MusicBrainz id, title, artist, monitoring, the pinned pressing
                and the pressings' ids, and how many track files each has
                (skipped with --no-albums: the full list is Lidarr's heaviest call)
  track files   per artist (all, or --sample N artists): id, path, album, quality
  wanted        the missing-album ids
  queue         the download ids in flight
  config        quality/metadata profile ids and names, root folders, indexers,
                download clients (implementation and category)

The live library keeps changing while this runs (a grab, an import), so a handful
of differences in the queue or the newest albums is expected; anything in the
config, artists or track files is not. Exit status 1 when anything differs.

--known classifies a fixed list of understood differences as EXPECTED: they are
reported in a separate section and do not affect the exit status. Matched narrowly:
the whole queue section; indexer/download client implementation and category;
statistics.trackFileCount Lidarr None vs cellarr 0; the quality profile cutoff id;
a root folder id differing for the same path; album pressings that differ only in
which one is pinned. Anything else stays a DIFF. --known also compares the enabled
flags of indexers and download clients. --show-expected lists the expected lines
(default: only their counts). Without --known nothing is classified.
Self-test: python3 -I scripts/test_lidarr_shadow_diff.py
Standard library only.
"""
import argparse
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request


class Api:
    def __init__(self, base, key, name):
        self.base = base.rstrip("/") + "/api/v1"
        self.key = key
        self.name = name

    def get(self, path, timeout=300):
        req = urllib.request.Request(self.base + path, headers={"X-Api-Key": self.key})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    return json.loads(r.read() or b"null")
            except urllib.error.HTTPError as e:
                if e.code < 500 or attempt == 4:
                    raise SystemExit(f"{self.name} GET {path}: HTTP {e.code}")
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                if attempt == 4:
                    raise SystemExit(f"{self.name} GET {path}: {e}")
            time.sleep(5 * (attempt + 1))

    def paged(self, path):
        out, page = [], 1
        sep = "&" if "?" in path else "?"
        while True:
            body = self.get(f"{path}{sep}page={page}&pageSize=1000")
            out.extend(body.get("records") or [])
            if page * 1000 >= (body.get("totalRecords") or 0) or not body.get("records"):
                return out, body.get("totalRecords") or 0
            page += 1


class Report:
    def __init__(self, max_shown, known=False, show_expected=False):
        self.max_shown = max_shown
        self.known = known
        self.show_expected = show_expected
        self.sections = {}
        self.expected = {}

    def diff(self, section, message, expected=False):
        if expected and self.known:
            self.expected.setdefault(section, []).append(message)
            self.sections.setdefault(section, [])
            return
        self.sections.setdefault(section, []).append(message)

    def ok(self, section):
        self.sections.setdefault(section, [])

    def render(self):
        lines, bad = [], 0
        for section, items in self.sections.items():
            mark = "OK  " if not items else "DIFF"
            lines.append(f"{mark} {section}" + (f" ({len(items)})" if items else ""))
            for m in items[: self.max_shown]:
                lines.append(f"       {m}")
            if len(items) > self.max_shown:
                lines.append(f"       ... and {len(items) - self.max_shown} more")
            bad += len(items)
        n_exp = sum(len(v) for v in self.expected.values())
        if self.known:
            lines.append(f"EXPECTED ({n_exp}) known differences, not counted")
            for section, items in self.expected.items():
                lines.append(f"       {section}: {len(items)}")
                if self.show_expected:
                    for m in items[: self.max_shown]:
                        lines.append(f"         {m}")
                    if len(items) > self.max_shown:
                        lines.append(f"         ... and {len(items) - self.max_shown} more")
        return "\n".join(lines), bad


def by_id(rows):
    return {r.get("id"): r for r in rows if isinstance(r, dict)}


def expected_field(section, f, va, vb):
    """Known, understood field differences (only honoured with --known)."""
    if f.endswith("statistics.trackFileCount") and va is None and vb == 0:
        return True
    if section == "/qualityprofile" and f == "cutoff":
        return True
    return False


ROOTFOLDER_DEFAULTS = ["defaultQualityProfileId", "defaultMetadataProfileId", "defaultMonitorOption",
                       "defaultNewItemMonitorOption", "defaultTags"]


def compare_rootfolders(report, live, shadow):
    a = {norm(r.get("path")): r for r in live}
    b = {norm(r.get("path")): r for r in shadow}
    for p in sorted(set(a) - set(b), key=str):
        report.diff("/rootfolder", f"path {p!r} only in Lidarr")
    for p in sorted(set(b) - set(a), key=str):
        report.diff("/rootfolder", f"path {p!r} only in cellarr")
    for p in sorted(set(a) & set(b), key=str):
        if a[p].get("id") != b[p].get("id"):
            report.diff("/rootfolder", f"path {p!r} id: Lidarr {a[p].get('id')!r}, cellarr {b[p].get('id')!r}", expected=True)
        for f in ROOTFOLDER_DEFAULTS:
            if a[p].get(f) != b[p].get(f):
                report.diff("/rootfolder", f"path {p!r} {f}: Lidarr {a[p].get(f)!r}, cellarr {b[p].get(f)!r}")
    report.ok("/rootfolder")


def compare_rows(report, section, live, shadow, fields):
    a, b = by_id(live), by_id(shadow)
    for i in sorted(set(a) - set(b), key=str):
        report.diff(section, f"id {i} only in Lidarr ({a[i].get(fields[0])!r})")
    for i in sorted(set(b) - set(a), key=str):
        report.diff(section, f"id {i} only in cellarr ({b[i].get(fields[0])!r})")
    for i in sorted(set(a) & set(b), key=str):
        for f in fields:
            va, vb = pick(a[i], f), pick(b[i], f)
            if norm(va) != norm(vb):
                report.diff(section, f"id {i} {f}: Lidarr {va!r}, cellarr {vb!r}",
                            expected=expected_field(section, f, va, vb))
    report.ok(section)


def pick(row, dotted):
    cur = row
    for part in dotted.split("."):
        cur = cur.get(part) if isinstance(cur, dict) else None
    return cur


def norm(v):
    if isinstance(v, str):
        return v.rstrip("/")
    return v


def field(item, name):
    for f in item.get("fields") or []:
        if f.get("name") == name:
            return f.get("value")
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("lidarr")
    ap.add_argument("cellarr")
    ap.add_argument("--lidarr-key", default=os.environ.get("LIDARR_API_KEY", ""))
    ap.add_argument("--cellarr-key", default=os.environ.get("CELLARR_API_KEY", ""))
    ap.add_argument("--sample", type=int, default=0, help="track files of N random artists (0 = all)")
    ap.add_argument("--no-albums", action="store_true",
                    help="skip the full album list (Lidarr's heaviest call) and the pressings")
    ap.add_argument("--max-shown", type=int, default=20)
    ap.add_argument("--report", help="also write the report here")
    ap.add_argument("--known", action="store_true",
                    help="classify known-expected differences as EXPECTED (exit status ignores them)")
    ap.add_argument("--show-expected", action="store_true", help="list the expected lines, not just counts")
    a = ap.parse_args()
    live = Api(a.lidarr, a.lidarr_key, "Lidarr")
    shadow = Api(a.cellarr, a.cellarr_key or a.lidarr_key, "cellarr")
    text, bad = run(a, live, shadow)
    print(text)
    if a.report:
        with open(a.report, "w") as fh:
            fh.write(text + "\n")
    sys.exit(1 if bad else 0)


def run(a, live, shadow):
    """Compare two Api-like objects; return (report text, number of DIFF lines)."""
    report = Report(a.max_shown, a.known, a.show_expected)
    started = time.time()

    # --- config -----------------------------------------------------------------
    for path, fields in [
        ("/qualityprofile", ["name", "cutoff", "upgradeAllowed"]),
        ("/metadataprofile", ["name"]),
        ("/rootfolder", ["path"] + ROOTFOLDER_DEFAULTS),
    ]:
        if path == "/rootfolder" and a.known:
            compare_rootfolders(report, live.get(path), shadow.get(path))
        else:
            compare_rows(report, path, live.get(path), shadow.get(path), fields)
    for path, key in [("/indexer", "implementation"), ("/downloadclient", "implementation")]:
        la = {i["name"]: i for i in live.get(path)}
        sh = {i["name"]: i for i in shadow.get(path)}
        for name in sorted(set(la) | set(sh)):
            if name not in sh:
                report.diff(path, f"{name!r} only in Lidarr")
            elif name not in la:
                report.diff(path, f"{name!r} only in cellarr")
            else:
                if la[name].get(key) != sh[name].get(key):
                    report.diff(path, f"{name!r} implementation: {la[name].get(key)!r} vs {sh[name].get(key)!r}",
                                  expected=True)
                if path == "/downloadclient" and field(la[name], "musicCategory") != field(sh[name], "musicCategory"):
                    report.diff(path, f"{name!r} category: {field(la[name], 'musicCategory')!r} vs {field(sh[name], 'musicCategory')!r}",
                                  expected=True)
                if a.known:
                    for flag in ("enable", "enableRss", "enableAutomaticSearch", "enableInteractiveSearch"):
                        if flag in la[name] and flag in sh[name] and la[name][flag] != sh[name][flag]:
                            report.diff(path, f"{name!r} {flag}: {la[name][flag]!r} vs {sh[name][flag]!r}")
        report.ok(path)

    # --- artists ----------------------------------------------------------------
    artists_live = live.get("/artist", timeout=600)
    artists_shadow = shadow.get("/artist", timeout=600)
    compare_rows(report, "artists", artists_live, artists_shadow, [
        "artistName", "foreignArtistId", "path", "monitored", "monitorNewItems",
        "qualityProfileId", "metadataProfileId", "statistics.trackFileCount",
    ])

    # --- albums -----------------------------------------------------------------
    if not a.no_albums:
        albums_live = live.get("/album", timeout=1800)
        albums_shadow = shadow.get("/album", timeout=1800)
        compare_rows(report, "albums", albums_live, albums_shadow, [
            "title", "foreignAlbumId", "artistId", "monitored", "anyReleaseOk",
            "statistics.trackFileCount",
        ])
        al, ash = by_id(albums_live), by_id(albums_shadow)
        for i in sorted(set(al) & set(ash), key=str):
            ra = {r["id"]: (r.get("foreignReleaseId"), r.get("monitored")) for r in al[i].get("releases") or []}
            rb = {r["id"]: (r.get("foreignReleaseId"), r.get("monitored")) for r in ash[i].get("releases") or []}
            if ra and rb and ra != rb:
                pin_a = [k for k, v in ra.items() if v[1]]
                pin_b = [k for k, v in rb.items() if v[1]]
                only_pin = ({k: v[0] for k, v in ra.items()} == {k: v[0] for k, v in rb.items()})
                report.diff("album pressings", f"album {i}: ids {sorted(ra)} pinned {pin_a} vs ids {sorted(rb)} pinned {pin_b}",
                            expected=only_pin)
        report.ok("album pressings")

    # --- track files ------------------------------------------------------------
    ids = [x["id"] for x in artists_live]
    if a.sample and a.sample < len(ids):
        ids = random.sample(ids, a.sample)
    for artist in ids:
        compare_rows(report, "track files",
                     live.get(f"/trackfile?artistId={artist}", timeout=300),
                     shadow.get(f"/trackfile?artistId={artist}", timeout=300),
                     ["path", "albumId", "quality.quality.name", "size"])

    # --- wanted and queue -------------------------------------------------------
    wl, wl_total = live.paged("/wanted/missing?sortKey=id&sortDirection=ascending&monitored=true")
    ws, ws_total = shadow.paged("/wanted/missing?sortKey=id&sortDirection=ascending&monitored=true")
    only_l = {r["id"] for r in wl} - {r["id"] for r in ws}
    only_s = {r["id"] for r in ws} - {r["id"] for r in wl}
    if wl_total != ws_total:
        report.diff("wanted/missing", f"total {wl_total} vs {ws_total}")
    for i in sorted(only_l)[:500]:
        report.diff("wanted/missing", f"album {i} wanted only in Lidarr")
    for i in sorted(only_s)[:500]:
        report.diff("wanted/missing", f"album {i} wanted only in cellarr")
    report.ok("wanted/missing")

    ql, _ = live.paged("/queue?includeUnknownArtistItems=true")
    qs, _ = shadow.paged("/queue?includeUnknownArtistItems=true")
    dl_l = {(r.get("downloadId") or "").lower() for r in ql} - {""}
    dl_s = {(r.get("downloadId") or "").lower() for r in qs} - {""}
    for d in sorted(dl_l - dl_s):
        report.diff("queue", f"download {d} only in Lidarr's queue", expected=True)
    for d in sorted(dl_s - dl_l):
        report.diff("queue", f"download {d} only in cellarr's queue", expected=True)
    report.ok("queue")

    text, bad = report.render()
    text += f"\n\n{bad} difference(s); {time.time() - started:.0f}s"
    return text, bad


if __name__ == "__main__":
    main()
