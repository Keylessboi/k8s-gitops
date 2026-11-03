//! Shared state and small helpers for the lobby and both games.

use pumpkin_plugin_api::{
    Server,
    text::TextComponent,
    uuid::Uuid,
    world::{BlockFlags, World},
};
use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, MutexGuard};

/// Where the lobby glass box sits: high above the terrain, so the terrain
/// below is never touched (same trick as the old Paper setup).
pub const LOBBY_SPAWN: (f64, f64, f64) = (0.5, 230.0, 0.5);

/// Stable key for a player. `Uuid` is a plain record of two u64s.
pub type Key = (u64, u64);

pub fn key_of(u: &Uuid) -> Key {
    (u.high, u.low)
}

pub fn uuid_of(k: Key) -> Uuid {
    Uuid { high: k.0, low: k.1 }
}

/// Where a connected player currently is, in terms of the games.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Place {
    Lobby,
    Tnt,
    Arena,
}

/// Everything the three modules share. One lock, short critical sections:
/// handlers never call into the host while holding it for long.
#[derive(Default)]
pub struct Shared {
    /// entity id -> player key, for events that only carry an entity id.
    pub by_entity: HashMap<i32, Key>,
    pub place: HashMap<Key, Place>,
    /// Players who just joined and still owe a trip to the lobby, with the
    /// number of join-task passes they have waited. Pumpkin remembers only the
    /// newest teleport id, so a teleport sent before the client confirmed the
    /// spawn teleport gets it kicked with "Wrong teleport id". A browser client
    /// can take several seconds to load the world and confirm, so we wait for
    /// the player's first accepted movement (see `moved`) or a long timeout.
    pub join_queue: Vec<(Key, u32)>,
    /// Queued players whose first movement was accepted: they have confirmed.
    pub moved: HashSet<Key>,
}

static SHARED: Mutex<Option<Shared>> = Mutex::new(None);

pub fn shared() -> MutexGuard<'static, Option<Shared>> {
    let mut g = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    if g.is_none() {
        *g = Some(Shared::default());
    }
    g
}

pub fn with_shared<R>(f: impl FnOnce(&mut Shared) -> R) -> R {
    let mut g = shared();
    f(g.as_mut().expect("initialised above"))
}

pub fn place_of(k: Key) -> Place {
    with_shared(|s| s.place.get(&k).copied().unwrap_or(Place::Lobby))
}

pub fn set_place(k: Key, p: Place) {
    with_shared(|s| {
        s.place.insert(k, p);
    });
}

pub fn text(s: &str) -> TextComponent {
    // `&` colour codes are what people type; the API wants section signs.
    TextComponent::from_legacy_string_with_code(s, '&')
}

pub fn flags() -> BlockFlags {
    BlockFlags::NOTIFY_LISTENERS
}

/// Overworld handle, or None while no world is loaded yet.
pub fn overworld(server: &Server) -> Option<World> {
    let worlds = server.get_all_worlds();
    worlds.into_iter().next()
}

/// Load the chunks a build touches. Placing blocks in a chunk nobody has
/// loaded can fail without any error, which leaves the arena missing.
pub fn load_chunks(world: &World, x0: i32, z0: i32, x1: i32, z1: i32) {
    for cx in (x0 >> 4)..=(x1 >> 4) {
        for cz in (z0 >> 4)..=(z1 >> 4) {
            let _ = world.get_chunk(cx, cz);
        }
    }
}

/// Is this block really there? Used to refuse a game start with no floor.
pub fn block_is(world: &World, x: i32, y: i32, z: i32, name: &str) -> bool {
    world
        .get_block(pumpkin_plugin_api::world::BlockPos { x, y, z })
        .name
        == name
}

/// Fill a box with a block by name. The host has no /fill, so loop. Returns
/// how many blocks the host refused to place.
pub fn fill(world: &World, a: (i32, i32, i32), b: (i32, i32, i32), name: &str, hollow: bool) -> u32 {
    let mut failed = 0;
    let mut set = |x: i32, y: i32, z: i32, n: &str| {
        if !world.set_block_by_name(pumpkin_plugin_api::world::BlockPos { x, y, z }, n, flags()) {
            failed += 1;
        }
    };
    let (x0, x1) = (a.0.min(b.0), a.0.max(b.0));
    let (y0, y1) = (a.1.min(b.1), a.1.max(b.1));
    let (z0, z1) = (a.2.min(b.2), a.2.max(b.2));
    for x in x0..=x1 {
        for y in y0..=y1 {
            for z in z0..=z1 {
                let edge = x == x0 || x == x1 || y == y0 || y == y1 || z == z0 || z == z1;
                if hollow && !edge {
                    // Clear the inside so a rebuild over old blocks is clean.
                    set(x, y, z, "minecraft:air");
                    continue;
                }
                set(x, y, z, name);
            }
        }
    }
    failed
}
