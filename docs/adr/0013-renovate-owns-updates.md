# ADR-0013: Renovate owns every update, and merges its own PRs

**Status:** Accepted, supersedes the ArgoCD Image Updater setup
**Date:** 2026-09-30

## Context

On 2026-09-30 most of the cluster was months behind upstream: Authentik on
2025.12.4 with 2026.8.3 out, ArgoCD on v2.12.3, Traefik chart 33 against 41,
and dozens of app images on whatever tag they were added with. Nothing was
broken. Two updaters were running, and neither was doing the job.

- **Renovate only saw Helm charts.** Its `kubernetes` manager has no default
  file patterns, so every image in a plain Deployment or CronJob (about 60 of
  them) was invisible to it. Image tags set inside a chart's `valuesInline`
  (Immich's `tag: v3.1.0`, Nextcloud's `tag: stable`) are invisible to every
  manager. `renovate.json` also disabled all majors, and Authentik's calendar
  versions make every January a "major", so Authentik could never move past
  2025.x. The PRs Renovate did open had no automerge, and six sat open for up
  to a month.
- **Image Updater covered 8 images in 6 apps**, each constrained to its
  current major, and excluded every Helm app by design. It reconciled every
  ~2 minutes and logged `images_updated=0 errors=0` for weeks. Earlier it had
  also fought ArgoCD over digest pins (gluetun, navidrome), which is how it
  ended up covering so little.

## Decision

Renovate is the only updater, configured in `renovate.json`:

- The `kubernetes` manager scans `apps/**/*.yaml`. A regex manager picks up a
  `# renovate: datasource=docker depName=<image>` comment on the line above a
  `tag:` for images inside Helm values.
- Every update type is enabled, majors included. Updates wait 3 days after
  release (`minimumReleaseAge`), which filters out yanked releases.
- Renovate merges its own PRs (`platformAutomerge: false`, so it merges only
  after `validate` is green) between midnight and 06:00 America/New_York, so
  pods do not restart while someone is watching something.
- **Majors are not automerged** for Nextcloud, Immich, the Postgres/VectorChord
  image, Mongo, Redis and MinIO. Those are one-way data migrations, and some
  must step through each major (Nextcloud refuses to skip one). They still get
  PRs, and a person merges them.
- The Postgres image keeps its PG major as a fixed prefix. A PG major is a CNPG
  major upgrade, never a tag bump.
- Locally built images and the owner's `ghcr.io/keylessboi/*` fork builds are
  ignored.

The ImageUpdater CR is removed, so the controller runs idle. Decommissioning
the app (namespace, deploy key, DopplerSecret) is a follow-up.

## Consequences

- An update reaches the cluster at most ~3 days + one night after release,
  without anyone reviewing it. A bad release lands on its own. Recovery is
  `git revert` of Renovate's squash commit, and `validate` only proves the
  manifests render, not that the app starts. The trade was made deliberately:
  stale was the failure that actually happened.
- The Dependency Dashboard issue is the single place to see what is pending,
  including the held-back majors.
- New images inside Helm values need the `# renovate:` comment, or they go
  stale again silently.
