# SI — System and Information Integrity

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

<!-- SUMMARY-PLACEHOLDER -->

| Disposition | Count |
|---|---|
| Partially implemented | 4 |
| Planned | 1 |
| **Total** | **5** |
---

### SI-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner (policy §3.1, Security Officer role) |
| **Parameters** | si-1_prm_1 = the System Owner and every Automated Operator (policy §3.1); si-01_odp.03 = organization-level; si-01_odp.04 = the System Owner, acting as Security Officer; si-01_odp.05 = 12 months (policy App. A); si-01_odp.06 = a SEV-1 or SEV-2 incident, a new Tier 0 or Tier 1 component, a change in who has privileged access, or a major platform change recorded in an ADR (App. A); si-01_odp.07 = 12 months (App. A); si-01_odp.08 = the events in si-01_odp.06, plus any change of updater or monitoring path |

> a. Develop, document, and disseminate to [Assignment: the System Owner and every Automated Operator]:
>   1. [Selection: organization-level] system and information integrity policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the system and information integrity policy and the associated system and information integrity controls;
> b. Designate an [Assignment: System Owner, acting as Security Officer] to manage the development, documentation, and dissemination of the system and information integrity policy and procedures; and
> c. Review and update the current system and information integrity:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident, a new Tier 0 or 1 component, a change in privileged access, or a major platform change (ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, plus any change of updater or monitoring path].

**Implementation.**
**a.1.** There is no separate SI policy. HL-POL-001 (`docs/security/01-policy.md`) covers the family: purpose and scope (§1–2), roles (§3), integrity as a categorization objective (§4: configuration and identity at MODERATE integrity), logging and monitoring (§14), vulnerability and patch management (§17), supply chain and image pinning (§15.3), agents treating read content as data (§10.2.5) and retention (§13). Management commitment is the owner's approval and risk acceptance (§20–21). For (b), the only external obligations on a private homelab are provider terms and licences; nothing in the SI area adds to them.
**a.2.** Procedures are scattered across runbooks, not written for SI: `scripts/doctor.sh` and `docs/doctor-log.md` (diagnosis and its record), `docs/ntfy.md` (alert paths), `docs/recovery/cluster-down.md` (the external watchers), `renovate.json` (updates), and the `validate` workflow (`.github/workflows/validate.yaml`). There is no written procedure for triaging a vulnerability, responding to a malware finding, or reviewing alerts. Agents receive the rules through `AGENTS.md`.
**b.** The System Owner holds the role (§3.1).
**c.** Cadence is set in §19 and App. A. The policy is a **DRAFT** (header, §21), so no review has run.

**Evidence.** `docs/security/01-policy.md` §§1–4, 10.2, 13–15, 17, 19–21; `AGENTS.md`; `docs/ntfy.md`; `docs/recovery/cluster-down.md`; `renovate.json`.

**Gaps.**
- `G-SI-01`: The policy is unapproved, and there are no SI procedures for vulnerability triage, a malware finding, or alert review. Risk: when one of these happens, the response depends on whichever agent is driving and what it guesses. Remedy: the owner approves HL-POL-001, and a `docs/runbooks/integrity.md` covers CVE triage (with the §17 clocks), a suspected-malware playbook (isolate the namespace with a deny-all NetworkPolicy, preserve, rebuild from git) and a weekly alert-review checklist. Target: **2026-12-15**.

**Related.** Policy §§3, 10.2.5, 14, 15, 17, 19–21; SA-1; IR-1; all SI controls below.

### SI-2 Flaw Remediation

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; Renovate (GitHub App); argocd-image-updater (this branch only); ArgoCD |
| **Parameters** | si-02_odp = for container images, 14 days for critical and 30 days for high-severity flaws from a fix being available (policy §17, App. A); for host OS packages, at least monthly (§17); for k3s, within one minor version of a security-supported release (§17, HS-HOST-03) |

> a. Identify, report, and correct system flaws;
> b. Test software and firmware updates related to flaw remediation for effectiveness and potential side effects before installation;
> c. Install security-relevant software and firmware updates within [Assignment: 14 days (critical) / 30 days (high) for container images; monthly for host OS packages; one minor version of a supported k3s release] of the release of the updates; and
> d. Incorporate flaw remediation into the organizational configuration management process.

