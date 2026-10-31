# Minecraft minigames for games-hub (parked, not deployed)

Status: **parked 2026-10-31.** The games-hub stack (Eaglercraft client, EaglerXServer, Paper 1.8.8 on Java 17, scribble.rs) is live and merged (#181, #182, #184, #185). This directory holds the unfinished minigames layer so it can be picked up later. Nothing here is under `apps/`, so ArgoCD does not sync it.

## What was settled

Tested in a throwaway container (`config-drafts/run-test.sh`, run on the backup server, not the laptop):

| Plugin | Version | Result |
|---|---|---|
| WorldEdit | 6.1.9 (dev.bukkit.org file 2597538) | loads |
| DeluxeHub | 3.5.2 (GPL3, archived 2024) | loads on 1.8.8, api-version ignored |
| TNTRun_reloaded | 6.8.9 (GPL3, legacy 1.8-1.12) | loads |
| MobArena | 0.106 `MobArena-1.8.jar` (GPL3) | loads |
| Skywars | 0.5.1 (MIT) | loads, but dropped: needs a map world and GUI setup |
| Multiverse | 4.3.16 | **fails** on 1.8.8 (Phantom NoClassDef) |
| HGJabba | | **fails** (NoClassDefFound `org.bukkit.GameRule`, 1.13+) |
| Spleef_reloaded, Plajer BuildBattle/MurderMystery | | need 1.13+/1.20+; try old releases if wanted |

MobArena and TNTRun phone home for update checks. Jar SHA-256 prefixes are in git history of the scratch notes; re-verify when re-downloading.

## Design

- Single world, no Multiverse. Sky arenas near the origin, built by `RCON_CMDS_STARTUP` (`config-drafts/rcon-startup.txt`).
- Layout: lobby y=229..236 at 0,0; TNTRun x40..60 at y200/192; MobArena arena x-60..-40 y200, lobby z20..30.
- Configs ship as a ConfigMap at `/config`; set `COPY_CONFIG_DEST=/data` or itzg syncs them into `/data/config` instead.
- Console `fill` only works in loaded chunks of the overworld around **world spawn**, and spawn differs per world (a fresh test world failed at the origin). `config-drafts/patch-spawn.py` patches `level.dat` to spawn 0,64,0 (backs up to `level.dat.pre-games` once). Run it from an initContainer using the itzg image (it has python3).
- The console cannot target the End or Nether.

## To resume

1. Add the jars somewhere the pod can reach (no registry; the image build pattern is in `docs/SESSION-HANDOFF.md`).
2. Add an initContainer running `patch-spawn.py`, mount the drafts as a ConfigMap, pass `rcon-startup.txt` as `RCON_CMDS_STARTUP`.
3. Test with `run-test.sh` first, then change `apps/games-hub/minecraft.yaml` (the pod is off by default and sized for 3 players; wake it manually).
