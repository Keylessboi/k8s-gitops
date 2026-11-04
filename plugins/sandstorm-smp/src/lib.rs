//! The survival server's own plugin. For now it only does one thing: /lobby (or
//! /hub) sends the player back to the games server. The browser client follows
//! the Transfer packet to the same public address, and the notmc bridge, which
//! saw the packet leave the SMP, routes that connection to the lobby.

use pumpkin_plugin_api::{
    Context, Plugin, PluginMetadata, Result, Server, register_plugin,
    command::{Command, CommandError, CommandSender, ConsumedArgs},
    commands::CommandHandler,
    permission::{Permission, PermissionDefault},
    text::TextComponent,
};

const PERM: &str = "sandstorm-smp:lobby";
const PUBLIC_HOST: &str = "notmc.sandstorm.chat";
const PUBLIC_PORT: u16 = 443;

struct Smp;

impl Plugin for Smp {
    fn new() -> Self {
        Smp
    }

    fn metadata(&self) -> PluginMetadata {
        PluginMetadata {
            name: "sandstorm-smp".into(),
            version: "0.1.0".into(),
            authors: vec!["sandstorm".into()],
            description: "The survival server: the way back to the lobby".into(),
            dependencies: vec![],
            permissions: vec![],
        }
    }

    fn on_load(&self, context: Context) -> Result<()> {
        context.register_permission(&Permission {
            node: PERM.into(),
            description: "Use /lobby".into(),
            default: PermissionDefault::Allow,
            children: vec![],
        })?;
        let lobby = Command::new(&["lobby".to_string(), "hub".to_string()], "Back to the games lobby")
            .execute(ToLobby);
        context.register_command(lobby, PERM);
        Ok(())
    }
}

struct ToLobby;
impl CommandHandler for ToLobby {
    fn handle(
        &self,
        sender: CommandSender,
        _server: Server,
        _args: ConsumedArgs,
    ) -> std::result::Result<i32, CommandError> {
        let Some(p) = sender.as_player() else {
            return Ok(0);
        };
        p.send_system_message(TextComponent::from_legacy_string_with_code("&aSending you to the lobby...", '&'), false);
        p.transfer(PUBLIC_HOST, PUBLIC_PORT);
        Ok(1)
    }
}

register_plugin!(Smp);
