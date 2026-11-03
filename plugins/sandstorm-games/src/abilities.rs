//! Mob Arena class abilities: right-click the nether star in slot 7.
//! Each class has one, on a shared cooldown, with particles and sound.

use crate::arena::Class;
use crate::util::*;
use pumpkin_plugin_api::{
    DamageType, EntityType, ItemStack, ItemStackExt, Server,
    entity::Entity,
    particles::Particle,
    player::Player,
    wit::pumpkin::plugin::{
        sounds::{Sound, SoundCategory},
        status_effect::{StatusEffectInstance, StatusEffectType},
    },
};
use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

/// Ticks between uses.
const COOLDOWN: u64 = 160;

static NOW: AtomicU64 = AtomicU64::new(0);
static READY: Mutex<Option<HashMap<Key, u64>>> = Mutex::new(None);

/// Called from the arena tick so the plugin has a clock.
pub fn advance(ticks: u64) {
    NOW.fetch_add(ticks, Ordering::SeqCst);
}

fn ready_at() -> std::sync::MutexGuard<'static, Option<HashMap<Key, u64>>> {
    let mut g = READY.lock().unwrap_or_else(|e| e.into_inner());
    g.get_or_insert_with(HashMap::new);
    g
}

pub fn forget(k: Key) {
    if let Some(m) = ready_at().as_mut() {
        m.remove(&k);
    }
}

fn name_of(class: Class) -> (&'static str, &'static str) {
    match class {
        Class::Knight => ("&c&lWhirlwind", "Spin and cut down everything near you."),
        Class::Archer => ("&e&lAdrenaline", "A burst of speed and height."),
        Class::Tank => ("&6&lShockwave", "Slam the ground and hurl mobs away."),
        Class::Chemist => ("&a&lHealing Mist", "Heal yourself and your allies."),
        Class::Oddjob => ("&b&lThunderstrike", "Call lightning on nearby mobs."),
    }
}

/// The item that fires the ability.
pub fn item(class: Class) -> ItemStack {
    let (name, blurb) = name_of(class);
    let it = ItemStack::of("minecraft:nether_star", 1);
    it.set_custom_name(Some(text(&format!("{name} &7(right-click)"))));
    it.set_lore(vec![text(&format!("&7{blurb}")), text("&8Cooldown 8s")]);
    it
}

fn is_mob(e: &Entity) -> bool {
    matches!(
        e.get_type(),
        EntityType::Zombie | EntityType::Skeleton | EntityType::Spider | EntityType::Creeper
    )
}

fn mobs_near(server: &Server, c: (f64, f64, f64), r: f64) -> Vec<Entity> {
    let Some(w) = overworld(server) else {
        return vec![];
    };
    w.get_entities()
        .into_iter()
        .filter(|e| {
            let p = e.get_position();
            is_mob(e) && (p.0 - c.0).powi(2) + (p.1 - c.1).powi(2) + (p.2 - c.2).powi(2) <= r * r
        })
        .collect()
}

fn burst(server: &Server, particle: Particle, at: (f64, f64, f64), spread: f64, speed: f32, count: i32) {
    if let Some(w) = overworld(server) {
        w.spawn_particle(particle, at, (spread, spread * 0.6, spread), speed, count);
    }
}

fn sound(server: &Server, s: Sound, at: (f64, f64, f64), volume: f32, pitch: f32) {
    if let Some(w) = overworld(server) {
        w.play_sound(s, SoundCategory::Players, at, volume, pitch);
    }
}

fn effect(p: &Player, kind: StatusEffectType, seconds: u32, amp: u8) {
    p.add_effect(StatusEffectInstance {
        effect_type: kind,
        duration: seconds * 20,
        amplifier: amp,
        ambient: false,
        show_particles: true,
        show_icon: true,
    });
}

/// Push a mob away from `from`.
fn shove(e: &Entity, from: (f64, f64, f64), force: f64, lift: f64) {
    let p = e.get_position();
    let (dx, dz) = (p.0 - from.0, p.2 - from.2);
    let len = (dx * dx + dz * dz).sqrt().max(0.01);
    e.set_velocity((dx / len * force, lift, dz / len * force));
}

