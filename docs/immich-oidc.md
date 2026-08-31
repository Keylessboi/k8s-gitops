# Immich + Authentik OIDC — the redirect-URI breakage and its fix

Immich v3.1.0 (server + ML, chart 0.12.0) signs in through Authentik 2025.6.4
via the provider `Immich` (client_id `immich-oidc`, application slug `immich`).
Immich's OAuth config is declared, not clicked: the `immich-config` Secret is
mounted at `/config/immich.json` (`IMMICH_CONFIG_FILE=/config/immich.json` in
`apps/immich/kustomization.yaml`), because Immich has no env vars for OAuth and
without the file the login page shows no SSO button at all.

## Root cause (found 2026-08-30)

The user reported SSO "fails because of the redirect URI". It was the **mobile
app** flow, and the mismatch was Authentik-side:

- `immich.json` sets `mobileOverrideEnabled: true` and
  `mobileRedirectUri: https://immich.sandstorm.chat/api/oauth/mobile-redirect`.
  With the override on, Immich's server **replaces** whatever callback the
  client sends (`app.immich:///oauth-callback`) with that override URL before
  talking to Authentik (`resolveRedirectUri()` in
  `server/src/services/auth.service.ts` at v3.1.0). So every mobile login asks
  Authentik to redirect to `https://immich.sandstorm.chat/api/oauth/mobile-redirect`.
- The Authentik provider only had three STRICT redirect URIs:
  `https://immich.sandstorm.chat/auth/login`,
  `https://immich.sandstorm.chat/user-settings`, `app.immich:///oauth-callback`.
  The mobile-redirect URL was **not registered** → Authentik's authorize
  endpoint answered **HTTP 400** (same signature as a bogus-URI control probe),
  which the app surfaces as "invalid redirect URI".
- Proof that Immich itself requests it: `POST /api/oauth/authorize` with body
  `{"redirectUri":"app.immich:///oauth-callback"}` returned an authorize URL
  with `redirect_uri=https://immich.sandstorm.chat/api/oauth/mobile-redirect`,
  `scope=openid email profile`, PKCE S256, client_id `immich-oidc`.

Ruled out along the way:

- **Client secret**: the `immich-oidc` Secret in ns `immich`, the
  `clientSecret` inside `immich.json`, and the Authentik provider's
  `client_secret` are all byte-identical (compared by sha256, never printed).
- **Property mappings**: the provider has the default `openid`, `email`,
  `profile` mappings — everything Immich needs. `immich_quota` /
  `immich_role` claims are optional; with `defaultStorageQuota: 0` and no
  custom mappings, users just get the defaults.
- **Stale app callback**: `app.immich:///oauth-callback` is NOT outdated —
  the v3.1.0 mobile app still sends exactly that (`mobile/lib/services/
  oauth.service.dart`), and the server's `GET /api/oauth/mobile-redirect`
  forwards to it (verified live: `307 → app.immich:///oauth-callback?code=…`).
  It is simply never sent to Authentik while the override is enabled.
- **Web flow**: was never broken. `redirect_uri=https://immich.sandstorm.chat/
  auth/login` 302'd to the Authentik login flow before and after the fix.

## Fix applied (runtime, ak shell — not in Git)

The Authentik provider's redirect URIs live in the DB (`OAuth2Provider.
_redirect_uris`, a JSON array; `redirect_uris` is a parsed property, so save
`_redirect_uris` with `update_fields=['_redirect_uris']`). One URI appended,
nothing removed:

```
before: auth/login, user-settings, app.immich:///oauth-callback
after:  auth/login, user-settings, app.immich:///oauth-callback,
        https://immich.sandstorm.chat/api/oauth/mobile-redirect   <- added, strict
```

Revert = re-run the same snippet without the append (the before-state above is
the restore point). No other provider was touched.

## Verification (headless, 2026-08-30)

- `GET /application/o/authorize/?client_id=immich-oidc&redirect_uri=…` with the
  full `openid email profile` scope:
  - `https://immich.sandstorm.chat/api/oauth/mobile-redirect` → **302** to the
    Authentik authentication flow (was 400 before the fix).
  - `https://immich.sandstorm.chat/auth/login` → 302 (no regression).
  - `https://immich.sandstorm.chat/user-settings` → 302 (no regression).
- `GET /api/oauth/mobile-redirect?code=…&state=…` on Immich → `307` to
  `app.immich:///oauth-callback?code=…&state=…` (the app hand-off leg works).
- Not verifiable headlessly: the actual Authentik login (needs a browser) and
  the token exchange (needs a real authorization code). The secret match is
  proven by hash comparison, so the code-for-token leg has no known blocker.

## User-facing answer

- **Web**: use `https://immich.sandstorm.chat` exactly. Immich derives the web
  `redirect_uri` from the request origin, so any other origin (Tailscale IP,
  `localhost` port-forward, a different hostname) requests an unregistered URI
  and fails the same way. If another origin is ever needed, register
  `<origin>/auth/login` (and `<origin>/user-settings`) on the provider first.
- **Mobile app**: server URL `https://immich.sandstorm.chat`, then "Sign in
  with Authentik". The browser hop now lands on
  `/api/oauth/mobile-redirect`, which bounces into the app via
  `app.immich:///oauth-callback`.
