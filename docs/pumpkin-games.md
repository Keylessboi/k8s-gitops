# Pumpkin games server

A Rust Minecraft server ([Pumpkin](https://github.com/Pumpkin-MC/Pumpkin)) with
our own plugin, `plugins/sandstorm-games`, giving a lobby and two minigames.
It replaced the Paper + Eaglercraft server (`apps/games-hub`), retired from git
on 2026-11-02. That namespace's volume and Namespace are still on the cluster
until the owner deletes them (see "Retiring games-hub" below).

## What it is, and is not

- Java Edition **26.3** clients (vanilla launcher, or Horizon). Not a browser
  game: Eaglercraft speaks 1.8.8, this server speaks 26.3.
- Idle cost is about 60 MiB (measured with all three arenas built), against
  1.3-2.3 GiB for the Paper pod. The image is about 120 MB, nearly all of it the
  server binary. It is always on; there is no wake/stop dance.
- The server needs **no Mojang files**: it ships its own data. Clients download
  their game from Mojang as usual.

## Playing

Join `<address>:25565` (the MetalLB address from `kubectl -n pumpkin-games get
svc pumpkin`). You land in the glass lobby. `/games` lists the games with
click-to-run buttons; `/lobby` brings you home.

| Game | Commands | Rules |
|---|---|---|
| TNT Run | `/tntrun join`, `/tntrun leave` | 2-6 players, 20 s countdown. Two floors of sand on TNT in the sky; a block you stand on vanishes after 8 ticks. Last one standing wins. |
| Mob Arena | `/arena join`, `/arena leave`, `/arena class <Knight\|Archer\|Tank\|Chemist\|Oddjob>` | 1-6 players, starts 30 s after the first join. Co-op waves; a hit that would kill you sends you back to the lobby. |

Everything is built high in the sky (lobby y 229-236, TNT Run x 40..60, Mob
Arena x -61..-39), as the Paper version did. The plugin builds it on start.

## Offline mode (owner's decision)

`online_mode = false` in `apps/pumpkin-games/pumpkin.toml`, because friends play
from machines that are reset and cannot sign in each time. The consequence:
**anyone who can reach port 25565 can join under any name, including an
operator's.** Keep it on the LAN or Tailscale; do not forward the port from the
internet. If it must be public, add a join gate first.

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