**Implementation.**
**a. Identify.** Flaws are found two ways: operationally, through the doctor log (every diagnosed incident has a root cause and a prevention, `AGENTS.md` "The doctor log"), and by version drift, through updaters. No tool identifies *security* flaws: nothing scans images, hosts or Helm charts for known CVEs (HS-SUP-04 UNMEASURED; no `trivy`, `grype` or equivalent anywhere in the repo). A critical CVE in an internet-facing image is noticed only if an update for it happens to arrive.

**Correct, in this branch.** Renovate opens PRs for Helm charts only, majors are disabled, and 0.x minors are disabled (`renovate.json`). argocd-image-updater bumps 8 images in 6 apps within a major (`apps/image-updater/imageupdaters.yaml`). **On `main`**, ADR-0013 (2026-09-30) replaced both: Renovate scans `apps/**`, waits 3 days (`minimumReleaseAge`), and merges its own PRs once `validate` is green, majors included except for listed data services. ADR-0013 records why: Authentik, ArgoCD (v2.12.3) and Traefik had sat months behind upstream.

**b. Test.** `validate` proves manifests render and pass schema; it does not start the app (ADR-0013, "Consequences"). There is no staging (system description §6.1). Testing is in production, followed by data-plane verification (HS-AGENT-07) and `git revert` if it fails.

**c. Timeliness.** Not measured for any component. Host OS updates on pve, the nas and travisbackupserver have no automation in `ansible/playbooks/` and no record. k3s is `v1.31.5+k3s1` (system description §2.1); whether 1.31 is still security-supported is **[UNVERIFIED]**.

**d.** Image and chart updates are git commits through ArgoCD (HS-GIT-01). Host and k3s updates are outside configuration management.

**Evidence.** `renovate.json`; `git show origin/main:renovate.json`; `git show origin/main:docs/adr/0013-renovate-owns-updates.md`; `apps/image-updater/imageupdaters.yaml`; `.github/workflows/validate.yaml`; HS-SUP-01, HS-SUP-04, HS-HOST-03.

**Gaps.**
- `G-SI-02`: No vulnerability scanning of images, charts or hosts. Risk: the §17 clocks cannot start, because nobody learns a fix is available. Remedy: a scheduled CI job that renders every app, lists images and runs `trivy image --severity HIGH,CRITICAL` on internet-facing ones weekly, opening an issue per finding; the same job on every Renovate PR. Target: **2027-01-31**.
- `G-SI-03`: Host OS and k3s patching has no mechanism or record. Risk: kernel, OpenZFS, sshd and k3s flaws on Tier 0 hosts stay open indefinitely. Remedy: an Ansible patch playbook per host (kernel/ZFS updates as Normal changes, §17), run monthly with a doctor-log line; a k3s upgrade plan to a supported minor. Target: **2027-03-31**.
- `G-SI-04`: On `main`, updates (majors included) reach production with no test beyond rendering, against policy §11.1 and §15.3. Risk: a bad release lands overnight unattended. Remedy: the owner reconciles ADR-0013 with the policy (one of them changes), and automerge is limited to Z2 apps with a post-merge smoke test. Target: **2026-11-30**.

**Related.** Policy §§11, 15.3, 17; HS-SUP-01, HS-SUP-04, HS-HOST-03, HS-AGENT-07; ADR-0013 (`main`); CM-3, RA-5, SA-10; SI-2(2).

### SI-2(2) Automated Flaw Remediation Status

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; Renovate |
| **Parameters** | si-02.02_odp.01 = Renovate's Dependency Dashboard issue and the PRs it opens (images and charts); a scheduled image vulnerability scan (planned, G-SI-02); a host package report (planned, G-SI-03); si-02.02_odp.02 = Renovate's run schedule for images and charts; weekly for the scan; monthly for hosts |

> Determine if system components have applicable security-relevant software and firmware updates installed using [Assignment: Renovate's Dependency Dashboard and PRs; a scheduled image vulnerability scan (planned); a host package report (planned)] [Assignment: on Renovate's schedule; weekly; monthly].

