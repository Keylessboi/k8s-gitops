# Architecture Decision Records

Referenced by `AGENTS.md` and `docs/agents/domain.md`. Read the ADRs touching an area before you change it.

An ADR records a decision that is **not obvious from the code**. Especially one where the obvious choice is wrong. If someone could reasonably "fix" a setting back and break things, it belongs here.

## Format

Copy [`0000-template.md`](0000-template.md), number it sequentially, and keep it short. Status is one of `Accepted`, `Superseded by ADR-NNNN`, or `Reversed`.

The **Consequences** section matters most. Particularly the negative ones and the tripwires that tell a future reader the decision is being violated.

## Index

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-media-storage-on-tank-mirror.md) | All cluster storage lives on the `tank` mirror | Accepted |
| [0002](0002-direct-download-disabled.md) | Book direct-download is disabled; torrents only | Accepted |
| [0003](0003-navidrome-header-auth.md) | Navidrome uses reverse-proxy header auth, not OIDC | Accepted |
| [0004](0004-lidarr-is-the-tag-writer.md) | Lidarr writes audio tags; beets is read-only | Accepted |
| [0005](0005-pterodactyl-needs-mysql-and-kvm.md) | Pterodactyl waits for a MySQL host and a KVM node | Accepted |
