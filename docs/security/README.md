# Homelab Information Security Program

This directory holds the homelab's security program, written the way an
organisation documents one: a policy that governs, a system security plan that
says how each control is met, a catalogue of testable requirements, and a
tracked list of what is not done yet.

It is built on **NIST SP 800-53 Rev. 5, MODERATE baseline**, tailored for a
one-person operation. That choice is deliberate. 800-53 is public domain,
published in machine-readable form (OSCAL), and has decades of edge cases
built into its control text. A standard written from scratch would not have
them.

## Documents

| # | Document | What it answers | Kind |
|---|---|---|---|
| 00 | [System description](00-system-description.md) | What is the system? Where is the boundary, what data is where, who and what can touch it? | Facts, verified and dated |
| 01 | [Information security and data governance policy](01-policy.md) | What are the rules? Classification, protection zones, access, agent conduct, change, keys, retention, incidents | **Normative**: governs everything below |
| 02 | [Baseline tailoring](02-tailoring.md) | Which 800-53 controls apply, which are inherited, which are tailored out, and why | Decisions |
| 03 | [Homelab standard](03-homelab-standard.md) | Which concrete, testable requirements apply here, and is each one met today? | Requirements with measured status |
| 04 | [Plan of action and milestones (POA&M)](04-poam.md) | What is not done, how risky is that, and when will it be fixed? | Tracked findings |
| ssp/ | [Control implementations](ssp/) | For each of the 287 MODERATE controls: disposition, parameters, how it is met here, evidence, gaps | One file per control family |

The machine-readable parts live outside this directory:

| Path | What it is |
|---|---|
| `security/registers/` | The registers that rules refer to. Exceptions take effect only with the owner's hardware-key signature (`03` §12.9). |
| `policy/` | Policy as code: Conftest rules over the rendered manifests, the Polaris quality config and its score floor |
| `scripts/security/` | Render, check, approve and scan scripts, used by CI and by hand |
| `.github/workflows/security.yaml` | The CI that runs them; weekly Trivy image scans |

## How to use it

**If you are an AI agent working in this repository:** read `01-policy.md`
§5–6 (data classes), §8 (protection zones) and §10 (your rules), and follow
them. They override `AGENTS.md` where the two differ. In short:
- never read a secret's value;
- never touch Zone 0;
- Zone 1 changes go through a PR the owner merges;
- show data-plane evidence before saying something works;
- stop and ask at the points §10.4 lists.

**If you are the owner:**
- `04-poam.md` is the work list.
- `03-homelab-standard.md` §2 is the scorecard.
- `01-policy.md` §19 is the review calendar.
- §21 is how the policy comes into force: merging it.

**If you are assessing it:** start with `00` and `02`, then sample `ssp/`
sections and run the evidence commands they list. Every implementation claim
cites a file, or is marked **[UNVERIFIED]**.

## How this was produced, and what it is not

- The control text in `ssp/` is quoted from NIST's official OSCAL catalog
  (`usnistgov/oscal-content`, SP 800-53 Rev. 5), not paraphrased from
  memory.
- The implementation statements were drafted by AI agents on 2026-10-01..03,
  about 50 in full form and the rest in compact form (`02-tailoring.md` §2). They
  were written from the repository and its documentation only, under a rule
  that forbade inventing facts. **Runtime state was not inspected**: no
  cluster, host or provider console was queried. Anything that can only be
  known by looking (MFA settings, sanoid schedules, encryption of local disks,
  k3s secrets encryption) is marked [UNVERIFIED] and listed in the POA&M.
- **This is not a certification or an audit.** No independent assessor has
  reviewed it. It is a self-assessment that is honest about its gaps. The
  status columns are the part to trust least until the owner re-measures
  them (`01-policy.md` §19).
- ISO/IEC 27001/27002 were not used as the base, because their text is not
  freely available. Most of what a 27001 programme would demand maps onto
  the 800-53 controls here.

## Keeping it alive

- Changes to `01`, `02` and `03` are Zone 1 (`01-policy.md` §8): a PR the
  owner merges.
- When a control's implementation changes (a new mechanism, a closed gap),
  update its `ssp/` section and the matching `03` status in the same PR.
- Every SEV-1 or SEV-2 incident reopens the policy review (§19).