**Implementation.** The only automated mechanism is Renovate. In this branch it sees Helm charts only. On `main` it sees every image in `apps/**/*.yaml` and, through a regex manager, image tags inside Helm `valuesInline` that carry a `# renovate:` comment. ADR-0013 names the Dependency Dashboard issue as "the single place to see what is pending, including the held-back majors". Two limits make this an *update* status, not a *security* status. Renovate reports that a newer version exists; it does not say whether the installed one has a known vulnerability. And it cannot see the locally built images (`applemusic-decryptor`, `applemusicarr-plugin`, `spatial-sidecar`, `wrapper-lite-src`) or the owner's GHCR forks, which `renovate.json` on `main` disables explicitly, nor anything on the hosts (kernel, ZFS, Proxmox, Arch packages, k3s binary, the scripts in `scripts/host/`). Firmware (BIOS on the Vostro and the nas board, disk firmware) has no status mechanism. SMART monitoring (`apps/monitoring/smartctl-alerts.yaml`) reports disk health, not firmware currency.

**Evidence.** `git show origin/main:renovate.json` (`kubernetes.managerFilePatterns`, `customManagers`, first `packageRules` entry); ADR-0013 on `main`; GitHub Dependency Dashboard issue (owner can open it).

**Gaps.**
- `G-SI-05`: No automated view of security-relevant updates for hosts, k3s, locally built images or firmware. Risk: the components with the most privilege (Tier 0 hosts) are the ones nobody's tooling reports on. Remedy: covered by G-SI-02 (images) and G-SI-03 (hosts); in addition, a monthly `scripts/host/patch-report` that lists pending security updates on pve, the nas and travisbackupserver into one ntfy message. Target: **2027-03-31**.

**Related.** SI-2; RA-5; CM-8; HS-SUP-04, HS-HOST-03; ADR-0013.

### SI-3 Malicious Code Protection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |
| **Responsible** | System Owner |
| **Parameters** | si-03_odp.01 = signature-based; si-03_odp.02 = weekly; si-03_odp.03 = network entry and exit points (the completed-download hand-off in `downloads`, ConvertX uploads, the Nextcloud upload path); si-03_odp.04 = quarantine malicious code; si-03_odp.05 = not selected; si-03_odp.06 = the System Owner, via ntfy and email (policy App. A) |

> a. Implement [Selection: signature-based] malicious code protection mechanisms at system entry and exit points to detect and eradicate malicious code;
> b. Automatically update malicious code protection mechanisms as new releases are available in accordance with organizational configuration management policy and procedures;
> c. Configure malicious code protection mechanisms to:
>   1. Perform periodic scans of the system [Assignment: weekly] and real-time scans of files from external sources at [Selection: network entry and exit points] as the files are downloaded, opened, or executed in accordance with organizational policy; and
>   2. [Selection: quarantine malicious code] ; and send alert to [Assignment: the System Owner, via ntfy and email] in response to malicious code detection; and
> d. Address the receipt of false positives during malicious code detection and eradication and the resulting potential impact on the availability of the system.

**Implementation.**
**a–c. Not in place.** No malicious code protection mechanism exists. A repository search finds no ClamAV, YARA or file scanner. The system nonetheless ingests a lot of untrusted content:
- **Peer-to-peer downloads.** qBittorrent and slskd (`apps/downloads/qbittorrent.yaml`) fetch arbitrary files from strangers. The repo itself calls this "this untrusted torrent pod" (`apps/downloads/qbit-upload-config.yaml:11-12`). Completed torrents in one category are **pushed automatically into Nextcloud over WebDAV** (same file, lines 1-8), the store that holds service users' personal files, from which clients sync them to devices. Lidarr imports audio into the library that Navidrome and remux serve to users.
- **ConvertX** runs ffmpeg, LibreOffice and ImageMagick on uploaded files, as root by upstream design (`apps/convertx/deployment.yaml:46-52`). It is published **without** Authentik forward-auth (`apps/convertx/ingress.yaml:22-35`), behind only its own login with registration closed.
- **Other ingress of files:** Nextcloud and Immich uploads, the Kiwix ZIM download (`apps/kiwix/deployment.yaml:64-85`), Octo and the yt-dlp shim.

