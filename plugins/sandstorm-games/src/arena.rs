//! Mob Arena: co-op waves of monsters in a stone-brick box at x -61..-39.
//! Pick a class with /arena class <name>, then /arena join. 30 s after the
//! first player joins the round starts. A hit that would kill you sends you
//! back to the lobby instead (no death screen, no dropped items).

use crate::util::*;
use pumpkin_plugin_api::{
    Context, EntityType, ItemStack, ItemStackExt, Result, Server,
    command::{Arg, Command, CommandError, CommandNode, CommandSender, ConsumedArgs, ArgumentType, StringType},
    commands::CommandHandler,
    common::GameMode,
    events::{EntityDamageEvent, EntityDeathEvent, EntityDropItemEvent, EventHandler, EventPriority, FromIntoEvent},
    scheduler::SchedulerExt,
    world::World,
};
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

// In the lobby's chunks on purpose; see the note in tntrun.rs.
const X0: i32 = -11;
const X1: i32 = 11;
const Z0: i32 = -11;
const Z1: i32 = 11;
const FLOOR_Y: i32 = 200;
const TOP_Y: i32 = 216;
const SPAWN: (f64, f64, f64) = (0.5, 201.0, 0.5);
const MAX_PLAYERS: usize = 6;
const START_DELAY: i32 = 600; // 30 s
const NEXT_WAVE_DELAY: i32 = 100; // 5 s
const PERIOD: i32 = 10;
/// If a wave drags on (a mob stuck somewhere), move on after this long.
const WAVE_TIMEOUT: i32 = 20 * 120;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Class {
    Knight,
    Archer,
    Tank,
    Chemist,
    Oddjob,
}

impl Class {
    fn parse(s: &str) -> Option<Class> {
        match s.to_ascii_lowercase().as_str() {
            "knight" => Some(Class::Knight),
            "archer" => Some(Class::Archer),
            "tank" => Some(Class::Tank),
            "chemist" => Some(Class::Chemist),
            "oddjob" => Some(Class::Oddjob),
            _ => None,
        }
    }
}

#[derive(PartialEq, Eq)]
enum Phase {
    Idle,
    Countdown,
    Running,
    Between,
}

struct Game {
    phase: Phase,
    members: Vec<Key>,
    alive: Vec<Key>,
    class: HashMap<Key, Class>,
    wave: u32,
    mobs: HashSet<i32>,
    timer: i32,
    wave_age: i32,
}

static GAME: Mutex<Option<Game>> = Mutex::new(None);

fn with<R>(f: impl FnOnce(&mut Game) -> R) -> R {
    let mut g = GAME.lock().unwrap_or_else(|e| e.into_inner());
    let game = g.get_or_insert_with(|| Game {
        phase: Phase::Idle,
        members: vec![],
        alive: vec![],
        class: HashMap::new(),
        wave: 0,
        mobs: HashSet::new(),
        timer: 0,
        wave_age: 0,
    });
    f(game)
}

pub fn init(ctx: &Context) -> Result<()> {
    let cmd = Command::new(&["arena".to_string(), "ma".to_string()], "Mob Arena")
        .then(CommandNode::literal("join").execute(Act::Join))
        .then(CommandNode::literal("leave").execute(Act::Leave))
        .then(
            CommandNode::literal("class").then(
                CommandNode::argument("name", &ArgumentType::String(StringType::SingleWord))
                    .execute(Act::Class),
            ),
        );
    ctx.register_command(cmd, crate::lobby::PERM);

    ctx.register_event_handler::<EntityDamageEvent, _>(Damage, EventPriority::High, true)?;
    ctx.register_event_handler::<EntityDropItemEvent, _>(NoMobDrops, EventPriority::High, true)?;
    ctx.register_event_handler::<EntityDeathEvent, _>(Death, EventPriority::Monitor_or_normal(), false)?;
    ctx.schedule_delayed_task(220, |server| build(&server));
    ctx.schedule_repeating_task(300, PERIOD as u64, |server| tick(&server));
    Ok(())
}

/// Mobs drop nothing: Mob Arena zombies were dropping music discs, and loose
/// items on the ground cost the client frames. Players are not affected.
struct NoMobDrops;
impl EventHandler<EntityDropItemEvent> for NoMobDrops {
    fn handle(
        &self,
        _s: Server,
        mut ev: <EntityDropItemEvent as FromIntoEvent>::Data,
    ) -> <EntityDropItemEvent as FromIntoEvent>::Data {
        let is_player = with_shared(|s| s.by_entity.contains_key(&ev.entity_id));
        if !is_player {
            ev.cancelled = true;
        }
        ev
    }
}

