"""One password, every service on sandstorm.chat that needs one.

WHY THIS EXISTS. Most published apps here take their identity from authentik
and provision themselves on first login - Navidrome and Calibre-Web from the
forward-auth username header, Immich and Nextcloud and ConvertX from OIDC. One
does not, and cannot:

  remux      0.27.0 reads exactly two headers - the Jellyfin
             X-Emby-Authorization and X-Forwarded-For - and has no OIDC
             anywhere in its source.

(Invidious used to be the other one, for the same reason - it never gained
OIDC. It was decommissioned on 2026-09-05 to reclaim memory, and its
provisioner went with it.)

So for that one the account needs a password, and the useful thing is that it
is the SAME password as authentik. This form does that in one step and reports
what each system said.

WHAT IT DELIBERATELY DOES NOT DO.

  Vaultwarden is absent and cannot be added. A Bitwarden master password is
  never sent to the server - it derives the vault's encryption key in the
  browser. Provisioning one server-side is not "not implemented", it is
  meaningless. Vaultwarden takes the account on first SSO login instead.

  It never deletes or disables anything. Removing someone is a deliberate act
  with consequences per service (watch history, subscriptions), and it is cheap
  to do by hand and impossible to undo.

  It never logs the password, and never puts it in a URL.

AUTHORISATION. The ingress runs authentik-forward-auth, and this checks
X-authentik-groups itself on top. Two independent gates, because the endpoint
creates accounts and a middleware list is one careless edit away from being
shorter.
"""
import html
import json
import os
import re
import socketserver
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

AK_URL = os.environ["AUTHENTIK_URL"].rstrip("/")
AK_TOKEN = os.environ["AUTHENTIK_TOKEN"]
RX_URL = os.environ["REMUX_URL"].rstrip("/")
RX_USER = os.environ["REMUX_ADMIN_USER"]
RX_PASS = os.environ["REMUX_ADMIN_PASSWORD"]
REQUIRED_GROUP = os.environ.get("REQUIRED_GROUP", "authentik Admins")
NTFY_URL = os.environ.get("NTFY_URL", "")
PORT = int(os.environ.get("PORT", "8080"))

USERNAME_RE = re.compile(r"^[a-zA-Z0-9._-]{2,64}$")


def call(url, data=None, headers=None, method=None, timeout=45):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        return r.status, (json.loads(raw) if raw and r.headers.get(
            "Content-Type", "").startswith("application/json") else raw)


def notify(title, message):
    if not NTFY_URL:
        return
    try:
        urllib.request.urlopen(urllib.request.Request(
            NTFY_URL, data=message.encode(), method="POST",
            headers={"Title": title, "Tags": "bust_in_silhouette",
                     "Priority": "low"}), timeout=15).read()
    except (urllib.error.URLError, OSError) as e:
        print(f"warning: could not notify: {e}", file=sys.stderr)


# --------------------------------------------------------------------------
# authentik - the identity of record. Everything else is a copy of this.
# --------------------------------------------------------------------------
def ak_headers():
    return {"Authorization": f"Bearer {AK_TOKEN}", "Content-Type": "application/json"}


def authentik_provision(username, email, password):
    q = urllib.parse.urlencode({"username": username})
    _, found = call(f"{AK_URL}/api/v3/core/users/?{q}", headers=ak_headers())
    results = found.get("results") or []
    if results:
        uid = results[0]["pk"]
        created = False
    else:
        _, u = call(f"{AK_URL}/api/v3/core/users/",
                    data=json.dumps({"username": username, "name": username,
                                     "email": email, "is_active": True,
                                     "type": "internal"}).encode(),
                    headers=ak_headers(), method="POST")
        uid = u["pk"]
        created = True
    # set_password is idempotent and is what makes "the same credentials"
    # true rather than aspirational - an existing account gets realigned.
    call(f"{AK_URL}/api/v3/core/users/{uid}/set_password/",
         data=json.dumps({"password": password}).encode(),
         headers=ak_headers(), method="POST")
    return ("created" if created else "existed, password set"), f"id {uid}"


