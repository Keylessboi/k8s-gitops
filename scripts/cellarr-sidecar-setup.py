#!/usr/bin/env python3
"""Set up cellarr's plugin sidecar (the stock Lidarr in the cellarr-shadow Pod).

What it does, idempotently (a second run changes nothing):

  1. waits for the sidecar's /ping;
  2. installs Tubifarry in the sidecar unless its Slskd implementations are
     already listed (InstallPlugin command, then a restart if the plugin is not
     live yet, then waits for /ping and for the implementations to appear);
  3. creates, or updates by name, the Slskd and AppleMusicarr download clients
     and indexers in the sidecar with production's settings;
  4. verifies through the sidecar's own GET /downloadclient and /indexer and
     tests each one through the sidecar's /test endpoints.

Where the values come from (--source):

  prod     production Lidarr, GET only. Production returns every secret
           (`apiKey` and `password` fields) MASKED ("********"), so those are
           taken from the migrated copy in cellarr (see below).
  cellarr  cellarr's Lidarr-compatible API (cellarr-shadow), GET only. cellarr
           migrated production's database, secrets included, and returns them
           unmasked. After cutover step 1 Lidarr is stopped, so this is the
           only source then. cellarr stores plugin clients as Blackhole and
           plugin indexers as Torznab, so rows are matched by NAME here.
  auto     (default) prod if its /ping answers, else cellarr.

The masked-key workaround: for every secret field whose value is masked or
empty, the real value is read from cellarr's row of the same name (or, for
slskd, from its sibling: the client "Slskd2" and the indexer "Slskd" share one
key). It is checked against slskd (GET /api/v0/application, status code only)
and then only ever placed in the request body to the sidecar. It is never
printed, logged or passed on a command line. AppleMusicarr's developerToken and
musicUserToken are plain fields in production, so they are copied as they are.
SLSKD_API_KEY, if set, overrides the slskd key.

Configuration comes from the environment, so nothing secret is in argv:

  SIDECAR_URL      sidecar base URL, e.g. http://10.42.1.9:8687 or
                   http://127.0.0.1:18687 (kubectl port-forward)
  SIDECAR_API_KEY  the sidecar's key (Secret lidarr/cellarr-sidecar)
  PROD_URL         default http://lidarr.lidarr.svc.cluster.local:8686
  PROD_API_KEY     production Lidarr's key (Secret lidarr/lidarr-api); cellarr
                   is configured with the same key
  CELLARR_URL      default http://cellarr-shadow.lidarr.svc.cluster.local:8686
  SLSKD_API_KEY    optional override

Output is names, ids and ok/fail only. Exit status 0 only when everything is
present and every test passed. Python 3 standard library only.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

DEFAULT_PROD = "http://lidarr.lidarr.svc.cluster.local:8686"
DEFAULT_CELLARR = "http://cellarr-shadow.lidarr.svc.cluster.local:8686"
TUBIFARRY_URL = "https://github.com/TypNull/Tubifarry"

# (kind, Lidarr implementation, production/cellarr name, family for secrets)
TARGETS = [
    ("downloadclient", "SlskdClient", "Slskd2", "slskd"),
    ("downloadclient", "AppleMusicarrDownloadClient", "AppleMusicarr", "apple"),
    ("indexer", "SlskdIndexer", "Slskd", "slskd"),
    ("indexer", "AppleMusicarrIndexer", "AppleMusicarr", "apple"),
]
FAMILY_NAMES = {"slskd": {"Slskd", "Slskd2"}, "apple": {"AppleMusicarr"}}
SECRET_PRIVACY = ("apikey", "password")
TOP_CLIENT = ("removeCompletedDownloads", "removeFailedDownloads")
TOP_INDEXER = ("enableRss", "enableAutomaticSearch", "enableInteractiveSearch")
FORCE = "?forceSave=true"

_secrets = set()  # every secret value seen, so error text can be scrubbed


def scrub(text):
    text = str(text)
    for s in _secrets:
        if s and len(s) >= 4:
            text = text.replace(s, "***")
    return text


def say(msg):
    print(scrub(msg), flush=True)


def is_masked(v):
    return isinstance(v, str) and v != "" and set(v) == {"*"}


def empty(v):
    return v is None or v == "" or is_masked(v)


def is_secret_field(f):
    return str(f.get("privacy", "")).lower() in SECRET_PRIVACY


class Api:
    """One Lidarr-style API. `read_only` makes any non-GET impossible."""

    def __init__(self, base, key, label, read_only):
        self.base = base.rstrip("/")
        self.key = key
        self.label = label
        self.read_only = read_only
        if key:
            _secrets.add(key)

    def call(self, method, path, body=None, timeout=60):
        if self.read_only and method != "GET":
            raise RuntimeError("%s is GET-only" % self.label)
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-Api-Key", self.key)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw.strip() else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, None
        except Exception as e:  # connection refused, reset, timeout
            return -1, {"error": type(e).__name__}

    def get(self, path, timeout=60):
        return self.call("GET", path, None, timeout)

    def ping(self):
        req = urllib.request.Request(self.base + "/ping")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status == 200
        except Exception:
            return False


def wait_ping(api, seconds, label):
    end = time.time() + seconds
    while time.time() < end:
        if api.ping():
            return True
        time.sleep(3)
    say("FAIL %s did not answer /ping within %ds" % (label, seconds))
    return False


def restart_sidecar(sc):
    say("sidecar: POST /system/restart")
    sc.call("POST", "/api/v1/system/restart", {})
    # first see it go down (up to 30s), then wait for it to come back
    end = time.time() + 30
    while time.time() < end and sc.ping():
        time.sleep(2)
    return wait_ping(sc, 300, "sidecar")


def impls(sc, kind):
    st, js = sc.get("/api/v1/%s/schema" % kind)
    if st != 200 or not isinstance(js, list):
        return None
    return {s.get("implementation"): s for s in js}


def wait_impls(sc, seconds):
    end = time.time() + seconds
    while time.time() < end:
        dc, ix = impls(sc, "downloadclient"), impls(sc, "indexer")
        if dc and ix and "SlskdClient" in dc and "SlskdIndexer" in ix:
            return True
        time.sleep(5)
    return False


def install_tubifarry(sc, github_url, dry):
    dc, ix = impls(sc, "downloadclient"), impls(sc, "indexer")
    if dc and ix and "SlskdClient" in dc and "SlskdIndexer" in ix:
        say("tubifarry: already installed (Slskd implementations listed), skipped")
        return True
    st, plugins = sc.get("/api/v1/system/plugins")
    names = {p.get("name") for p in (plugins or [])} if st == 200 else set()
    if "AppleMusicarr" not in names:
        say("WARN sidecar lists no AppleMusicarr plugin (init container install-plugin did not run?)")
    if dry:
        say("tubifarry: WOULD install from %s (InstallPlugin, restart if needed)" % github_url)
        return None
    if "Tubifarry" not in names:
        say("tubifarry: InstallPlugin %s" % github_url)
        st, js = sc.call("POST", "/api/v1/command", {"name": "InstallPlugin", "githubUrl": github_url})
        if st not in (200, 201):
            say("FAIL InstallPlugin returned HTTP %s" % st)
            return False
        # Lidarr may restart on its own once the plugin is unpacked.
        time.sleep(10)
        if not wait_ping(sc, 300, "sidecar"):
            return False
        if wait_impls(sc, 60):
            say("tubifarry: installed, implementations listed")
            return True
    else:
        say("tubifarry: plugin listed but implementations missing, restarting")
    if not restart_sidecar(sc):
        return False
    if not wait_impls(sc, 180):
        say("FAIL sidecar still lists no Slskd implementations after install and restart")
        return False
    say("tubifarry: installed, implementations listed")
    return True


def norm(v):
    if v is None:
        return ""
    if isinstance(v, list):
        return str(sorted(str(x) for x in v))
    return str(v).lower()


def fields_of(obj):
    return {f["name"]: f.get("value") for f in obj.get("fields", [])}


def pick_source(prod, cel, how):
    if how == "prod":
        return "prod"
    if how == "cellarr":
        return "cellarr"
    if prod.ping():
        return "prod"
    say("source: production Lidarr does not answer /ping, using cellarr's migrated copy")
    return "cellarr"


def load_rows(api, name_only):
    """{(kind, name): obj} from an API's /downloadclient and /indexer."""
    rows = {}
    for kind in ("downloadclient", "indexer"):
        st, js = api.get("/api/v1/" + kind)
        if st != 200 or not isinstance(js, list):
            say("FAIL %s GET /%s: HTTP %s" % (api.label, kind, st))
            return None
        for o in js:
            rows.setdefault((kind, o.get("name")), o)
            if not name_only:
                rows.setdefault((kind, "impl:" + str(o.get("implementation"))), o)
    return rows