// `EventPriority` has no Monitor; keep the call site readable.
trait Prio {
    #[allow(non_snake_case)]
    fn Monitor_or_normal() -> pumpkin_plugin_api::events::EventPriority;
}
impl Prio for EventPriority {
    fn Monitor_or_normal() -> EventPriority {
        EventPriority::Lowest
    }
}

fn build(server: &Server) {
    let Some(w) = overworld(server) else {
        return;
    };
    load_chunks(&w, X0, Z0, X1, Z1);
    let mut failed = fill(&w, (X0, FLOOR_Y, Z0), (X1, TOP_Y, Z1), "minecraft:stone_bricks", true);
    for z in [-5, 0, 5] {
        failed += fill(&w, (X0 + 1, TOP_Y - 1, z), (X1 - 1, TOP_Y - 1, z), "minecraft:sea_lantern", false);
    }
    pumpkin_plugin_api::logging::log(
        pumpkin_plugin_api::logging::LogLevel::Info,
        &format!("sandstorm-games: mob arena built ({failed} blocks refused)"),
    );
}

enum Act {
    Join,
    Leave,
    Class,
}

impl CommandHandler for Act {
    fn handle(
        &self,
        sender: CommandSender,
        server: Server,
        args: ConsumedArgs,
    ) -> std::result::Result<i32, CommandError> {
        let Some(p) = sender.as_player() else {
            return Ok(0);
        };
        let k = key_of(&p.get_id());
        match self {
            Act::Class => {
                let Arg::Simple(name) = args.get_value("name") else {
                    return Ok(0);
                };
                match Class::parse(&name) {
                    Some(c) => {
                        with(|g| g.class.insert(k, c));
                        p.send_system_message(text(&format!("&7Class set to &e{name}&7.")), false);
                    }
                    None => p.send_system_message(
                        text("&cClasses: Knight, Archer, Tank, Chemist, Oddjob"),
                        false,
                    ),
                }
            }
            Act::Join => {
                let msg = with(|g| {
                    if g.phase == Phase::Running || g.phase == Phase::Between {
                        Some("&cA round is running. Try again soon.")
                    } else if g.members.contains(&k) {
                        Some("&7You are already in.")
                    } else if g.members.len() >= MAX_PLAYERS {
                        Some("&cThe arena is full.")
                    } else {
                        g.members.push(k);
                        if g.phase == Phase::Idle {
                            g.phase = Phase::Countdown;
                            g.timer = START_DELAY;
                        }
                        None
                    }
                });
                match msg {
                    Some(m) => p.send_system_message(text(m), false),
                    None => say(&server, &format!("&e{} &7joined Mob Arena. Starts in 30s (/arena class <name>).", p.get_name())),
                }
            }
            Act::Leave => {
                forget(k);
                crate::lobby::send_to_lobby(&p, &server);
            }
        }
        Ok(1)
    }
}

fn say(server: &Server, msg: &str) {
    let keys = with(|g| g.members.clone());
    for k in keys {
        if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
            p.send_system_message(text(msg), false);
        }
    }
}

/// Drop a player from the round (left, disconnected, or sent back).
pub fn forget(k: Key) {
    with(|g| {
        g.members.retain(|x| *x != k);
        g.alive.retain(|x| *x != k);
    });
}

