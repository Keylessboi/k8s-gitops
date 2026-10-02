# CM — Configuration Management

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

<!-- FAMILY-SUMMARY -->

### Reading this family: which tree is "the system"

This section was written in the `homelab-standard` worktree, whose branch
point is commit `13d65cf` (2026-09-28). `origin/main`, which ArgoCD deploys,
is **43 commits ahead** of that point (head `dcc8703`, 2026-10-01). Two
differences change CM answers and are called out per control:

1. **PR #21 is not on `main`.** `components/protect-state`,
   `preserveResourcesOnDeletion: true`, `scripts/ci/check-protected-state.py`
   and the gitleaks job exist only in this branch
   (`git diff HEAD origin/main --stat` shows them deleted on `main`).
   `03-homelab-standard.md` §2 says its counts are "after PR #21 merges";
   this SSP treats those mechanisms as **not yet in production**.
2. **ADR-0013 is on `main` and not here.** Commit `dcc8703` (PR #24) made
   Renovate the only updater, enabled majors, and set it to merge its own
   PRs overnight once `validate` is green. It retired Image Updater as an
   updater (the `ImageUpdater` CR is removed; the controller, its namespace
   and its git deploy key remain, per ADR-0013 "Decommissioning … is a
   follow-up"). This contradicts policy §8.3.3, §11.1, §11.5.3 and §15.3,
   which were written after it (see CM-3).

Where this file says "the repository" without qualification it means this
worktree; "`main`" means `origin/main` at `dcc8703`.

<!-- END -->
