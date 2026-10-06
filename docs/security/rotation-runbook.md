# Rotating a secret

Rules: `01-policy.md` §12.3. Register: `security/registers/secrets.yaml`.
Never read, print or paste the old or the new value (§6). Check results with
lengths and hashes: `secret-meta <namespace> <name>`.

## 0. Before you start

1. Find the entry in the secrets register. Read its `rotatable` class, its
   `method` and its `consumers`.
2. If the class is **no**, stop. Read the reason in `method`.
3. Rotate one secret at a time. Do not rotate during an incident or a freeze.

## 1. Class *yes*: Doppler only

1. Make a new value in the secrets store (the owner does this in the Doppler
   console or with `doppler secrets set`; use a generated value of 128 bits or
   more).
2. The operator copies it into the Kubernetes Secret within 60 seconds.
3. Each consumer Deployment restarts by itself (`secrets.doppler.com/reload`).
   Each Job uses the new value at its next start.
4. Check: `secret-meta` shows a new hash prefix. The consumer pod is newer
   than the change, and its readiness probe passes. Make one real request
   through the application (HS-AGENT-07).
5. Set `last_rotated` in the register, and merge the change.

## 2. Class *coupled*: two steps

Do the step that the `method` field names first, then the Doppler step. Order
matters: the system that checks the secret must accept the new value before
the consumer sends it.

| Origin | Order |
|---|---|
| database | One Doppler key feeds both secrets. Change it once. The CNPG role updates, then the application reloads. Check with one query from the application. |
| oidc | New client secret in Authentik, then in Doppler, then the consumer reloads. Check with one login. |
| app-generated | New key in the application, then in Doppler. Check with one API call. |
| internal (CrowdSec) | New value in Doppler. Restart the LAPI, then the agents and the bouncer. Check the bouncer list. |
| deploy-key | `scripts/setup-image-updater-key.sh`, then the GitHub deploy key, then Doppler. |

## 3. Class *external*

Make a new credential in the provider's console. Change it in Doppler. Check
with one real use (a test mail, a VPN connect). Revoke the old credential.

## 4. After an exposure

Follow `01-policy.md` §16.5 first. This runbook is step 2 of that procedure.

## 5. If it goes wrong

Put the old value back in Doppler. The operator and the reload annotation
undo the change in the same way. Doppler keeps the history of each key.
