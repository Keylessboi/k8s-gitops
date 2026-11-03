//! TNT Run: the floor under you disappears; last one standing wins.
//! Two floors of sand-on-TNT in the sky at x 40..60, y 191..200.

use crate::util::*;
use pumpkin_plugin_api::{
    Context, Result, Server,
    command::{Command, CommandError, CommandNode, CommandSender, ConsumedArgs},
    commands::CommandHandler,
    common::GameMode,
    scheduler::SchedulerExt,
    world::{BlockPos, World},
};
use std::sync::Mutex;

// Every arena sits in the chunks around the world spawn (x and z within
// -11..11), the same ones the lobby uses. Blocks placed in chunks nobody has
// loaded vanish without an error, which is how the arenas went missing when
// they were 40-60 blocks out. Stacked by height: this game 161-170, the Mob
// Arena 200-216, the lobby 229-236.
const X0: i32 = -10;
const X1: i32 = 10;
const Z0: i32 = -10;
const Z1: i32 = 10;
const SPAWN: (f64, f64, f64) = (0.5, 172.0, 0.5);
/// (tnt_y, sand_y) of the two floors.
const FLOORS: [(i32, i32); 2] = [(169, 170), (161, 162)];
/// Fall below this and you are out (the lower floor is at 191..192).
const OUT_Y: f64 = 155.0;
const MIN_PLAYERS: usize = 2;
const MAX_PLAYERS: usize = 6;
const COUNTDOWN_TICKS: i32 = 400; // 20 s
/// Ticks between stepping on a block and it vanishing.
const FALL_DELAY: u64 = 8;
const PERIOD: u64 = 2;

#[derive(PartialEq, Eq)]
enum Phase {
    Idle,
    Countdown,
    Running,
}

struct Game {
    phase: Phase,
    queue: Vec<Key>,
    alive: Vec<Key>,
    countdown: i32,
    now: u64,
    /// (block pos of the sand, tick it should vanish)
    doomed: Vec<((i32, i32, i32), u64)>,
}

static GAME: Mutex<Game> = Mutex::new(Game {
    phase: Phase::Idle,
    queue: Vec::new(),
    alive: Vec::new(),
    countdown: 0,
    now: 0,
    doomed: Vec::new(),
});

fn game() -> std::sync::MutexGuard<'static, Game> {
    GAME.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn init(ctx: &Context) -> Result<()> {
    let cmd = Command::new(&["tntrun".to_string()], "TNT Run")
        .then(CommandNode::literal("join").execute(Act::Join))
        .then(CommandNode::literal("leave").execute(Act::Leave));
    ctx.register_command(cmd, crate::lobby::PERM);

    ctx.schedule_delayed_task(160, |server| build(&server));
    ctx.schedule_repeating_task(200, PERIOD, |server| tick(&server));
    Ok(())
}

fn build(server: &Server) {
    let Some(w) = overworld(server) else {
        return;
    };
    load_chunks(&w, X0, Z0, X1, Z1);
    let mut failed = 0;
    for (tnt_y, sand_y) in FLOORS {
        failed += fill(&w, (X0, tnt_y, Z0), (X1, tnt_y, Z1), "minecraft:tnt", false);
        failed += fill(&w, (X0, sand_y, Z0), (X1, sand_y, Z1), "minecraft:sand", false);
    }
    pumpkin_plugin_api::logging::log(
        pumpkin_plugin_api::logging::LogLevel::Info,
        &format!("sandstorm-games: tnt run arena built ({failed} blocks refused)"),
    );
}

enum Act {
    Join,
    Leave,
}

impl CommandHandler for Act {
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
        match self {
            Act::Join => {
                let mut g = game();
                if g.phase == Phase::Running {
                    p.send_system_message(text("&cA round is running. Try again soon."), false);
                } else if g.queue.contains(&k) {
                    p.send_system_message(text("&7You are already queued."), false);
                } else if g.queue.len() >= MAX_PLAYERS {
                    p.send_system_message(text("&cThe lobby is full."), false);
                } else {
                    g.queue.push(k);
                    let n = g.queue.len();
                    drop(g);
                    announce(&server, &format!("&e{} &7joined TNT Run ({n}/{MAX_PLAYERS})", p.get_name()));
                }
            }
            Act::Leave => {
                player_left(k);
                crate::lobby::send_to_lobby(&p, &server);
            }
        }
        Ok(1)
    }
}

fn announce(server: &Server, msg: &str) {
    let g = game();
    let keys: Vec<Key> = g.queue.iter().chain(g.alive.iter()).copied().collect();
    drop(g);
    for k in keys {
        if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
            p.send_system_message(text(msg), false);
        }
    }
}

/// A player disconnected, left, or was sent to the lobby: forget them.
pub fn player_left(k: Key) {
    let mut g = game();
    g.queue.retain(|x| *x != k);
    g.alive.retain(|x| *x != k);
}

fn eliminate(server: &Server, k: Key, why: &str) {
    if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
        p.send_system_message(text(&format!("&c{why}")), false);
        crate::lobby::send_to_lobby(&p, server);
    }
}

