<!--
For a change that FIXES something, fill in all five headings below and add the
matching entry to docs/doctor-log.md in the same commit. CI checks that the log
grew when a commit says fix().

For anything else - a new app, a docs change, a version bump - delete the whole
block and just say what changed and why.
-->

## Symptom

<!-- What was observed, in the words someone would use to report it. This is
what a future grep of doctor-log.md will match on, so use the real error text:
"connection refused", "404", "CrashLoopBackOff". -->

## Root cause

<!-- The mechanism. Not "the config was wrong" but why the wrong thing produced
this particular symptom. -->

## Fix

<!-- What changed, and why this rather than the other options. -->

## Prevention

<!-- What stops a repeat. Prefer a CHECK over a sentence: this repo has twice
written the correct prevention as prose and then hit the same bug again,
because prose only protects whoever reads it at the right moment. If it can be
expressed in scripts/ci/check-invariants.py, put it there instead. -->

## Confidence

<!-- Pick one. This heading exists because the 2026-08-31 Ghost entry said
"root cause not fully pinned" and everything downstream still treated it as
settled - including a patch built on a diagnosis that turned out to be wrong.

- CONFIRMED  - reproduced the failure and the fix, or verified against live state
- PROBABLE   - consistent with the evidence, not directly reproduced
- PROVISIONAL- plausible, unverified. Say what would confirm or refute it.
-->

## Verification

<!-- The command you ran and its output. "ArgoCD says Synced" is not
verification - it hid three separate failures. Prove the data plane did the
thing: a status code, a row count, a snapshot age. -->
