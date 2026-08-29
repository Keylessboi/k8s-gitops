# ADR-0004: Lidarr writes audio tags; beets runs read-only

**Status:** Accepted
**Date:** 2026-08-27

## Context

Both Lidarr and beets can tag a music library, and both were pointed at the same tree. Two taggers on one tree means whichever ran last wins and the other's work is wasted I/O.

There is a sharper hazard than churn. Files are hardlinked from `/data/torrents` into the library, so rewriting a file's tags **modifies the bytes being seeded** and breaks the torrent.

Lidarr is configured with `writeAudioTags: sync` and `scrubAudioTags: true` — it strips and rewrites tags on every metadata refresh.

## Decision

Lidarr is the single authoritative tag writer. Beets imports **in place** with all five file operations off (`copy`, `move`, `link`, `hardlink`, `reflink`) and `write: no`, so it catalogues and fetches art but never touches an audio byte.

The Servarr beets-integration guide's advice to set Lidarr's "Write Tags: Never" was deliberately **not** followed: that applies when beets is the tag writer. Here beets is read-only, so disabling Lidarr's tag writing would leave nothing writing tags at all.

## Consequences

**Good:** exactly one writer. Seeding torrents cannot be corrupted by the tagger, and `beet update` / `beet modify` cannot silently reorganise Lidarr's tree (`ui.should_move()` is false with all file operations off).

**Bad:** `sync` rewrites tags on every refresh, which is heavier I/O than necessary. Beets' superior tagging is unused.

**Tripwire:** if beets' `import.write` or any of its file operations is set to `yes`, both problems return at once — duelling taggers *and* corrupted seeds.
