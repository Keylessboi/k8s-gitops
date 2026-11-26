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

The nightly `cellarr-shadow-diff-fresh` CronJob (04:11 UTC) does not need a
re-sync: it snapshots Lidarr itself into its own scratch volume
(`cellarr-diff-scratch`), runs a throwaway shadow cellarr in the same pod and
diffs against that, so its log shows only differences that are not live drift.
It needs no RBAC and never touches `cellarr-shadow`.

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
that hosts the plugins. cellarr mirrors its download clients and indexers into
it and asks it to search and grab. The sidecar imports into a staging root
folder, and cellarr takes it from there.

The rehearsal cannot run in shadow mode, because grabbing is a write. It runs a
**separate** cellarr with its own empty database and library.
`apps/cellarr-shadow/rehearsal/` holds it. ArgoCD never syncs that directory
(the ApplicationSet only reads `apps/*`, and `apps/cellarr-shadow/kustomization.yaml`
does not list it), so you apply it and remove it by hand.

| Object | What |
|---|---|
| Deployment `cellarr-rehearsal` | One Pod on nas. Container `cellarr` (not shadow; API 8686, UI 9494) and container `lidarr-sidecar` (hotio `testing-3.1.3.4987` pinned by digest, on 8687, reached by cellarr at `127.0.0.1:8687`). initContainers: `install-plugin` (AppleMusicarr, copied from `apps/lidarr`) and `prepare-dirs` (`mkdir -p` only) |
| PVC `cellarr-rehearsal-data` | cellarr's SQLite, new and empty, local-path on nas |
| PVC `cellarr-rehearsal-sidecar-config` | the sidecar's `/config`, new and empty, local-path on nas. **Not** `lidarr-config-nas` |
| Secret `cellarr-rehearsal` | not in git; you create it below. `sidecar-api-key` (read by both containers), `cellarr-api-key` |

How it is kept away from production:

- **Only `/data/torrents` is mounted** (subPath `torrents` of `media-data-nas`).
  The production library, `/data/media/music`, is not in the Pod's filesystem
  at all, so no setting can import into it, rename it or tag it. What it
  cannot avoid: production's downloads under `/data/torrents` are visible
  read-write. slskd and the decryptor write to fixed folders there, and a
  hardlink cannot cross mounts, so the mount cannot be any narrower.