/// Is the floor really under the spawn? If not, try one rebuild.
fn arena_ready(server: &Server) -> bool {
    let probe = |w: &World| block_is(w, SPAWN.0 as i32, FLOORS[0].1, SPAWN.2 as i32, "minecraft:sand");
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
        let queued = {
            let mut g = game();
            g.phase = Phase::Idle;
            std::mem::take(&mut g.queue)
        };
        for k in queued {
            if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
                p.send_system_message(text("&cThe TNT Run arena is not ready. Try again in a minute."), false);
                crate::lobby::send_to_lobby(&p, server);
            }
        }
        return;
    }
    let mut g = game();
    g.alive = std::mem::take(&mut g.queue);
    g.phase = Phase::Running;
    g.doomed.clear();
    let players = g.alive.clone();
    drop(g);
    for (i, k) in players.iter().enumerate() {
        if let Some(p) = server.get_player_by_uuid(uuid_of(*k)) {
            // Spread them out a little so nobody starts on the same block.
            let off = (i as f64 - players.len() as f64 / 2.0) * 2.0;
            if let Some(w) = overworld(server) {
                p.teleport((SPAWN.0 + off, SPAWN.1, SPAWN.2), Some(0.0), Some(0.0), w);
            }
            p.set_gamemode(GameMode::Adventure);
            set_place(*k, Place::Tnt);
            p.send_system_message(text("&6&lGO! &7Keep moving."), false);
        }
    }
}

fn tick(server: &Server) {
    // Only ever hold the lock for bookkeeping; host calls happen outside it.
    let phase_now = {
        let mut g = game();
        g.now += PERIOD;
        // Forget anyone who vanished without telling us.
        let online = |k: &Key| server.get_player_by_uuid(uuid_of(*k)).is_some();
        g.queue.retain(online);
        g.alive.retain(online);
        match g.phase {
            Phase::Idle => PhaseNow::Idle,
            Phase::Countdown => PhaseNow::Countdown,
            Phase::Running => PhaseNow::Running,
        }
    };
    match phase_now {
        PhaseNow::Idle => {
            let mut g = game();
            if g.queue.len() >= MIN_PLAYERS {
                g.phase = Phase::Countdown;
                g.countdown = COUNTDOWN_TICKS;
                drop(g);
                announce(server, "&6TNT Run starts in 20 seconds!");
            }
        }
        PhaseNow::Countdown => {
            let mut g = game();
            if g.queue.len() < MIN_PLAYERS {
                g.phase = Phase::Idle;
                drop(g);
                announce(server, "&cNot enough players. Countdown cancelled.");
                return;
            }
            g.countdown -= PERIOD as i32;
            let c = g.countdown;
            drop(g);
            if c <= 0 {
                start(server);
            } else if c % 20 < PERIOD as i32 && [200, 100, 60, 40, 20].contains(&(c - c % 20)) {
                announce(server, &format!("&eStarting in {}...", (c + 19) / 20));
            }
        }
        PhaseNow::Running => run(server),
    }
}

enum PhaseNow {
    Idle,
    Countdown,
    Running,
}

fn run(server: &Server) {
    let Some(w) = overworld(server) else {
        return;
    };
    let alive = game().alive.clone();
    let mut fell = Vec::new();
    let mut newly = Vec::new();
    for k in &alive {
        let Some(p) = server.get_player_by_uuid(uuid_of(*k)) else {
            continue;
        };
        let (x, y, z) = p.get_position();
        if y < OUT_Y {
            fell.push(*k);
            continue;
        }
        // The block(s) under the feet: sample the four corners of the hitbox.
        let by = (y - 0.05).floor() as i32;
        for (dx, dz) in [(-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)] {
            let bx = (x + dx).floor() as i32;
            let bz = (z + dz).floor() as i32;
            if bx < X0 || bx > X1 || bz < Z0 || bz > Z1 {
                continue;
            }
            if w.get_block(BlockPos { x: bx, y: by, z: bz }).name == "minecraft:sand" {
                newly.push((bx, by, bz));
            }
        }
    }
    let (due, over) = {
        let mut g = game();
        let now = g.now;
        for pos in newly {
            if !g.doomed.iter().any(|(p, _)| *p == pos) {
                g.doomed.push((pos, now + FALL_DELAY));
            }
        }
        let (due, keep): (Vec<_>, Vec<_>) = g.doomed.drain(..).partition(|(_, at)| *at <= now);
        g.doomed = keep;
        g.alive.retain(|k| !fell.contains(k));
        (due, g.alive.len() <= 1)
    };
    for ((x, y, z), _) in due {
        vanish(&w, x, y, z);
    }
    for k in fell {
        eliminate(server, k, "You fell!");
    }
    if over {
        finish(server);
    }
}

/// Remove the sand and the TNT under it (it is only there to look the part).
fn vanish(w: &World, x: i32, y: i32, z: i32) {
    w.set_block_by_name(BlockPos { x, y, z }, "minecraft:air", flags());
    w.set_block_by_name(BlockPos { x, y: y - 1, z }, "minecraft:air", flags());
}

fn finish(server: &Server) {
    let winners = std::mem::take(&mut game().alive);
    {
        let mut g = game();
        g.phase = Phase::Idle;
        g.doomed.clear();
    }
    for k in winners {
        if let Some(p) = server.get_player_by_uuid(uuid_of(k)) {
            p.send_system_message(text("&6&lYou won TNT Run!"), false);
            let name = p.get_name();
            crate::lobby::send_to_lobby(&p, server);
            server.broadcast(&format!("§6{name} §ewon TNT Run!"));
        }
    }
    // The arena floor is rebuilt for the next round.
    if let Some(w) = overworld(server) {
        for (tnt_y, sand_y) in FLOORS {
            fill(&w, (X0, tnt_y, Z0), (X1, tnt_y, Z1), "minecraft:tnt", false);
            fill(&w, (X0, sand_y, Z0), (X1, sand_y, Z1), "minecraft:sand", false);
        }
    }
}