fn kit(p: &pumpkin_plugin_api::player::Player, class: Class) {
    let inv = p.get_inventory();
    inv.clear_all();
    let main = inv.as_inventory();
    let give = |slot: u32, id: &str, n: u8| main.set_item(slot, Some(ItemStack::of(id, n)));
    give(8, "minecraft:cooked_beef", 24);
    match class {
        Class::Knight => {
            give(0, "minecraft:iron_sword", 1);
            inv.set_helmet(Some(ItemStack::of("minecraft:iron_helmet", 1)));
            inv.set_chestplate(Some(ItemStack::of("minecraft:iron_chestplate", 1)));
            inv.set_boots(Some(ItemStack::of("minecraft:iron_boots", 1)));
        }
        Class::Archer => {
            give(0, "minecraft:stone_sword", 1);
            give(1, "minecraft:bow", 1);
            give(2, "minecraft:arrow", 64);
            give(3, "minecraft:arrow", 64);
            inv.set_helmet(Some(ItemStack::of("minecraft:leather_helmet", 1)));
            inv.set_chestplate(Some(ItemStack::of("minecraft:leather_chestplate", 1)));
        }
        Class::Tank => {
            give(0, "minecraft:stone_sword", 1);
            inv.set_helmet(Some(ItemStack::of("minecraft:iron_helmet", 1)));
            inv.set_chestplate(Some(ItemStack::of("minecraft:iron_chestplate", 1)));
            inv.set_leggings(Some(ItemStack::of("minecraft:iron_leggings", 1)));
            inv.set_boots(Some(ItemStack::of("minecraft:iron_boots", 1)));
        }
        Class::Chemist => {
            give(0, "minecraft:stone_sword", 1);
            give(1, "minecraft:golden_apple", 6);
            inv.set_chestplate(Some(ItemStack::of("minecraft:leather_chestplate", 1)));
        }
        Class::Oddjob => {
            give(0, "minecraft:iron_axe", 1);
            give(1, "minecraft:golden_apple", 2);
            inv.set_helmet(Some(ItemStack::of("minecraft:chainmail_helmet", 1)));
            inv.set_boots(Some(ItemStack::of("minecraft:chainmail_boots", 1)));
        }
    }
}

/// Is the floor really under the spawn? If not, try one rebuild.
fn arena_ready(server: &Server) -> bool {
    let probe = |w: &World| block_is(w, SPAWN.0 as i32, FLOOR_Y, SPAWN.2 as i32, "minecraft:stone_bricks");
    let Some(w) = overworld(server) else {
        return false;
    };
    if probe(&w) {
        return true;
    }
    build(server);
    probe(&w)
}

fn start(server: &Server) {
    if !arena_ready(server) {
        let members = with(|g| {
            g.phase = Phase::Idle;
            g.alive.clear();
            std::mem::take(&mut g.members)
        });
        for k in members {
            if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
                p.send_system_message(text("&cThe Mob Arena is not ready. Try again in a minute."), false);
                crate::lobby::send_to_lobby(&p, server);
            }
        }
        return;
    }
    let members = with(|g| {
        g.members.retain(|k| server.get_player_by_uuid(uuid_of(*k)).is_some());
        g.alive = g.members.clone();
        g.wave = 0;
        g.mobs.clear();
        g.phase = Phase::Between;
        g.timer = 0;
        g.members.clone()
    });
    if members.is_empty() {
        with(|g| g.phase = Phase::Idle);
        return;
    }
    for k in &members {
        let Some(p) = server.get_player_by_uuid(uuid_of(*k)) else {
            continue;
        };
        let class = with(|g| g.class.get(k).copied().unwrap_or(Class::Knight));
        if let Some(w) = overworld(server) {
            p.teleport(SPAWN, Some(0.0), Some(0.0), w);
        }
        p.set_gamemode(GameMode::Survival);
        p.set_health(20.0);
        set_place(*k, Place::Arena);
        kit(&p, class);
        p.send_system_message(text("&6&lMob Arena! &7Survive the waves."), false);
    }
}

fn pick(wave: u32, i: u32) -> EntityType {
    match (wave, i % 4) {
        (1..=2, _) => EntityType::Zombie,
        (3..=4, 0) => EntityType::Skeleton,
        (3..=4, _) => EntityType::Zombie,
        (5..=6, 0) => EntityType::Spider,
        (5..=6, 1) => EntityType::Skeleton,
        (5..=6, _) => EntityType::Zombie,
        (_, 0) => EntityType::Creeper,
        (_, 1) => EntityType::Skeleton,
        (_, 2) => EntityType::Spider,
        _ => EntityType::Zombie,
    }
}