fn hurt(e: &Entity, amount: f32) {
    if let Some(l) = e.as_living() {
        l.damage(amount, DamageType::Magic);
    }
}

/// Use the ability if it is off cooldown. Returns false when it was not used.
pub fn fire(server: &Server, p: &Player, class: Class) -> bool {
    let k = key_of(&p.get_id());
    let now = NOW.load(Ordering::SeqCst);
    {
        let mut g = ready_at();
        let m = g.as_mut().expect("initialised above");
        if let Some(&t) = m.get(&k) {
            if now < t {
                let secs = (t - now).div_ceil(20);
                p.send_system_message(text(&format!("&7Ability ready in &e{secs}s&7.")), false);
                return false;
            }
        }
        m.insert(k, now + COOLDOWN);
    }
    let at = p.get_position();
    let up = (at.0, at.1 + 1.0, at.2);
    match class {
        Class::Knight => {
            for e in mobs_near(server, at, 4.5) {
                hurt(&e, 9.0);
                shove(&e, at, 0.9, 0.3);
            }
            for i in 0..12 {
                let a = f64::from(i) / 12.0 * std::f64::consts::TAU;
                burst(server, Particle::SweepAttack, (at.0 + 3.0 * a.cos(), at.1 + 1.0, at.2 + 3.0 * a.sin()), 0.2, 0.0, 1);
            }
            burst(server, Particle::Crit, up, 2.5, 0.4, 40);
            sound(server, Sound::EntityPlayerAttackSweep, at, 1.2, 0.8);
        }
        Class::Archer => {
            effect(p, StatusEffectType::Speed, 6, 2);
            effect(p, StatusEffectType::JumpBoost, 6, 1);
            burst(server, Particle::Cloud, at, 0.6, 0.1, 30);
            burst(server, Particle::Flame, up, 0.5, 0.05, 20);
            sound(server, Sound::EntityPlayerLevelup, at, 0.8, 1.6);
        }
        Class::Tank => {
            for e in mobs_near(server, at, 5.5) {
                hurt(&e, 5.0);
                shove(&e, at, 1.6, 0.5);
            }
            burst(server, Particle::ExplosionEmitter, at, 0.1, 0.0, 1);
            burst(server, Particle::Explosion, up, 3.0, 0.0, 12);
            sound(server, Sound::EntityGenericExplode, at, 1.0, 0.7);
        }
        Class::Chemist => {
            for q in server.get_all_players() {
                let qa = q.get_position();
                if (qa.0 - at.0).powi(2) + (qa.1 - at.1).powi(2) + (qa.2 - at.2).powi(2) <= 49.0 {
                    q.heal(8.0);
                    effect(&q, StatusEffectType::Regeneration, 6, 1);
                    burst(server, Particle::Heart, (qa.0, qa.1 + 1.5, qa.2), 0.6, 0.0, 8);
                }
            }
            burst(server, Particle::HappyVillager, up, 3.0, 0.0, 50);
            sound(server, Sound::BlockBeaconActivate, at, 1.0, 1.4);
        }
        Class::Oddjob => {
            let mut targets = mobs_near(server, at, 12.0);
            targets.sort_by(|a, b| {
                let d = |e: &Entity| {
                    let p = e.get_position();
                    (p.0 - at.0).powi(2) + (p.2 - at.2).powi(2)
                };
                d(a).partial_cmp(&d(b)).unwrap_or(std::cmp::Ordering::Equal)
            });
            if let Some(w) = overworld(server) {
                for e in targets.iter().take(3) {
                    w.strike_lightning(e.get_position(), true);
                    hurt(e, 12.0);
                    burst(server, Particle::ElectricSpark, e.get_position(), 1.0, 0.3, 30);
                }
            }
            sound(server, Sound::EntityLightningBoltThunder, at, 1.0, 1.0);
            if targets.is_empty() {
                p.send_system_message(text("&7No mobs in range, but the sky rumbles."), false);
            }
        }
    }
    true
}
