# AT — Awareness and Training

**SSP part of:** Homelab Information Security Program · **Baseline:** NIST SP 800-53 Rev. 5 MODERATE (tailored) · **Written:** 2026-10-01 · **Evidence basis:** repository and docs only; runtime state not inspected

## Family summary

This system has three kinds of "user" to make aware, and AT treats each one
differently. The **owner** holds every human role (policy §3.1). Policy App. A
sets their training as reading the policy and the doctor log at each review.
**Automated operators** (Claude Code, opencode, Codex, Gemini) are trained
through context: `AGENTS.md`, which points to policy §5–6, §8 and §10. They
get it at the start of every session, which is more often than any annual
course. **Service users** (friends and family) get nothing at all. They hold
password vaults, photos and files here, yet no document tells them how to spot
phishing, that MFA is expected (§9.4), or how to report a suspected compromise
(§3.1 makes reporting their responsibility but never gives them a channel).

The family's strongest feature is AT-2(d), feeding lessons learned back in.
Every doctor-log entry must state its prevention as the rule that
generalises, and the worst lessons are promoted into `AGENTS.md` ("Rules that
have been paid for").

The biggest gaps:

- nothing in the repository proves that each harness actually loads
  `AGENTS.md`;
- no training activity has ever been recorded (AT-4);
- service users get no security content at all;
- the policy that would make any of this binding is still a DRAFT (§21).

| Disposition | Count |
|---|---|
| Partially implemented | 2 |
| **Total** | **2** |

---

### AT-1 Policy and Procedures

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner |
| **Parameters** | at-1_prm_1 = System Owner and automated operators; at-01_odp.03 = system-level; at-01_odp.04 = System Owner (Security Officer role, policy §3.1); at-01_odp.05 = 12 months (policy App. A); at-01_odp.06 = SEV-1 or SEV-2 incident; new Tier 0 or 1 component; change in who has privileged access; major platform change (an ADR) (App. A); at-01_odp.07 = 12 months (App. A); at-01_odp.08 = the App. A events, plus any change to policy §8 or §10 or to `AGENTS.md` |

> a. Develop, document, and disseminate to [Assignment: System Owner and automated operators]:
>   1. [Selection: system-level] awareness and training policy that:
>     (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and
>     (b) Is consistent with applicable laws, executive orders, directives, regulations, policies, standards, and guidelines; and
>   2. Procedures to facilitate the implementation of the awareness and training policy and the associated awareness and training controls;
> b. Designate an [Assignment: System Owner] to manage the development, documentation, and dissemination of the awareness and training policy and procedures; and
> c. Review and update the current awareness and training:
>   1. Policy [Assignment: every 12 months] and following [Assignment: a SEV-1 or SEV-2 incident; a new Tier 0 or 1 component; a change in who has privileged access; a major platform change (an ADR)]; and
>   2. Procedures [Assignment: every 12 months] and following [Assignment: the same events, and any change to policy §8 or §10 or to `AGENTS.md`].

**Implementation.**
**a.1.** Awareness and training has no policy section of its own. What exists, all in `docs/security/01-policy.md`:
- purpose and scope (§1–§2);
- roles, with the Automated Operator role defined so its rules can be "trained" (§3.1);
- the duty of honesty and the duty to stop (§10.4–§10.5), which are what an agent must learn;
- the review calendar (§19);
- one row in App. A, which *is* the training policy: "The owner reads this policy and the doctor log at each review; agents receive it through `AGENTS.md`".

Management commitment is §20–§21. Coordination with other organizations does not arise. Consistency with law (a.1(b)) is not addressed for training, and nothing external requires a private homelab to train anyone.
**a.2.** The procedures:
- for agents, `AGENTS.md` (the "Where things are" table sends the agent to policy §5–6, §8 and §10);
- `docs/security/README.md` "How to use it", which has separate instructions for agents, the owner and assessors;
- for the owner, the doctor-log conventions (`docs/doctor-log.md` header) and `.github/pull_request_template.md`, which teach by prompting at the moment of work.

**Dissemination.** The repository is public, and agents read it in place. Service users are not included in at-1_prm_1, and that omission is itself a gap (AT-2).
**b.** The owner, as Security Officer.
**c.** The review cadence is the policy's 12-month cycle (document control; §19). No review has happened yet: the policy is version 0.1, DRAFT.

**Evidence.** `docs/security/01-policy.md` §3.1, §10, §19, §21 and App. A (last row); `AGENTS.md` "Where things are"; `docs/security/README.md` "How to use it".

**Gaps.**
- `G-AT-01` Training policy is one App. A row inside an unapproved (DRAFT) policy. It does not cover service users, does not say what "receive it through `AGENTS.md`" requires of a harness, and sets no record-keeping. *Risk:* awareness depends on habits nobody has written down, so a new harness or a new service user falls outside it. *Remedy:* add a short awareness-and-training subsection to the policy covering all three audiences, the delivery mechanism for each, and records (AT-4). Merge it with the policy approval. Target **2026-12-31**.

**Related.** Policy §3.1, §10, §19, §21, App. A; AT-2, AT-3, AT-4; PL-4; G-PL-01.

### AT-2 Literacy Training and Awareness

| | |
|---|---|
| **Baseline** | LOW, MODERATE |
| **Disposition** | Partially implemented |
| **Responsible** | System Owner; automated operators (as recipients) |
| **Parameters** | at-2_prm_1 = owner: every 12 months (each policy review); automated operators: at the start of every session; at-2_prm_2 = the App. A policy review events, and any change to policy §5–§10 or to `AGENTS.md`; at-02_odp.05 = doctor-log entries and its symptom index; the "Rules that have been paid for" section of `AGENTS.md`; the PR template's prompts; the waiver register and standard statuses; at-02_odp.06 = 12 months; at-02_odp.07 = every SEV-1 or SEV-2 incident, and every doctor-log prevention that changes a rule |

> a. Provide security and privacy literacy training to system users (including managers, senior executives, and contractors):
>   1. As part of initial training for new users and [Assignment: owner: every 12 months, at each policy review; automated operators: at the start of every session] thereafter; and
>   2. When required by system changes or following [Assignment: the App. A policy review events, and any change to policy §5–§10 or to `AGENTS.md`];
> b. Employ the following techniques to increase the security and privacy awareness of system users [Assignment: doctor-log entries and its symptom index; the "Rules that have been paid for" section of `AGENTS.md`; the pull request template's prompts; the waiver register and the measured standard statuses];
> c. Update literacy training and awareness content [Assignment: every 12 months] and following [Assignment: every SEV-1 or SEV-2 incident, and every doctor-log prevention that changes a rule]; and
> d. Incorporate lessons learned from internal or external security incidents or breaches into literacy training and awareness techniques.

**Implementation.**
**a.** *Owner:* literacy comes from operating the system. The formal requirement is App. A's read-through at each review, and none has been recorded (AT-4). *Agents:* `AGENTS.md` opens with the rules that matter most:
- a push is a production deploy;
- never read a secret value, with a do/don't table;
- deleting state takes a human.

It then sends the agent to policy §5–6, §8 and §10. "Initial" and "periodic" are the same event for an agent: each session starts with no memory, so the content is delivered every time, *if* the harness loads it. `AGENTS.md` line 3 says it is "read by opencode, Codex, Copilot, Gemini and Claude-style harnesses". The repository has no `CLAUDE.md` or other per-harness pointer, though, so whether each harness loads it is **[UNVERIFIED]**.

*Service users:* nothing. Account creation (`docs/accounts.md` "The workflow"; `docs/RUNDOWN.md` "Adding a Person") ends at "tell the person to log in". There is no step that tells them about MFA, phishing, or how to report a compromise.

**b.** These techniques are real and specific:
- the doctor log's symptom index ("This index is the point of the file");
- the PR template's Prevention and Verification prompts;
- the status vocabulary in `03-homelab-standard.md` §1, which keeps a requirement from being reported as better than it is.

**c.** `AGENTS.md` changed on 2026-10-01 to match measured state (HS-WL-01, 16/85 pinned). That is content updated after an event. There is no 12-month content review yet.
**d.** This is the part that is implemented. Every doctor-log entry carries a Prevention line, "the rule that generalises" (`AGENTS.md` "The doctor log"). The most expensive lessons are lifted into `AGENTS.md` "Rules that have been paid for", and from there into HS requirements whose Source column cites the incident (for example HS-REC-05 ← the 2026-09-04 outage).

**Evidence.** `AGENTS.md` (whole file, especially lines 1–8, 37–58, 90–121); `docs/doctor-log.md` header and symptom index; `.github/pull_request_template.md`; `docs/security/03-homelab-standard.md` §3–§11, Source column; `docs/accounts.md` "The workflow, start to finish".

**Gaps.**
- `G-AT-02` Service users get no security literacy content. Policy §3.1 makes them responsible for "reporting suspected compromise", and §9.4 says they **SHOULD** use MFA, but they are never told either, nor given a channel. *Risk:* a phished Vaultwarden or Authentik account goes unreported, and §16.6 notification has no counterpart for reporting the other way. *Remedy:* a one-page welcome note sent with every new account and to existing users. It covers MFA enrolment, Vaultwarden's master password being separate from SSO, what a genuine message from the owner looks like, and how to report a problem. Target **2027-01-31**.
- `G-AT-03` Nothing proves each harness loads `AGENTS.md`. The repo has no `CLAUDE.md` or equivalent pointer, and no check confirms the policy is in an agent's context before it acts. *Risk:* an agent works with none of the rules and only the Claude Code hooks to stop it, and other harnesses have no hooks at all (HS-SEC-03). *Remedy:* add a pointer file for each harness in use, and have the owner confirm each harness's loading behaviour once (G-AT-03 command in the lead report). Target **2026-12-15**.

**Related.** Policy §3.1, §9.4, §10, §16.6, App. A; HS-AGENT-01, HS-OBS-05; AT-2(2), AT-2(3), AT-3; PL-4; IR-2.