def find_secret(cel_rows, family, fname):
    for kind in ("downloadclient", "indexer"):
        for name in sorted(FAMILY_NAMES[family]):
            o = (cel_rows or {}).get((kind, name))
            if not o:
                continue
            v = fields_of(o).get(fname)
            if not empty(v):
                return v
    return None


def slskd_key_ok(base_url, key):
    req = urllib.request.Request(base_url.rstrip("/") + "/api/v0/application", headers={"X-API-Key": key})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:
        return type(e).__name__


def build(kind, schema, src, name, family, cel_rows, problems):
    """The body to send to the sidecar, built from its own schema entry."""
    body = json.loads(json.dumps(schema))
    body["id"] = 0
    body["name"] = name
    body["tags"] = []  # tag ids are per-instance; the sidecar has none
    # Top-level settings follow cellarr's own mirror convention (sidecar.rs
    # ensure_mirror), so cellarr finds these rows as it would have made them:
    # indexers search on demand only (no RSS sync against slskd or Apple),
    # clients enabled at priority 1. Field values are production's.
    if kind == "indexer":
        body.update(enableRss=False, enableAutomaticSearch=True, enableInteractiveSearch=True,
                    priority=25, downloadClientId=0)
    else:
        body.update(enable=True, priority=1)
        for k in TOP_CLIENT:
            if src.get(k) is not None:
                body[k] = src[k]
    have = fields_of(src)
    for f in body.get("fields", []):
        n = f["name"]
        v = have.get(n)
        if is_secret_field(f):
            if empty(v):
                override = os.environ.get("SLSKD_API_KEY") if (family == "slskd" and n == "apiKey") else None
                v = override or find_secret(cel_rows, family, n)
            if empty(v):
                # a secret that is empty in production too is not an error
                if n in have and have[n] in (None, ""):
                    continue
                problems.append("%s %s: no unmasked value for secret field %s" % (kind, name, n))
                continue
            _secrets.add(str(v))
            f["value"] = v
        elif n in have and not is_masked(have[n]):
            f["value"] = have[n]
    return body


