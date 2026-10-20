# ejabberd (XMPP component host for the iMessage bridge)

`apps/ejabberd` runs ejabberd with **no accounts and no client access**. It exists so the
iMessage bridge can appear as `imessage.sandstorm.chat` and federate (S2S) with the owner's
Snikket (`travis@snikket.sandstorm.chat`). JMP is not in the path.

## Shape

| What | Value |
|---|---|
| Component domain (the bridge's JID) | `imessage.sandstorm.chat` |
| Placeholder vhost | `local.invalid`. The component domain must **not** also be a vhost: the XEP-0114 handshake then fails silently (tested on 26.09). |
| S2S | TCP 5269 (STARTTLS required) and 5270 (direct TLS, XEP-0368); TLS 1.2+ with AEAD ciphers only; allowlist = `snikket.sandstorm.chat` only (`acl.federation_peers` in `ejabberd.yml`) |
| Component link | `ejabberd.ejabberd.svc.cluster.local:5347`, ClusterIP only, NetworkPolicy admits namespace `imessage` only |
| Health | 5280, TCP probe only |
| c2s 5222 / registration / admin API | not configured |
| Component secret | Doppler `kubernetes/prd` key `EJABBERD_COMPONENT_SECRET`, synced to Secret `ejabberd/ejabberd-component` (key `secret`). Characters `[A-Za-z0-9_-]` only. |
| Certificate | `Certificate imessage-s2s` -> Secret `ejabberd/imessage-s2s-tls`, Let's Encrypt via `letsencrypt-prod` |
| S2S address | MetalLB `192.168.1.241:5269` (Service `ejabberd-s2s`, `externalTrafficPolicy: Local`) |

The component secret reaches ejabberd as a file: an init container renders it into a
memory-backed volume as an ejabberd `define_macro`. It is never an environment variable.

### Bridge wiring (the `imessage` namespace, not in this app)

The bridge connects with `COMPONENT_HOST=ejabberd.ejabberd.svc.cluster.local`,
`COMPONENT_PORT=5347`, `COMPONENT_JID=imessage.sandstorm.chat`. Because it is another pod,
not a sidecar of ejabberd, it needs:

- the same Doppler key, via a second `DopplerSecret` (managedSecret in `imessage`);
- an egress NetworkPolicy rule to namespace `ejabberd` TCP 5347 (the ingress half is already here);
- the component secret as a mounted file, not an env var (HS-DATA-02), if its client allows.

## One-time steps outside git

1. **Doppler**: add `EJABBERD_COMPONENT_SECRET` to `kubernetes/prd` (e.g. 40 hex chars).
2. **Porkbun DNS** for `sandstorm.chat` (DNS is at Porkbun, not Cloudflare):
   - No A record needed: the `*.sandstorm.chat` wildcard already resolves
     `imessage.sandstorm.chat` to the public IP, which also serves the HTTP-01 challenge.
   - `SRV _xmpps-server._tcp.imessage.sandstorm.chat  0 5 5270 imessage.sandstorm.chat.`
     (advertises direct-TLS S2S; only publish it once 5270 is forwarded, step 3).
   - `SRV _xmpp-server._tcp.imessage.sandstorm.chat  0 5 5269 imessage.sandstorm.chat.`
     (optional, 5269 is the default).
3. **Router**: forward public TCP **5269 -> 192.168.1.241:5269**, and 5270 -> 192.168.1.241:5270
   for direct-TLS S2S (optional; STARTTLS on 5269 works alone). Optionally restrict the
   source to `49.13.15.16` (the Snikket host); the pod's NetworkPolicy cannot know the peer
   set, ejabberd's ACL enforces it at the XMPP layer.
4. **Snikket side**: nothing, S2S is on by default; confirm it can resolve the A record.
5. **DANE** (after the certificate is issued). `sandstorm.chat` is DNSSEC-signed, so peers
   running DANE-aware stacks (Prosody `mod_s2s_auth_dane_in`) can pin the key:

   ```sh
   openssl s_client -starttls xmpp-server -xmpphost imessage.sandstorm.chat \
     -connect imessage.sandstorm.chat:5269 </dev/null 2>/dev/null \
   | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum
   ```

   Publish `TLSA _5269._tcp.imessage.sandstorm.chat  3 1 1 <that hash>`. The Certificate sets
   `rotationPolicy: Never`, so the key (and the record) survives the 60-day renewals. If the
   Secret is ever deleted, regenerate the record. ejabberd itself has **no DANE validation
   code** (checked in 26.09), so this protects peers verifying us, not us verifying them.

## Verify

```sh
# from outside the LAN, once the forward exists
openssl s_client -starttls xmpp-server -xmpphost imessage.sandstorm.chat \
  -connect imessage.sandstorm.chat:5269 </dev/null 2>&1 | grep -E 'subject=|Verify return'
```

Then from `travis@snikket.sandstorm.chat` send a message to `imessage.sandstorm.chat`; the
ejabberd log shows the inbound S2S from `snikket.sandstorm.chat`. Prove the component link
by the bridge's own handshake log, not by "pod Ready".

## Gotchas

- **`drop: ALL` alone breaks the pod** (`erlexec: Error 1 executing beam.smp`): the Erlang VM
  binary has a file capability, so `NET_BIND_SERVICE` must stay in the bounding set. PSA
  `restricted` allows exactly that add.
- Let's Encrypt no longer issues `clientAuth` certificates, so SASL EXTERNAL may not be
  offered. `mod_s2s_dialback` stays enabled as the fallback (confined by the allowlist to
  `snikket.sandstorm.chat`); remove it from `ejabberd.yml` once certificate auth is seen
  working, to make S2S certificate-only. `s2s_use_starttls: required_trusted` is deprecated
  in 26.09 (it also drops dialback), so it is not used.
- The "No certificate found matching local.invalid" start-up warning is expected: the
  placeholder vhost never speaks S2S.
- The Certificate uses HTTP-01 (Porkbun has no built-in cert-manager DNS-01 solver). Moving
  to DNS-01 needs a webhook solver and Porkbun API keys in Doppler.
- Mnesia holds only route bookkeeping (no accounts, no archive); the PVC is `local-path`
  (ADR-0009) and the pod is pinned to its node.

## k3s notes

- k3s's ServiceLB runs next to MetalLB here (`svclb-traefik` exists). `ejabberd-s2s` gets an
  `svclb-ejabberd-s2s` DaemonSet too, like Traefik. Point the router at the MetalLB address
  `192.168.1.241`, which is not used by any other Service.
- The pod lands on `k3s-server`: the `nas` node is tainted `storage` and the pod has no
  toleration. `local-path` is `WaitForFirstConsumer`, so the PVC binds there.
- `externalTrafficPolicy: Local` keeps the peer's real address (visible in the log).
- kube-router enforces the NetworkPolicy; DNS egress goes to CoreDNS in `kube-system`.
- The ConfigMap name carries a content hash, so a config change rolls the pod.

## What from the "everything" checklist applies

This server has no accounts and no client listener, so the client-facing items have nothing
to attach to. They belong on `snikket.sandstorm.chat` (a Snikket already ships most of them).

| Item | Here |
|---|---|
| TLS 1.2+ / AEAD ciphers, s2s and (absent) c2s | Done. 1.3 is negotiated when the peer supports it. 1.3-only is not forced because it would lock out 1.2-only peers. |
| DANE (TLSA + DNSSEC) | Published by hand, step 5. `sandstorm.chat` has a DS record. ejabberd cannot validate DANE itself. |
| Direct TLS (XEP-0368) | Done for S2S on 5270. There are no clients, so no c2s 5223/443. |
| SCRAM-SHA-256/512 | Not applicable: no accounts, `auth_method: internal` with no users. |
| OMEMO (Snikket <-> bridge) | **Not an ejabberd feature.** OMEMO is end-to-end between the two endpoints, here the owner's client and the bridge. The bridge must itself publish a device list and encrypt/decrypt (a component has no PEP of its own). ejabberd only relays the stanzas, protected hop-by-hop by TLS (+DANE). Needs bridge support. |
| OpenPGP, Carbons, HTTP File Upload (+XEP-0454), Jingle, Push (XEP-0357, MAM) | Client/user features; this host serves none. OMEMO between the owner's client and the bridge would end at the bridge anyway, because iMessage is re-encrypted by Apple. |
