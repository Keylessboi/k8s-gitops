# cellarr: shadow, cutover and rollback

cellarr is a Rust reimplementation of Lidarr that serves the same `/api/v1`.
This runbook takes it from a read-only shadow to replacing Lidarr, and back.
Each step says what it changes and how to undo it. **Nothing here is applied
by merging this branch alone**, except the shadow, which is read-only.

Source: `github.com/Keylessboi/cellarr`, branch `ccr-28dccdf6-ysjbz9`.

## What is and is not verified

Verified off-cluster, against a production-sized copy (914 artists, 41,459
albums, 1.03M tracks, 35,798 track files, 934,521 history rows, 16,271
blocklist rows):

- the migration (278 s, 119 MiB peak, 505 MB database);
- the API answers Octo, the maintenance script, the search sniper, the mass
  search and Prowlarr make, replayed as contract tests against real Lidarr's
  field types;
- memory: 30 MiB idle, about 220 MiB after the full artist and album lists,
  125 MiB peak while streaming the whole 935k-row history. Lidarr sits near
  900 MiB;
- shadow mode never writes: no scheduled jobs, and every non-GET request
  returns 403;
- torrents are never removed after import (seed-reaper and private-tracker
  rules depend on that); only Usenet downloads are cleaned up.

**Not verified, and needing the cluster:**

- Tubifarry (Soulseek, YouTube, Lucida, DABMusic) and AppleMusicarr through
  cellarr's plugin sidecar. The sidecar is tested against a stock Lidarr with
  its built-in clients, not these plugins. Until step 4 passes, cutting over
  loses those sources.
- Prowlarr's application sync against cellarr (contract-tested only).
- The 3.9 GB real `lidarr.db`, as opposed to a synthetic copy of the same
  shape.

## 0. Build the image

GitHub Actions is not enabled on the fork, so there is no published image yet.
`apps/cellarr-shadow/kustomization.yaml` pins an all-zero digest that cannot
pull, so the shadow sits in `ImagePullBackOff` and does nothing until this
step is done.

Either enable Actions on `Keylessboi/cellarr` (Settings → Actions) and run the
`release` workflow on the branch (Actions → release → Run workflow), which
pushes `ghcr.io/keylessboi/cellarr:sha-<commit>`, or build on a machine with
Docker:

```sh
git clone -b ccr-28dccdf6-ysjbz9 https://github.com/Keylessboi/cellarr && cd cellarr
(cd web && npm ci && npm run build)
cargo install cross
cross build --release --locked -p cellarr-cli --target x86_64-unknown-linux-musl
cp target/x86_64-unknown-linux-musl/release/cellarr cellarr-amd64
docker buildx build --platform linux/amd64 -t ghcr.io/keylessboi/cellarr:shadow --push .
```

Then pin the digest. It must be the manifest digest the registry reports,
not a local image id:

```sh
docker buildx imagetools inspect ghcr.io/keylessboi/cellarr:shadow | grep Digest
```

Put it in `apps/cellarr-shadow/kustomization.yaml` under `images[0].digest`.
If the package is private, the nas node needs pull credentials, or make the
package public; nothing secret is in the image.

## 1. Shadow: deploy

`apps/cellarr-shadow` (namespace `lidarr`):