What exists is *containment*, not detection. qBittorrent can only egress through the AirVPN tunnel (system description §3). ConvertX has DNS-only egress (`apps/convertx/networkpolicy.yaml`), drops all capabilities and uses seccomp `RuntimeDefault`. CrowdSec's `crowdsecurity/http-cve` collection matches known exploit *requests* at the edge (`apps/crowdsec/kustomization.yaml`), which is SI-4, not file scanning. An agent asked to look at a downloaded file treats its contents as data (policy §10.2.5) but has no scanner to call either.

**d.** Any future scanner must not modify library files in place. They are hardlinked from `/data/torrents`, and rewriting one breaks the torrent it seeds (ADR-0004, `AGENTS.md`). Quarantine has to mean "not forwarded, plus an alert", not deleting or moving the seeded copy.

**Evidence.** `grep -rniE 'clamav|clamd|yara' .` (no hits); the files cited above.

**Gaps.**
- `G-SI-06`: No file scanning at any entry point. Risk: malware from P2P or an upload reaches Nextcloud, and from there service users' devices, with nothing to detect it. Remedy: deploy ClamAV (`clamd` with `freshclam`, which covers b) in-cluster. Scan in the qBittorrent completion hook *before* the WebDAV upload: on a hit, skip the upload and alert through ntfy. Add a weekly read-only scan of the completed-downloads tree and the Nextcloud bot user's folder. Target: **2027-02-28**.
- `G-SI-07`: ConvertX, a converter of arbitrary files running as root, is published without forward-auth. Its own header comment, `docs/RUNDOWN.md:25` and system description §3 all say otherwise. Risk: a crafted file aimed at a converter flaw needs only the app's own password. Remedy: put forward-auth bound to `authentik Admins` back in front, or restrict it with the `lan-only` middleware, and correct the comments and docs. Target: **2026-11-15**.

**Related.** Policy §§6, 10.2.5, 17; ADR-0004; HS-PSS-02 (W-04, `downloads` is `privileged`); SC-7; SI-4, SI-8, SI-10.

### SI-4 System Monitoring

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; CrowdSec (`apps/crowdsec`); monitoring stack (`apps/monitoring`); host watchers (`scripts/host/`) |
| **Parameters** | si-04_odp.01 = detect (1) attacks on published hosts: scanning, brute force, exploitation of known CVEs; (2) loss of a Tier 0/1 component or of the monitoring path itself; (3) failed or stale backups and storage faults; (4) configuration drift from git; si-04_odp.02 = CrowdSec scenarios and the community blocklist over Traefik access logs; ArgoCD diff and selfHeal; git attribution; Authentik's event log; on-demand log review in Loki; si-04_odp.03 = alerts, and the Prometheus and Loki data behind them; si-04_odp.04 = the System Owner; si-04_odp.05 = as needed; si-04_odp.06 = not selected |

