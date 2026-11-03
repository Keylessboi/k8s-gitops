# notmc: browser client for the Pumpkin games server

Status 2026-11-02: designed and partly proven, nothing deployed. Written so any
agent can resume. Owner decisions are marked **(owner)**.

## Goal

Friends play the Pumpkin minigames (`apps/pumpkin-games`) and open-to-LAN
single-player worlds from a browser at `notmc.sandstorm.chat`, from anywhere.
Client: Incari's experimental **Rust** build (Horizon, WebGPU, MC 26.3), served
by us. **(owner)** Hosting the client and its Mojang files from the cluster is
the owner's decision and risk; keep them out of the public git repo (build onto a
PVC).

## What is proven

- Horizon web joins a plain `host:port` by opening `wss://host:port/` and
  sending the raw Minecraft byte stream as binary WebSocket frames. No client
  patch is needed, only a WebSocket-to-TCP bridge.
- A ~20-line Node (`ws`) bridge to Pumpkin answered a real status ping through it
  (`26.3`, protocol 777). Prototype: `/work/wisp/bridge.mjs` on the vmhub VM
  (lease c3bcad13, may be gone); rewrite it properly, do not rely on it.
- Pumpkin 0.2.1+26.3-26.51 runs offline-mode (`online_mode = false`).

## Design

1. **One hostname, Authentik in front.** `notmc.sandstorm.chat` is an
   `IngressRoute`: `Host(...) && Header(Upgrade, websocket)` goes to the bridge,
   everything else to an nginx serving the client. Both use
   `kube-system-authentik-forward-auth`, `crowdsec` and `rate-limit`. One host so
   the login cookie covers the WebSocket handshake. The Authentik application and
   provider live outside git (`ak shell`); the owner runs those commands.
2. **Identity = the OIDC account, like a Mojang account. (owner)** The bridge
   reads the `X-authentik-*` headers Traefik forwards on the upgrade request and
   binds the player: the Login Start name and UUID must be the ones derived from
   that account, otherwise the connection is dropped. Nobody can pretend to be
   someone else, and player data in Pumpkin is keyed by that stable UUID. It
   replaces "pick any name"; skins stay the player's choice.
3. **Pumpkin is not exposed.** ClusterIP only, NetworkPolicy allows ingress from
   the bridge pod alone. The MetalLB LoadBalancer on 25565 goes away.
4. **Bridge hardening:** Origin must be `https://notmc.sandstorm.chat`; per-IP
   connection and bandwidth caps (real IP from Traefik); frame-size cap and idle
   timeouts; validate the handshake (protocol 777) and login before forwarding;
   fixed target `pumpkin` Service only; no ops.
5. **Persistence. (owner)** Players' single-player worlds should persist per
   account (Horizon keeps them in browser storage today): sync them to the
   server keyed by the OIDC subject, restore on any machine. Do after step 1-4
   work; needs its own design (storage API, size limits, who can read what).
6. **Old stack retired.** PR 204 merged 2026-11-03 and the workloads and
   Ingress went with the Application. The `games-hub` Namespace and
   `minecraft-data` PVC remain for the owner to delete.
7. **Authentik app `notmc` exists** (created 2026-11-03 with the owner's
   go-ahead): proxy provider "Notmc (forward-auth)", `forward_single`, external
   host `https://notmc.sandstorm.chat`, application slug `notmc`, bound to
   groups `game-friends` and `authentik Admins`, attached to the embedded
   outpost. No stray `ak-outpost-*` Ingress appeared.

## Not done / open

- The Rust client build (the vmhub VM and its overnight build were lost on
  2026-11-03, the lease vanished despite a renewal; it must be redone):
  `./incari build --only rust --no-sounds`
  (needs clang, rustup, nightly-2026-10-14 + rust-src, wasm-bindgen-cli 0.2.129,
  binaryen). First attempt failed on missing clang. Output is not on the cluster
  yet; the VM cannot reach the LAN, so getting it there needs a plan (build as a
  cluster Job, or an upload path).
- Players need WebGPU (Chrome/Edge; Linux needs flags). The owner said their
  machines may not have it; untested.
- The page must be a secure context (HTTPS) for WebGPU, which Traefik provides.
- Bridge image: build in CI, pin by digest in a second commit.
- Doctor log / registers: add a publication register entry for notmc
  (`status: proposed`, owner signs).
