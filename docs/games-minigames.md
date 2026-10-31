# Games hub: lobby and minigames

The Eaglercraft server (Paper 1.8.8, `apps/games-hub/minecraft.yaml`) has a lobby and two
minigames, all from existing open-source plugins with no custom code. Everything runs in
the one overworld: the lobby and both arenas are built high in the sky (y 191 to 236)
around the world spawn, so the terrain below is untouched.

## How a friend plays

1. Join `https://mc.sandstorm.chat` as usual. You land in a small glass lobby.
2. Right-click the Nether Star in the hotbar (or type `/games`) and click a game.
   - **TNT Run**: needs 2 to 6 players, 20 s countdown; the floor under you disappears, last one standing wins.
   - **Mob Arena**: 1 to 6 players, co-op against monster waves; pick a class with `/ma class Archer|Knight|Tank|Chemist|Oddjob`
     (default Knight), game starts 30 s after joining, `/ma leave` to quit.
3. When a game ends (or you die or leave) you are returned to the lobby.

## Plugins

| Plugin | Version | Licence | Released | 1.8.8 | sha256 |
|---|---|---|---|---|---|
| DeluxeHub (lobby, menu) | 3.5.2 | GPL-3.0 | 2022-06-24 (repo archived 2024-08) | loads and works, tested | `db7d125b...dcaa` |
| TNTRun_reloaded | 6.8.9 (legacy 1.8 to 1.12.2 line) | GPL-3.0 | 2024-06-10 | yes | `b854e9c6...0654` |
| WorldEdit (TNTRun dependency) | 6.1.9 | GPL-3.0 | 6.1.x line, 2017-2018 (not re-verified) | yes | `5a7b88f6...6186` |
| MobArena (`MobArena-1.8.jar`) | 0.106 | GPL-3.0 | 2021-05-10 | yes | `ed2788f4...e486a` |

Full hashes and URLs are in the `fetch-plugin` init container.

## How it is wired

- `games-config` ConfigMap (from `apps/games-hub/games-config/`) holds the DeluxeHub config,
  menu and `/games` command, the MobArena config (arena `default`) and the TNT Run arena
  `Arena1`. It is copied over `/data/plugins` on every start by the `copy-plugin-configs` init container
  (`cp -rL`, overwrite), so git is the source of truth for those files.
- The lobby and arenas are physical blocks built by `RCON_CMDS_STARTUP` /
  `RCON_CMDS_FIRST_CONNECT` (`/fill`, idempotent). The console can only fill loaded chunks,
  which are the ones around the world spawn, hence the `pin-world-spawn` init container that
  sets the spawn to 0,64,0 (backup: `world/level.dat.pre-games`).
- DeluxeHub protects the whole overworld (no building or breaking, no hunger, no fall damage).
  `disable_player_pvp` is off because DeluxeHub cancels every entity-to-player hit with it on,
  mobs included, which would make Mob Arena unloseable. Players can therefore hit each other
  in the lobby. DeluxeHub's join/leave messages are off on purpose: the itzg first-connect hook
  triggers on the vanilla "joined the game" log line.

## Checks after the first start

```
kubectl -n games-hub exec deploy/minecraft -- rcon-cli "testforblock 50 200 0 sand"
kubectl -n games-hub exec deploy/minecraft -- rcon-cli "ma checkdata default"
```
The first should say it found the block (otherwise the build commands lost a race: join once and
it will be rebuilt, or run the `fill` lines from the manifest). The second should say the arena is ready.

## Known limits and what was left out

- The old survival overworld is still on the PVC but is no longer playable: the lobby is walled in
  and the protections apply to it. Multiverse (needed to teleport between worlds) does not run on 1.8.8.
- Arenas depend on the spawn pin. If the world is ever recreated, the first start builds nothing until
  a second start (the spawn is then pinned and the chunks are loaded).
- Dropped: SkyWars (needs a map world and in-game GUI setup, no free map vetted), HGJabba Hunger Games
  (crashes on 1.8.8: `org.bukkit.GameRule`), Spleef_reloaded and TNTRun_reloaded 9.x (1.20/1.13+ only),
  BuildBattle and MurderMystery 2.x/5.x (api-version 1.13+), Multiverse-Core 4.3.x (1.13+ only).
- Xbox-360-style worlds: no maps were added (nothing freely redistributable was vetted). Glide needs
  elytra (1.9+) and is not possible on 1.8.8. Battle and Tumble would need a PvP arena plugin and a map.
