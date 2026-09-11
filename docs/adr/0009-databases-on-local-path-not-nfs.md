# ADR-0009: Databases live on node-local disk; NFS carries bulk media only

**Status:** Accepted
**Date:** 2026-09-11

## Context

Five apps were found running SQLite on the `nfs-csi` storage class, and every
one of them was pathologically slow in a way that read as an application bug:

| App | Database | Symptom |
|---|---|---|
| remux | `db.sqlite` | single-row primary-key lookups taking 17-21s |
| prowlarr | `prowlarr.db` | a 125s indexer fetch |
| crowdsec | `crowdsec.db` (7 MB) | decision stream 7.6-28.5s, bouncer failed CLOSED, total lockout |
| lidarr | `lidarr.db` (**3.94 GB**) | `GET /api/v1/artist` >180s; mass search at 1 album/hour |
| navidrome | `navidrome.db` (149 MB) | search fails while playback works |

Each was first misdiagnosed as something else - a corrupt database, a wrong
credential, a bad plugin, a slow indexer. The navidrome case is the clearest
tell: playback streams files sequentially from the media mount and always
worked, while search queries the database and always failed. Same server, same
network, opposite outcomes.

### Why it is slow - measured, not assumed

The NAS pool is a **two-disk mirror of spinning disks** (`rotational=1` on
both), healthy, 61% full, no SLOG and no special vdev. It has **7 GB of RAM
total**, of which ARC is capped at 3.5 GB and sits permanently full.

    tank  4.43T  2.82T  79 reads 161 writes   total_wait 223ms read / 34ms write
                                              asyncq_wait 427ms read

Two properties of `tank/extra` - which holds the nfs-csi PVCs **and** the bulk
media, on one dataset - make it worse:

- `recordsize=128K`. SQLite does 4 KiB page I/O, so every database page read
  pulls a 128 KiB record: **32x read amplification** on a device that can
  serve maybe 100-150 random IOPS.
- `primarycache=all`. Media streaming and torrent writes evict database pages
  from a 3.5 GB ARC that is already at its ceiling.

### What was tried and rejected

- **`sync=disabled` on the dataset.** Already set, and it is the reason the
  obvious fix does nothing: a 512-byte fsync still measures ~1.9s and a SQLite
  commit ~7.5s. The bottleneck is not the ZIL, it is random read latency,
  128K read amplification, and ARC pressure. This is the single most
  misleading fact about this pool - disabling sync looks like it should fix
  everything and it does not.
- **Raising `zfs_arc_max`.** The NAS has 7 GB of RAM with ~1 GB available.
  There is no headroom worth taking.
- **Moving the database to a fresh inode / dropping caches.** Fixed one
  specific NFSv4 delegation hang (crowdsec, 2026-09-11) but does nothing for
  throughput.
- **Postgres instead of SQLite.** Rejected per-app: most of these apps either
  do not support it or support it badly, and it trades a storage problem for a
  migration problem.

## Decision

**Anything that does small random I/O - every embedded database - gets a
`local-path` PVC on the node's disk. NFS carries bulk media and nothing else.**

Each migrated app keeps its `nfs-csi` claim declared in git, holding the
pre-migration copy, so a rollback is a one-line change to the Deployment.

This is not a workaround for a misconfigured NAS. Two spinning disks and 7 GB
of RAM cannot serve 4 KiB random I/O, and no tuning knob changes that. The
split is the correct architecture for this hardware.

## Consequences

**Good:** the measured wins are not marginal. crowdsec's decision stream went
from 28.5s to **22 ms**; remux's lookups from 21s to 394 microseconds;
prowlarr's fetch 125s to 32s; bookdl 0/1 to 200 in 2 ms.

**Bad:** node-local storage does not survive losing the node, and it removes
these volumes from whatever the NAS was doing for them. For remux, prowlarr
and crowdsec that is nearly free - their data is replicable (addons, an API
key, a community blocklist all regenerate). **Lidarr and Navidrome are not
replicable**: they hold monitoring state, quality profiles, play counts,
history and import decisions. For those two the backup CronJob stops being
hygiene and becomes the actual safety net.

It also concentrates load on the node's 112 GB disk, which was 71% full at
migration time. Lidarr alone wanted 20 GB.

**Tripwire:** a new app appears with `storageClassName: nfs-csi` on a volume
that will hold a `.db`, `.sqlite`, or any embedded store. Or an existing app
starts showing multi-second latency on operations that touch a database while
sequential file access stays fine - that asymmetry is the signature. Check
`ls -la` on the config volume for a database file and check the PVC's storage
class before diagnosing the application.

Anything left on NFS that must do small I/O should at minimum get its own
dataset with `recordsize=16K`, since `128K` is costing 32x on every read.
