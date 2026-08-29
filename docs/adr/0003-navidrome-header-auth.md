# ADR-0003: Authenticate Navidrome with reverse-proxy headers, not OIDC

**Status:** Accepted
**Date:** 2026-08-28

## Context

Navidrome was internet-facing with **zero users in its database** — sitting on the first-run "create admin" wizard. The first stranger to find the hostname would have been handed the admin account.

Every other app here uses Authentik. Navidrome cannot: verified three ways against the deployed `navidrome:0.58.0`, it has **no OIDC support at all**. The binary contains `ReverseProxyWhitelist` / `ReverseProxyUserHeader` and zero OIDC symbols; `server/auth.go` at that tag exposes `UsernameFromReverseProxyHeader()` as the only external login path; upstream documents only "Externalized Authentication".

A version trap sits alongside this: the current docs site names the options `ExtAuth.TrustedSources` / `ExtAuth.UserHeader`, but 0.58.0 only accepts `ND_REVERSEPROXYWHITELIST` / `ND_REVERSEPROXYUSERHEADER` — and an unrecognised `ND_*` variable is ignored **silently**, leaving the app unauthenticated with no error.

## Decision

Authentik **forward-auth** at the Ingress, passing `X-authentik-username`, with `ND_REVERSEPROXYWHITELIST` set to the Traefik pod CIDR.

`/rest` (Subsonic API) and `/share` are carved out to a separate Ingress without forward-auth — mobile clients cannot follow an OAuth redirect, and upstream explicitly recommends this. A strip middleware removes any client-supplied `X-authentik-*` header on that carve-out: without it, `curl -H 'X-authentik-username: admin'` was a total bypass, since Traefik's pod sits inside the whitelisted CIDR.

Bootstrap is the first SSO login, which `handleLoginFromHeaders` auto-creates as admin when the user count is zero. `ND_DEVAUTOCREATEADMINPASSWORD` was rejected: it hardcodes the username to `admin`, so the SSO user would become a *second, non-admin* account with no reachable native login form to fix it.

## Consequences

**Good:** the web player is behind SSO; mobile Subsonic clients still work.

**Bad:** `/rest` is outside SSO. Navidrome authenticates it against its own per-user password, so revoking a user in Authentik does not revoke their phone. CrowdSec and rate limiting still apply.

**Tripwire:** if `/rest` ever stops returning a Subsonic error for a forged `X-authentik-username` header — and instead authenticates — the strip middleware has been lost and the carve-out is a full admin bypass.