- **Its own folders**, all on that one mount so every step hardlinks:
  `/data/torrents/cellarr-rehearsal/library` (the rehearsal library),
  `…/staging` (the sidecar's root folder, `CELLARR_PLUGINS__DOTNET_SIDECAR_ROOT`),
  `…/downloads` (Tubifarry's in-process clients: YouTube, Lucida, DABMusic) and
  `…/qbittorrent` (the qBittorrent category's save path). Navidrome and beets
  only read `/data/media/music`, so none of it shows up in the players.
- **qBittorrent** gets its own category, `music-rehearsal`. seed-reaper only
  lists category `music`, and production Lidarr only polls its own category.
- **slskd and the Apple Music decryptor** each have one fixed output folder
  (`/data/torrents/soulseek`, `/data/torrents/apple`) shared with production.
  So the test album is by an artist **not** in production Lidarr's library:
  neither Lidarr can match the other's download to anything it monitors.
- **Tags.** The sidecar's tag writing stays off (Lidarr's default for a fresh
  config; checked below), so nothing rewrites a hardlinked download. ADR-0004
  is about the production library, which this never reaches.

Network: everything is in the `lidarr` namespace, so `apps/lidarr`'s
`app-isolation` policy (`podSelector: {}`) treats this Pod exactly like Lidarr.
cellarr to the sidecar is the Pod's loopback and needs no rule. The flows the
sidecar needs:

| Flow | lidarr egress | other end's ingress |
|---|---|---|
| slskd `downloads:5030` | yes | yes (from `lidarr`, 5030) |
| qBittorrent `downloads:8080` | yes | yes (from `lidarr`, 8080) |
| Prowlarr `prowlarr:9696` | yes | yes (from `lidarr`, 9696) |
| FlareSolverr `flaresolverr:8191` | yes | yes |
| decryptor → applemusic-wrapper `:8080` | yes | yes (from `lidarr`, 8080) |
| internet 443 (metadata, GitHub for the plugin install, YouTube, Apple, Lucida) | yes (`0.0.0.0/0` minus private) | n/a |
| **in-namespace**: applemusic-decryptor `:8080`, bgutil-provider `:4416`, lucida-solver `:8080` | **no**: in-namespace egress is 8686 only | yes (from `lidarr`, any port) |

The last row is the same for production Lidarr: on paper its AppleMusicarr,
YouTube (PO token) and Lucida clients cannot reach their helpers either. If
they work for Lidarr, kube-router is admitting the traffic despite the policy,
and they work for the sidecar too. If the Apple Music or YouTube grab fails
with `connection refused`, this is why. The fix belongs in
`apps/lidarr/networkpolicy.yaml` (production, so a deliberate commit): an
egress rule to `namespaceSelector: kubernetes.io/metadata.name: lidarr` on
TCP 8080 and 4416, beside the existing 8686 rule.

### 4.1 Before you start

- Step 0 is done, and the same digest is in **both**
  `apps/cellarr-shadow/kustomization.yaml` and
  `apps/cellarr-shadow/rehearsal/kustomization.yaml`.
- Pick the test album: a short album (a few tracks) by an artist that is
  **not** in production Lidarr's library (search Lidarr's UI for it), and that
  Apple Music, YouTube Music and Soulseek all have. Note its artist's and
  release group's MusicBrainz ids.
- Note from production Lidarr's Settings → Download Clients and Indexers the
  settings of its Slskd, YouTube and AppleMusicarr entries (slskd URL and API
  key, the decryptor URL, the PO token server). You will enter the same values.
- Note Tubifarry's GitHub URL from production:
  `GET /api/v1/system/plugins` on Lidarr, field `githubUrl`.

### 4.2 Create the secret

Two keys of 32 lowercase hex characters, the shape Lidarr generates. Keep both
in your shell for the commands below; nothing here prints them.

```sh
kubectl -n lidarr create secret generic cellarr-rehearsal \
  --from-literal=sidecar-api-key='<32 lowercase hex characters>' \
  --from-literal=cellarr-api-key='<another 32 lowercase hex characters>'
```

Or generate them into variables and create the secret from those:

```sh
SIDECAR_KEY=$(openssl rand -hex 16); CELLARR_KEY=$(openssl rand -hex 16)
kubectl -n lidarr create secret generic cellarr-rehearsal \
  --from-literal=sidecar-api-key="$SIDECAR_KEY" \
  --from-literal=cellarr-api-key="$CELLARR_KEY"
```

The sidecar takes its key from `LIDARR__AUTH__APIKEY`. That is Lidarr's own
convention, checked in the source at tag `v3.1.3.4987`: `Bootstrap.cs` binds
the `Lidarr:Auth` configuration section, environment variables included, and
`ConfigFileProvider.ApiKey` prefers it over `config.xml`. Not yet checked
against a running pod; 4.4 checks it.

### 4.3 Apply

```sh
kubectl kustomize apps/cellarr-shadow/rehearsal | kubectl apply --dry-run=server --validate=strict -f -
kubectl apply -k apps/cellarr-shadow/rehearsal
kubectl -n lidarr rollout status deploy/cellarr-rehearsal --timeout=10m
kubectl -n lidarr logs deploy/cellarr-rehearsal -c prepare-dirs
```

The sidecar runs Lidarr's binary directly as uid 1000 with a read-only root
filesystem, not through hotio's s6 `/init` (which needs root). If it does not
come up, `kubectl -n lidarr logs deploy/cellarr-rehearsal -c lidarr-sidecar`
says why; a write to a path outside `/config` and `/tmp` is the likely one.

Then, in a second terminal, keep a port-forward open (cellarr's Lidarr API, its
UI, the sidecar):

```sh
kubectl -n lidarr port-forward deploy/cellarr-rehearsal 18686:8686 19494:9494 18687:8687
```

```sh
C=http://127.0.0.1:18686/api/v1; S=http://127.0.0.1:18687/api/v1
c() { curl -fsS -H "X-Api-Key: $CELLARR_KEY" -H 'Content-Type: application/json' "$@"; }
s() { curl -fsS -H "X-Api-Key: $SIDECAR_KEY" -H 'Content-Type: application/json' "$@"; }
```

### 4.4 Check the sidecar, install Tubifarry

```sh
s "$S/system/status" | jq '{version, appData}'       # 3.1.3.4987, /config: the key from the Secret works
s "$S/system/plugins" | jq '.[].name'                # AppleMusicarr, from the initContainer
s "$S/config/metadataprovider" | jq .writeAudioTags  # must be "no"
```

Install Tubifarry through cellarr, which forwards the command to the sidecar
(use the `githubUrl` production reports):

```sh
c -X POST "$C/command" -d '{"name": "InstallPlugin", "githubUrl": "<Tubifarry githubUrl from production>"}'
```

Or in the sidecar's own UI at `http://127.0.0.1:18687`, System → Plugins. A
fresh Lidarr asks you to set up authentication on the first UI visit; the API
key works without it. Lidarr restarts to load the plugin; if the port-forward
drops, start it again. Then:

```sh
s "$S/system/plugins" | jq '.[] | {name, version: .installedVersion}'   # Tubifarry and AppleMusicarr
c "$C/downloadclient/schema" | jq -r '.[].implementation'              # now lists the plugins' clients
c "$C/indexer/schema" | jq -r '.[].implementation'
```

Lidarr installs the newest compatible Tubifarry release; its API cannot pin a
tag. If that is not v2.1.1, write the version down: the rehearsal then tests a
newer Tubifarry than production runs.

### 4.5 Configure one test album

In cellarr's UI at `http://127.0.0.1:19494` (or `POST $C/indexer` and
`POST $C/downloadclient` from the schemas above), add the Slskd, YouTube and
AppleMusicarr indexer and download client, with production's values except:

