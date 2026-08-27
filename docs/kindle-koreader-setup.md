# Jailbroken Kindle + KOReader against self-hosted Calibre-Web-Automated

Follow this with the device in hand. Everything server-side is already done and
verified; sections 1–2 are on the Kindle, section 3 is in the CWA web UI, and
section 4 is back on the Kindle.

Verified against the live cluster on 2026-08-27. Facts marked **(verified)**
were checked against the running system or upstream source, not recalled.

---

## 0. What already exists (do not redo)

| Thing | State |
|---|---|
| CWA | `crocodilestick/calibre-web-automated:V3.1.4`, namespace `books` **(verified)** |
| Library UI | `https://books.sandstorm.chat/` — behind Authentik forward-auth |
| OPDS feed | `https://books.sandstorm.chat/opds` — **no** Authentik, CWA's own HTTP Basic instead |
| OPDS ingress | `apps/books/opds-ingress.yaml`, keeps CrowdSec + rate-limit middlewares |
| Anonymous browsing | OFF (`config_anonbrowse = 0`) **(verified)** |
| Public registration | OFF (`config_public_reg = 0`) **(verified)** |
| Reverse-proxy header login | OFF (`config_allow_reverse_proxy_header_login = 0`) **(verified)** — important, since `/opds` has no forward-auth, this stops header spoofing from logging anyone in |
| Default role for new users | `0` — **no rights at all** **(verified)**, so you must tick boxes manually in §3 |
| Users today | `admin` (role 479 = everything) and `Guest` (role 32 = anonymous, unused) **(verified)** |
| Library contents | 1 book, EPUB **(verified)** |

Every OPDS sub-path was re-checked externally and all return CWA's own
`401 WWW-Authenticate: Basic`, i.e. none of them fall through to Authentik
**(verified 2026-08-27)**:

```
/opds/                     401 Basic
/opds/new                  401 Basic
/opds/osd                  401 Basic
/opds/stats                401 Basic
/opds/search?query=test    401 Basic
/opds/cover/1              401 Basic
/opds/download/1/epub/     401 Basic
```

---

## 1. Jailbreak the Kindle

### Current state, August 2026

Kindle jailbreaking is maintained by the **KindleModding** project at
<https://kindlemodding.org>. The landscape as of now:

- **Véra** — released 2026-08-10, the current jailbreak for modern hardware.
  Covers **KT5** (Kindle Basic 11th gen, 2022), **PW5** (Paperwhite 11th gen),
  **KT6** (Kindle Basic 11th gen, 2024), **PW6** (Paperwhite 12th gen),
  **CS** (Colorsoft), **KS** and **KS2** (Scribe 2022 / 2024), on firmware from
  roughly 5.17.1 **up to and including 5.19.6**. Scribe 3rd gen (`KS3`) and
  `KSC` are *not yet supported* — a port is stated as planned.
- **Sanctuary** — firmware 5.16.4 – 5.18.3.
- **AdBreak** — firmware 5.18.1 – 5.18.5.0.1.
- **SpringBreak / Nosebleed / WinterBreak / WinterBreak2** — older windows.
  Nosebleed is the one reported to work on some *blacklisted / unregistered*
  devices.
- **Legacy** methods for 5.16.2.1.1 and below.

> **Do not pick from that list yourself.** Run the **Jailbreak Wizard** at
> <https://kindlemodding.org/jailbreak-wizard.html>, give it your exact model
> and firmware, and use whatever it names. All the jailbreaks are functionally
> identical — different exploits, one outcome — so there is no "better" one.

### Before you start

1. **Find your exact firmware**: `3 Dots → Settings → Device options → Device
   info`. Write down the number after "Kindle" (e.g. `5.19.4`).
2. **Fill the storage**, then work offline until you jailbreak. A Kindle with
   free space will silently OTA-update itself the moment it sees Wi-Fi, and an
   updated Kindle may land on a firmware with no jailbreak at all — with **no
   way to downgrade** on stock firmware. Leave **50–90 MB free**.
   - 11th-gen and newer Kindles present as **MTP, not USB mass storage**, so
     the usual `Filler.sh` script does not work. Use the pre-made filler files
     from <https://github.com/Crosunt223/Kindle-Filler-Disk/tree/main/MTP> and
     copy them to the Kindle root by hand.
   - Delete any `update*.bin` or `update.bin.tmp.partial` from the Kindle root
     first.
   - Turn on **Airplane mode** until the jailbreak step.

### Véra, step by step (if the wizard sends you there)

Véra runs entirely **on the Kindle** — no computer needed for the jailbreak
itself.

1. Re-enable Wi-Fi (storage is full, so it cannot update).
2. `3 Dots → Web Browser`, go to **`https://kindlemodding.org/vera`**.
3. Pick your model, then your firmware from the dropdown. If your exact
   firmware is missing but is between 5.17 and 5.19.6, the nearest listed
   version is worth trying — ask in their Discord first if you'd rather not
   guess.
