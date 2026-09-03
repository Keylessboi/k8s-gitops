# ADR-0007: Freeze the platform layer; spend effort on headroom and checks

**Status:** Accepted
**Date:** 2026-09-03

## Context

Read against the whole of `docs/doctor-log.md` — 18 incidents between 26 Aug
and 3 Sep 2026 — roughly half are Kubernetes tax: failures that exist because
of the platform rather than the workload. The kube-router policy-programming
race twice, three probe misconfigurations, `command` replacing a container's
ENTRYPOINT, bare hostnames failing across namespaces, the ArgoCD ServerSideDiff
bug, and ArgoCD reporting `Healthy` over stale objects. On Compose plus systemd,
none of those exist.

The instinct that produced this cluster — "keep it enterprise" — was read as
*add more capable machinery*. Cilium was the specific proposal. Walking the
whole log against it:

| Incident class | Count | Would Cilium have helped? |
|---|---|---|
| Resource exhaustion | 4 | No — disk and RAM |
| Silent success | 5 | No — application state |
| Probe misconfiguration | 3 | No — our own manifests |
| Startup ordering | 4 | One of them (the kube-router race) |
| Mental-model traps | 4 | No — config |
| Wrong diagnosis | 2 | No — process |

**One incident of eighteen.** And even the duplicate-ARP outage sits outside it:
that was a Raspberry Pi answering for `192.168.1.240` on the L2 segment, below
anything a CNI observes. Against that: swapping the CNI on a live single-node
cluster is among the highest-risk changes available, a failed migration means no
pod networking at all with recovery needing console access to a box running 35
apps, and the agent and operator want several hundred MB on a node that idles at
**~89–92% of 13.8 GB**.

What *did* pay, on the same evidence: alert routing (11 of 18 incidents were
already detectable by rules that existed and were being discarded), one
diagnostic command, and a handful of cheap checks — one of which found a
seven-day-old bug on its first run.

### Rejected: migrating off Kubernetes

Counted honestly, about half the operational cost here is Kubernetes, and for
one node it is more machinery than the workload needs. Migration is still
rejected, but for a narrower reason than "k8s is fine": those eight or nine
failure modes are now **known, written down, and mostly solved**, and the
marginal cost of a documented trap is small. Migration trades a mapped minefield
for an unmapped one, costs months, and the person paying has explicitly said
they want to spend *less* effort on this, not more.

## Decision

The platform layer is frozen. No new CNI, no service mesh, no additional
operators, no second scheduler, no new abstraction between the workload and the
node — unless it removes more moving parts than it adds.

Remaining effort goes to three things instead:

1. **Headroom.** The only lever that reduces incident *count* rather than
   detection time. Resource exhaustion is 4 incidents with the widest blast
   radius in the log, and it is causal for others.
2. **Checks.** Preventions expressed as code rather than prose. This log
   records its own prose preventions failing twice.
3. **Data-plane proof.** Assertions that something actually worked, because
   `Synced/Healthy` hid three separate failures in one week.

For a single-node homelab, *enterprise* means fewer moving parts observed
ruthlessly — not more parts observed partially.

## Consequences

**Good:** every future "should we add X" has an answer already. The cluster
stays small enough to reason about at 2am and small enough for a 9B model to
debug, which is the stated goal. Effort concentrates on the two levels of
self-diagnosis that are actually missing — proving the detector works and
proving the recovery works.

**Bad:** genuine capabilities are given up. Hubble really would visualise the
kube-router race. eBPF-based policy really is faster than kube-router. Accepting
this ADR means accepting that those stay unavailable, and that some future
incident will be harder to diagnose than it would have been with more machinery.
The bet is that such incidents are rarer than the ones the machinery itself
would cause.

**Tripwire:** a pull request that adds a Helm chart in the `kube-system`,
`cilium`, `istio`, `linkerd`, or a new `*-system` namespace; anything
introducing a CRD that other applications must then be annotated for; or any
change whose justification is "this is how production clusters do it."

When one appears, ask the question this ADR was written from: **walk it against
`docs/doctor-log.md` and count how many real incidents it would have prevented.**
If the answer is one or fewer, the answer is no.

The other tripwire is the node. If it is still above 85% memory when the next
capacity decision comes up, that is this ADR being violated by omission —
headroom was decision #1 and it did not get bought.
