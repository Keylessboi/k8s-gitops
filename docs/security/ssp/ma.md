# MA — Maintenance

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

All maintenance is done by the owner (or by agents acting for the owner), mostly remotely over Tailscale. There is no IPMI or BMC, so hands-on BIOS work happens from the running OS (`smbios-token-ctl`). No third party has ever maintained the hardware. The gaps are records: maintenance is visible in git and the doctor log for software, but hardware work (disk swaps, moves, BIOS changes) is not logged anywhere.

| Disposition | Count |
|---|---|
| Partially implemented | 5 |
| Alternative implementation | 1 |
| Not applicable | 3 |
| **Total** | **9** |
---

### MA-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Maintenance rules: policy §11 (change), §13.4 (disposal). No maintenance procedure. DRAFT until merged.

**Evidence.** Policy §11, §13

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All MA.

### MA-2 Controlled Maintenance

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Software maintenance is git and the doctor log. Hardware maintenance (disk replacement, BIOS settings, moving equipment) has no record or procedure, except doctor-log entries when something broke.

**Evidence.** `docs/doctor-log.md`

**Gaps.**
- `G-MA-01` Hardware maintenance is not recorded. Risk: a disk swap, BIOS change or move is not traceable when it later causes a fault; a removed disk leaves without sanitization. Remedy: a hardware log in `docs/` (date, host, what, disk serials), linked to MP-6 disposal. Target **2027-03-31**.

**Related.** MP-6, CM-3.

### MA-3 Maintenance Tools

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Maintenance tools are standard OS tools and `scripts/` in git; `smbios-token-ctl` on pve. Not inventoried.

**Evidence.** `scripts/`; `00-system-description.md` §2.1

**Gaps.** Covered by `G-MA-01`.

**Related.** MA-3(1).

### MA-3(1) Inspect Tools

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No maintenance tools are brought in from outside; tools are packages on the hosts.

**Evidence.** —

**Gaps.** None.

**Related.** MA-3.

### MA-3(2) Inspect Media

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No diagnostic media is introduced to the systems.

**Evidence.** —

**Gaps.** None.

**Related.** MA-3.

### MA-3(3) Prevent Unauthorized Removal

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No maintenance equipment leaves the home; disk removal follows MP-6.

**Evidence.** —

**Gaps.** None.

**Related.** MP-6.

### MA-4 Nonlocal Maintenance

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Nonlocal maintenance is the normal mode: SSH over Tailscale with the `worker_key` key to pve, the nas and travisbackupserver. Sessions are not logged centrally (`G-AU-03`), and agents perform maintenance with the owner's credentials (`G-AC-10`).

**Evidence.** `docs/access-procedures.md`

**Gaps.** Covered by `G-AU-03`, `G-AC-10`.

**Related.** AC-17.

### MA-5 Maintenance Personnel

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S1: the owner is the only maintenance person. AI agents maintain the system under policy §10 with the owner's credentials; their limits are the protection zones (§8) and approval points (HS-AGENT-05).

**Evidence.** Policy §8, §10; HS-AGENT-05

**Gaps.** None.

**Related.** PS-6, AC-6.

### MA-6 Timely Maintenance

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Spare parts and support: no spares or support contracts. Recovery after hardware failure is restore-in-place within tier RTOs (policy §7), which have never been measured (`G-CP-06`).

**Evidence.** Policy §7

**Gaps.** Covered by `G-CP-06`.

**Related.** CP-2.