4. Download **both** books it offers: *Font Calibration* and the
   device-specific *Véra* book. Confirm each with "Ok".
5. Close the browser with the X. **Leave Wi-Fi on.** Wait 2–3 seconds.
6. Open **Font Calibration**. Tap the top of the screen → `Aa`.
7. `Font` tab: Font Family = **Bookerly**, Bold = **0**, Size = **maximum**.
8. `Layout` tab: Spacing = **medium**. (If you get a `Spacing` option at the
   bottom instead, set Line Spacing = **2**, then back-arrow out.)
9. `Themes` tab: **Save current settings** → **Save**.
10. Leave the book (tap top-left three times).
11. Open the **Véra** book. Text scrolls from the top-left, then a
    **RESTARTING GUI** screen appears. Any "application error" popups are
    harmless. If it sits on "Restarting GUI" for more than ~10 minutes, hold
    power and Restart.
12. Once back at the home screen, delete both books, delete the filler files,
    and delete any remaining `.bin` in the root. **Update blocking is installed
    automatically by the jailbreak** — you do not need to stay in Airplane mode.

### Then install KOReader

**KUAL and MRPI are obsolete.** Every guide older than ~2025 tells you to copy
`KUAL.jar`, `extensions/` and `mrpackages/` onto the device. Modern jailbreaks
use the `hdnext` stack and ship a package manager called **KPM** instead;
KindleModding's own docs state KUAL "is now obsolete and does not work". Ignore
any tutorial that mentions it.

1. **Reboot** the Kindle if you have not since jailbreaking. Make sure Wi-Fi is
   on.
2. In the **search bar on the home screen**, type `;kpm update` and press
   enter. Text flashes at the top, then you're back at the home screen.
3. Type `;kpm install koreader` and press enter. Wait; a new scriptlet icon
   appears in your library (it may take a moment to render).
4. Tap it to launch. `;kpm launch koreader` also works.
   (`;kpm uninstall koreader` removes it.)

Launch options you'll see later:
- **Start KOReader** — the normal way.
- **Start KOReader (no framework)** — kills the Kindle UI to free RAM. Faster,
  but the Kindle reader is gone until you exit.
- **Start KOReader (ASAP)** — skips some checks.

### Gotchas that will bite you

- **KOReader cannot do USB file transfer.** No USBMS support — you must exit
  KOReader before the Kindle will mount over USB.
- **Deregistering the Kindle wipes `/documents`**, which is where scriptlets
  live. Back up first if you ever deregister.
- **Long stretches in Airplane mode can make Amazon delete your sideloaded
  books** on the next reconnect, jailbroken or not. Unrelated to the jailbreak;
  keep the originals on the server (which is the point of this whole exercise).
- **A Kindle bought today may already be un-jailbreakable.** Firmware above
  5.19.6 has no method yet.

---

## 2. Create the Kindle's own CWA account

**Do not put the `admin` password on the Kindle.** Reasons, specific to this
setup:

- Basic credentials sit in KOReader's plaintext `opds.lua` settings file on a
  device with no lock screen and no disk encryption, and they travel to a
  hostname that is reachable from the whole internet.
- The `admin` account carries role 479 — admin, upload, edit, delete books,
  change password, edit public shelves **(verified)**. A leaked OPDS password
  is then a full library-destruction password *and* a CWA admin-panel password.
- `/opds` deliberately has **no Authentik forward-auth**, so these credentials
  are the only thing in front of the feed. That is exactly the account you want
  to be able to revoke in one click without touching your own login.
- Revoking a dedicated account is a two-second delete. Rotating `admin` means
  re-doing Authentik-adjacent plumbing and every other place that password
  lives.

### Steps in the CWA UI

1. Log in to `https://books.sandstorm.chat/` as `admin` (through Authentik).
2. **Admin** (gear icon, top right) → **Users** → **Add New User**.
3. Fill in:
   - **Username**: `kindle`
   - **Password**: a long random string. Generate it in Vaultwarden and store
     it there — you will type it once on an e-ink keyboard, so favour length
     over exotic symbols.
   - **Email**: anything unique, e.g. `kindle@sandstorm.chat`. CWA requires the
     field; nothing is sent to it.
   - **Locale / Default language**: leave as-is.
4. **Tick exactly one permission box:**

   | Box | Set to | Why |
   |---|---|---|
   | **Allow Downloads** | ✅ **ON** | **Required.** `/opds/download/<id>/<format>/` explicitly calls `role_download()` and returns `401` without it **(verified in `cps/opds.py`)**. Browsing the feed works without it; downloading does not. |
   | Allow Uploads | ❌ off | A reader never writes to the library. |
   | Allow Edit | ❌ off | |
   | Allow Delete books | ❌ off | |
   | Allow Changing Password | ❌ off | You manage this from admin. |
   | Allow Editing Public Shelves | ❌ off | |
   | Admin user | ❌ off | Never. |
   | **Allow Viewer / Show books** | ✅ ON | Not checked by the OPDS code, but it is what lets the account see the library if you ever log it into the web UI. Harmless and sensible. |

   Result: role value `258` (download + viewer). Compare to `admin`'s `479`.

