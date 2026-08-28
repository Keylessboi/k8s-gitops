# ADR-0002: Disable book direct-download; acquire via torrents only

**Status:** Accepted
**Date:** 2026-08-28

## Context

Book search through Shelfmark (`book-downloader`) hung for 5-11 minutes per
query, starving the shared FlareSolverr instance that Prowlarr's indexers also
depend on.

The cause is structural, not configuration. Shelfmark's direct-download
**search** backend is Anna's Archive *only* — `search_books()` in
`release_sources/direct_download.py` builds `get_aa_base_url() + "/search"` and
has no other branch. Z-Library, welib and LibGen are fetch-by-MD5 sources: they
can only retrieve a file once AA's search has produced its identifier.

Anna's Archive now gates `/search` behind **DDoS-Guard**, which neither solver
available here can beat:

- **FlareSolverr** — error after 60s, 75s and 83s timeouts, every attempt.
- **Byparr** (deployed specifically to test this) — four attempts across both
  mirrors returned the byte-identical DDoS-Guard interstitial (1896 bytes, zero
  results) in 4-8s, reporting `status: ok` while handing back the challenge stub.

Because it fails *fast and successfully*, a longer timeout cannot help. Removing
AA and keeping the other sources was tested and the app refuses outright:
`"Direct Download is not configured. Add at least one Anna's Archive mirror."`

## Decision

Set `DIRECT_DOWNLOAD_ENABLED=false`. Books are acquired through Prowlarr →
qBittorrent. Byparr was removed rather than left idling at ~540Mi.

Internet Archive was separately dropped as a book source — its scans are OCR'd
and the text quality is poor.

## Consequences

**Good:** searches fail fast instead of hanging; FlareSolverr is freed for the
indexers, which is what actually blocked Prowlarr.

**Bad:** no clearnet direct HTTP ebook downloads. In practice this costs
nothing, because that path did not work regardless.

**Tripwire:** if someone re-enables it, book search latency will return to
minutes and Prowlarr indexer searches will start timing out as a side effect.
Re-enable only after verifying a solver actually returns a real AA results page
— check for real result rows, not just HTTP 200, since DDoS-Guard returns 200
with a challenge body.
