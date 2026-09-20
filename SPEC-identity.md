# SPEC-identity.md — how an app signs people in through the family IdP

## Scope

The **optional** identity contract of an app born from this boilerplate:
**Umbral** is the family's IdP (an OAuth2/OIDC authorization server) and an app
may sign people in through it. Umbral answers **two** questions — *who is this
person?* and *may they enter this app?* — and nothing else: workspaces, roles
and permissions live inside each app.

**This repo does not govern Umbral.** The IdP is its own project, with its own
shape and its own consumer contract; what is here is how **an app** connects,
next to the local modes of `SPEC-auth.md` (username/password and Google without
Umbral). No app of the family consumes the IdP yet: this spec is the contract to
follow when one does.

## Hard rules

1. **There are no scopes.** What authorizes is the **access cell** (person ×
   app, a boolean, deny-by-default); an incoming `scope` is ignored.
2. **There is no `id_token`.** The **RS256 access token is the identity**: it is
   verified against the JWKS (`kid`, signature, `iss`, `aud`, `exp`) before a
   single claim is read, or `/userinfo` is called with the bearer. Fail closed:
   any check rejected means no session.
3. **The app never stores Umbral passwords**, and never keeps a second directory
   with a second password: the identity of the family is the email, and
   duplicating it breaks the matrix.
4. **The app does not create people in Umbral**; for that there is delegated
   provisioning (`POST /api/v1/users`, which leaves a `pending` invitation for a
   human to approve).
5. **Agents do not go through Umbral**: Umbral authenticates **people**. An
   agent uses the app's `api_key`/`api_token` against the app's own API.
6. **There is no cookie shared between apps.** Each app establishes **its own**
   session after redeeming the code, and its plug plus its mirror `on_mount`
   keep reading that cookie (the `phoenix-session-mirror` pattern); Umbral's
   token is not validated on every socket request.
7. **An `invalid_grant` is resolved by re-authorizing**, never by silently
   stretching the local session.

## Consumer variables

Names **proposed by the IdP** for its consumers — a naming proposal, not a
contract of the IdP. The SDK takes explicit configuration (it does not read the
environment for you), so an app decides where each value comes from; the family
fixes these names so every environment looks alike:

| Variable | Meaning |
|---|---|
| `UMBRAL_BASE_URL` | issuer / base URL, **no trailing slash** (e.g. `https://umbral.example`) |
| `UMBRAL_CLIENT_ID` | from the registered app |
| `UMBRAL_CLIENT_SECRET` | confidential clients only; **omit it for public clients (PKCE)** |
| `UMBRAL_REDIRECT_URI` | must be **exactly** one registered URI; default `<app>/auth/sso/callback` |
| `UMBRAL_SERVICE_CREDENTIAL` | optional; only if the provisioning API `/api/v1/*` is used |
| `UMBRAL_JWKS_TTL_MS` | JWKS cache TTL (`/.well-known/jwks.json`) |
| `UMBRAL_SCOPE` | **ignored**: it exists only so an old environment does not break |

**With no `client_id` SSO stays off** and the app keeps its local sign-in.

## SDK (monorepo, by path)

The Elixir client lives **inside the IdP's repo** (there is no external repo and
no Hex package; publishing it is a pending human decision):

```elixir
{:umbral_ex, path: "../umbral/sdk/umbral_ex"}   # + req and jose
```

- Configuration is explicit: `Umbral.Client.new(issuer:, client_id:,
  client_secret:, redirect_uri:, service_credential:)` — with no secret the
  client is **public** (PKCE) and identifies itself with its `client_id`;
  a secret is never sent in the body.
- Modules: `Umbral.Client`, `Umbral.Router`, `Umbral.Plug`, `Umbral.LiveAuth`
  (the Phoenix glue) and `UmbralEx.{OAuth,IdToken,Device,Service,LogoutToken,Jwks,Tokens,Error,Response}`.
- No test touches the network: `req_options: [plug: {Req.Test, …}]`.

## Wiring in Phoenix

1. **Entry point of the app:** an unauthenticated request goes to the app's
   **own** `/auth/sso` (not straight to Umbral) with `return_to`, so the
   destination lives in the app's own state.
