# 04 — Plan of Action and Milestones (POA&M)

**Part of:** the Homelab Information Security Program (see `README.md`) ·
**Version:** 0.1 draft · **Written:** 2026-10-03 · **Reviewed:** monthly
(`01-policy.md` §19)

This is the work list. Each item groups the SSP gaps (`G-<FAM>-<NN>` in
`ssp/`) that share one fix. Every gap in `ssp/` appears here exactly where
its fix is planned; `scripts/security/ssp-index.py check` fails if one is
missing. The System Owner accepts the residual risk of each open item until
its target date (`01-policy.md` §20). A target that slips by more than 90 days
needs the risk accepted again, or the function stopped.

## Risk rating

| Rating | Meaning |
|---|---|
| **High** | Reachable from the internet or by a routine agent action, and leads to disclosure of C4 data, takeover of an account or the platform, or data that cannot be recovered. |
| **Moderate** | Needs a prior foothold (LAN, tailnet, a compromised pod), or harms C3 data or availability, or removes the ability to detect or investigate. |
| **Low** | Weakens documentation, assurance or hygiene; no direct path to harm. |

Items are ordered by rating, then target date. Status is **Open** unless
stated.

## Items

| # | Weakness | Risk | Milestones | Target | Gaps |
|---|---|---|---|---|---|
| 1 | **Agents act with the owner's full privileges.** Cluster-admin over `ssh pve` and host root are the normal path for people and AI agents; agents have no identity of their own and can be steered by text they read. | High | (a) a `view`-bound kubeconfig without Secret access for agents; (b) writes only through git; (c) cluster-admin kept for break-glass and logged; (d) distinct agent identity in commits checked by CI | 2026-12-31 | G-AC-10, G-IA-01, G-AU-04, G-SI-13 |
| 2 | **`main` is unprotected and CI does not gate.** Anything can be pushed or force-pushed straight to production; `validate` is red on `main`. | High | (a) make `validate` green; (b) require it and a PR on `main`; (c) block force-push and deletion; (d) a CI zone check for Zone 1 paths | 2026-11-30 | G-AC-09, G-CM-06, G-CP-05, G-CM-08 |
| 3 | **remux API is published without forward-auth while synced accounts may have empty passwords.** | High | (a) merge PR #20; (b) reset existing synced accounts; (c) verify an empty-password login fails | 2026-11-01 | G-AC-07 |
| 4 | **ConvertX converts arbitrary files as root and is published without forward-auth.** | High | Put it behind forward-auth (or unpublish) and drop root | 2026-11-15 | G-SI-07 |
| 5 | **MFA unverified on the owner's provider accounts and `akadmin`; not required for service users.** | High | (a) owner checks GitHub, Doppler, Tailscale, Cloudflare, registrar, `akadmin`, enables passkeys, records status in `00` §5 (2026-11-15); (b) Authentik MFA enrolment flow for service users (2027-03-31) | 2026-11-15 | G-IA-02, G-IA-03 |
| 6 | **Credentials are not inventoried or rotated, and a past key exposure was never recorded.** Authentik's signing key was the public literal `MANAGED_BY_DOPPLER`; initial/default admin credentials are not confirmed changed. | High | (a) incident entry for the signing-key exposure; (b) credential inventory with last rotation; (c) rotate anything that reached a transcript; (d) CI check rejecting placeholder secret values | 2026-11-30 | G-IA-04, G-SC-07, G-IR-14 |
| 7 | **Off-site backup is unalerted and undocumented, and some PVCs have no backup layer.** | High | (a) freshness alert for borgmatic; (b) record target, coverage, retention, encryption, append-only; (c) list every PVC with its layer and add missing ones; (d) fix the 03:15 schedule collision; (e) accessibility analysis | 2026-12-31 | G-CP-11, G-CP-12, G-CP-13, G-CP-14, G-CP-15, G-CP-16 |
| 8 | **Escrowed keys (ZFS, borg, restic) have never been tested from escrow.** | High | First 6-monthly escrow verification, recorded | 2026-12-31 | G-SC-04 |
| 9 | **No vulnerability scanning; host and k3s patching has no mechanism.** | High | (a) Trivy (or equivalent) on images monthly and on digest bumps; (b) host/k3s patch routine with a record and advisory subscriptions | 2027-01-31 | G-SI-02, G-SI-03, G-SI-05 |
| 10 | **Policy not yet approved; procedures scattered or stale.** Until merged nothing here is in force; several runbooks still had wrong steps (fixed on this branch, not yet on `main`). | Moderate | (a) owner merges #21 and this program; (b) one AC/accounts runbook; (c) agents pointed at §16 too | 2026-11-30 | G-AU-01, G-AC-01, G-CM-01, G-CM-02, G-CP-01, G-IR-01, G-IR-03, G-SA-01, G-SI-01, G-AT-01 |
| 11 | **ArgoCD has an Ingress that policy §9.5 does not allow.** | Moderate | Owner decides: remove it or amend §9.5 | 2026-11-30 | G-AC-11 |
| 12 | **Update pipeline contradicts the policy.** Renovate on `main` automerges majors of some Zone 1 / Tier 0–1 components (HS-SUP-01 is marked MET and needs re-measuring); no runtime test before or after a change. | Moderate | (a) align `renovate.json` with §11.1/§15.3; (b) re-measure HS-SUP-01; (c) post-sync smoke checks for Tier 0–1 | 2026-12-31 | G-CM-07, G-SA-05, G-SI-04, G-CM-09 |
| 13 | **Authentik configuration lives outside git and is unverified** (session lifetime, password policy, lockout). | Moderate | Read settings, set session ≤24 h idle, capture flows/stages in blueprints (W-01) | 2026-12-31 | G-AC-06 |
| 14 | **No Kubernetes API audit log, no central host logs, and logs are deletable by the actors they record.** | Moderate | (a) k3s audit policy (metadata level) to Loki; (b) host journals to Loki; (c) security streams copied to a host the cluster cannot write; (d) host-compromise eradication steps | 2027-01-31 | G-AU-02, G-AU-03, G-AU-07, G-AC-13, G-SI-08, G-IR-11 |
| 15 | **Security events are logged but never alerted on or reviewed; monitoring has blind spots.** | Moderate | (a) Loki ruler alerts (Authentik admin logins, failures, CrowdSec spikes, cert expiry); (b) ingestion and capacity alerts; (c) clock-skew alert; (d) scheduled end-to-end alert-path test; (e) heartbeat receiver into git; (f) egress allow-lists on Tier 1–2 | 2027-01-31 | G-SI-09, G-IR-13, G-AU-05, G-AU-06, G-IR-05, G-IR-07, G-SI-10, G-SI-12 |
| 16 | **Account lifecycle is incomplete.** No user register, shared/local admin accounts unlisted, leavers not removed from local-account apps, no inactivity disable, no review, open group bindings for Pelican/Forgejo/bookdl. | Moderate | (a) register in `docs/accounts.md`; (b) leaver checklist covering local accounts; (c) 90-day inactivity report; (d) first access review; (e) owner decides the three bindings | 2027-01-31 | G-AC-02, G-AC-03, G-AC-04, G-AC-05, G-AC-12, G-AC-31 |
| 17 | **Encryption at rest unverified** for `local-path` disks, the k3s datastore (Secrets) and the operator laptop; no rule for devices that hold admin credentials. | Moderate | (a) check and enable k3s secrets encryption; (b) record pve/laptop disk encryption; (c) device rule in policy §9 | 2027-01-31 | G-SC-05, G-AC-15 |
| 18 | **The program has never been checked against the running system.** | Moderate | One verification pass settling every [UNVERIFIED] item, then 3-monthly re-measure of `03`; a one-page threat list | 2027-01-31 | G-CA-01, G-RA-01 |
| 19 | **Home network undocumented** (router, WiFi, which hosts are wired). | Moderate | Record it in `00` | 2027-01-31 | G-AC-14 |
| 20 | **Contingency plan untested.** No single plan, RTO/RPO never measured, file-data restores untested, results not kept, runbooks stale (`scripts/restore.sh`, root@nas). | Moderate | (a) one contingency plan; (b) fix stale runbooks; (c) timed restore exercise per tier; (d) file-PVC restore test; (e) keep results | 2027-03-31 | G-CP-02, G-CP-03, G-CP-04, G-CP-06, G-CP-08, G-CP-09, G-CP-10 |
| 21 | **Host configuration is not baselined; drift is undetected.** ArgoCD bootstrap is outside the applied baseline; no check that each app applied its last commit. | Moderate | (a) host config in git (Ansible or documented files); (b) ArgoCD bootstrap pinned and recorded; (c) sync-vs-commit check | 2027-03-31 | G-CM-03, G-CM-04, G-CM-05 |
| 22 | **NFS between the nas and CT 200 is plaintext.** | Moderate | Encrypt the path or waive with the LAN as compensating boundary | 2027-03-31 | G-SC-03 |
| 23 | **Incident response is untested for security incidents.** No severities applied, no tracking, no exercises, break-glass unrecorded, no user reporting path, no legal analysis, unattended agents cannot escalate. | Moderate | (a) apply severities to the log; (b) incident tracking via GitHub issues; (c) tabletop the credential-exposure playbook; (d) break-glass record; (e) user reporting path; (f) note on breach-notice obligations | 2027-03-31 | G-IR-02, G-IR-04, G-IR-06, G-IR-08, G-IR-09, G-IR-10, G-IR-12, G-IR-15 |
| 24 | **Workloads and hosts below the hardening standard**; no CIS scans; host firewalls and listening services undocumented. | Moderate | (a) per-container report for HS-WL-03/04/10, fix Tier 1 first; (b) kube-bench k3s profile; (c) CIS L1 on hosts, `ss -tlnp` record, deny-by-default host firewall; (d) W-04 reasons | 2027-06-30 | G-CM-11, G-SC-02, G-CM-10 |
| 25 | **Image provenance is weak.** 19% digest-pinned, no allow-listing, no signatures, custom images built by hand outside CI. | Moderate | (a) pin all images; (b) admission policy rejecting unpinned images; (c) build and sign custom images in CI, verify after push | 2027-06-30 | G-CM-12, G-SR-02, G-SA-03 |
| 26 | **No malware scanning of uploads or downloads.** | Moderate | ClamAV on Nextcloud uploads and the downloads path | 2027-06-30 | G-SI-06 |
| 27 | **Dead NetworkPolicy selectors** (`pangolin`, `forgejo`, `invidious`) with no CI check. | Low | Remove them; add HS-NET-03 check to `check-invariants.py` | 2026-11-30 | G-AC-08 |
| 28 | **No vulnerability disclosure channel or user-facing notice.** Service users get no security guidance, monitoring notice or documentation; harness loading of `AGENTS.md` is unproven; public share links unregulated. | Low | (a) `SECURITY.md` and private reporting; (b) a short page for service users (monitoring, MFA, reporting, share links); (c) a check each harness loads `AGENTS.md` | 2027-03-31 | G-RA-02, G-AT-02, G-AT-03, G-SI-11, G-SA-07, G-AC-16 |
| 29 | **Inventory and classification gaps.** No namespace class/tier labels or check, supporting components untiered, no support-status or ports inventory. | Low | (a) labels + CI check (policy §5.3); (b) tiers for laptop, backup server, off-site, escrow; (c) support-status column; (d) per-host ports list | 2027-03-31 | G-CM-13, G-CP-07, G-SA-10, G-SA-06 |
| 30 | **No supply-chain plan or external-service register.** No admission criteria, provider assessments, exit plans, principles statement or security budget. | Low | (a) SCRM one-pager; (b) provider register (MFA, retention, contacts, attestation, exit); (c) admission criteria; (d) principles + ADR index; (e) time/money note | 2027-03-31 | G-SR-01, G-SA-09, G-SA-04, G-SA-08, G-SA-02 |
| 31 | **Data handling details.** Shared Redis isolation undocumented; agent transcripts kept indefinitely; DNSSEC unverified. | Low | (a) record Redis isolation; (b) transcript cleanup timer and provider retention record; (c) check DNSSEC | 2027-03-31 | G-SC-01, G-SI-14, G-SC-06 |
| 32 | **Physical, maintenance and media records missing.** No physical policy section, no UPS evidence, no hardware log, no disposal procedure. | Low | (a) physical section in policy; (b) hardware and disposal log; (c) sanitization runbook; (d) UPS decision | 2027-06-30 | G-PE-01, G-PE-02, G-MA-01, G-MP-01 |

## Findings outside the SSP

`00-system-description.md` §7 listed six discrepancies. Status on 2026-10-03:

| # | Finding | Status |
|---|---|---|
| 1 | `docs/access-procedures.md` told readers to print the ArgoCD admin password | Fixed on this branch (owner-only, with `secret-meta` alternative); still on `main` until merged (item 10) |
| 2 | "Emergency Bypass" deleted an Application with `--cascade=background` | Fixed on this branch (`--cascade=orphan`); still on `main` until merged (item 10). **Dangerous while it remains on `main`.** |
| 3 | Restore re-applied ArgoCD from the unpinned `stable` manifest | Fixed on this branch: uses `scripts/bootstrap-argocd.sh`, which pins the version; still on `main` until merged |
| 4 | "Maintenance Windows" names an `#ops-alerts` channel and a Sunday window | Open, part of `G-AC-01` (item 10) |
| 5 | `docs/RUNDOWN.md` told readers to grep a password from qBittorrent logs | Fixed (`6a99803`) |
| 6 | `AGENTS.md` claimed images were digest-pinned | Fixed (`6a99803`); pinning itself is item 25 |
