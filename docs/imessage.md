# iMessage relay (imessage-xmpp-relay) on the cluster

Project: <https://github.com/Keylessboi/imessage-xmpp-relay> (checkout: `~/Projects/openbubbles-relay`).
It gives the owner's phone number an Apple IDS identity from a server, so iMessages reach XMPP
without an iPhone online.

```
 Snikket (travis@snikket.sandstorm.chat)
        │  S2S (TLS, DANE)
        ▼
 ejabberd  (apps/ejabberd)  — component host imessage.sandstorm.chat, no accounts
        │  XEP-0114, ClusterIP :5347, secret from Doppler
        ▼
 ┌─ pod imessage (apps/imessage, node nas) ───────────────────────────┐
 │ bridge ──HTTP/SSE localhost:8790──► server (imessage-server-rustpush)│── APNs/IDS ──► Apple
 └──────────────────────────────────────────────────────────────────────┘
        PVC imessage-data (nfs-csi, encrypted NAS pool): the IDS registration
```

## What is deployed

| Piece | Where |
|---|---|
| Namespace, default-deny NetworkPolicy, Apple-only egress | `apps/imessage` |
| Server + bridge (one pod, `replicas: 0` until the cutover) | `apps/imessage/deployment.yaml` |
| Registration state | PVC `imessage-data` (1 Gi, `nfs-csi`); attachments share it under subPath `attachments` |
| Attachment downloads | Service `imessage-files` (:80 -> :8791), Ingress `imessage-files.sandstorm.chat` (`/dl/` only) |
| Download-link key | Doppler `IMESSAGE_FILE_HMAC_KEY` -> Secret `imessage/imessage-files-hmac` (key `files-hmac-key`), mounted as a file (`IMESSAGE_FILE_HMAC_KEY_FILE`) |
| Component secret | Doppler `EJABBERD_COMPONENT_SECRET` -> Secret `imessage/ejabberd-component`, mounted as a file (`COMPONENT_SECRET_FILE`) |
| Images | `localhost/imessage-server:<tag>`, `localhost/imessage-bridge:<tag>`, built on the NAS and imported into its containerd (no registry); pod pinned to `nas`, `imagePullPolicy: Never` |

The registration-relay and the iPhone X are **not** deployed. They are needed only to
(re-)register the number.

## Building the images (on the NAS, never the laptop)

From a checkout of the relay repo (it stages the two source trees the server crate needs and
refuses to continue if a secret-shaped file is present):

```sh
scripts/stage-build-context.sh /tmp/ctx ~/Projects/imessage-lab/rustpush
rsync -a --delete /tmp/ctx/ nas:build/imessage/ctx/
ssh nas '~/build/imessage/nas-build.sh <tag>'     # podman build x2, import into k3s containerd
```

`nas-build.sh` builds `ctx/openbubbles-relay/bridge` and `ctx/openbubbles-relay/deploy/docker/server.Dockerfile`,
then `podman save | k3s ctr images import` and leaves the tarballs in
`/var/lib/rancher/k3s/agent/images/` so k3s re-imports them after a restart. Bump the tag in
`apps/imessage/deployment.yaml` on every build (currently 0.2.0 for both).

## Rules specific to this app

- **One live copy only.** The registration is one push identity. Never run the laptop services
  (`imessage-relay.service`, `imessage-bridge.service`) and this pod at the same time.
- **`/data` is the phone number.** It holds `state.plist`, `hwconfig.plist`, `keystore.plist`
  and the anisette state. Class C4: never read, print or commit it, never `kubectl cp` it into
  a transcript. Deleting the PVC means re-registering with the iPhone and the SIM handset.
- The server API on :8790 has **no authentication**. The NetworkPolicy (intra-namespace only)
  is its only protection; do not add a Service or Ingress for it.
- **OMEMO is off.** The bridge refuses OMEMO in component mode (a component has no device
  identity), so traffic is plaintext inside the S2S TLS hop. OMEMO needs the bridge in client
  mode with a real account, which is a different ejabberd design (see `docs/ejabberd.md`).

## Attachments (server/bridge 0.2.0)