- any **download path** for YouTube (and Lucida, DABMusic if you add them):
  `/data/torrents/cellarr-rehearsal/downloads`. Any tool path the YouTube
  client writes (ffmpeg) goes under `/config`: the sidecar's root filesystem is
  read-only. Leave the cookie path empty (`bgutil-provider` supplies the PO
  token);
- AppleMusicarr's download path stays production's (`/data/torrents/apple`):
  the decryptor's output folder is fixed;
- slskd's download folder is fixed (`/data/torrents/soulseek`);
- qBittorrent, if you add it: category `music-rehearsal`, created first in
  qBittorrent with save path `/data/torrents/cellarr-rehearsal/qbittorrent`.

Run `POST $C/indexer/test` and `POST $C/downloadclient/test` on each (the UI's
Test button). Then the library and the album:

```sh
c -X POST "$C/rootfolder" -d '{"name": "rehearsal", "path": "/data/torrents/cellarr-rehearsal/library",
  "defaultMetadataProfileId": 1, "defaultQualityProfileId": 1}'
c -X POST "$C/artist" -d '{"foreignArtistId": "<artist MBID>", "artistName": "<artist>",
  "qualityProfileId": 1, "metadataProfileId": 1, "monitored": true,
  "rootFolderPath": "/data/torrents/cellarr-rehearsal/library",
  "addOptions": {"monitor": "none", "searchForMissingAlbums": false}}' | jq .id
c "$C/album?artistId=<artist id>" | jq '.[] | select(.foreignAlbumId == "<release group MBID>") | .id'
c -X PUT "$C/album/monitor" -d '{"albumIds": [<album id>], "monitored": true}'
```

