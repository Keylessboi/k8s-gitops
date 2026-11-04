//! Lobby: where everyone lands, build protection, and the /games menu.

use crate::util::*;
use pumpkin_plugin_api::{
    Context, Result, Server,
    command::{CommandError, CommandSender, ConsumedArgs},
    commands::CommandHandler,
    common::{GameMode, Hand},
    ItemStackExt,
    events::{
        BlockBreakEvent, BlockPlaceEvent, EventHandler, EventPriority, FoodLevelChangeEvent,
        InventoryClickEvent, PlayerInteractEvent, PlayerJoinEvent, PlayerLeaveEvent, PlayerMoveEvent,
    },
    gui::Gui,
    item_stack::ItemStack,
    screens_wit::Screen,
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
    ctx.register_event_handler::<PlayerInteractEvent, _>(Interact, EventPriority::High, true)?;
    ctx.register_event_handler::<InventoryClickEvent, _>(MenuClick, EventPriority::High, true)?;
    ctx.register_event_handler::<PlayerMoveEvent, _>(Moved, EventPriority::Lowest, false)?;

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
    let smp = pumpkin_plugin_api::command::Command::new(
        &["smp".to_string()],
        "Join the survival server",
    )
    .execute(ToSmp);
    ctx.register_command(smp, PERM);

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

/// Put a player back to a clean slate: full health and food, no effects,
/// not on fire, empty inventory. Called on every entry to the lobby and every
/// game, so nothing (hunger, potions, worn tools) carries over.
pub fn fresh(p: &pumpkin_plugin_api::player::Player) {
    use pumpkin_plugin_api::wit::pumpkin::plugin::status_effect::StatusEffectType as E;
    p.set_health(20.0);
    p.set_food_level(20);
    p.set_saturation(20.0);
    for e in [E::Speed, E::Slowness, E::JumpBoost, E::Regeneration, E::Resistance, E::Strength, E::Poison, E::Weakness] {
        p.remove_effect(e);
    }
    p.as_entity().set_on_fire(false);
    p.get_inventory().clear_all();
}

/// Remove loose items, experience orbs and arrows everywhere. Mob loot
/// ignores the item-drop event, so this sweeps it instead.
pub fn sweep_loot(server: &Server) {
    let Some(w) = overworld(server) else {
        return;
    };
    for e in w.get_entities() {
        if matches!(
            e.get_type(),
            pumpkin_plugin_api::EntityType::Item
                | pumpkin_plugin_api::EntityType::ExperienceOrb
                | pumpkin_plugin_api::EntityType::Arrow
        ) {
            e.remove();
        }
    }
}

pub fn send_to_lobby(p: &pumpkin_plugin_api::player::Player, server: &Server) {
    if let Some(w) = overworld(server) {
        p.teleport(LOBBY_SPAWN, Some(0.0), Some(0.0), w);
    }
    p.set_gamemode(GameMode::Adventure);
    fresh(p);
    give_compass(p);
    set_place(key_of(&p.get_id()), Place::Lobby);
}

/// The one item a lobby player carries: right-click it for the games menu.
fn give_compass(p: &pumpkin_plugin_api::player::Player) {
    let inv = p.get_inventory();
    inv.clear_all();
    let compass = ItemStack::of("minecraft:compass", 1);
    compass.set_custom_name(Some(text("&a&lGames &7(right-click)")));
    compass.set_lore(vec![text("&7Pick a minigame to join")]);
    inv.as_inventory().set_item(4, Some(compass));
    inv.set_selected_slot(4);
}

const SLOT_TNT: i16 = 11;
const SLOT_SMP: i16 = 13;
const SLOT_ARENA: i16 = 15;

/// Where the browser client reconnects after a Transfer packet: the same public
/// address it joined by. The notmc bridge sees the packet leave this server and
/// sends that account's next connection to the SMP (apps/notmc, bridge.mjs).
const PUBLIC_HOST: &str = "notmc.sandstorm.chat";
const PUBLIC_PORT: u16 = 443;

/// Hand the player over to the SMP server.
fn go_smp(p: &pumpkin_plugin_api::player::Player) {
    p.send_system_message(text("&aSending you to the SMP..."), false);
    p.transfer(PUBLIC_HOST, PUBLIC_PORT);
}

fn menu_item(key: &str, name: &str, lore: &[&str]) -> ItemStack {
    let it = ItemStack::of(key, 1);
    it.set_custom_name(Some(text(name)));
    let lines: Vec<TextComponent> = lore.iter().map(|l| text(l)).collect();
    it.set_lore(lines);
    it
}

fn open_menu(p: &pumpkin_plugin_api::player::Player) {
    let gui = Gui::new(Screen::Generic9x3, text("&6Pick a game"));
    gui.set_allow_grab_items(false);
    gui.set_allow_put_items(false);
    gui.set_item(
        SLOT_TNT as u32,
        menu_item(
            "minecraft:tnt",
            "&c&lTNT Run",
            &["&72-6 players", "&7The floor falls away under you.", "&eClick to join"],
        ),
    );
    gui.set_item(
        SLOT_SMP as u32,
        menu_item(
            "minecraft:grass_block",
            "&2&lSurvival (SMP)",
            &["&7A normal survival world.", "&7Build, mine, explore.", "&eClick to join"],
        ),
    );
    gui.set_item(
        SLOT_ARENA as u32,
        menu_item(
            "minecraft:iron_sword",
            "&a&lMob Arena",
            &["&71-6 players, co-op", "&7Survive the waves together.", "&eClick to join"],
        ),
    );
    p.open_gui(gui);
}

struct Interact;
impl EventHandler<PlayerInteractEvent> for Interact {
    fn handle(
        &self,
        _s: Server,
        mut ev: <PlayerInteractEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <PlayerInteractEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        use pumpkin_plugin_api::events_wit::InteractAction as A;
        let right = matches!(ev.action, A::RightClickAir | A::RightClickBlock);
        let holds = ev
            .player
            .get_inventory()
            .get_item_in_hand(Hand::Right)
            .is_some_and(|i| i.matches_item("minecraft:compass"));
        if right && holds && place_of(key_of(&ev.player.get_id())) == Place::Lobby {
            open_menu(&ev.player);
            ev.cancelled = true;
        }
        ev
    }
}

/// Clicks in the games menu join a game. Lobby players cannot move items.
struct MenuClick;
impl EventHandler<InventoryClickEvent> for MenuClick {
    fn handle(
        &self,
        server: Server,
        mut ev: <InventoryClickEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <InventoryClickEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        if place_of(key_of(&ev.player.get_id())) != Place::Lobby || is_op(&ev.player) {
            return ev;
        }
        ev.cancelled = true;
        if ev.raw_slot == SLOT_SMP && ev.window_type == Some(Screen::Generic9x3) {
            go_smp(&ev.player);
            return ev;
        }
        let cmd = match ev.raw_slot {
            SLOT_TNT if ev.window_type == Some(Screen::Generic9x3) => Some("tntrun join"),
            SLOT_ARENA if ev.window_type == Some(Screen::Generic9x3) => Some("arena join"),
            _ => None,
        };
        if let Some(cmd) = cmd {
            // The event keeps its own player handle; the command takes one by value.
            if let Some(p) = server.get_player_by_uuid(ev.player.get_id()) {
                server.execute_command(cmd, pumpkin_plugin_api::server::CommandSender::Player(p));
            }
        }
        ev
    }
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
            s.join_queue.push((k, 0));
        });
        ev
    }
}

