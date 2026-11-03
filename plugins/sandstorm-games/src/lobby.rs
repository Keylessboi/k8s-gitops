//! Lobby: where everyone lands, build protection, and the /games menu.

use crate::util::*;
use pumpkin_plugin_api::{
    Context, Result, Server,
    command::{CommandError, CommandSender, ConsumedArgs},
    commands::CommandHandler,
    common::GameMode,
    events::{
        BlockBreakEvent, BlockPlaceEvent, EventHandler, EventPriority, FoodLevelChangeEvent,
        PlayerJoinEvent, PlayerLeaveEvent,
    },
    permission::{Permission, PermissionDefault},
    scheduler::SchedulerExt,
    text::TextComponent,
    world::BlockPos,
};
use std::sync::atomic::{AtomicBool, Ordering};

pub const PERM: &str = "sandstorm-games:play";
static BUILT: AtomicBool = AtomicBool::new(false);

pub fn init(ctx: &Context) -> Result<()> {
    ctx.register_permission(&Permission {
        node: PERM.into(),
        description: "Use /games, /lobby and the minigames".into(),
        default: PermissionDefault::Allow,
        children: vec![],
    })?;

    ctx.register_event_handler::<PlayerJoinEvent, _>(Join, EventPriority::Normal, true)?;
    ctx.register_event_handler::<PlayerLeaveEvent, _>(Leave, EventPriority::Normal, true)?;
    ctx.register_event_handler::<BlockBreakEvent, _>(NoBreak, EventPriority::High, true)?;
    ctx.register_event_handler::<BlockPlaceEvent, _>(NoPlace, EventPriority::High, true)?;
    ctx.register_event_handler::<FoodLevelChangeEvent, _>(NoHunger, EventPriority::High, true)?;

    let games = pumpkin_plugin_api::command::Command::new(
        &["games".to_string()],
        "Open the games menu",
    )
    .execute(Menu);
    ctx.register_command(games, PERM);
    let lobby = pumpkin_plugin_api::command::Command::new(
        &["lobby".to_string(), "hub".to_string()],
        "Return to the lobby",
    )
    .execute(ToLobby);
    ctx.register_command(lobby, PERM);

    // Build the lobby shortly after start, once the world is up.
    ctx.schedule_delayed_task(100, |server| build(&server));
    ctx.schedule_repeating_task(40, JOIN_PERIOD, |server| flush_joins(&server));
    Ok(())
}

/// The glass lobby: same footprint as the Paper-era one so the muscle memory
/// carries over. Idempotent (sets blocks by name, never relies on old state).
pub fn build(server: &Server) {
    if BUILT.swap(true, Ordering::SeqCst) {
        return;
    }
    let Some(world) = overworld(server) else {
        BUILT.store(false, Ordering::SeqCst);
        return;
    };
    fill(&world, (-11, 229, -11), (11, 236, 11), "minecraft:glass", true);
    fill(&world, (-10, 229, -10), (10, 229, 10), "minecraft:quartz_block", false);
    fill(&world, (-9, 229, 0), (9, 229, 0), "minecraft:sea_lantern", false);
    fill(&world, (0, 229, -9), (0, 229, 9), "minecraft:sea_lantern", false);
    // Lights, so mobs never spawn on the quartz in the dark.
    for (x, z) in [(-8, -8), (8, -8), (-8, 8), (8, 8)] {
        world.set_block_by_name(BlockPos { x, y: 235, z }, "minecraft:sea_lantern", flags());
    }
    pumpkin_plugin_api::logging::log(pumpkin_plugin_api::logging::LogLevel::Info, "sandstorm-games: lobby built");
}

pub fn send_to_lobby(p: &pumpkin_plugin_api::player::Player, server: &Server) {
    if let Some(w) = overworld(server) {
        p.teleport(LOBBY_SPAWN, Some(0.0), Some(0.0), w);
    }
    p.set_gamemode(GameMode::Adventure);
    p.set_health(20.0);
    set_place(key_of(&p.get_id()), Place::Lobby);
}

