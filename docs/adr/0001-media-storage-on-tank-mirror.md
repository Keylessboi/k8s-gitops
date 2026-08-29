# ADR-0001: Keep all cluster storage on the `tank` mirror

**Status:** Accepted
**Date:** 2026-08-27

## Context

The NAS presented two ZFS pools, and the cluster was using the wrong one.

```
extra  3.56T  single vdev   scsi-35000cca2536b1f60-part2
tank   7.25T  mirror-0      scsi-35000cca2536b1f60-part1 + sdb1
```

Both live on the **same physical 12TB disk**: partition 1 mirrors with the 8TB `sdb1` to form `tank`, and the 3.56T remainder became `extra`. Every NFS export the cluster consumed (`/extra/nfs-csi`) sat on `extra` — the **unmirrored** leftover — while the mirrored `tank/media` and `tank/data` sat empty.

That capped usable space at 3.5T for a library expected to reach ~8TB, and gave every PVC in the cluster zero redundancy. Losing that one disk would have taken all application data *and* degraded the mirror simultaneously.

Powering the disk down was not an option, and it is worth being explicit about why: `extra` is not a separate drive. Spinning it down removes half the mirror.

## Decision

Move everything to the mirror, keeping the export path identical.

`tank/extra` was created, populated from an atomic `zfs snapshot` + `send/recv` of `extra` (verified 68,100 files on both sides), and then mounted at `/extra` so the NFS export path `/extra/nfs-csi` was unchanged. **No PersistentVolume in the cluster needed editing** — the alternative, recreating ~30 PVs to change `share:`, was rejected as far riskier for identical benefit.

The old pool was left mounted at `/extra-old` as a rollback for a day, then destroyed once the mirror was proven (`tank/extra` had grown to 314G of live downloads).

## Consequences

**Good:** 3.5T → 6.1T usable, with real redundancy. Export path unchanged, so no PV churn and no drift between git and the cluster.

**Bad:** the dataset is still *named* `extra` and mounted at `/extra`, which reads as the old unmirrored pool. This is cosmetic but genuinely confusing — `zfs list` is the way to check what is actually backing it.

The 3.56T freed by destroying `extra` cannot extend the mirror: `tank` is capped by the smaller 8TB member. That capacity can only ever be non-redundant scratch.

**Tripwire:** `df /extra/nfs-csi` must report `tank/extra`. If it ever reports anything else, storage has silently fallen back to a non-redundant pool.
