# Contributing

This repository *is* the cluster. ArgoCD watches `main` with `prune: true` and
`selfHeal: true`, so **a push to main is a deploy**. There is no staging
environment and no undo beyond another commit.

That single fact sets everything below.

## The loop

```
edit apps/<app>/…  →  validate locally  →  commit  →  push  →  ArgoCD syncs
```

`kubectl edit` does not stick. Self-heal reverts any live change on the next
pass. `kubectl` is the right tool for *looking* — logs, events, exec, a
throwaway test pod — and never for changing.

The exception is `apps/argocd/`, which is excluded from the ApplicationSet
because ArgoCD cannot reconcile its own definition. Nothing applies those files
for you; run `scripts/bootstrap-argocd.sh` after any change there.

## Before you push

Run what CI runs. It is fast and it is the same code:

```bash
# 1. does it parse?
python3 -c "import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))" apps/<app>/<file>.yaml

# 2. does the app still render?
kustomize build --enable-helm apps/<app> >/dev/null

# 3. do the repo invariants still hold?
python3 scripts/ci/check-invariants.py

# 4. best single check available - does the API server accept it?
kubectl apply --dry-run=server --validate=strict -k apps/<app>
```

Step 4 is the highest-yield check in this repo and needs cluster access, so CI
approximates it with `kubeconform -strict`. It catches the class where a
manifest renders perfectly and the API server rejects it: a pending Ghost patch
once put `scheme` at probe level instead of inside `httpGet`, which looks
entirely plausible in review and is an unknown field.

A YAML error is not a small mistake here. It surfaces as an ArgoCD
`ComparisonError` that fails the **entire** Application, not just the bad file,
and auto-sync keeps reporting the last good state — so a broken push looks like
a successful one until somebody notices an app is weeks stale.

## What CI enforces

| Check | Catches |
|---|---|
| `yaml-parse` | The ComparisonError class |
| `kustomize-build` | Bad refs, missing files, chart/version mistakes |
| `yamllint` | Style regressions (advisory rules are warnings) |
| `invariants` | Missing wait-init on Jobs; one-sided NetworkPolicies |
| `schema` | Fields the API server would reject |
| `fix-needs-log` | A `fix()` touching `apps/` with no doctor-log entry |

### The two invariants, and why they exist

Both are in `scripts/ci/check-invariants.py`, and both exist because the
doctor's log records the same mistake happening twice. The log's own header
says a repeat means the prevention failed.

**wait-init on Jobs and CronJobs.** kube-router needs 1–2 s after a pod starts
to program its per-pod policy chains. Until then, egress the NetworkPolicy
explicitly *allows* is REJECTed — surfacing as "connection refused" rather than
a timeout. It hit lidarr's maintenance CronJob, was written up with the correct
prevention as a sentence, and five days later took out three consecutive
pg_dump runs because nobody re-read the sentence.

**NetworkPolicies declared on both sides.** A cross-namespace flow needs egress
in the source namespace *and* ingress in the destination. One side alone reads
correct and drops traffic. This has now bitten four times; the fourth was found
by this check on its first run, seven days after it was introduced.

Pre-existing exceptions live in `scripts/ci/wait-init-baseline.txt`. That file
should only ever shrink, and the checker fails if a line in it is stale.

## Fixing something

Add an entry to `docs/doctor-log.md` in the same commit, newest first, with the
headings in `.github/pull_request_template.md`: **symptom, root cause, fix,
prevention, confidence**.

Confidence is not decoration. The 2026-08-31 Ghost entry concluded the kubelet
was constructing an HTTPS probe on its own and said the root cause was "not
fully pinned" — and everything downstream inherited that as settled, including
a proposed patch that the API server rejects and that would have fixed nothing.
The real cause was that Ghost 301-redirects plaintext to https on its own host
and the kubelet follows probe redirects into a TLS handshake.

Write the symptom in the words someone would actually use — the real error
text. `scripts/doctor.sh` greps that file by app name, so an entry written for
grep is an entry a future model finds for free.

## Verification is not "ArgoCD says Synced"

Synced/Healthy hid three separate failures in a single week: Ghost restarting
523 times, pg_dump 27 hours stale, and a sync server that had never once
synced. Sync status reports that the manifests match git, which says nothing
about whether the process did its job.