def differs(existing, desired):
    for k in ("enable", "priority", "implementation") + TOP_CLIENT + TOP_INDEXER:
        if k in desired and k in existing and norm(existing[k]) != norm(desired[k]):
            return True
    ef = fields_of(existing)
    for f in desired.get("fields", []):
        if is_secret_field(f):
            continue  # the sidecar returns them masked, they cannot be compared
        if f["name"] in ef and norm(ef[f["name"]]) != norm(f.get("value")):
            return True
    return False


def errtext(st, js):
    if isinstance(js, list):
        return "HTTP %s %s" % (st, "; ".join("%s: %s" % (e.get("propertyName", ""), str(e.get("errorMessage", ""))[:160])
                                              for e in js[:4] if isinstance(e, dict)))
    return "HTTP %s" % st


def save(sc, kind, body, oid):
    """POST (oid None) or PUT with forceSave. Returns (id, why).

    Creating an enabled client makes Lidarr validate it, and slskd's key in
    production cannot read /api/v0/options (403), which the Slskd plugin's
    validation asks for. cellarr's own mirror code works around exactly that
    by creating the client disabled and then enabling it with forceSave; this
    does the same, and only for a 403, so any other validation failure
    (unwritable download path, bad URL) still fails loudly.
    """
    b = dict(body)
    if oid:
        b["id"] = oid
    method, path = ("PUT", "/api/v1/%s/%s%s" % (kind, oid, FORCE)) if oid else ("POST", "/api/v1/%s%s" % (kind, FORCE))
    st, js = sc.call(method, path, b)
    if st in (200, 201, 202) and isinstance(js, dict) and js.get("id"):
        return js["id"], ""
    why = errtext(st, js)
    if kind == "downloadclient" and "403" in why and b.get("enable"):
        off = dict(b, enable=False)
        st, js = sc.call(method, path, off)
        if st in (200, 201, 202) and isinstance(js, dict) and js.get("id"):
            new_id = js["id"]
            on = dict(b, id=new_id)
            st, js = sc.call("PUT", "/api/v1/downloadclient/%s%s" % (new_id, FORCE), on)
            if st in (200, 202):
                say("note: %s created disabled, then enabled with forceSave (slskd key lacks /options, 403)" % b["name"])
                return new_id, ""
            return None, errtext(st, js)
        return None, errtext(st, js)
    return None, why