2. **Routes:** `GET /auth/sso` → `Umbral.Router.login_redirect` and
   `GET /auth/sso/callback` → `Umbral.Router.callback_redirect`, in a scope with
   `pipe_through :browser` and `:fetch_session`.
3. **Single-use signed `state`** carrying the `nonce` and the `return_to`, also
   stored in the app's session; the callback compares it and **consumes it even
   when it fails**.
4. **Identity → local profile:** upsert by `sub` (falling back to `email`) with
   `provider: "sso"`, refreshing `name`, **with no password**, and only then the
   app's session.
5. **Pipeline:** `plug Umbral.Plug, client: …` leaves `current_user` in the
   assigns; **every privileged `live_session` carries its mirror `on_mount`**
   (`Umbral.LiveAuth, :require_user`) — the websocket does not go through plugs
   (`phoenix-session-mirror` pattern).
6. **Logout:** destroys the local session **and** sends the browser to Umbral's
   `/logout`.
7. **Push revocation (optional):** with `backchannel_logout_url` registered,
   Umbral sends a form-encoded `POST` carrying a `logout_token` (RS256 JWT;
   `iss`, `aud`, `sub`, `jti`, `events`, no `nonce`); the app answers **2xx** and
   closes that `sub`'s sessions. Retries: 5, one minute apart, best-effort.

## Token lifecycle

| Situation | What arrives | What to do |
|---|---|---|
| Refresh | a new access token + a **rotated** refresh token | store the new pair; a reused refresh token revokes the whole chain |
| Revoked chain / suspended person | `400 invalid_grant`, `active: false` in `/oauth/introspect` | drop the local session and re-authorize |
| Grant removed in the panel | a `logout_token` on the back-channel (if registered) | close that local session |
| Rotated secret | `401 invalid_client` at the token endpoint | the operator updates the env and restarts |

Never cache a negative decision; the JWKS **is** cached with a TTL.

## IdP operation (what the app may assume)

| Route | What it is |
|---|---|
| `GET /health` | liveness: **200 without touching the database** — the same rule as `SPEC-docker.md` |
| `GET /ready` | real readiness: `SELECT 1`; **this is the probe the proxy watches** |
| `GET /.well-known/jwks.json` | public keys, cacheable, indexed by `kid` |
| `GET /.well-known/openid-configuration` | discovery (issuer, endpoints, flows) |
| `GET /metrics` | Prometheus, **not public** (token `UMBRAL_METRICS_TOKEN`; with no token configured, 404) |

Key rotation without downtime: `UMBRAL_SIGNING_KEYS` (a JSON `[{"kid","pem"}]`
list) — the **first** entry signs and the rest only verify; the single-key
`UMBRAL_SIGNING_KEY` keeps working.

## How an app is registered

- **Dev:** the IdP's seeds pre-register the family's apps with their local
  callbacks (each app's development port). Production apps are not covered by
  those seeds.
- **Production:** the app is registered **in the panel** (there are no prod
  seeds): `/admin/apps` with the **exact** `redirect_uri` (no wildcards),
  `origins[]` if it is a public browser client, `launch_url` and branding; the
  person × app cell is marked in `/admin/access` (deny-by-default); and
  `/admin/apps/:id/credentials` only if the app uses `/api/v1/*`.

## Known gaps

| Gap | Note |
|---|---|
| No app consumes the IdP yet | this spec is the contract to follow |
| The IdP's seeds are **development** seeds | callbacks to local ports; in production every app is registered in the panel with its real URI |
| The SDK is not published | it is consumed by path inside the IdP's monorepo |
| The name `UMBRAL_*` for consumer variables | a proposal by the IdP, not an IdP contract (see §Consumer variables) |

## Anti-patterns

- Granting access by domain: an allowed domain **never** grants identity or
  access — the cell is the only decision.
- Assuming a `scope` in the token or in the response.
- Believing the `email` before verifying the signature, or accepting a token
  whose `aud` belongs to another app.
- Pointing the proxy's probe at Umbral's `/health` when readiness is what you
  need: `/ready` is for that.
- Sending agents through the sign-in flow.