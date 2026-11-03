# Pumpkin games server

A Rust Minecraft server ([Pumpkin](https://github.com/Pumpkin-MC/Pumpkin)) with
our own plugin, `plugins/sandstorm-games`, giving a lobby and two minigames.
It replaced the Paper + Eaglercraft server (`apps/games-hub`), retired from git
on 2026-11-02. That namespace's volume and Namespace are still on the cluster
until the owner deletes them (see "Retiring games-hub" below).

## What it is, and is not

- Java Edition **26.3** clients. Players come in through the browser client at
  `notmc.sandstorm.chat` (apps/notmc), which speaks 26.3 over a WebSocket bridge.
  A desktop Java client can no longer connect directly: the server has no
  LoadBalancer any more (see "Offline mode").
- Idle cost is about 60 MiB (measured with all three arenas built), against
  1.3-2.3 GiB for the Paper pod. The image is about 120 MB, nearly all of it the
  server binary. It is always on; there is no wake/stop dance.
- The server needs **no Mojang files**: it ships its own data. Clients download
  their game from Mojang as usual.

## Playing

Open `https://notmc.sandstorm.chat`, sign in with Authentik, and add the server
`notmc.sandstorm.chat:443` (Multiplayer). You land in the glass lobby. `/games` lists the games with
click-to-run buttons; `/lobby` brings you home.

| Game | Commands | Rules |
|---|---|---|
| TNT Run | `/tntrun join`, `/tntrun leave` | 2-6 players, 20 s countdown. Two floors of sand on TNT in the sky; a block you stand on vanishes after 8 ticks. Last one standing wins. |
| Mob Arena | `/arena join`, `/arena leave`, `/arena class <Knight\|Archer\|Tank\|Chemist\|Oddjob>` | 1-6 players, starts 30 s after the first join. Co-op waves; a hit that would kill you sends you back to the lobby. |

Everything is built high in the sky (lobby y 229-236, TNT Run x 40..60, Mob
Arena x -61..-39), as the Paper version did. The plugin builds it on start.

## Offline mode (owner's decision) and the join gate

`online_mode = false` in `apps/pumpkin-games/pumpkin.toml`, because friends play
from machines that are reset and cannot sign in to Microsoft each time. The
consequence for any offline-mode server is that whoever can open the port can
join under any name, including an operator's. So the port has no public path:

- The Service is **ClusterIP**, and the NetworkPolicy admits only the
  `notmc-bridge` pod (`apps/notmc`). There is no LoadBalancer.
- The bridge is reachable only through nginx behind Authentik forward-auth, and
  it rewrites each player's Login Start so their in-game name and offline UUID
  are the ones derived from their Authentik account. Nobody can play as someone
  else, and the server's per-player data is keyed by that stable UUID.
- Keep the `ops` list empty. A name is bound to an account, but an operator
  name would still be a fixed target if its account were ever compromised.

To debug from a desktop client, port-forward over Tailscale
(`kubectl -n pumpkin-games port-forward svc/pumpkin 25565`); the NetworkPolicy
still blocks that path only for other pods, not for the API server's forward.

## Known gaps

- Built and loaded against the real 0.2.1 server binary, but **not yet played**:
  no Minecraft client for protocol 777 was available where it was written.
  First session: join, `/games`, run both games with two players, report what
  misbehaves. Likely spots: block-under-feet detection in TNT Run, kit slots in
  Mob Arena, entity-id mapping in the damage handler.
- No DeluxeHub-style nether-star menu item yet (`/games` is the menu).
- No PvP rules in the lobby: it is protected by cancelling all damage.
- Pumpkin is pre-1.0 and plugin support is young. Expect rough edges.

## Updating

The plugin ABI follows the server release, so both move together: bump
`PUMPKIN_TAG`/`PUMPKIN_SHA256` in `images/sandstorm-pumpkin/Dockerfile` and
the `tag =` of `pumpkin-plugin-api` in `plugins/sandstorm-games/Cargo.toml`,
let `.github/workflows/sandstorm-pumpkin.yaml` build, then change the digest in
`apps/pumpkin-games/deployment.yaml` (both containers) in a deliberate commit.

## Retiring games-hub

`apps/games-hub` was removed from git (PR 204, 2026-11-03). Removing the app
deleted the Application and, with it, the Deployments, Services, Ingress
(`mc.` and `games.sandstorm.chat`) and the idle-stop CronJob. The protect-state
objects stayed: the `games-hub` Namespace and the `minecraft-data` PVC (5Gi,
local-path, Paper world data). The owner deletes those last, after taking
whatever they want from the world. The Authentik applications "Games hub",
"Minecraft minigames" and "Party games" still exist and point at hostnames
that no longer serve anything.