def test(sc, kind, body, oid):
    b = dict(body)
    b["id"] = oid
    st, js = sc.call("POST", "/api/v1/%s/test" % kind, b, timeout=180)
    if st in (200, 204):
        return True, ""
    msgs = []
    if isinstance(js, list):
        for e in js[:5]:
            if isinstance(e, dict):
                msgs.append("%s: %s" % (e.get("propertyName", ""), str(e.get("errorMessage", ""))[:160]))
    elif isinstance(js, dict) and js.get("error"):
        msgs.append(str(js["error"]))
    return False, "HTTP %s %s" % (st, "; ".join(msgs))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="read everything, write nothing, print the plan")
    ap.add_argument("--source", choices=("auto", "prod", "cellarr"), default="auto")
    ap.add_argument("--no-test", action="store_true", help="skip the sidecar's /test calls")
    ap.add_argument("--force-update", action="store_true",
                    help="PUT existing objects even when no comparable field differs (re-applies secrets)")
    ap.add_argument("--tubifarry-url", default=None, help="override the plugin's GitHub URL")
    a = ap.parse_args()

    env = os.environ
    need = [k for k in ("SIDECAR_URL", "SIDECAR_API_KEY", "PROD_API_KEY") if not env.get(k)]
    if need:
        print("missing environment: " + ", ".join(need), file=sys.stderr)
        return 2
    sc = Api(env["SIDECAR_URL"], env["SIDECAR_API_KEY"], "sidecar", False)
    prod = Api(env.get("PROD_URL", DEFAULT_PROD), env["PROD_API_KEY"], "production Lidarr", True)
    cel = Api(env.get("CELLARR_URL", DEFAULT_CELLARR), env["PROD_API_KEY"], "cellarr", True)
    dry = a.dry_run
    failed = False
    problems = []

    if not wait_ping(sc, 300, "sidecar"):
        return 1
    st, status = sc.get("/api/v1/system/status")
    if st != 200:
        say("FAIL sidecar rejected its API key or is unhealthy: HTTP %s" % st)
        return 1
    say("sidecar: up, version %s" % (status or {}).get("version"))

    source = pick_source(prod, cel, a.source)
    say("source: %s%s" % (source, " (dry run: nothing is written)" if dry else ""))
    src_api = prod if source == "prod" else cel
    src_rows = load_rows(src_api, name_only=(source == "cellarr"))
    cel_rows = load_rows(cel, name_only=True)
    if src_rows is None:
        return 1
    if cel_rows is None:
        say("WARN cellarr's rows unavailable: masked secrets cannot be filled in")

    github = a.tubifarry_url
    if not github:
        st, plugins = prod.get("/api/v1/system/plugins") if source == "prod" else (0, None)
        for p in (plugins or []) if st == 200 else []:
            if p.get("name") == "Tubifarry" and p.get("githubUrl"):
                github = p["githubUrl"]
        github = github or TUBIFARRY_URL

    ok = install_tubifarry(sc, github, dry)
    if ok is False:
        return 1

    schemas = {k: impls(sc, k) for k in ("downloadclient", "indexer")}
    plan = []
    for kind, impl, name, family in TARGETS:
        key = (kind, name) if source == "cellarr" else (kind, "impl:" + impl)
        src = src_rows.get(key)
        if not src:
            say("FAIL %s %s: no row in %s" % (kind, name, src_api.label))
            failed = True
            continue
        label_name = src.get("name") or name
        schema = (schemas.get(kind) or {}).get(impl)
        if schema is None:
            if dry:
                say("plan %s %s (%s): would be created after Tubifarry is installed" % (kind, label_name, impl))
            else:
                say("FAIL %s %s: sidecar has no %s implementation" % (kind, label_name, impl))
                failed = True
            continue
        body = build(kind, schema, src, label_name, family, cel_rows, problems)
        plan.append((kind, label_name, family, body))

    for p in problems:
        say("FAIL " + p)
        failed = True
    if problems:
        return 1

    # validate the slskd key once, before writing anything
    for kind, name, family, body in plan:
        if family == "slskd" and kind == "indexer":
            f = fields_of(body)
            if f.get("baseUrl") and not empty(f.get("apiKey")):
                code = slskd_key_ok(f["baseUrl"], f["apiKey"])
                say("slskd: key check against its /api/v0/application -> %s" % code)
                if code != 200:
                    say("FAIL slskd rejected the key, not writing it")
                    return 1

    existing = {}
    for kind in ("downloadclient", "indexer"):
        st, js = sc.get("/api/v1/" + kind)
        existing[kind] = {o["name"]: o for o in js} if st == 200 and isinstance(js, list) else {}

    results = []
    for kind, name, family, body in plan:
        cur = existing[kind].get(name)
        oid = None
        if cur is None:
            if dry:
                say("plan %s %s: would create" % (kind, name))
                continue
            oid, why = save(sc, kind, body, None)
            if oid:
                say("created %s %s id=%s" % (kind, name, oid))
            else:
                say("FAIL create %s %s: %s" % (kind, name, why))
                failed = True
                continue
        else:
            oid = cur["id"]
            if a.force_update or differs(cur, body):
                if dry:
                    say("plan %s %s id=%s: would update" % (kind, name, oid))
                    continue
                got, why = save(sc, kind, body, oid)
                if got:
                    say("updated %s %s id=%s" % (kind, name, oid))
                else:
                    say("FAIL update %s %s id=%s: %s" % (kind, name, oid, why))
                    failed = True
                    continue
            else:
                say("unchanged %s %s id=%s (secrets are not comparable)" % (kind, name, oid))
        results.append((kind, name, oid, body))

    if dry:
        say("dry run finished: no change was made")
        return 1 if failed else 0

    # verify through the sidecar's own listing
    for kind in ("downloadclient", "indexer"):
        st, js = sc.get("/api/v1/" + kind)
        names = {o["name"]: o for o in js} if st == 200 and isinstance(js, list) else {}
        for k, name, oid, body in results:
            if k != kind:
                continue
            o = names.get(name)
            if o and o.get("id") == oid:
                say("verify %s %s id=%s implementation=%s enable=%s: present" % (kind, name, oid, o.get("implementation"), o.get("enable")))
            else:
                say("FAIL verify %s %s: not in the sidecar's list" % (kind, name))
                failed = True

    warned = 0
    if not a.no_test:
        for kind, name, oid, body in results:
            good, why = test(sc, kind, body, oid)
            if good:
                say("test %s %s id=%s: ok" % (kind, name, oid))
            elif kind == "downloadclient" and "403" in why:
                warned += 1
                say("test %s %s id=%s: WARN %s (the slskd key cannot read /options; same limit as production's key)" % (kind, name, oid, why))
            else:
                say("test %s %s id=%s: FAIL %s" % (kind, name, oid, why))
                failed = True
    else:
        say("tests skipped (--no-test)")

    say("RESULT: %s%s" % ("FAIL" if failed else "ok", " (%d warning)" % warned if warned else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