# --------------------------------------------------------------------------
# remux - Jellyfin-compatible. Unlike remux-user-sync, which leaves the
# password empty because forward-auth is the real gate, this sets a real one:
# the whole point of the form is that the credential matches everywhere.
# --------------------------------------------------------------------------
def remux_provision(username, password):
    _, auth = call(f"{RX_URL}/Users/AuthenticateByName",
                   data=json.dumps({"Username": RX_USER, "Pw": RX_PASS}).encode(),
                   headers={"Content-Type": "application/json",
                            "X-Emby-Authorization":
                                'MediaBrowser Client="accounts", Device="accounts",'
                                ' DeviceId="accounts", Version="1.0"'},
                   method="POST")
    H = {"X-Emby-Token": auth["AccessToken"], "Content-Type": "application/json"}
    _, users = call(f"{RX_URL}/Users", headers=H)
    for u in users:
        if u["Name"].strip().lower() == username.lower():
            # REALIGN rather than skip. Submitting the form again with a new
            # password is how you change it everywhere, and a target that
            # silently kept the old one would quietly break the promise this
            # tool exists to make. An admin may set another user's password
            # with NewPw alone - CurrentPw is only demanded of a non-admin
            # changing their own (crates/remux-server/src/api/users.rs).
            call(f"{RX_URL}/Users/{u['Id']}/Password",
                 data=json.dumps({"NewPw": password}).encode(),
                 headers=H, method="POST")
            return "existed, password set", f"id {u['Id']}"
    _, u = call(f"{RX_URL}/Users/New",
                data=json.dumps({"Name": username, "Password": password}).encode(),
                headers=H, method="POST")
    return "created", f"id {u.get('Id')}"


TARGETS = [
    ("authentik", lambda u, e, p: authentik_provision(u, e, p)),
    ("remux", lambda u, e, p: remux_provision(u, p)),
]

# Shown on the page so the list of what is NOT here is as visible as what is.
SELF_PROVISIONING = [
    ("Navidrome", "creates the user from the forward-auth header on first page load"),
    ("Immich", "OIDC autoRegister"),
    ("Nextcloud", "OIDC (user_oidc)"),
    ("ConvertX", "OIDC on first login"),
    ("Calibre-Web", "forward-auth header on first page load"),
    ("Readarr", "no per-user accounts - forward-auth is the gate"),
    ("Vaultwarden", "first SSO login. Cannot be provisioned here: the master "
                    "password derives the vault key in the browser and never "
                    "reaches the server"),
]

PAGE = """<!doctype html>
<title>sandstorm.chat accounts</title>
<style>
 :root {{ color-scheme: light dark; }}
 body {{ font: 15px/1.55 system-ui, sans-serif; max-width: 46rem; margin: 3rem auto;
        padding: 0 1.25rem; }}
 h1 {{ font-size: 1.4rem; margin-bottom: .25rem; }}
 p.sub {{ color: #777; margin-top: 0; }}
 label {{ display: block; margin: .9rem 0 .2rem; font-weight: 600; }}
 input {{ width: 100%; padding: .55rem .6rem; font: inherit;
          border: 1px solid #8886; border-radius: 6px; background: transparent;
          color: inherit; }}
 button {{ margin-top: 1.4rem; padding: .6rem 1.3rem; font: inherit;
           font-weight: 600; border: 0; border-radius: 6px;
           background: #3b6ea5; color: #fff; cursor: pointer; }}
 table {{ border-collapse: collapse; width: 100%; margin: 1rem 0; }}
 td, th {{ text-align: left; padding: .4rem .6rem; border-bottom: 1px solid #8883;
           vertical-align: top; }}
 .ok {{ color: #2c7a39; font-weight: 600; }}
 .bad {{ color: #b3261e; font-weight: 600; }}
 .note {{ background: #8881; border-left: 3px solid #8886; padding: .7rem 1rem;
          border-radius: 0 6px 6px 0; margin: 1.5rem 0; }}
 code {{ background: #8882; padding: .1rem .3rem; border-radius: 3px; }}
</style>
<h1>sandstorm.chat accounts</h1>
<p class="sub">One password, everywhere it is actually needed. Signed in as
<code>{who}</code>.</p>
{result}
<form method="post">
  <label for="u">Username</label>
  <input id="u" name="username" required autocomplete="off"
         pattern="[a-zA-Z0-9._-]{{2,64}}" autofocus>
  <label for="e">Email</label>
  <input id="e" name="email" type="email" required autocomplete="off">
  <label for="p">Password</label>
  <input id="p" name="password" type="password" required minlength="10"
         autocomplete="new-password">
  <button type="submit">Create account</button>
</form>
<div class="note">
  <strong>These three need a password of their own.</strong> Everything else
  takes the authentik identity on first login and needs nothing here:
  <table>{self_prov}</table>
</div>
"""