The server downloads inbound iMessage attachments to `/data/attachments` and mints signed,
short-lived links (`https://imessage-files.sandstorm.chat/dl/<id>?exp=..&sig=..`) that the
bridge sends over XMPP. Design and threat notes: `docs/k8s-attachments.md` in the relay repo.

- **Hostname:** `imessage-files.sandstorm.chat`, Ingress `imessage-files`, routes `/dl/` only,
  crowdsec + rate-limit, **no forward-auth** (the HMAC signature is the gate; chat clients
  must be able to fetch it). Publication register entry `P-20` is `proposed` and needs the
  owner's signature (HS-NET-06); CI's publish check fails until then.
- **DNS:** nothing to add. The `*.sandstorm.chat` wildcard at Porkbun already resolves every
  subdomain to the public IP (as for `imessage.sandstorm.chat`, `docs/ejabberd.md`), and the
  same IP serves the cert-manager HTTP-01 challenge for `imessage-files-tls`.
- **Key:** Doppler `kubernetes/prd` `IMESSAGE_FILE_HMAC_KEY` (C4: with it anyone can mint
  links for files on the PVC). Never read it. Register entry `S-50`.
- **Rotation:** change the value in Doppler, then restart the pod (the key is read at start;
  the Secret resyncs in 5 minutes). Effect: every outstanding download link stops working;
  files and registration are untouched. Without the key the feature is off (no downloads,
  nothing listens on 8791).
- **Network:** the NetworkPolicy admits `kube-system` (Traefik) to TCP 8791 only (plus 8089
  for the ACME solver pod). :8790 stays intra-namespace; there is still no Service for it.
- **Storage:** the server quota is 2 GiB (`IMESSAGE_ATTACH_QUOTA_BYTES`, default) and the PVC
  request is 1 Gi. NFS does not enforce the request, and eviction is oldest-first on the
  server's own accounting, but the number is nominal; raise `pvc.yaml` (and check the
  `nfs-csi` class allows expansion) if you want the claim to match. The `data-perms` init
  container creates `attachments/` so it is owned by uid 10001.
- **Bridge:** `PUBLIC_FILE_BASE_URL=https://imessage-files.sandstorm.chat`. `LOG_LEVEL` is
  `DEBUG` for now to capture client call stanzas; set it back to `INFO` afterwards. OMEMO
  stays off.
- **Rollback:** revert the PR. The 0.1.1 server and 0.1.0 bridge images stay imported in the
  NAS's containerd, so the old pod starts without a rebuild. Files already under
  `/data/attachments` are harmless and can be left or deleted by the owner.

## Cutover (done 2026-10-20) and how to repeat it

The laptop ran `imessage-relay.service` (the server) and `imessage-bridge.service` as systemd
user units, with the state in `~/Projects/openbubbles-relay/data`. They were stopped and the
bridge unit disabled, then the state was moved:

1. `systemctl --user stop imessage-bridge imessage-relay` (one live copy only).
2. Apply a throwaway pod that mounts `imessage-data` (busybox, pinned digest, deleted after).
3. Stream the data without printing it:
   `tar -C <data dir> --exclude=relay-secret -cf - . | ssh pve 'pct exec 200 -- kubectl -n imessage exec -i imessage-seed -- tar -xf - -C /data'`
   (`relay-secret` is the registration-relay's own secret and is not needed here).
4. Compare sha256 of each file on both sides (print only match/mismatch).
5. `chown -R 10001:10001 /data` in the seed pod (the files arrive owned by the laptop uid; the
   server runs as 10001 and the files are mode 0600), delete the seed pod.
6. Scale `apps/imessage` to `replicas: 1` by commit.

To roll back: scale to 0 by commit, copy `/data` back, `systemctl --user enable --now` the two
units. The laptop `data/` directory was left untouched.

## Device identity at boot

With `REGISTRATION_RELAY_URL` unset the server falls back to the Mac identity from
`hwconfig.plist`; that is what the laptop was already running on (the relay is only reachable
when the iPhone is online) and it stayed registered and received messages. A server build that
caches the relay's iPhone identity on first contact (`relay-identity.json`) is in the relay
repo; build it and bump the tag to use it.