> a. Monitor the system to detect:
>   1. Attacks and indicators of potential attacks in accordance with the following monitoring objectives: [Assignment: attacks on published hosts; loss of Tier 0/1 components or of monitoring; backup and storage failures; configuration drift] ; and
>   2. Unauthorized local, network, and remote connections;
> b. Identify unauthorized use of the system through the following techniques and methods: [Assignment: CrowdSec scenarios and community blocklist; ArgoCD diff and selfHeal; git attribution; Authentik's event log; on-demand log review];
> c. Invoke internal monitoring capabilities or deploy monitoring devices:
>   1. Strategically within the system to collect organization-determined essential information; and
>   2. At ad hoc locations within the system to track specific types of transactions of interest to the organization;
> d. Analyze detected events and anomalies;
> e. Adjust the level of system monitoring activity when there is a change in risk to organizational operations and assets, individuals, other organizations, or the Nation;
> f. Obtain legal opinion regarding system monitoring activities; and
> g. Provide [Assignment: alerts, and the Prometheus and Loki data behind them] to [Assignment: the System Owner] [Selection: as needed].

**Implementation.**
**a.1.** CrowdSec parses Traefik's access logs with the `traefik`, `http-cve` and `base-http-scenarios` collections and pulls the community blocklist. The owner raised the brute-force bucket capacity from 5 to 75 (`apps/crowdsec/kustomization.yaml`). Cluster, LAN and the owner's two WAN addresses are trusted and cannot be bounced (`apps/traefik/crowdsec-middleware.yaml`), so an attack from inside, such as a compromised pod or LAN device, is neither detected nor blocked there. Availability is watched by Prometheus/Alertmanager, in-cluster blackbox probes (`apps/monitoring/edge-probes.yaml`), the external watchdog on the nas (pve ICMP and k3s `:6443`) and the edge probe on travisbackupserver (`docs/recovery/cluster-down.md`, "What is in place now").
**a.2.** NetworkPolicies block undeclared flows, but kube-router REJECTs are not logged or alerted. SSH logins to pve, the nas and CT 200 are not collected. travisbackupserver runs fail2ban (system description §2.1).
**b.** There is no Kubernetes API audit log (HS-AGENT-13; policy §14.5). Authentik's event log stays inside Authentik; nothing exports it or alerts on it. Agents act with the owner's credentials (policy §9.2), so an agent's actions and the owner's look the same everywhere except in git trailers.
**c.1.** Alloy, a DaemonSet, ships every pod's logs and all Kubernetes Events to Loki, whose chunks are stored in MinIO (`apps/monitoring/kustomization.yaml:620-700, 814-905`). Host journals on pve, the nas and travisbackupserver are not shipped. **c.2.** Probes and ServiceMonitors are added per app as needed, and `scripts/doctor.sh` is the on-demand tool.
**d.** Only a "physical set" reaches a human: SMART, temperature, CrowdSec bouncer, node down, filesystem full, backup and MinIO. These go to ntfy through the pve relay and to email (`kustomization.yaml:376-540`). The default receiver is `null`. `KubeJobFailed`, crash loops and `TargetDown` "go to the model on report", meaning an agent reads them when asked. `EndpointDown` and `EndpointCertExpiringSoon` are not routed to anyone. On `main`, Grafana is disabled (`git show origin/main:apps/monitoring/kustomization.yaml`, `grafana.enabled: false`), so Loki has no UI.
**e.** Monitoring is adjusted after incidents, not when risk changes. The CrowdSec alert followed the 2026-09-11 lockout, and the external watchdog followed the 2026-09-04 outage.
**f.** No legal opinion has been obtained. Logs hold service users' IP addresses and usernames (C3, policy §14.2).
**g.** Alerts reach the owner in real time. Everything else is pulled on demand.

**Evidence.** Files cited above; `docs/ntfy.md`; `scripts/host/homelab-external-watchdog`; `scripts/host/homelab-edge-probe`; doctor-log 2026-09-04, 2026-09-11, 2026-09-14.

**Gaps.**
- `G-SI-08`: No API audit log, and no host authentication logs. Risk: a stolen kubeconfig, an SSH login or an agent misusing cluster-admin leaves no trace outside git. Remedy: enable k3s API audit logging (metadata level, with Secrets at metadata only) and ship it, plus the journals of CT 200 and the nas, through Alloy. Forward pve and travisbackupserver `sshd` logs. Keep 30 days (App. A). Target: **2027-02-28**.
- `G-SI-09`: Security logs (Authentik events, CrowdSec decisions) are never reviewed on a schedule, and nothing routes `EndpointCertExpiringSoon`. Risk: slow attacks and expiring certificates go unseen. Remedy: a weekly review step in the G-SI-01 runbook, and route `Endpoint.*` to `smart-email`. Target: **2026-12-31**.
- `G-SI-10`: The heartbeat receiver and checker on pve (`homelab-beat-receiver`, `homelab-beat-check.timer`) are not in the repository. `docs/ntfy.md` says "Source for both is in `scripts/host/`", but only the relay is there. Risk: the dead-man's switch cannot be rebuilt or reviewed. Remedy: commit both units. Target: **2026-11-30**.
- `G-SI-11`: No legal opinion on, or notice of, monitoring (f). Risk: service users are not told that their IPs and logins are logged. Remedy: in place of a legal opinion, which is disproportionate here, add a short monitoring and retention notice to `docs/accounts.md` and the accounts page. Target: **2026-12-31**.

**Related.** Policy §§9.2, 14, 16; HS-OBS-01..05, HS-AGENT-13; ADR-0007; AU-2, AU-6, AU-12; SI-4(2), SI-4(4), SI-4(5).