5. Save. Optionally restrict what this account can see with **Denied Tags** /
   **Allowed Tags** on the same form — a cheap way to keep, say, anything
   tagged `private` off the portable device.

### Verify before you touch the Kindle

From your laptop:

```sh
curl -u kindle:'THEPASSWORD' -s -o /dev/null -w '%{http_code}\n' \
  https://books.sandstorm.chat/opds
# expect 200

curl -u kindle:'THEPASSWORD' -s https://books.sandstorm.chat/opds \
  | head -20
# expect an <?xml ...><feed ...> Atom document
```

If the first returns `401`, the password is wrong. If it returns `302` with a
`Location:` pointing at `authentik.sandstorm.chat`, you are hitting the wrong
Ingress — stop and check `apps/books/opds-ingress.yaml` is still applied.

---

## 3. Add the catalog in KOReader

### First: the Calibre plugin is the WRONG tool **(verified)**

In the same **Search (magnifier)** tab, directly above *OPDS catalog*, sits
**Find book in calibre catalog**. It is one line away and it is the wrong
feature. Its menu reads *Manage libraries* / *Rescan disk for calibre
libraries* / *No calibre libraries* — the giveaway is the word **disk**.

KOReader's `calibre.koplugin` does exactly two things **(verified in
`plugins/calibre.koplugin/main.lua`)**:

1. **Metadata search** — walks the device's own storage looking for a
   `metadata.calibre` file written by a real Calibre install. It never makes a
   network request to a server.
2. **Calibre wireless** — the Calibre desktop app's "Connect to folder /
   Smart device app" protocol, a custom binary protocol on port 9090 to a
   *running Calibre GUI on your LAN*. CWA does not speak it.

Neither reaches a remote CWA server. Scanning will keep returning
**"No calibre libraries"** forever, because there is no Calibre library on the
Kindle's disk.

**To back out:** press the **back arrow** (top-left of the dialog), or tap
outside the popup, until you are at the plain file manager. Then re-open the
menu and pick the *last* entry in the Search tab, **OPDS catalog** — below the
separator, below the calibre entry.

### The URL

Use exactly:

```
https://books.sandstorm.chat/opds
```

**(verified)** — `/opds` and `/opds/` are both registered routes in CWA and
both answer `401 Basic` unauthenticated, so the trailing slash does not matter.
Everything else in the catalogue (`/opds/new`, `/opds/author`, `/opds/series`,
`/opds/search`, `/opds/cover/<id>`, `/opds/download/<id>/<format>/`) hangs off
that same prefix, which is why the one Ingress rule covers the whole feed.

There is **no** `/opds/nav/start`, no `/opds/v1.2/catalog`, and no separate
"OPDS root" — those belong to other servers. `/opds/nav/start` on this host
returns a `302` to `/login` **(verified)**; if you type it you will get a
confusing HTML page instead of a feed.

Type the `https://` prefix. KOReader will not assume it, and a bare hostname
is what produced the well-known "tlsv1 protocol error" reports against CWA
(koreader/koreader#14962 — closed, it was a reverse-proxy/URL mistake, not a
KOReader TLS bug).

### Menu path **(verified against KOReader master)**

1. Launch KOReader. Stay in the **file manager** — the OPDS entry only exists
   when no book is open.
2. Tap the top of the screen to open the menu bar.
3. Go to the **magnifying-glass (Search) tab** — it is the second-from-right
   icon.
4. Scroll to the bottom: **OPDS catalog**.
5. Tap the **hamburger / ☰ button in the top-left** of the OPDS screen → **Add
   catalog**.

   **(verified)** On the OPDS *root* screen the left title-bar icon is always
   the hamburger (`appbar.menu`). A **＋** icon appears there only once you
   have navigated *into* a catalog, where it means "add this sub-catalog as its
   own entry" — not "add a new server". If you see ＋, back out one level.
6. Fill the four fields:

   | Field | Value |
   |---|---|
   | Catalog name | `sandstorm` |
   | Catalog URL | `https://books.sandstorm.chat/opds` |
   | Username (optional) | `kindle` |
   | Password (optional) | the password from §2 |

7. **Save**.

KOReader sends the credentials as an HTTP Basic `Authorization` header on the
*first* request (LuaSocket adds it pre-emptively when `user`/`password` are
set) — it does not wait for a 401 first. That matters: in normal operation this
setup generates **zero** 401 responses, which keeps CrowdSec's brute-force
counters at zero (see §6).

Tap the catalog to open it. You should see CWA's navigation feed —
*Hot Books*, *New Books*, *Authors*, *Series*, *Categories*, etc.

### If it errors

KOReader gives specific messages:

- *"Authentication required for catalog. Please add a username and password."*
  → HTTP 401. Wrong username/password, or you left them blank.
