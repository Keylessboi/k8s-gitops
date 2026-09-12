# 10. Raise NFS client readahead from the 128 kB kernel default

Date: 2026-09-12

## Status

Accepted. Refines [0009](0009-databases-on-local-path-not-nfs.md).

## Context

Downloading a 5 GB game file from Nextcloud ran at ~300 kB/s. The same file
read with `dd` inside the Nextcloud pod, with no PHP and no network in the
path, ran at 2-4 MB/s. Read locally on the NAS it ran at **81 MB/s**.

So neither Nextcloud nor the pool was the problem. Everything in between was.

Two hypotheses were tested and rejected before the real one:

- **nfsd thread starvation on the server.** `pool_stats` looked damning -
  `sockets-enqueued` (4.6B) was 2x `packets-arrived` (2.3B) and
  `threads-timedout` was 0, meaning no nfsd thread was ever idle. Threads were
  raised 16 -> 64 on a 12-core box. Throughput did not move: still 2 MB/s.
- **The pool being saturated by ~959 seeding torrents.** Real, and it is what
  0009 is about, but not this. A cold sequential read of an untouched offset of
  this very file, on the busy pool, returned 200 MiB in 2577 ms.

The actual cause is on the client. Every NFS bdi is created with
`read_ahead_kb=128` while the mounts negotiate `rsize=1048576`. A 128 kB
readahead window cannot keep more than a fraction of a 1 MB read in flight, so
a sequential stream degenerates into serialized 128 kB round trips. Each round
trip then waits behind whatever else the pool is doing - which is where the
torrent load does enter the story, as latency the client has no way to hide.

Local reads do not suffer this because ZFS prefetch issues large asynchronous
readahead of its own. That is the entire 81 MB/s vs 2 MB/s gap.

## Decision

Set `read_ahead_kb=15360` (15 MB, the long-standing 15x-rsize guidance) on
every NFS bdi, reapplied on a timer.

Measured on `192.168.1.67:/extra/nfs-csi/data`, same file, cold offsets:

| path                              | before   | after     |
| --------------------------------- | -------- | --------- |
| NAS local, cold, sequential       | 81.4 MB/s | -        |
| `dd` over NFS in the pod          | 2.0 MB/s | 12.0 MB/s |
| Nextcloud download (PHP, WebDAV)  | 0.30 MB/s | 10.4 MB/s |

**32x on the path that was actually complained about.**

60 MB readahead was tested and rejected: 17 MB/s raw but 9.5 MB/s through
Nextcloud - no better end to end, while multiplying per-stream memory
exposure. That matters here because qBittorrent holds ~959 seeding torrents
open on the same export, and readahead is charged per stream, not per mount.
Inflating the window for random piece reads would add pool IOPS, which is the
opposite of what 0009 is trying to achieve.

## Consequences

The knob lives on the **Proxmox host**, not in CT 200 and not in git as a
manifest: bdi objects are kernel-global, but sysfs is read-only inside the
unprivileged container, so a DaemonSet cannot write it.

It runs on a **2-minute timer**, not once at boot, because the NFS CSI driver
creates a fresh mount - and therefore a fresh bdi at the 128 kB default - every
time a pod claiming an NFS volume starts. A one-shot fix would silently decay
back to 300 kB/s one pod restart at a time.

- `/usr/local/sbin/nfs-readahead.sh` on `pve`
- `nfs-readahead.service` + `nfs-readahead.timer`, enabled

This is cluster state outside git. It is recorded here and in the doctor log
because nothing in the repository will reproduce it.

**This does not make NFS a fast path.** 10 MB/s is still 8x off what the NAS
can read locally. 0009's ladder is unchanged: databases belong on local-path,
NFS is for bulk media. For moving whole game files, SFTP straight to the NAS
measures **48.8 MB/s** and remains the right tool - see the `nas:` rclone
remote.
