# ADR-0012: Agents work unattended; the guardrails are code, not prose

**Status:** Accepted
**Date:** 2026-09-28

## Context

Most commits to this repo are written by coding agents (Claude Code, opencode,
Codex, Gemini), and the owner wants that to stay fully automated. Two failure
modes kept recurring, and the only defence against either was a sentence in
`AGENTS.md`:

1. **Agents read secret values.** Diagnosing a failing pod leads naturally to
   `kubectl get secret -o yaml`, `env` inside the pod, or `doppler secrets`.
   Each one puts a live credential into a session transcript on disk, and
   sometimes into a commit to this public repo.
2. **One careless edit could delete data.** The root ApplicationSet syncs with
   `prune: true` and every Application carries the resources finalizer. Before
   this ADR, *no* PVC, PV, Namespace or CNPG Cluster carried `Prune=false`, and
   the ApplicationSet had no `preserveResourcesOnDeletion`. So:
   - dropping `pvc.yaml` from a `resources:` list deleted that PVC, and on
     `local-path` the provisioner's `Delete` reclaim policy deleted the data;
   - renaming or deleting an `apps/*` directory deleted its Application, and
     the finalizer cascade-deleted the namespace and every PVC in it.
   ArgoCD would report the result as Synced/Healthy.

ADR-0007 already says preventions belong in checks, not prose, because this
repo has watched its prose preventions fail twice.

Rejected: **Kyverno or another admission controller** to block deletes. It is
one more operator on a frozen platform (ADR-0007), and prune protection is
already an ArgoCD annotation. Rejected: **turning `prune` off globally**. Stale
objects pile up and the tree stops describing the cluster, which is the whole
point of GitOps.

## Decision

Guardrails that hold whichever agent is driving, enforced by machinery:

- **Stateful objects are never pruned or cascade-deleted.**
  `components/protect-state` gives every PVC, PV, Namespace and CNPG Cluster
  `argocd.argoproj.io/sync-options: Prune=false,Delete=false`, and every
  `apps/*/kustomization.yaml` includes it. The root ApplicationSet sets
  `syncPolicy.preserveResourcesOnDeletion: true`. Deleting state is now
  deliberately two steps: remove it from git, then `kubectl delete` it by hand.
- **CI enforces it.** The kubeconform job runs
  `scripts/ci/check-protected-state.py` over every rendered app, Helm output
  included, and fails on any unprotected stateful object.
- **CI refuses committed credentials.** A gitleaks job scans every new commit,
  with `--redact` so a finding never reaches the public Actions log.
- **Agents never read secret values.** This one is enforced outside the repo,
  on the operator's machine, by a Claude Code PreToolUse hook and auto-mode
  rules. `secret-meta <ns> <name>` shows keys, lengths and hash prefixes
  instead. See the Secrets section of `AGENTS.md`.

## Consequences

**Good:** the worst thing a bad agent commit can do to data is leave an orphan
behind. Orphans show as OutOfSync in ArgoCD and are cleaned up on purpose. The
guardrails do not depend on the agent having read `AGENTS.md`.

**Bad:** real decommissions need a manual `kubectl delete` of the namespace and
PVCs, plus an `argocd app delete` for an Application whose directory is gone.
A few orphaned PVCs will accumulate between cleanups. `apps/argocd` is not
synced by ArgoCD, so the ApplicationSet change only takes effect once someone
runs `kubectl apply -f apps/argocd/root-applicationset.yaml`.

The secret hook is a tripwire, not a boundary: a regex can be talked past, and
it only covers Claude Code. The airtight fix is an agent kubeconfig bound to
the built-in `view` ClusterRole, which cannot read Secrets, in place of
`ssh pve 'pct exec 200 -- kubectl'` (cluster-admin, root on the host). That is
not done yet.

**Tripwire:** the "Stateful objects are protected from prune" step goes red, or
a new app's `kustomization.yaml` lacks `components/protect-state`. Add the
component; never delete the check. If an agent's transcript shows a secret
value anyway, rotate that credential and add the command shape to
`~/.claude/hooks/secret-guard.py`.
