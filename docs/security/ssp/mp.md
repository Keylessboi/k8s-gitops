# MP — Media Protection

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

Media protection reduces to disks: the ZFS mirror on the nas, the local disks in pve, the backup server's disks and the operator laptop. There is no removable or paper media in normal use. ZFS native encryption on `tank` helps only against a removed disk (the key is on the host); encryption of the other disks is unverified; and there is no disposal record. Policy §13.4 sets sanitization by NIST SP 800-88 methods.

| Disposition | Count |
|---|---|
| Implemented | 1 |
| Partially implemented | 2 |
| Planned | 1 |
| Alternative implementation | 1 |
| Not applicable | 2 |
| **Total** | **7** |
---

### MP-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Media rules are policy §13.3–13.4 (retention, disposal, sanitization). No dedicated procedure exists. DRAFT until merged.

**Evidence.** Policy §13

**Gaps.** Approval tracked with `G-AU-01`.

**Related.** All MP.

### MP-2 Media Access

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** Digital media are fixed disks inside servers in a home (S2). Access is restricted by physical access to the home and, for `tank`, by encryption. No removable media.

**Evidence.** `02-tailoring.md` §3.1 S2

**Gaps.** Encryption of non-`tank` disks is `G-SC-05`.

**Related.** PE-3, SC-28.

### MP-3 Media Marking

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No media leaves the systems or is distributed; labelling has no audience in a one-person home. Disks to be disposed of are handled under MP-6.

**Evidence.** —

**Gaps.** None.

**Related.** MP-6.

### MP-4 Media Storage

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Disks stay inside their hosts. Protection against theft relies on the home and on encryption (`tank` yes; others **[UNVERIFIED]**, `G-SC-05`).

**Evidence.** `00-system-description.md` §4.1

**Gaps.** Covered by `G-SC-05`.

**Related.** SC-28, PE-3.

### MP-5 Media Transport

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No system media is transported; off-site copies travel over the network (Tailscale). If a disk is ever moved between sites, MP-6 and the encryption requirement apply.

**Evidence.** `00-system-description.md` §4.2

**Gaps.** None.

**Related.** MP-6.

### MP-6 Media Sanitization

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Planned |

**Implementation.** Policy §13.4 requires sanitization by SP 800-88 methods (clear/purge/destroy by class) before a disk leaves the owner's control. No disposal has been recorded, and no procedure says how a ZFS mirror member or a pve disk is purged.

**Evidence.** Policy §13.4

**Gaps.**
- `G-MP-01` No disposal procedure or record. Risk: a failed or sold disk carries C4 data (databases, Secrets) out of the home. Remedy: a short runbook (ZFS: destroy the key and `blkdiscard`/secure erase; other disks: ATA/NVMe sanitize or physical destruction) and a disposal log in `docs/`. Target **2027-03-31**.

**Related.** MA-2, SR-12.

### MP-7 Media Use

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Implemented |

**Implementation.** No removable media is used with the system; servers are headless and data moves over the network.

**Evidence.** `00-system-description.md` §2.1

**Gaps.** None.

**Related.** AC-20(2).

