# ADR-0015: A cache has one owner and one direction

**Status:** Accepted
**Date:** 2026-11-03

## Context

The browser Minecraft client (notmc) will keep each player's worlds in their
Nextcloud, with a fast local copy on the NAS NVMe while they play. The owner
does not want two hard copies of a world, and does not want two programs
clearing or rewriting the same cache at different times. The cluster already
has jobs that touch shared storage (scans, cleaners, backups), and
doctor-log 2026-11-01 shows what happens when one of them fights a serving pod
for the same volume.

Tried and rejected: a shared scratch volume that any workload may use. It
saves one PVC and costs the ability to say who may delete from it.

## Decision

A cache is a disposable copy of data whose source of truth is somewhere else.

1. The source of truth holds the only durable copy. Losing the cache loses
   nothing but time.
2. Each cache has exactly one owner workload. Only the owner mounts it, writes
   to it, writes back from it, or clears it. Nothing else mounts it.
3. Data moves one way per phase: source to cache when opened, cache to source
   when changed or closed. The owner evicts only what the source has confirmed.
4. A cache volume is labelled `homelab/role: cache` and
   `homelab/cache-owner: <workload name>`, and has the annotation
   `homelab/cache-source` naming the source of truth.

Conftest `policy/cache.rego` checks (1) the labels and (2) that no other
workload in the namespace mounts the volume (HS-CACHE-01, HS-CACHE-02).

## Consequences

**Good:** "who may clear this?" has one answer, and CI finds a second mounter
before it ships.

**Bad:** every cache needs its own PVC and owner. The rule applies only to
volumes that declare themselves a cache; it cannot tell that an unlabelled
volume is used as one. Whether the owner writes back before it evicts is not
checkable from manifests (HS-CACHE-03 is manual).

**Tripwire:** a PVC used as a cache without the `homelab/role: cache` label, a
hostPath into a cache directory, or a CronJob that deletes files on a cache
volume. Label the volume, or move the work into the owner.