/// Runs every JOIN_PERIOD ticks. A queued player is sent once they have moved
/// (so they have confirmed the spawn teleport) and at least one pass has gone,
/// or after JOIN_GIVE_UP passes whatever happens.
const JOIN_PERIOD: u64 = 10;
const JOIN_GIVE_UP: u32 = 20;

struct Moved;
impl EventHandler<PlayerMoveEvent> for Moved {
    fn handle(
        &self,
        _s: Server,
        ev: <PlayerMoveEvent as pumpkin_plugin_api::FromIntoEvent>::Data,
    ) -> <PlayerMoveEvent as pumpkin_plugin_api::FromIntoEvent>::Data {
        let k = key_of(&ev.player.get_id());
        with_shared(|s| {
            if s.join_queue.iter().any(|(q, _)| *q == k) {
                s.moved.insert(k);
            }
        });
        ev
    }
}

fn flush_joins(server: &Server) {
    let ready: Vec<Key> = with_shared(|s| {
        let mut ready = Vec::new();
        let moved = s.moved.clone();
        s.join_queue.retain_mut(|(k, age)| {
            *age += 1;
            if (*age >= 2 && moved.contains(k)) || *age >= JOIN_GIVE_UP {
                ready.push(*k);
                false
            } else {
                true
            }
        });
        for k in &ready {
            s.moved.remove(k);
        }
        ready
    });
    for k in ready {
        if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
            send_to_lobby(&p, server);
            p.send_system_message(
                text("&6Welcome! &7Right-click the &acompass&7 in your hand, or click a game below."),
                false,
            );
            send_menu_lines(&p);
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
            s.moved.remove(&k);
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

fn send_menu_lines(p: &pumpkin_plugin_api::player::Player) {
    p.send_system_message(text("&6&lGames"), false);
    for (label, cmd, blurb) in [
        ("TNT Run", "/tntrun join", "2-6 players, the floor falls away"),
        ("Mob Arena", "/arena join", "1-6 players, co-op waves"),
        ("Survival SMP", "/smp", "a normal survival world"),
    ] {
        let line = text(&format!("&e[{label}] &7{blurb}"))
            .click_run_command(cmd)
            .hover_show_text(text(&format!("&aClick to run {cmd}")));
        p.send_system_message(line, false);
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
        send_menu_lines(&p);
        Ok(1)
    }
}

struct ToSmp;
impl CommandHandler for ToSmp {
    fn handle(
        &self,
        sender: CommandSender,
        _server: Server,
        _args: ConsumedArgs,
    ) -> std::result::Result<i32, CommandError> {
        let Some(p) = sender.as_player() else {
            return Ok(0);
        };
        go_smp(&p);
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