- *"Failed to authenticate. Please check your username and password."* → 403.
- *"Catalog not found."* → 404. Wrong path.
- *"Insecure HTTPS → HTTP downgrade attempted by redirect"* → something is
  redirecting `https` to `http`. Should not happen here.
- Anything mentioning `tlsv1` → almost always a typo'd URL (missing `https://`,
  or a raw `host:port`), not a real TLS problem. See §6.

### Ongoing sync: the nightly workflow **(verified)**

The goal is: grab a book on the computer tonight, read it on the Kindle tonight.
Three hops, and only the last one is manual.

#### Hop 1 — computer into the library

Any of these; all land in the same ingest folder, which CWA watches:

| Way | How | Works off-LAN? |
|---|---|---|
| **Web upload** | `https://books.sandstorm.chat/` → upload button | Yes (via Authentik) |
| **NFS drop** | mount `192.168.1.67:/extra/nfs-csi` and copy into `data/ingest/books/` | LAN only |
| **book-downloader** | `https://bookdl.sandstorm.chat/` — searches Anna's Archive, files straight into ingest | Yes |

CWA's ingest watcher then converts to EPUB, files it into the Calibre library,
and **deletes the ingest copy**. Give it a minute or two before the book shows
up in the feed.

#### Hop 2 — the sync catalog

**The `/opds` nav root cannot be synced.** This is the trap, and it is silent:

KOReader's sync walks the feed assuming **entry #1 is the newest book** and
stops when it reaches the `last_download` href it recorded last time
**(verified in `getSyncDownloadList`/`fillPendingSyncs`)**. The `/opds` root is
a *navigation* feed — Hot Books, New Books, Authors, Series — and those entries
carry **no acquisition links at all**. Sync walks the whole list, finds nothing
downloadable, and returns an empty set. No error, no message. It just does
nothing, forever.

Point sync at the **New Books** acquisition feed instead:

```
https://books.sandstorm.chat/opds/new
```

**(verified in `cps/opds.py`)** — `feed_new()` sorts
`[db.Books.timestamp.desc()]`, i.e. newest-added first, which is exactly the
ordering KOReader's sync assumes.

So keep **two** catalog entries:

| Name | URL | Sync catalog |
|---|---|---|
| `sandstorm` | `https://books.sandstorm.chat/opds` | ❌ unticked — for browsing by author/series |
| `sandstorm-sync` | `https://books.sandstorm.chat/opds/new` | ✅ **ticked** — for the nightly pull |

**"Sync catalog"** is a checkbox on the same add/edit form as the four text
fields, below the password box **(verified)**.

One more gate: `feed_new()` calls `check_visibility(SIDEBAR_RECENT)` and
**aborts with 404** if the account lacks it. `config_default_show = 262143`
(every visibility bit) **(verified)**, so a new user gets it automatically —
just don't untick **Show Recent Books** on the `kindle` account, or sync starts
404ing with no useful message.

#### Hop 3 — pull it on the Kindle

Set the folder **once**, before the first sync:

