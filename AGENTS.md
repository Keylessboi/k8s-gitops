# k8s-gitops: working brief for any coding agent

This file is read by opencode, Codex, Copilot, Gemini and Claude-style
harnesses alike, so the context lives here in the repo rather than in one
agent's session. If you are resuming another agent's work, run
`continues list` to find its session and `/continue` in opencode to pull its
handoff (see `~/.config/opencode/commands/continue.md`).

## Pushing to `main` is a production deploy

ArgoCD watches `apps/*` through one ApplicationSet and auto-syncs `main` with
`prune: true` and `selfHeal: true`. There is no staging.

- A push is live within about three minutes. Treat it as a deploy and confirm
  with the owner first unless they already asked for the change.
- `kubectl edit` / `kubectl scale` gets reverted on the next sync. Change the
  file, push, let it land.
- Images are pinned by digest. Bumping one is a deliberate commit.
- Before pushing a manifest change, render it and dry-run it server-side:
  `kubectl kustomize apps/<app> | kubectl apply --dry-run=server --validate=strict -f -`.
  That catches misplaced fields a YAML linter accepts.

## Reaching the cluster

The laptop is **not** on the cluster's LAN (same `192.168.1.0/24` numbering,
different network), so never diagnose reachability from it. Everything goes
over Tailscale. Hosts, keys and users are in `docs/access-procedures.md`.
In short:

- `ssh pve 'pct exec 200 -- kubectl ...'`: the whole cluster is LXC CT 200
  on pve.
- `ssh nas ...`: the storage node and the second k3s node. Its user is
  `travis`, with `doas` rather than `sudo`.

Secrets come from Doppler through DopplerSecret objects
(`apps/doppler/dopplersecrets.yaml`). Never print a secret's value: compare
hashes or lengths, or work inside the pod, where the credential is already in
the environment.

## Where things are

| You need | Look at |
|---|---|
| Something is broken | `scripts/doctor.sh <app>` first, then grep `docs/doctor-log.md` for the literal error text. Its symptom index is the point of the file. |
| Why something is built the way it is | `docs/adr/` |
| What each app is and how to log in | `docs/RUNDOWN.md` |
| Plans the owner has parked | `docs/expansion-plan.md` |
| A full outage | `docs/recovery/cluster-down.md` |
| Accounts and SSO | `docs/accounts.md` |

`docs/SESSION-HANDOFF.md` and `docs/handoff.md` are historical snapshots from
past outages, not current state. Check the live cluster before trusting them.

## Rules that have been paid for

- **Only Lidarr writes audio tags** (ADR-0004). Beets is read-only
  (`write: no`, every file operation off). Library files are hardlinked from
  `/data/torrents`, so any tool that rewrites a file breaks the torrent it is
  seeding. Loudness and ReplayGain are handled in the players, never on disk.
- **Databases and SQLite never go on nfs-csi** (ADR-0009). Use `local-path`
  on the node that runs the pod.
- **NetworkPolicies need both ends.** A kube-router REJECT reads as
  `connection refused`, which looks like the app is down. A `namespaceSelector`
  that names a deleted namespace denies everything.
- **Things that run on the NAS** need this placement:

  ```yaml
  nodeSelector:
    kubernetes.io/hostname: nas
  tolerations:
    - {key: storage, operator: Equal, value: "true", effect: NoSchedule}
  ```

- **Some cluster state is not in git**: Authentik applications and providers
  (managed with `ak shell`), and the `metallb` namespace. Removing an app from
  git does not remove its Authentik entries.

## The doctor log

Record every diagnosed **cluster** incident in `docs/doctor-log.md`, newest
first. Each entry has the symptom, root cause, fix, prevention and a
confidence line (CONFIRMED / PROBABLE / PROVISIONAL), and gets a row in the
symptom index. Write the prevention as the rule that generalises, not a
restatement of the fix. Problems on the owner's laptop never go in this
file.

## Issue tracker and domain docs

- Issues live in GitHub Issues (`Keylessboi/k8s-gitops`), via the `gh` CLI.
  See `docs/agents/issue-tracker.md`.
- Triage labels are the five-role vocabulary in `docs/agents/triage-labels.md`.
- Domain docs: `docs/adr/`, and a root `CONTEXT.md` if one exists. See
  `docs/agents/domain.md`.

This repository is **public**. Nothing written here, in a commit message or in
the doctor log may contain a credential, token or session transcript.
