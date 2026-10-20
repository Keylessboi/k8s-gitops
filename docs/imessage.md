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
| Registration state | PVC `imessage-data` (1 Gi, `nfs-csi`) |
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
`apps/imessage/deployment.yaml` on every build.

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
