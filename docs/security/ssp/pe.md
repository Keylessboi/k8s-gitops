# PE — Physical and Environmental Protection

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-03 (compact form, see `02-tailoring.md` §2) · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

The servers sit in a home (S2): pve and the nas at the main site, travisbackupserver at a second residence. Facility controls (badges, guards, visitor logs, fire suppression, emergency lighting) are tailored out, but the physical risks are real and are kept in scope: theft or a household member at a server, power loss (the 2026-09-04 outage; AC power recovery now on, HS-REC-05), heat, and a move of equipment (the 2026-08-28 closet move in the doctor log). There is no UPS evidence.

| Disposition | Count |
|---|---|
| Partially implemented | 4 |
| Alternative implementation | 3 |
| Not applicable | 11 |
| **Total** | **18** |
---

### PE-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Physical rules are scattered: power recovery (HS-REC-05), encryption against disk theft (policy §12). No physical policy section.

**Evidence.** HS-REC-05; policy §12

**Gaps.**
- `G-PE-01` No physical and environmental section in the policy. Risk: power, heat and access are handled only after an incident. Remedy: a short policy section (where servers live, who can reach them, power, temperature alerting, moves). Target **2027-03-31**.

**Related.** All PE.

### PE-2 Physical Access Authorizations

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** S2: authorized physical access is the household; the servers are in the owner's home. Disk encryption (`G-SC-05`) is the compensating control against someone with physical access.

**Evidence.** `02-tailoring.md` §3.1

**Gaps.** Covered by `G-SC-05`.

**Related.** PE-3.

### PE-3 Physical Access Control

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** As PE-2: the home's locks control entry. No monitored access to the server location.

**Evidence.** —

**Gaps.** Covered by `G-PE-01`.

**Related.** PE-2.

### PE-4 Access Control for Transmission

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Cabling is inside the home; no shared transmission medium outside the owner's control beyond the ISP link.

**Evidence.** —

**Gaps.** None.

**Related.** SC-8.

### PE-5 Access Control for Output Devices

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Output devices (console screens) are not used in normal operation; servers are headless.

**Evidence.** `00-system-description.md` §2.1

**Gaps.** None.

**Related.** —

### PE-6 Monitoring Physical Access

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S2: no facility monitoring. Physical intrusion would be noticed as an outage (heartbeat watchdog).

**Evidence.** HS-OBS-01

**Gaps.** None.

**Related.** PE-6(1).

### PE-6(1) Intrusion Alarms and Surveillance Equipment

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Follows PE-6.

**Evidence.** —

**Gaps.** None.

**Related.** PE-6.

### PE-8 Visitor Access Records

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** S2: no visitor records in a home.

**Evidence.** —

**Gaps.** None.

**Related.** PE-2.

### PE-9 Power Equipment and Cabling

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Power cabling is household wiring; nothing to protect beyond PE-11.

**Evidence.** —

**Gaps.** None.

**Related.** PE-11.

### PE-10 Emergency Shutoff

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No facility emergency shutoff; the owner powers down hosts by hand. Hosts recover on power return (HS-REC-05).

**Evidence.** HS-REC-05

**Gaps.** None.

**Related.** PE-11.

### PE-11 Emergency Power

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** After the 2026-09-04 power loss, CT 200 got `onboot: 1` and pve AC power recovery was turned on, so the cluster returns without a human (HS-REC-05, MET 2026-09-05). Whether any UPS protects pve or the nas is **[UNVERIFIED]**; a power cut during a ZFS or Postgres write relies on their crash consistency.

**Evidence.** HS-REC-05; doctor log 2026-09-04

**Gaps.**
- `G-PE-02` No UPS evidence for pve and the nas. Risk: repeated power cuts during writes risk corruption of databases on `local-path`. Remedy: record whether a UPS exists; if not, a small UPS with NUT-triggered clean shutdown for pve and the nas. Target **2027-06-30**.

**Related.** CP-10, PE-14.

### PE-12 Emergency Lighting

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Household lighting; no emergency lighting requirement for a home.

**Evidence.** —

**Gaps.** None.

**Related.** —

### PE-13 Fire Protection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Alternative implementation |

**Implementation.** Household smoke detection is the home's; servers have no suppression. Data survives a fire through the off-site copy (CP-6), whose freshness is unalerted (`G-CP-12`).

**Evidence.** `00-system-description.md` §4.2

**Gaps.** Covered by `G-CP-12`.

**Related.** CP-6.

### PE-13(1) Detection Systems — Automatic Activation and Notification

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No automatic fire detection that notifies anyone other than household alarms.

**Evidence.** —

**Gaps.** None.

**Related.** PE-13.

### PE-14 Environmental Controls

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** Temperature alerts exist (`apps/monitoring/temperature-alerts.yaml`). Humidity is not monitored. After the closet move (doctor log 2026-08-28) heat is the realistic environmental risk.

**Evidence.** `apps/monitoring/temperature-alerts.yaml`; doctor log 2026-08-28

**Gaps.** Covered by `G-PE-01`.

**Related.** SI-4.

### PE-15 Water Damage Protection

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** No water shutoff valves to manage; water damage is covered by the off-site copy (CP-6).

**Evidence.** —

**Gaps.** None.

**Related.** CP-6.

### PE-16 Delivery and Removal

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Not applicable |

**Implementation.** Equipment delivery and removal is the owner's; disposal of storage follows MP-6.

**Evidence.** —

**Gaps.** None.

**Related.** MP-6.

### PE-17 Alternate Work Site

| | |
|---|---|
| **Baseline** | MODERATE |
| **Disposition** | Partially implemented |

**Implementation.** travisbackupserver runs at a second residence and is administered remotely over Tailscale (root SSH, fail2ban active). Its physical security is the other household's.

**Evidence.** `00-system-description.md` §2.1

**Gaps.** Covered by `G-PE-01`.

**Related.** AC-17.

