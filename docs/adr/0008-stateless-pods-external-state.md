# ADR-0008: Pods are disposable; state lives in Postgres or on the NAS

**Status:** accepted, 2026-09-04

## Context

This has been the working practice for most of the cluster but was never
written down, so it kept getting re-litigated per app and drifted in two
directions at once.

The drift showed up concretely on 2026-09-04. Two apps were found holding
state in ways nothing was tracking:

- **Blinko** ran on the NAS under docker-compose with its Postgres in a sibling
  container. That container was deleted at some point. The app stayed up and
  reported "healthy" - its healthcheck only fetched `/` - while every request
  failed with `Please make sure your database server is running at
  postgres:5432`. **71 notes** sat in an orphaned data directory that nothing
  read, nothing backed up, and nothing alerted on.
- **The old Immich stack**, on the same box, had restarted **8,197 times**
  against a data path that stopped being a mountpoint on 2026-08-28.

Neither was in git. Neither was in the backup chain. Neither raised an alert.
Both were "running".

## Decision

**A pod is disposable. Deleting any pod in this cluster, at any time, must lose
nothing.**

Everything that survives a pod goes in exactly one of two places:

1. **The shared CNPG Postgres cluster** (`app-databases`) - all relational
   state. This is what `scheduledbackup`, the WAL archive, the nightly
   `pgdump-cronjob` and the monthly `restore-drill-cronjob` already protect. An
   app that stores in Postgres inherits all of that for free.
2. **NAS-backed NFS** (`storageClassName: nfs-csi`) - blobs that are not
   relational: photo originals, media, attachments, book files.

**Nothing durable on a node.** No `hostPath`, no `local` volumes, no
`emptyDir` holding anything that matters past the pod's life.

This is what makes the rest of the design work. It is why apps can be moved
between nodes freely, why adding the NAS as a second node is low-risk, and why
"delete the pod and see" is a safe first debugging step here.

### The SQLite corollary

Restated from CONTRIBUTING rule 1, because it is the same principle: **if an
app supports Postgres, it uses Postgres.** SQLite on an NFS claim is durable
but slow, unbackupable by the Postgres chain, and locks badly.

Apps genuinely unable to: **remux**, **ghost**, **convertx**. Those three are
exempt and their claims are on NFS. Every other app that ships a Postgres
driver uses it - most recently Memos and Blinko, both of which default to
SQLite and were deployed against CNPG instead.

### Core infrastructure is the exception, and is named

CNPG itself, MinIO, and the NFS provisioner ARE the storage layer and cannot
store their state in it. They are the only exceptions, and there are no others.

## Consequences

- Adding a node is safe: no app is pinned to one by its data.
- The blast radius of losing the compute node is "restart the pods", not
  "restore from backup".
- Backups have one story instead of one per app: Postgres for relational,
  restic/borgmatic over NFS for blobs.
- **Anything running outside this cluster is outside all of it.** The blinko
  and old-Immich findings are what that costs. Migrating a compose stack in is
  not tidiness; it is the difference between backed-up and not.

## What this does not say

It does not say every app must be in Kubernetes. It says every app's *state*
must be in one of the two places above, and that an app running outside the
cluster is running without backups, alerting or SSO until it is moved in.
