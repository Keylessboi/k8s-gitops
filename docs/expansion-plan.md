# Expansion plan: federation, gaming, GPU, music

**Written:** 2026-09-13. **Status:** step 0 done; everything else is parked
until the owner picks it back up. Nothing below step 0 has been built.

## Where the hardware stands

| Host | CPU | RAM | Notes |
|---|---|---|---|
| **pve / k3s-server** (CT 200) | i5-10400 | 16 GB, both slots full | 72-73% used. More RAM here means replacing both sticks (board max 64 GB). |
| **NAS** | Ryzen 5 3600, 12 threads, no iGPU | **24 GB** (was 8) | 3 of 4 slots; the 4th is blocked by the cooler. One spare 8 GB stick left over. |
| NAS GPU | RX 5500, **4 GB**, Navi 14 | | **Cannot be removed**: the board halts at the VGA debug LED without it. It draws idle power regardless, so using it only costs load watts. |
| NAS disks | 12 TB + 8 TB mirror (`tank`, 7.25 T), 2.7 TB spare | NVMe 1 TB root, 810 GB free | Second NVMe is out of the machine: it was never enumerated on PCIe and the BOOT-LED hang cleared once it was removed. Test it in another box. |

## Step 0: make the NAS a real worker (DONE 2026-09-13)

- navidrome, lidarr, beets and beets-import, and both mass-search Jobs run on
  the `nas` node (commits a7e0222, 1267acb). Configs are on the NAS NVMe via
  local-path, and media is a `local` PV onto `/extra/nfs-csi/data`, the same
  directory the NFS PVs serve. The old claims are still declared for rollback.
- k3s-agent on the NAS is ordered after `zfs-mount`
  (`/etc/systemd/system/k3s-agent.service.d/10-after-zfs.conf`).
- Wings moved to the NAS: [ADR-0011](adr/0011-wings-on-the-nas.md).
- **Not moved: slskd.** It is a sidecar in the qBittorrent pod behind gluetun,
  so moving it means moving qBittorrent, the VPN and seedboxapi together. That
  would also take the heaviest NFS reader (959 seeding torrents) off the
  network path. It is worth doing, but as its own change.

Placement pattern for anything else that should run on the NAS:

```yaml
nodeSelector:
  kubernetes.io/hostname: nas
tolerations:
  - {key: storage, operator: Equal, value: "true", effect: NoSchedule}
```

## Disk space and compression (reviewed 2026-09-13)

**Compression is not a lever.** Every dataset is already `zstd`, and the pool
compresses at **1.01x** because it holds FLAC, video and torrents that are
already compressed. A higher zstd level would cost CPU and save close to
nothing. Lossy re-encoding of the library is not on the table either.

What actually holds space, largest first:

| What | Size | Lever |
|---|---|---|
| `data/torrents` | 1.2 T **not** hardlinked into the library | Seeding policy. Hardlinks are working, so this is torrents that were never imported: other media, the 188 GB `nextcloud` category backfill, and long-tail seeds. The seed-reaper's thresholds are the real knob. |
| `data/media` | 903 G | The library itself. |
| `tank/appdata/personal` | 566 G | See the spare disk below. |
| `tank` root (MinIO) | 361 G | Backups (CNPG, Wings, etc). Check bucket lifecycles. |
| Snapshots on `tank` | 225 G | **Frees on its own.** 149 G is the 2026-09-09 daily and 22 G the 09-10 daily. Sanoid keeps 7 dailies, so they age out by ~09-17. |
| Manual snapshots | ~14 G | Almost all of it is `tank/extra@immich-pre-port-20260904` (14.3 G unique). `@cutover`, `@cutover2` and `tank/appdata@pre-wave2-20260823` hold only megabytes. Destroy once nobody needs those rollback points. |

Unused capacity found:

- **`sda`, 2.7 TB, btrfs labelled `personal`, not mounted, 565.6 GiB used.**
  That matches `tank/appdata/personal` (566 G), so it looks like the
  pre-migration copy. If a diff confirms it, the disk is free.
- **`sdc2`, 3.6 TB on the 12 TB drive**, carries a stale ZFS label `extra`
  from the old pool (`zpool import` finds nothing). The mirror cannot use it
  while the other side is the 8 TB disk.
- **The 8 TB mirror member has 33,931 power-on hours** (~3.9 years). The 12 TB
  has 2,686. Replacing the 8 TB with another 12 TB grows the mirror to
  ~10.8 TB once `sdc1` is expanded over `sdc2`. That is the one purchase that
  adds real space.

**Not space: the ZFS ARC is raised (DONE 2026-09-14).** The cap was 3.5 GiB
from when the NAS had 7 GB. ADR-0009 traced the pool's latency to ~200 IOPS
shared with 959 seeding torrents and a full ARC, and said raising it had no
headroom *then*. It is now **10 GiB**, set live via
`/sys/module/zfs/parameters/zfs_arc_max` and persisted in
`/etc/modprobe.d/zfs.conf` (backup `zfs.conf.bak-2026-09-14`). The ZFS module
is not in the initramfs, so modprobe.d applies at boot with no rebuild. Budget:
10 GiB ARC + 6 GiB Wings allocation + ~2 GiB pods + the OS leaves headroom on
24 GB. ARC also shrinks under memory pressure.