Prove the data plane: a status code, a row count, a snapshot age, a restore
that came back. `scripts/doctor.sh <app>` collects most of it in one command.

## Standing rules for any new app

These are decided, not up for re-litigation per app. Each exists because the
alternative has already cost something here.

### 1. Postgres, not SQLite

**If an application can use PostgreSQL, it must.** The shared CNPG cluster is
`app-databases-rw.databases.svc.cluster.local`; add a `Database` CR in
`apps/databases/databases.yaml` and a managed role in `cluster.yaml`.

SQLite on this cluster is not "one less moving part" — it is *more* overhead in
every way that matters:

- It needs a PVC, which means NFS, which means a network filesystem underneath a
  database that assumes local disk. Single-writer locking over NFS is how you get
  corruption and `database is locked` stalls.
- It is excluded from every backup guarantee this cluster has. The pgdump chain,
  the WAL archive, the restic repository and the monthly restore drill all cover
  Postgres. A SQLite file is covered only by whatever happens to snapshot its PVC,
  and has never been restore-tested.
- It forces `strategy: Recreate` and blocks any future replica, because two pods
  cannot share the file.

Eleven apps already use the shared Postgres. **Still on SQLite and owing a
migration:** `remux` (a 295 MB `db.sqlite`), `aiostreams`, `convertx`, `ghost`.
Migrate when each is next touched; do not add a twelfth.

### 2. Sensitive data lives on the NAS

Credentials, vault contents, personal documents and anything whose loss or
exposure would actually matter belong on the NAS (`tank`), which is encrypted at
rest, snapshotted by sanoid, and replicated off-site nightly by borgmatic.

Not on a `local-path` PVC — that is the node's own disk, is not snapshotted, is
not replicated, and is pinned to a node. Vaultwarden's vault lives in Postgres
for exactly this reason rather than in a container-local file.

### 3. S3 first, then NFS, then local-path — and never local-path for state

Storage preference, in order:

1. **S3 (MinIO on the NAS)** — for anything an application can address as an
   object store: backups, archives, artefacts, large blobs. Versionable,
   replicable, and reachable from anywhere in the cluster with no node affinity.
2. **NFS (`nfs-csi`)** — for filesystem-shaped data: media libraries, ingest
   directories, config that must be a real directory. Note the hardlink rule in
   RUNDOWN: one mount for `/data`, because hardlinks cannot cross filesystems and
   splitting them turns every import into copy-then-delete.
3. **`local-path`** — caches and scratch only. It pins the pod to a node, is
   invisible to every backup, and disappears with the node.

If a claim holds something you would be upset to lose, it is in the wrong tier.

### 4. One shared instance, not one per app

Redis, Postgres and the VPN gateway are shared on purpose. A per-app copy costs
RAM on a node that idles near 90%, and the log already records the cleanup: three
per-app gluetun sidecars collapsed into one `vpn` gateway, and per-app AirVPN
secrets collapsed with them. Before deploying a second instance of infrastructure
that already exists, say why the shared one cannot serve.

### 5. Declare cross-namespace flows on both sides

An egress rule in the source namespace **and** an ingress rule in the
destination. One side alone reads correct in review and drops traffic. This has
bitten four times; `scripts/ci/check-invariants.py` now fails on it.

The intra-namespace case is the same trap wearing a different hat: a default-deny
ingress policy blocks pod-to-pod traffic *inside its own namespace* too. Immich
lost all machine learning to this and nothing showed it.

### 6. State the worst-case cost of anything unattended

Any Job or CronJob that touches the database or the disk must say, in its own
manifest, what it costs at worst — and cap it. The restore drill restored a
1.31 GB dump into a 5.5 GB scratch database on a node at 92% memory and restarted
the apiserver twice. It now caps at 300 MB with a 12 GB free-space floor.

## Adding an app

Create `apps/<name>/` with a `kustomization.yaml`. The ApplicationSet's git
directory generator turns every directory under `apps/` into an Application
automatically — there is no list to update. Include a `namespace.yaml` with Pod
Security Admission labels and a `networkpolicy.yaml` with default-deny ingress
and egress, then open exactly what the app needs, **on both sides**.

Set `argocd.argoproj.io/sync-wave` on the kustomization: platform first,
user-facing apps at wave `20`.