| Object | What |
|---|---|
| PVC `cellarr-shadow-data` | cellarr's own SQLite plus the transient snapshot, local-path on nas |
| Deployment `cellarr-shadow` | `CELLARR_SHADOW=true`, Lidarr API on 8686; Lidarr's config and `/data` mounted **readOnly** |
| Service `cellarr-shadow:8686` | Nothing points at it except the diff |
| CronJob `cellarr-shadow-diff` | 04:41 UTC daily, GET-only diff (100 random artists' track files, no full album list), report in the Job log |
| CronJob `cellarr-shadow-diff-full` | Suspended; the same diff over every artist, run on demand |

On first start the `migrate` initContainer runs
`cellarr snapshot /lidarr-config/lidarr.db …`, a `VACUUM INTO` on a read-only
connection. That is one consistent copy, with no write lock: Lidarr keeps
writing throughout. It then runs `cellarr migrate` on the copy and deletes it.
Expect several minutes for the real database. A marker file makes later
restarts skip it.

Render and dry-run before pushing, as for any app:

```sh
kubectl kustomize apps/cellarr-shadow | kubectl apply --dry-run=server --validate=strict -f -
```

Check it is up:

```sh
kubectl -n lidarr logs deploy/cellarr-shadow -c migrate      # the migration report
kubectl -n lidarr get pods -l app.kubernetes.io/name=cellarr-shadow
kubectl -n lidarr top pod -l app.kubernetes.io/name=cellarr-shadow
```

**Undo:** delete `apps/cellarr-shadow` from git. The PVC stays (protect-state);
deleting it is yours.

## 2. Shadow: re-sync

The shadow is a snapshot; it drifts as Lidarr grabs and imports. To refresh
it, remove the marker and the database, then restart. Only the shadow's own
volume is touched:

```sh
kubectl -n lidarr exec deploy/cellarr-shadow -c cellarr -- \
  sh -c 'rm -f /cellarr/.migrated-from-lidarr /cellarr/cellarr.sqlite*'
kubectl -n lidarr rollout restart deploy/cellarr-shadow
```

(`/cellarr` holds `cellarr.sqlite` and its `-wal`/`-shm`, `MediaCover/` and
`logs/`. Only the database goes.)

## 3. Verify: the gate for cutover

1. Run the diff once in full, right after a re-sync. `cellarr-shadow-diff-full`
   is the same diff over every artist, suspended so it only runs on demand:

   ```sh
   kubectl -n lidarr create job --from=cronjob/cellarr-shadow-diff-full diff-full-$(date +%s)
   kubectl -n lidarr logs -f job/diff-full-<that suffix>
   ```

   **Gate:** `OK` for every config section (quality and metadata profiles,
   root folders, indexers, download clients with their categories), artists
   and track files. The queue and the newest albums may differ by what Lidarr
   did since the snapshot, and nothing else.
2. Let the nightly diff run for a week. Each night should look like step 1.
   It skips the album list to spare Lidarr, so re-run the full diff once more
   just before cutover. The full album list is Lidarr's heaviest call, so run
   it when nothing else is hammering Lidarr.
3. Spot-check by hand what the clients read, against both Services. The same
   GET to each should give the same answer:
   `/api/v1/system/status`, `/api/v1/artist`, `/api/v1/wanted/missing?page=1&pageSize=50`,
   `/api/v1/queue`, `/api/v1/history?page=1&pageSize=50`.

## 4. Plugin sidecar rehearsal (needs your go-ahead)

Soulseek, YouTube, Lucida, DABMusic and Apple Music are .NET Lidarr plugins.
cellarr runs them through a **sidecar**: a stock Lidarr with an empty library
that hosts the plugins. cellarr mirrors its download clients into it, and asks
it to search and grab. The sidecar imports into a staging folder, and cellarr
takes it from there.

To rehearse, add a second container or Deployment beside the shadow:

- the same image and plugin initContainer as `apps/lidarr` (hotio
  `testing-3.1.3.4987`, `applemusicarr-plugin:0.1.2`), with a **fresh** config
  PVC, never Lidarr's. Install Tubifarry v2.1.1 through its System → Plugins
  page, as in `apps/lidarr`;
- `/data` mounted read-write, with a staging root such as
  `/data/torrents/music/.cellarr-staging`, on the same filesystem so imports
  hardlink;
- on cellarr: `CELLARR_PLUGINS__DOTNET_SIDECAR_URL`, `…_KEY` (the sidecar's
  own key, through a secret) and `…_ROOT` set to the staging root.

The rehearsal cannot run in shadow mode, because grabbing is a write. Run it
against a **separate** cellarr instance with its own empty library and one
test album. Never point a non-shadow cellarr at the production library before
step 5.

**Gate:** one album each through Soulseek, YouTube and Apple Music lands
complete in the test library.

## 5. Cutover

Do it in one commit, at a quiet time, with the queue empty or near it:

1. **Stop Lidarr**: `apps/lidarr/deployment.yaml` `replicas: 0`. Lidarr's PVC,
   database and plugins stay exactly as they are: that is the rollback.
2. **Re-sync** (step 2) so cellarr migrates the database as Lidarr left it,
   with nothing in flight.
3. In `apps/cellarr-shadow/deployment.yaml`:
   - remove `CELLARR_SHADOW`;
   - mount `/data` read-write (drop both `readOnly: true` on `data`);
   - add the sidecar settings from step 4, if it passed.
4. Point the `lidarr` Service at cellarr. In `apps/lidarr/deployment.yaml`,
   set the Service's selector to `app.kubernetes.io/name: cellarr-shadow`.
   Octo, Prowlarr, the maintenance, sniper and mass-search jobs, Hermes and the
   Ingress keep using `lidarr:8686` unchanged.
5. Suspend the `cellarr-shadow-diff` CronJob (`suspend: true`). With Lidarr
   stopped it has nothing to compare.

Watch: `kubectl -n lidarr logs -f deploy/cellarr-shadow`, then the next
search-sniper and maintenance runs, and Octo's next hand-off.

Two behaviours differ from Lidarr and are known:

- the web UI at the Lidarr Ingress is cellarr's own UI on port 9494, not
  Lidarr's. Port 8686 is API only. Add an Ingress path to 9494 if you want the
  UI;
- a stalled or failed download is still removed from the client when it is
  blocklisted (Lidarr's default too). Torrents that imported are never removed.

## 6. Rollback

Revert the cutover commit. That restores Lidarr to `replicas: 1`, the
Service selector to Lidarr, and the shadow to read-only. Lidarr starts on its
untouched database.

What does not carry back: anything cellarr did while it was live. Files it
imported are in the library folders, and Lidarr picks them up on its next
disk scan (or run `RescanFolders`). Its grabs, history and blocklist entries
are not in Lidarr's database. Downloads still in flight in qBittorrent stay
there; Lidarr does not know them and will not import them, so import them by
hand with Manual Import.

cellarr never writes `lidarr.db`: the shadow mounts it readOnly, and after
cutover nothing mounts it at all.
