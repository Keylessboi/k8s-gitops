mod abilities;
mod arena;
mod lobby;
mod tntrun;
mod util;

use pumpkin_plugin_api::{Context, Plugin, PluginMetadata, Result, register_plugin};

struct Games;

impl Plugin for Games {
    fn new() -> Self {
        Games
    }

    fn metadata(&self) -> PluginMetadata {
        PluginMetadata {
            name: "sandstorm-games".into(),
            version: "0.1.0".into(),
            authors: vec!["sandstorm".into()],
            description: "Lobby, TNT Run and Mob Arena".into(),
            dependencies: vec![],
            permissions: vec![],
        }
    }

    fn on_load(&self, context: Context) -> Result<()> {
        lobby::init(&context)?;
        tntrun::init(&context)?;
        arena::init(&context)?;
        Ok(())
    }
}

register_plugin!(Games);