fn spawn_wave(server: &Server) {
    let Some(w) = overworld(server) else {
        return;
    };
    let (wave, players) = with(|g| {
        g.wave += 1;
        g.wave_age = 0;
        g.phase = Phase::Running;
        (g.wave, g.alive.len().max(1) as u32)
    });
    let count = 3 + wave * 2 + players * 2;
    let mut ids = Vec::new();
    for i in 0..count {
        // Ring of spawn points, kept clear of the walls.
        let ang = (i as f64 / count as f64) * std::f64::consts::TAU;
        let (x, z) = (SPAWN.0 + 8.0 * ang.cos(), SPAWN.2 + 8.0 * ang.sin());
        let e = w.spawn_entity(pick(wave, i), (x, SPAWN.1, z));
        ids.push(e.get_id() as i32);
    }
    with(|g| g.mobs.extend(ids));
    say(server, &format!("&c&lWave {wave}! &7{count} monsters."));
}

fn tick(server: &Server) {
    enum Next {
        Nothing,
        Start,
        Spawn,
        Reset,
    }
    let next = with(|g| {
        // Forget anyone who vanished.
        let online = |k: &Key| server.get_player_by_uuid(uuid_of(*k)).is_some();
        g.members.retain(online);
        g.alive.retain(online);
        match g.phase {
            Phase::Idle => Next::Nothing,
            Phase::Countdown => {
                if g.members.is_empty() {
                    g.phase = Phase::Idle;
                    return Next::Nothing;
                }
                g.timer -= PERIOD;
                if g.timer <= 0 { Next::Start } else { Next::Nothing }
            }
            Phase::Between => {
                if g.alive.is_empty() && g.wave > 0 {
                    return Next::Reset;
                }
                g.timer -= PERIOD;
                if g.timer <= 0 { Next::Spawn } else { Next::Nothing }
            }
            Phase::Running => {
                g.wave_age += PERIOD;
                if g.alive.is_empty() {
                    Next::Reset
                } else if g.mobs.is_empty() || g.wave_age > WAVE_TIMEOUT {
                    g.phase = Phase::Between;
                    g.timer = NEXT_WAVE_DELAY;
                    Next::Nothing
                } else {
                    Next::Nothing
                }
            }
        }
    });
    match next {
        Next::Nothing => {}
        Next::Start => start(server),
        Next::Spawn => spawn_wave(server),
        Next::Reset => reset(server),
    }
}

/// Round over: report, clear the arena, send everyone home.
fn reset(server: &Server) {
    let (wave, members) = with(|g| {
        let r = (g.wave, g.members.clone());
        g.phase = Phase::Idle;
        g.members.clear();
        g.alive.clear();
        g.mobs.clear();
        g.wave = 0;
        r
    });
    for k in members {
        if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
            p.get_inventory().clear_all();
            p.send_system_message(text(&format!("&6Mob Arena over. You reached &e&lwave {wave}&6.")), false);
            crate::lobby::send_to_lobby(&p, server);
        }
    }
    if let Some(w) = overworld(server) {
        for e in w.get_entities() {
            let (x, y, z) = e.get_position();
            let inside = x >= X0 as f64
                && x <= X1 as f64
                && z >= Z0 as f64
                && z <= Z1 as f64
                && y >= FLOOR_Y as f64
                && y <= TOP_Y as f64;
            if inside
                && matches!(
                e.get_type(),
                EntityType::Zombie | EntityType::Skeleton | EntityType::Spider | EntityType::Creeper
                )
            {
                e.remove();
            }
        }
    }
}

struct Damage;
impl EventHandler<EntityDamageEvent> for Damage {
    fn handle(
        &self,
        server: Server,
        mut ev: <EntityDamageEvent as FromIntoEvent>::Data,
    ) -> <EntityDamageEvent as FromIntoEvent>::Data {
        let Some(k) = with_shared(|s| s.by_entity.get(&ev.entity_id).copied()) else {
            return ev; // a mob: let it take damage
        };
        match place_of(k) {
            Place::Lobby | Place::Tnt => ev.cancelled = true,
            Place::Arena => {
                if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
                    if p.get_health() - ev.damage <= 0.0 {
                        ev.cancelled = true;
                        forget(k);
                        p.get_inventory().clear_all();
                        p.send_system_message(text("&cYou fell in the arena."), false);
                        crate::lobby::send_to_lobby(&p, &server);
                    }
                }
            }
        }
        ev
    }
}

struct Death;
impl EventHandler<EntityDeathEvent> for Death {
    fn handle(
        &self,
        _server: Server,
        ev: <EntityDeathEvent as FromIntoEvent>::Data,
    ) -> <EntityDeathEvent as FromIntoEvent>::Data {
        with(|g| g.mobs.remove(&ev.entity_id));
        ev
    }
}
