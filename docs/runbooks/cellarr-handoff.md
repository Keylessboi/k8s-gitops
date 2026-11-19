# cellarr: handoff (2026-11-19)

Read this first, then `docs/runbooks/cellarr-cutover.md` (the full plan) and
`AGENTS.md` (the repo rules: never read a secret's value, nothing deletes
state, `main` is a production deploy).

## Where things are

| Repo | Branch | State |
|---|---|---|
| `Keylessboi/cellarr` | `ccr-28dccdf6-ysjbz9` (head `b0a4395`) | All work pushed. 1,375 workspace tests pass. The Postgres feature build compiles. |
| `Keylessboi/k8s-gitops` | `ccr-28dccdf6-ysjbz9` | `apps/cellarr-shadow` (shadow + diff CronJobs), `apps/cellarr-shadow/rehearsal` (opt-in, never synced), `.github/workflows/cellarr.yaml` (image build), this runbook. **Nothing is on `main`; nothing is deployed.** |

What cellarr does on this branch:
- It serves Lidarr's `/api/v1` on 8686.
- `cellarr snapshot` copies a live `lidarr.db` read-only (VACUUM INTO).
- `cellarr migrate` carries over artists, albums, pressings, track files,
  history, the blocklist, profiles, indexers and clients (with their real
  category).
- `CELLARR_SHADOW=true` means read-only: no jobs, non-GET requests get 403,
  and the plugin sidecar is only read.
- Native Lidarr plugins run through an optional sidecar Lidarr.

## What the owner decided

- The shadow may be deployed (it is read-only, and nothing points at it).
- Keep cellarr commit `e9e3f0f`, the scheduler fix: no "fruitless search"
  backoff for a node that was never searched.
- The plugin rehearsal (cutover step 4) may go ahead. The agent picks a test
  artist that is **not** in the production library, and secrets come from the
  Doppler CLI. Never print a value; send `doppler secrets set` output to
  /dev/null.

## Next steps, in order

1. **Build the image.** Pick one of these:
   - On `Keylessboi/cellarr`, open the Actions tab, enable workflows, then
     run `release` on the branch. That pushes
     `ghcr.io/keylessboi/cellarr:sha-<commit>`.
   - Cherry-pick commit `3bf41a6` (`.github/workflows/cellarr.yaml`, nothing
     else) to `main` in k8s-gitops. That builds
     `ghcr.io/keylessboi/cellarr` from cellarr `b0a4395` and prints the
     digest.

   Either way, pin the **manifest digest** in
   `apps/cellarr-shadow/kustomization.yaml` (`images[0].digest`) and in
   `apps/cellarr-shadow/rehearsal/kustomization.yaml`. Both currently hold an
   all-zero placeholder.

2. **Check the possible NetworkPolicy gap. This may affect production today.**
   In-namespace egress in `apps/lidarr/networkpolicy.yaml` allows only 8686.
   On paper, Lidarr cannot reach `applemusic-decryptor:8080`,
   `lucida-solver:8080` or `bgutil-provider:4416`:

   ```sh
   ssh pve 'pct exec 200 -- kubectl -n lidarr exec deploy/lidarr -c lidarr -- sh -c "
     for t in applemusic-decryptor:8080 lucida-solver:8080 bgutil-provider:4416; do
       printf \"%s \" \$t; curl -sS -m5 -o /dev/null -w \"%{http_code}\n\" http://\$t/ 2>&1 | tail -1; done"'
   ```

   Any HTTP code means the flow works. "Connection refused" means a REJECT. If
   so, add an egress rule to the lidarr namespace on TCP 8080 and 4416 (a
   production change; ask the owner).

3. **Deploy the shadow.** Dry-run first:
   `kubectl kustomize apps/cellarr-shadow | kubectl apply --dry-run=server --validate=strict -f -`.
   Then merge the shadow to `main`. Leave `rehearsal/` unreferenced: it is
   applied by hand. Watch:
   - `kubectl -n lidarr logs deploy/cellarr-shadow -c migrate` (snapshot +
     migration of the 3.9 GB db, several minutes);
   - pod memory (expect ~30–250 MiB).

   Then run the full diff once:
   `kubectl -n lidarr create job --from=cronjob/cellarr-shadow-diff-full diff-full-$(date +%s)`.

4. **Plugin rehearsal (runbook step 4).** Make the Secret `cellarr-rehearsal`
   (keys `sidecar-api-key` and `cellarr-api-key`):
   - Doppler with a DopplerSecret needs an entry in
     `security/registers/secrets.yaml` (HS-ROT-01) that the owner signs. An
     agent may only add it as `status: proposed`.
   - The alternative is the hand-made Secret the runbook gives.

   Then `kubectl apply -k apps/cellarr-shadow/rehearsal`, install Tubifarry in
   the sidecar, and push one test album through each of Soulseek, YouTube and
   Apple Music. Tear down with the **label-scoped** delete in the runbook. A
   plain `delete -k` would delete the PVCs.

5. **Gate for cutover:**
   - the full diff is clean (config, artists, track files);
   - a week of clean nightly diffs;
   - the rehearsal passes.

   Then follow runbook steps 5 (cutover) and 6 (rollback).

## Known gaps, so they are not rediscovered

- Not verified on the cluster: the 3.9 GB real database, Prowlarr sync, and
  Tubifarry or AppleMusicarr through the sidecar.
- The sidecar runs Lidarr directly (no s6) as uid 1000 with a read-only root.
  It may need another writable path.
- `trackfile?unmapped=true` returns `[]`.
- The web UI is cellarr's own, on 9494; 8686 serves the API only.
- A failed or stalled download is removed when it is blocklisted. Imported
  torrents are never removed.
- A shadow logs in to qBittorrent for health checks (POST to its login only).
- Never point a shadow's `database_url` at a live Postgres. It would migrate
  and write to it. SQLite is unaffected.

## Local tooling notes

- Policy checks: `scripts/security/install-tools.sh` installs the exact tool
  versions from `.github/workflows/security.yaml`. Then run
  `scripts/security/render-all.sh`, `scripts/security/policy-check.sh`,
  `scripts/ci/check-invariants.py` and `scripts/ci/check-protected-state.py`
  (it reads the render on stdin).
- cellarr: `just setup`, then `just test`. The shadow-vs-Lidarr diff script is
  `scripts/lidarr-shadow-diff` (stdlib Python, GET only), vendored into
  `apps/cellarr-shadow/lidarr-shadow-diff.py`. Re-copy it when it changes.