struct Join;
impl EventHandler<PlayerJoinEvent> for Join {
    fn handle(
        &self,
        server: Server,
        ev: <PlayerJoinEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <PlayerJoinEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        build(&server);
        let eid = ev.player.as_entity().get_id() as i32;
        let k = key_of(&ev.player.get_id());
        with_shared(|s| {
            s.by_entity.insert(eid, k);
            s.place.insert(k, Place::Lobby);
            s.join_queue.push((k, false));
        });
        ev
    }
}

/// Runs every JOIN_PERIOD ticks. A queued player is sent on its second pass,
/// so at least one full period has passed since the join event and the client
/// has confirmed the spawn teleport.
const JOIN_PERIOD: u64 = 10;

fn flush_joins(server: &Server) {
    let ready: Vec<Key> = with_shared(|s| {
        let mut ready = Vec::new();
        s.join_queue.retain_mut(|(k, seen)| {
            if *seen {
                ready.push(*k);
                false
            } else {
                *seen = true;
                true
            }
        });
        ready
    });
    for k in ready {
        if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
            send_to_lobby(&p, server);
            p.send_system_message(text("&6Welcome! &7Type &e/games&7 to pick a game."), false);
        }
    }
}

struct Leave;
impl EventHandler<PlayerLeaveEvent> for Leave {
    fn handle(
        &self,
        _server: Server,
        ev: <PlayerLeaveEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <PlayerLeaveEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        let k = key_of(&ev.player.get_id());
        crate::tntrun::player_left(k);
        crate::arena::forget(k);
        with_shared(|s| {
            s.place.remove(&k);
            s.join_queue.retain(|(q, _)| *q != k);
            s.by_entity.retain(|_, v| *v != k);
        });
        ev
    }
}

fn is_op(p: &pumpkin_plugin_api::player::Player) -> bool {
    use pumpkin_plugin_api::permission::PermissionLevel as L;
    matches!(p.get_permission_level(), L::Three | L::Four)
}

struct NoBreak;
impl EventHandler<BlockBreakEvent> for NoBreak {
    fn handle(
        &self,
        _s: Server,
        mut ev: <BlockBreakEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <BlockBreakEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        if ev.player.as_ref().is_none_or(|p| !is_op(p)) {
            ev.cancelled = true;
        }
        ev
    }
}

struct NoPlace;
impl EventHandler<BlockPlaceEvent> for NoPlace {
    fn handle(
        &self,
        _s: Server,
        mut ev: <BlockPlaceEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <BlockPlaceEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        if !is_op(&ev.player) {
            ev.cancelled = true;
        }
        ev
    }
}

struct NoHunger;
impl EventHandler<FoodLevelChangeEvent> for NoHunger {
    fn handle(
        &self,
        _s: Server,
        mut ev: <FoodLevelChangeEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <FoodLevelChangeEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        ev.cancelled = true;
        ev
    }
}

struct Menu;
impl CommandHandler for Menu {
    fn handle(
        &self,
        sender: CommandSender,
        _server: Server,
        _args: ConsumedArgs,
    ) -> std::result::Result<i32, CommandError> {
        let Some(p) = sender.as_player() else {
            return Ok(0);
        };
        p.send_system_message(text("&6&lGames"), false);
        for (label, cmd, blurb) in [
            ("TNT Run", "/tntrun join", "2-6 players, the floor falls away"),
            ("Mob Arena", "/arena join", "1-6 players, co-op waves"),
        ] {
            let line = text(&format!("&e[{label}] &7{blurb}"))
                .click_run_command(cmd)
                .hover_show_text(text(&format!("&aClick to run {cmd}")));
            p.send_system_message(line, false);
        }
        Ok(1)
    }
}

struct ToLobby;
impl CommandHandler for ToLobby {
    fn handle(
        &self,
        sender: CommandSender,
        server: Server,
        _args: ConsumedArgs,
    ) -> std::result::Result<i32, CommandError> {
        let Some(p) = sender.as_player() else {
            return Ok(0);
        };
        let k = key_of(&p.get_id());
        crate::tntrun::player_left(k);
        crate::arena::forget(k);
        send_to_lobby(&p, &server);
        Ok(1)
    }
}

#[allow(dead_code)]
fn _unused(_: TextComponent) {}