def render(who, result=""):
    rows = "".join(
        f"<tr><td><strong>{html.escape(n)}</strong></td>"
        f"<td>{html.escape(d)}</td></tr>" for n, d in SELF_PROVISIONING)
    return PAGE.format(who=html.escape(who), result=result, self_prov=rows)


class Handler(BaseHTTPRequestHandler):
    server_version = "sandstorm-accounts/1"

    # --- authorisation -----------------------------------------------------
    def _who(self):
        return self.headers.get("X-authentik-username") or ""

    def _authorised(self):
        groups = self.headers.get("X-authentik-groups") or ""
        return REQUIRED_GROUP in [g.strip() for g in groups.split("|")]

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        raw = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        # Nothing here should ever be cached by anything.
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _guard(self):
        if self.path == "/healthz":
            return None
        who = self._who()
        if not who:
            # No header means the request did not come through forward-auth.
            self._send(403, "<h1>403</h1><p>This page is only reachable through "
                            "authentik.</p>")
            return False
        if not self._authorised():
            self._send(403, f"<h1>403</h1><p>{html.escape(who)} is not in "
                            f"{html.escape(REQUIRED_GROUP)}.</p>")
            return False
        return True

    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200, "ok\n", "text/plain")
        if self._guard() is not True:
            return
        self._send(200, render(self._who()))

    def do_POST(self):
        if self._guard() is not True:
            return
        length = int(self.headers.get("Content-Length") or 0)
        form = urllib.parse.parse_qs(self.rfile.read(length).decode())
        username = (form.get("username") or [""])[0].strip()
        email = (form.get("email") or [""])[0].strip()
        password = (form.get("password") or [""])[0]

        if not USERNAME_RE.match(username):
            return self._send(400, render(self._who(),
                "<p class='bad'>Username must be 2-64 characters of letters, "
                "digits, dot, underscore or dash.</p>"))
        if len(password) < 10:
            return self._send(400, render(self._who(),
                "<p class='bad'>Password must be at least 10 characters.</p>"))

        rows, failures = [], []
        for name, fn in TARGETS:
            try:
                state, detail = fn(username, email, password)
                rows.append(f"<tr><td><strong>{html.escape(name)}</strong></td>"
                            f"<td class='ok'>{html.escape(state)}</td>"
                            f"<td>{html.escape(detail)}</td></tr>")
            except Exception as e:
                # Deliberately broad: one service being down must not stop the
                # others, and the report is more useful than a stack trace.
                # str(e) is safe - the password is never in a URL or a message.
                msg = f"{type(e).__name__}: {e}"[:200]
                failures.append(name)
                rows.append(f"<tr><td><strong>{html.escape(name)}</strong></td>"
                            f"<td class='bad'>failed</td>"
                            f"<td>{html.escape(msg)}</td></tr>")
                print(f"provision {name} failed for {username!r}: {msg}",
                      file=sys.stderr)

        heading = ("<p class='bad'>Finished with errors - see below. Fix and "
                   "submit again; every step is safe to repeat.</p>"
                   if failures else
                   "<p class='ok'>Done. The same username and password now work "
                   "on all three, and on everything else the moment they log "
                   "in through authentik.</p>")
        notify(f"Account provisioned: {username}",
               "Created by " + self._who() + " on: "
               + ", ".join(n for n, _ in TARGETS if n not in failures)
               + (f"\nFAILED: {', '.join(failures)}" if failures else ""))
        self._send(200, render(self._who(), heading + f"<table>{''.join(rows)}</table>"))

    def log_message(self, fmt, *args):
        # Default logging writes the request line, which for a POST is just the
        # path - but keeping it minimal makes it obvious nothing here logs a body.
        print(f"{self.command} {self.path.split('?')[0]}", flush=True)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("0.0.0.0", PORT), Handler) as httpd:
        print(f"accounts listening on :{PORT}", flush=True)
        httpd.serve_forever()