**Also noticed:** `tank/extra`, which holds every nfs-csi PVC and the library,
has **no sanoid policy**. Only `tank` and `tank/appdata` are snapshotted.

## Parked: Lidarr and beets

Keep disk in mind. Anything database-shaped goes on the **NAS NVMe** (810 GB
free), never on `tank`.

1. **Self-hosted Lidarr metadata.** The official server has been unreliable
   all year. [NC1107/lidarr-metadata-provider](https://github.com/NC1107/lidarr-metadata-provider)
   is one container with a prebuilt MusicBrainz-derived dataset. The Lidarr
   image here (hotio testing / develop) already supports a custom metadata
   URL. Young project, so verify it first.
2. **Local MusicBrainz mirror for beets.** beets' import speed is bounded by
   musicbrainz.org's 1 req/s limit (see the `ratelimit` comment in
   `apps/music/beets-config.yaml`). A local mirror removes it. It is a big
   Postgres plus a search index: put it on NVMe and measure the size before
   committing.
3. **chroma (AcoustID fingerprinting) on imports.** Currently off for automatic
   imports. The NAS has the CPU now.
4. **"Expand search"**: open question. Either more sources (Prowlarr
   indexers, slskd share/search tuning) or more of what Lidarr wants (release
   profiles allowing EPs, singles, live).

## Parked: federation

Public reachability today is 80/443 only, forwarded to Traefik
(`192.168.1.240`).

- **Nextcloud federation.** Nextcloud is already public, so federated shares
  are mostly settings. Cheapest item.
- **XMPP** (Prosody or Snikket, ~100 MB). Needs **5222 and 5269 forwarded**,
  plus a TURN server and UDP ports for calls.
- **PeerTube.** Best use of the GPU. Put it on the NAS (storage plus GPU,
  `/dev/dri/renderD128`). Hardware transcoding via
  [peertube-plugin-hardware-transcode-vaapi](https://github.com/TheoLeCalvar/peertube-plugin-hardware-transcode-vaapi)
  has open AMD bug reports, so test before relying on it. Home upload
  bandwidth is the real limit.
- **Funkwhale was already tried and removed** (d066e8c, 2026-09-03). It
  served zero tracks, federated music never reaches Navidrome, and the network
  is mostly CC/netlabel material. Only revisit it for *publishing*, not for
  growing the library.

## Parked: gaming

- **Game servers**: Pelican plus Wings, now on the NAS. CPU-bound, not GPU.
- **Game streaming**: [Wolf / Games on Whales](https://github.com/games-on-whales/wolf).
  Headless, virtual displays, VAAPI encode on the RX 5500, Moonlight clients.
  Docker rather than k8s (their k8s project is not released), so it would sit
  beside Wings on the NAS host. Expect emulation, indie and older titles at
  1080p, not current AAA, on a 4 GB card.

## Open questions for the owner

1. Order after step 0. The proposal was Lidarr metadata, then Nextcloud
   federation and XMPP, then PeerTube, then gaming.
2. Home upload bandwidth.
3. XMPP needs 5222/5269 and TURN UDP. Game ports need no manual forwards:
   `pelican-portmap` leases them over UPnP while a server runs (now from the
   NAS). The router's UPnP could do the same for XMPP, or those could be
   static forwards.
4. Move qBittorrent + slskd + gluetun to the NAS?
5. Is `sda` (btrfs `personal`) really a stale copy, and can it be wiped?

## Backlog carried over from the task list (2026-09-14)

Cleared from the session task list at the owner's request, then worked the same
day. See `docs/doctor-log.md` 2026-09-14 for detail.

**Done 2026-09-14:**
- Prometheus TSDB off nfs-csi: on the NAS NVMe (4c6d28f). WAL replay 4.4s, down
  from ~9.5 min. 20.7 days of history kept.
- CrowdSec stale-bouncer alert (`CrowdSecBouncerNotPulling`, 8f91db6), plus the
  cause of LAPI restarting on every push (random chart secrets, now pinned from
  Doppler).
- CrowdSec orphan machine rows: auto-deleted after 24h (8bf7b69).
- qBittorrent "firewalled": stale tun0 sockets after a gluetun restart, fixed,
  plus a liveness probe so it self-heals.
- The NAS's node-exporter was never scraped (2fff431).
- `nextcloud-upload-sweep` is suspended **on purpose** (ec6220a, "stop
  uploading games"). Not a fault.

**Still open (blocked or waiting):**
- **pve / k3s-server RAM**, ~81%. Needs a 2x16/2x32 GB kit, or a decision to
  move qBittorrent + slskd + gluetun to the NAS.
- **After a soak period:** remove step 0's rollback copies
  (`navidrome-data-local`, `lidarr-config-local`, the nfs `media-data` PVs,
  `beets-config` nfs), `/root/wings-import` on the NAS, and the Released
  Prometheus nfs PV `pvc-946cbad0`.
- **k3s upgrades no longer update CoreDNS** (`coredns.yaml.skip`). Bump the
  image by hand.