- ☰ → **Set sync folder** → `/mnt/us/koreader-books`
  (mandatory — without it sync refuses with *"Please choose a folder for sync
  downloads first"* **(verified)**)
- ☰ → **Set file types to sync** → `epub`
- ☰ → **Set max number of files to sync** → default 50, fine

Then each night, two taps:

> **OPDS catalog → ☰ → Sync all catalogs**

or long-press just the one catalog → **Sync**. **Force sync** ignores the
`last_download` marker and re-walks the whole feed — use it if you think it
missed something.

#### It is manual. There is no autosync.

Worth knowing before you build a habit around it: KOReader's OPDS plugin
registers exactly **one** Dispatcher action, `opds_show_catalog`
**(verified in `plugins/opds.koplugin/main.lua`)**. There is no sync action, so
you cannot bind sync to a gesture, and nothing runs it on boot, on wake, or on
a schedule. The nightly tap is the workflow.

---

## 4. Formats

**Use EPUB. Nothing else.**

- KOReader's renderer (crengine) is built around EPUB and handles it best.
- KindleModding's own FAQ is blunt about it: KOReader "currently doesn't (and
  likely never will) support the proprietary formats that Amazon converts all
  ebooks into (KFX, AZW3, and very limited support for MOBI). It is recommended
  to get all your books as EPUB."
- **KEPUB is Kobo-only** — irrelevant on a Kindle, and CWA will happily let you
  set it as a target format by mistake.
- **PDF** only for genuinely fixed-layout material (scans, comics, sheet
  music). Reflowable text in PDF is miserable on a 6" e-ink screen.
- **AZW3/MOBI** only matter if you want to read the same book in the *stock*
  Kindle reader too. If that's the goal, keep both formats on the book in
  Calibre — CWA lists every format a book has, so KOReader will show you a
  choice.

### The thing that actually matters

**OPDS does no conversion.** The feed template iterates over
`entry.Books.data` — the formats that physically exist on disk — and emits one
`acquisition` link per format **(verified in `cps/templates/feed.xml`)**. There
is no on-the-fly convert-on-download. If a book is AZW3-only in the library,
the Kindle gets AZW3 and KOReader will render it badly.

CWA's conversion happens at **ingest** time instead, which is the lever to pull:

1. `https://books.sandstorm.chat/` → **CWA Settings** page.
2. Confirm the **Auto-Conversion Service** is **on** (it is by default) and
   **Target Format = EPUB** (also the default).
3. Add the formats you want auto-converted to the auto-convert list (`.azw3`,
   `.mobi`, `.pdb`, `.lit`, `.fb2`, …). CWA supports 27 input formats.
4. For books *already* in the library in the wrong format, use
   **Convert Library** (CWA's bulk tool). It keeps originals in
   `/config/processed_books` by default — leave that on.

Also worth leaving on: the **EPUB-Fixer service**, which repairs the
encoding/hyperlink/language-tag defects that make sloppy EPUBs render badly.

The library currently holds exactly **1 book, in EPUB** **(verified)**, so
there is nothing to fix today. This matters as the library grows.

### Where downloads land

KOReader saves to its OPDS download directory. Set it deliberately so the
Kindle's own indexer doesn't fight you:

- In the OPDS screen: ☰ → **Set sync folder** (also used as the download
  target for bulk sync).
- Pick something like `/mnt/us/koreader-books`, **not** `/mnt/us/documents`.
  Files in `documents` get picked up by the Amazon framework and may be
  reorganised or, per the FAQ above, deleted after a long offline period.
- Per-download you can also use **Choose folder** and **Change filename** from
  the book's action menu, and **Use server filenames** is a per-catalog toggle
  on the add/edit form.

---

## 5. Progress sync — assessment only, nothing deployed

### Is it worth it?

**Only if you will read the same book on a second device.** KOReader's sync
plugin syncs *reading position between KOReader instances*. It does not sync
with the stock Kindle reader, not with Amazon Whispersync, and not with CWA
(Calibre-Web's own read-status column is separate). If the Kindle is the only
place you read, this buys you nothing and adds an internet-exposed service.

If you *do* want it, the second instance would be KOReader on Android/desktop.

### What it looks like on-device

Menu path is different from OPDS — it lives in the **reader**, not the file
manager **(verified against KOReader master)**:

> Open a book → top menu → **wrench / Tools tab** → **Progress sync**

Settings there: **Custom sync server**, **Register / Login**, **Automatically
keep documents in sync**, **Push/Pull progress now**, and **Document matching
method**.

One trap worth knowing before you commit: **Document matching method** defaults
to **Binary** — "only identical files will be kept in sync". If you download
the same book to two devices from this OPDS feed you get byte-identical files,
so Binary works. If one copy came from anywhere else, you must switch both
devices to **Filename** matching.

### Self-hosted options

- **Official**: `koreader/koreader-sync-server` (`koreader/kosync:latest`) —
  OpenResty + Lua, **Redis-backed**. Note: the image **bundles its own Redis
  internally** (persisted at `/var/lib/redis`); it does not take an external
  Redis URL. So it would *not* reuse this cluster's shared
  `redis-master.redis.svc` — it would be a second Redis, which cuts against
  the one-Redis rule for this homelab.
  Usefully, it serves plain HTTP on port **17200** specifically for running
  behind a TLS-terminating reverse proxy (port 7200 is HTTPS with a
  self-signed cert). `17200` + Traefik is the right shape here.
- **Alternatives**, all lighter and SQLite/Postgres-backed:
  - `szaffarano/korrosync` — Rust.
  - `Cmooon/kosync` — Gleam.
  - `jberlyn/kosync-dotnet` — .NET.
  - `b1n4ryj4n/koreader-sync` — Python, arm64+amd64 images.

  Any of these would fit this cluster better than the official image: single
  container, SQLite on a small PVC, no second Redis.

### If you deploy it later, the same OPDS trap applies

The sync plugin authenticates with its own username + MD5'd password against
`/users/create`, `/users/auth`, `/syncs/progress`. Like OPDS, **it cannot
follow an OAuth redirect**. It would need its own Ingress with forward-auth
omitted — the identical pattern as `apps/books/opds-ingress.yaml`. Budget for
that; do not assume it can sit behind Authentik.

Rough shape: `apps/kosync/` with a Deployment, a 1Gi PVC, a Service on 17200,
an Ingress on `kosync.sandstorm.chat` with `crowdsec` + `rate-limit` and **no**
`authentik-forward-auth`, plus a cert-manager annotation. Not built. Ask when
you want it.

---

## 6. Things that will bite you, with real numbers

### Rate limiting — not a problem, and here's why

`apps/traefik/rate-limit-middleware.yaml` **(read from the repo, not guessed)**:

```yaml
spec:
  rateLimit:
    average: 50     # sustained req/s per source IP
    burst: 100      # short-burst allowance
    period: 1s
```

There is no `sourceCriterion`, so Traefik keys on the real connection source
(the Service runs `externalTrafficPolicy: Local`), i.e. your home IP gets its
own bucket.

Against that, a worst-case KOReader bulk sync:

- KOReader's **"Sync all catalogs"** defaults to **`sync_max_dl = 50`** books
  per run **(verified in `plugins/opds.koplugin/opdsbrowser.lua`)**, adjustable
  0–1000 via ☰ → *Set max number of files to sync*.
- CWA paginates the feed at **60 books per page** (`config_books_per_page = 60`
  **(verified)**), so 50 books is **one** feed fetch.
- Downloads are issued **sequentially**, one file at a time, each taking
  hundreds of milliseconds to seconds over the WAN.

That is ~51 requests spread over minutes against a 50/s sustained allowance.
**Nothing will be throttled.** Even the theoretical instantaneous case (51
requests in one second) sits under the burst of 100.

The stricter `rate-limit-auth` middleware (5/s, burst 10) is **not** attached to
either books Ingress, so it is irrelevant here.

### CrowdSec — the one I actually went and checked

The `books-opds` Ingress keeps the `crowdsec` middleware, running collections
`crowdsecurity/traefik`, `http-cve`, `base-http-scenarios`,
`whitelist-good-actors` **(from `apps/crowdsec/kustomization.yaml`)**.

The scenario that *could* plausibly fire on a bulk sync is
**`crowdsecurity/http-crawl-non_statics`**:

```yaml
filter:   GET/HEAD on non-static resources
distinct: evt.Parsed.file_name
capacity: 40
leakspeed: 0.5s        # drains ~2/s
groupby:  source_ip + target_fqdn
```

40 *distinct* non-static paths, draining at 2/s. Fifty book downloads sounds
like it should trip that. **It does not**, and the reason is worth recording:

CrowdSec's `crowdsecurity/http-logs` parser derives `file_name` with the grok
`%{DIR:file_dir}(%{FILE:file_frag}%{EXT:file_ext})?` where `DIR` is the greedy
`^.*/`. Every CWA download URL ends in a **trailing slash**
(`/opds/download/12/epub/`), so `DIR` swallows the whole path, the optional
file group matches nothing, and **`file_name` comes out empty for every single
download**. The scenario's `distinct: file_name` then collapses all 50 into
**one** bucket entry. Feed pages behave the same way — `?offset=N` is stripped
before the grok runs, so every page of `/opds/new` yields `file_name = "new"`.

Net effect: a whole bulk sync contributes a handful of distinct values against
a capacity of 40. Comfortable margin.

Two related notes:

- **`/opds/cover/<id>` does *not* have a trailing slash**, so it yields
  `file_name = "<id>"` — genuinely distinct per book. But KOReader's OPDS
  browser is a plain text list and only fetches a cover when you explicitly tap
  *Book cover*; it never fetches them in bulk. You would have to hand-tap 40+
  covers in under ~20 seconds to trip this. Not a realistic path.
- **Brute-force scenarios**: `crowdsecurity/http-generic-bf` is capacity 5 /
  leakspeed 10s, and the `LePresidente/http-generic-401-bf` and `-403-bf`
  variants **only match `POST`** — OPDS is all `GET`, so a mistyped password
  producing GET 401s will not trip those. Still, don't sit there retyping a
  wrong password twenty times.

There are currently **no active CrowdSec decisions** **(verified
2026-08-27)**.

To check or clear a ban:

```sh
ssh -i ~/.ssh/worker_key -o StrictHostKeyChecking=no root@100.125.108.56
pct exec 200 -- kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions list
pct exec 200 -- kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions delete --ip <your.home.ip>
```

`cscli decisions delete` is a runtime action, not cluster config — ArgoCD will
not revert it.

### TLS — a surprise worth knowing about

The certificate chain on `books.sandstorm.chat` right now **(verified
2026-08-27)**:

```
leaf  CN=books.sandstorm.chat
  ↑   issued by  Let's Encrypt YR2
  ↑   issued by  ISRG Root YR          (valid from 2026-05-13)
  ↑   cross-signed by  ISRG Root X1
```

Let's Encrypt switched the default ACME profile to its new **"Generation Y"**
hierarchy (`ISRG Root YR` for RSA, `ISRG Root YE` for ECDSA) on 2026-05-13.
Old clients do not have `ISRG Root YR` in their trust store. Two things save
you:

1. Traefik is serving the **cross-signed** `ISRG Root YR` — the one issued by
   the venerable `ISRG Root X1` — so any client that trusts X1 (Kindle firmware
   from roughly 5.12 onward) can still build a path. This is exactly the
   compatibility bridge LE built for the transition.
2. **KOReader does not verify server certificates for OPDS at all.** It uses
   LuaSocket's `socket.http`, which hands HTTPS to LuaSec's `ssl.https`
   defaults — `verify = "none"`. There is no `cafile`, `capath` or `verify`
   setting anywhere in the KOReader tree **(verified)**.

So: **no cert-trust failures are expected**, on any Kindle firmware. The
honest trade-off is that KOReader's OPDS traffic is encrypted but not
authenticated — it would not detect a MITM. Given the Basic password is the
crown jewel here, that is one more reason it should be the throwaway `kindle`
account and not `admin`.

Protocol side, also checked against the live endpoint:

| TLS version | Result |
|---|---|
| TLS 1.0 | rejected |
| TLS 1.1 | rejected |
| **TLS 1.2** | **OK** |
| **TLS 1.3** | **OK** (negotiated: `TLS_AES_128_GCM_SHA256`) |

LuaSec's default is `protocol = "any"` with `no_sslv2, no_sslv3, no_tlsv1`, so
it negotiates 1.2/1.3 happily. The `tlsv1 protocol error` reports you'll find
against CWA (koreader/koreader#14962) were a user hitting a bare `host:port`
through a misconfigured reverse proxy; the issue is **closed** and the
resolution was fixing the URL, not KOReader.

Separately: the **Kindle's built-in browser** has its own, much older trust
store, and you may see cert warnings there that KOReader never shows. Only
relevant during the jailbreak (kindlemodding.org) — it's not the OPDS client.

### Wi-Fi and sleep

- Turn **on**: `Settings (gear) → Network → Restore Wi-Fi connection on
  resume`. Without it, the Kindle wakes with Wi-Fi off and your first OPDS tap
  fails with a connection error before KOReader prompts you.
- Leave **off**: `Disable Wi-Fi connection when inactive`. KOReader's own help
  text says it is *"unlikely to function properly on a stock Kindle, given how
  much network activity the framework generates"* **(verified in
  `frontend/ui/network/manager.lua`)**.
- KOReader will prompt to turn Wi-Fi on when an action needs it, and bulk sync
  wraps itself in `NetworkMgr:runWhenConnected`, so it waits for the radio
  rather than failing outright. Do not let the device sleep mid-sync anyway;
  e-ink sleep will suspend the transfer.
- Certificate expiry: the current cert runs to **2026-11-24** and cert-manager
  renews it. But if the Kindle sits in a drawer for months and its clock drifts
  badly, TLS can fail for clock reasons. Irrelevant to KOReader (no
  verification) but relevant to the built-in browser.

### Feed icon

CWA's feed template emits `<icon>` pointing at `/static/favicon.ico` — which
is **outside `/opds`**, so it lands on the main Ingress and gets a `302` to
Authentik. KOReader does not fetch feed icons, so this is harmless. Mentioned
only so you don't chase it if you ever tcpdump the traffic or try the feed in
a different OPDS client that *does* fetch it.

---

## 7. Troubleshooting, keyed to this setup

| Symptom | Cause | Fix |
|---|---|---|
| KOReader: *"Authentication required for catalog"* | 401 — blank or wrong credentials | Re-enter username/password on the catalog (☰ → long-press catalog → **Edit**). Verify from a laptop with the `curl -u` command in §2 first. |
| Feed loads, but tapping a book gives an error / 401 | The `kindle` user is missing **Allow Downloads** | Admin → Users → `kindle` → tick **Allow Downloads**. `/opds/download/...` calls `role_download()` explicitly. Everything else in the feed works without it, which makes this failure look mysterious. |
| Calibre plugin says *"No calibre libraries"* no matter how often you rescan | Wrong plugin — it scans the device disk, and talks to a running Calibre GUI over LAN. It cannot reach CWA. | Back out, use **Search tab → OPDS catalog** (the entry *below* it). §3. |
| **"Sync all catalogs" appears to work but downloads nothing, silently** | The synced catalog points at `/opds` — a navigation feed with no acquisition links | Point the sync catalog at `https://books.sandstorm.chat/opds/new`. §3. |
| Sync errors 404 | The account lost **Show Recent Books** visibility; `feed_new()` aborts 404 without it | Admin → Users → re-tick **Show Recent Books**. |
| *"Please choose a folder for sync downloads first"* | No sync folder set | OPDS screen → ☰ → **Set sync folder** → `/mnt/us/koreader-books`. |
| Book is in CWA but not in the feed yet | Ingest watcher still converting/filing | Wait a minute or two; CWA deletes the ingest copy when it is done. |
| KOReader shows an HTML login page, or garbled parse errors | You hit a path outside `/opds` and got redirected to Authentik | Check the catalog URL is exactly `https://books.sandstorm.chat/opds`. Not `/opds/nav/start`, not `/`. |
| Browser redirect to `authentik.sandstorm.chat` for `/opds` itself | The `books-opds` Ingress is gone or lost its rule | `kubectl get ingress -n books` — you should see both `books` and `books-opds`. If missing, check ArgoCD synced `apps/books/opds-ingress.yaml`. **Fix it in git, not with `kubectl edit`** — selfHeal reverts. |
| `tlsv1 protocol error` | Almost certainly a malformed URL (missing `https://`, or `host:port`) | Retype the URL with the scheme. The server offers only TLS 1.2/1.3 and KOReader speaks both. |
| Connection times out only after the Kindle sleeps | Wi-Fi not restored on resume | `Settings → Network → Restore Wi-Fi connection on resume` = on. |
| Everything suddenly returns nothing / connection refused from home | CrowdSec ban on your home IP | `cscli decisions list` / `cscli decisions delete --ip <ip>` — commands in §6. Expected to be rare; see the analysis there. |
| Book downloads but renders badly (bad fonts, no TOC, weird spacing) | It's AZW3/MOBI/KFX, not EPUB | Convert it in CWA. §4. KOReader's MOBI support is *"very limited"* per KindleModding's FAQ. |
| Downloaded books vanish from the Kindle | Saved into `/mnt/us/documents` where the Amazon framework manages them | Set the OPDS download folder to `/mnt/us/koreader-books`. §4. |
| Can't mount the Kindle over USB | KOReader is running; it has no USBMS support | Exit KOReader first. |
| `;kpm install koreader` does nothing | Wi-Fi off, or sources never fetched | Enable Wi-Fi, run `;kpm update` first, reboot if you haven't since jailbreaking. |
| Guides tell you to install KUAL.jar / MRPI / mrpackages | The guide predates the `hdnext` jailbreaks | Ignore it. KUAL is obsolete and does not work on modern jailbreaks. Use `;kpm`. |
| Kindle updated itself and now no jailbreak applies | Storage wasn't filled before Wi-Fi | No downgrade path on stock firmware. Forget all Wi-Fi networks, enable Airplane mode, and wait for a new jailbreak — weeks to months. |

---

## Quick reference card

```
OPDS URL      https://books.sandstorm.chat/opds
Username      kindle
Password      (Vaultwarden)
CWA role      Allow Downloads + Allow Viewer  ONLY

Browse URL    https://books.sandstorm.chat/opds       (Sync catalog OFF)
SYNC URL      https://books.sandstorm.chat/opds/new   (Sync catalog ON)
              ^ sync MUST use /opds/new - /opds has no download links

Get books in  https://books.sandstorm.chat/     (upload button)
              https://bookdl.sandstorm.chat/    (Anna's Archive)
              192.168.1.67:/extra/nfs-csi  ->  data/ingest/books/

KOReader:
  Add catalog     File manager → Search (magnifier) tab → OPDS catalog
                  → ☰ top-left → Add catalog
  Nightly pull    OPDS screen → ☰ → Sync all catalogs   (manual only, no autosync)
  Download dir    OPDS screen → ☰ → Set sync folder     (/mnt/us/koreader-books)
  File types      OPDS screen → ☰ → Set file types to sync  (epub)
  Progress sync   open a book → Tools (wrench) tab → Progress sync
  Wi-Fi           Settings (gear) → Network
                  → Restore Wi-Fi connection on resume = ON

Kindle:
  Install KOReader   home search bar:  ;kpm update
                                       ;kpm install koreader
  Launch             ;kpm launch koreader   (or tap the scriptlet)
  Remove             ;kpm uninstall koreader
```

## Sources

- [KindleModding — Jailbreaking Your Kindle](https://kindlemodding.org/jailbreaking/)
- [KindleModding — Véra](https://kindlemodding.org/jailbreaking/Vera/)
- [KindleModding — What's Next / Installing Homebrew / Getting KOReader](https://kindlemodding.org/jailbreaking/whats-next/)
- [KindleModding — Prevent Automatic Updates](https://kindlemodding.org/jailbreaking/prevent-auto-update/)
- [KindleModding — Jailbreak FAQ](https://kindlemodding.org/jailbreaking/jailbreak-faq.html)
- [The eBook Reader — New "Véra" Jailbreak Released](https://blog.the-ebook-reader.com/2026/08/11/new-vera-jailbreak-released-for-latest-kindles-with-current-software/)
- [koreader/koreader — `plugins/opds.koplugin/opdsbrowser.lua`](https://github.com/koreader/koreader/blob/master/plugins/opds.koplugin/opdsbrowser.lua)
- [koreader/koreader — `plugins/kosync.koplugin/main.lua`](https://github.com/koreader/koreader/blob/master/plugins/kosync.koplugin/main.lua)
- [koreader/koreader issue #14962 — tlsv1 protocol error with CWA (closed)](https://github.com/koreader/koreader/issues/14962)
- [koreader/koreader-sync-server](https://github.com/koreader/koreader-sync-server)
- [Calibre-Web-Automated — `cps/opds.py`, `cps/constants.py`, `cps/templates/feed.xml`](https://github.com/crocodilestick/Calibre-Web-Automated)
- [CrowdSec Hub — `base-http-scenarios`, `http-crawl-non_statics`, `http-logs`](https://github.com/crowdsecurity/hub)
- [Let's Encrypt — New "Generation Y" Hierarchy of Root and Intermediate Certificates](https://letsencrypt.org/2025/11/24/gen-y-hierarchy)