### 4.6 One search and grab per source

For each of Soulseek, YouTube and Apple Music in turn, search, pick that
source's best release, grab it and wait:

```sh
c "$C/release?albumId=<album id>" | jq '.[] | {indexer, indexerId, guid, title, rejections}'
c -X POST "$C/release" -d '{"guid": "<guid>", "indexerId": <indexerId>}'
c "$C/queue" | jq '.records[] | {title, status, trackedDownloadState, statusMessages}'   # until it leaves the queue
c "$C/trackfile?albumId=<album id>" | jq '.[] | .path'
kubectl -n lidarr exec deploy/cellarr-rehearsal -c cellarr -- ls -lR /data/torrents/cellarr-rehearsal/library
```

Before the next source, clear the album's files from the rehearsal library so
the next import is not refused as "not an upgrade":

```sh
c -X DELETE "$C/trackfile/bulk" -d "{\"trackFileIds\": $(c "$C/trackfile?albumId=<album id>" | jq -c '[.[].id]')}"
```

**Success looks like**, for each of the three sources:

- the grab goes through the sidecar: `s "$S/queue"` shows it while it downloads;
- it lands in `/data/torrents/cellarr-rehearsal/staging` first, then in
  `/data/torrents/cellarr-rehearsal/library/<artist>/<album>`, every track of the
  album present (`trackfile` count equals the album's track count);
- `ls -li` shows each library file with a link count of 2 or more wherever
  its download still exists: a hardlink, not a copy;
- the staged copy is removed once cellarr has imported, and nothing appeared in
  `/data/media/music` or production Lidarr's queue/history (`Activity` in
  Lidarr's UI).

**Gate:** all three sources land complete. Lucida and DABMusic are worth one
try each while you are here, but are not part of the gate.

### 4.7 Teardown

```sh
kubectl delete -k apps/cellarr-shadow/rehearsal -l homelab/rehearsal-part=workload
```

The `-l` is load-bearing. protect-state's `Prune=false,Delete=false` stops
**ArgoCD** deleting a PVC; `kubectl` ignores it, so a plain
`kubectl delete -k apps/cellarr-shadow/rehearsal` deletes both PVCs as well, and
local-path deletes their data with them. With the selector only the Deployment
goes; the two PVCs and the Secret stay for a re-run. Deleting them is yours,
when you are done:

```sh
kubectl delete -k apps/cellarr-shadow/rehearsal -l homelab/rehearsal-part=state
kubectl -n lidarr delete secret cellarr-rehearsal
```

What is left on the media volume is yours to remove too:
`/extra/nfs-csi/data/torrents/cellarr-rehearsal` on nas, the test album's
folders under `/data/torrents/soulseek` and `/data/torrents/apple`, the
transfers in slskd's UI, and the `music-rehearsal` category in qBittorrent.

## 5. Cutover

Do it in one commit, at a quiet time, with the queue empty or near it:

1. **Stop Lidarr**: `apps/lidarr/deployment.yaml` `replicas: 0`. Lidarr's PVC,
   database and plugins stay exactly as they are: that is the rollback.
2. **Re-sync** (step 2) so cellarr migrates the database as Lidarr left it,
   with nothing in flight.
3. In `apps/cellarr-shadow/deployment.yaml`:
   - remove `CELLARR_SHADOW`;
   - mount `/data` read-write (drop both `readOnly: true` on `data`);
   - the plugin sidecar (`lidarr-sidecar`, its init containers, PVC
     `cellarr-sidecar-config` and the `CELLARR_PLUGINS__DOTNET_SIDECAR_*`
     variables) is already in this file in the cutover PR: set it up as in
     "Plugin sidecar" below, **before** step 4.
4. Point the `lidarr` Service at cellarr. In `apps/lidarr/deployment.yaml`,
   set the Service's selector to `app.kubernetes.io/name: cellarr-shadow`.
   Octo, Prowlarr, the maintenance, sniper and mass-search jobs, Hermes and the
   Ingress keep using `lidarr:8686` unchanged.
5. Suspend the `cellarr-shadow-diff` and `cellarr-shadow-diff-fresh` CronJobs (`suspend: true`). With Lidarr
   stopped it has nothing to compare.

### Plugin sidecar (interim, before the Service flips)

Soulseek and Apple Music are plugin-protocol download clients. After cutover
cellarr drives them through a stock-Lidarr sidecar in its own Pod, exactly as
in the step 4 rehearsal, until native Rust clients replace it. The cutover PR
adds to `apps/cellarr-shadow`: container `lidarr-sidecar` (the rehearsal's
digest-pinned hotio `testing-3.1.3.4987`, port 8687 on the Pod's loopback),
init containers `install-plugin` (AppleMusicarr 0.1.2, as `apps/lidarr`) and
`prepare-sidecar-dirs` (`mkdir -p /data/torrents/cellarr-sidecar-staging`),
PVC `cellarr-sidecar-config` (1Gi local-path on nas, new and empty, never
Lidarr's config) and a `NetworkPolicy` `cellarr-sidecar-egress`.

**The migrated cellarr download-client and indexer rows for Slskd and
AppleMusicarr only work once the sidecar has its twins.** Until step 5 below is
done, searches and grabs through those two sources fail; qBittorrent is
cellarr-native and unaffected.

Isolation, as in the rehearsal: the sidecar mounts `/data/torrents` only
(subPath `torrents`), so `/data/media/music` and Lidarr's config are not in its
filesystem. slskd writes `/data/torrents/soulseek` and the Apple decryptor
`/data/torrents/apple`; both are the same paths in the sidecar and in cellarr
(which mounts all of `/data`), on one volume. Its root folder,
`CELLARR_PLUGINS__DOTNET_SIDECAR_ROOT=/data/torrents/cellarr-sidecar-staging`,
is the same path in both containers. Ports: cellarr owns 8686 and 9494, the
sidecar 8687; no clash in the shared network namespace.

Memory: the sidecar adds about 224 MiB idle (observed in the rehearsal, empty
library); request 256Mi, limit 1Gi. Lidarr's own 3Gi is for the 41k-album
library, which the sidecar never holds, and Lidarr is at `replicas: 0`.

Network: `apps/lidarr`'s `app-isolation` policy selects every Pod in the
namespace (`podSelector: {}`), so the cellarr-shadow Pod already has what
Lidarr's Pod had: slskd (`downloads:5030`), qBittorrent, Prowlarr,
FlareSolverr, the Apple wrapper and 443 out. slskd's ingress already admits the
`lidarr` namespace on 5030. The one gap is the in-namespace egress to
`applemusic-decryptor:8080` (see the table in step 4; production Lidarr has the
same gap on paper). `apps/cellarr-shadow/networkpolicy.yaml` adds exactly that,
from the cellarr-shadow Pod to the decryptor Pod on TCP 8080, and nothing
broader. It is additive, so it cannot narrow anything.

Because the Service flip is in the same commit as the sidecar, land the cutover
in two pushes: the PR **without** the `lidarr` Service selector hunk in
`apps/lidarr/deployment.yaml`, then this section, then the selector hunk as a
second commit. (Lidarr is already at `replicas: 0` after the first push, so
clients see errors in between either way.)

1. **Create the Secret** (not in git; the command never prints the value):

   ```sh
   kubectl -n lidarr create secret generic cellarr-sidecar \
     --from-literal=sidecar-api-key="$(openssl rand -hex 16)"
   ```

   Load it into your shell for the steps below without printing it (assign it,
   never echo it): `SIDECAR_KEY` is the Secret's `sidecar-api-key` value.
2. **Sync** (push the first part) and wait for the Pod:
   `kubectl -n lidarr rollout status deploy/cellarr-shadow --timeout=10m`.
   Check `kubectl -n lidarr logs deploy/cellarr-shadow -c prepare-sidecar-dirs`
   and that `lidarr-sidecar` is Ready. The sidecar does not start until the
   Secret exists.
3. **Port-forward and helper**, as in 4.3 but for this Pod:

   ```sh
   kubectl -n lidarr port-forward deploy/cellarr-shadow 18686:8686 18687:8687
   S=http://127.0.0.1:18687/api/v1
   s() { curl -fsS -H "X-Api-Key: $SIDECAR_KEY" -H 'Content-Type: application/json' "$@"; }
   s "$S/system/status" | jq '{version, appData}'        # 3.1.3.4987
   s "$S/system/plugins" | jq '.[].name'                 # AppleMusicarr
   s "$S/config/metadataprovider" | jq .writeAudioTags   # must be "no"
   ```

4. **Install Tubifarry** in the sidecar through the same steps as 4.4
   (`InstallPlugin` with the `githubUrl` production reports; Lidarr restarts to
   load it; re-open the port-forward if it drops), then confirm
   `s "$S/downloadclient/schema" | jq -r '.[].implementation'` lists Slskd and
   AppleMusicarr.
5. **Create the Slskd and AppleMusicarr indexer and download client in the
   sidecar** (`POST $S/indexer`, `POST $S/downloadclient`, bodies from the
   schemas), with production's values (slskd URL, the decryptor URL, names and
   settings from production Lidarr's Settings, as in 4.1) **except the
   secrets**. Production's `apiKey` fields come back **masked** from
   `GET /api/v1/downloadclient`, so do not copy them from that output: take the
   real slskd key from the Secret or secret store it comes from (as the
   rehearsal had to) and splice it into the body server-side, in a shell
   variable, without printing it. Download paths stay
   `/data/torrents/soulseek` and `/data/torrents/apple`. If the import cannot
   find slskd's files because its `outputPath` is relative, use the per-album
   remote path mapping workaround from the rehearsal.
6. **Verify cellarr resolves them**: with cellarr's key,
   `GET http://127.0.0.1:18686/api/v1/downloadclient` and `/indexer` list the
   migrated Slskd and AppleMusicarr rows, and `POST .../downloadclient/test`
   and `.../indexer/test` on each pass (they reach the sidecar's twins over
   loopback). Only then push the Service selector hunk.

Rollback: revert the cutover commit. Lidarr comes back (it never knew the
sidecar) and the sidecar goes with the Deployment. The PVC
`cellarr-sidecar-config` and the Secret `cellarr-sidecar` are kept
(protect-state, and a hand-made Secret), so a re-cutover finds Tubifarry and
the twins already configured. Delete them by hand only when you are done:
`kubectl -n lidarr delete pvc cellarr-sidecar-config secret/cellarr-sidecar`.

Watch: `kubectl -n lidarr logs -f deploy/cellarr-shadow`, then the next
search-sniper and maintenance runs, and Octo's next hand-off.

Two behaviours differ from Lidarr and are known:

- the web UI at the Lidarr Ingress is cellarr's own UI on port 9494, not
  Lidarr's. Port 8686 is API only. Add an Ingress path to 9494 if you want the
  UI;
- a stalled or failed download is still removed from the client when it is
  blocklisted (Lidarr's default too). Torrents that imported are never removed.
- cellarr never writes audio tags. Lidarr ran with `writeAudioTags: sync`,
  so after cutover nothing keeps file tags in step with MusicBrainz. That is
  safe for seeding (ADR-0004's hazard is a tool rewriting hardlinked files),
  but ADR-0004 names Lidarr as the tag writer and needs an update to match.

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
