# SPEC-identity.md — cómo una app entra por el IdP de la familia

## Alcance

El contrato de identidad **opcional** de una app nacida de este boilerplate:
**Umbral** es el IdP (authorization server OAuth2/OIDC) de la familia y una app
puede entrar por él. Umbral responde **dos** preguntas — *¿quién es esta
persona?* y *¿puede entrar a esta app?* — y nada más: los workspaces, roles y
permisos viven en cada app (`umbral/docs/integration.md:14-18`).

**Este repo no gobierna a Umbral.** El IdP es su propio proyecto, con su propio
shape y su propio contrato de consumidor (`umbral/docs/integration.md`); lo que
está acá es cómo **una app** se conecta, al lado de los modos locales de
`SPEC-auth.md` (usuario/contraseña y Google sin Umbral). Ninguna app de la
familia integra Umbral todavía (0 referencias en `dran`, `tokengate`, `gorim`,
`skema`, `stiva`): este spec es el contrato a seguir cuando alguna se integre.

## Reglas duras

1. **No hay scopes.** Lo que autoriza es la **celda de acceso** (persona × app,
   booleana, deny-by-default); un `scope` entrante se ignora
   (`umbral/docs/integration.md:29-32`).
2. **No hay `id_token`.** El **access token RS256 es la identidad**: se verifica
   contra el JWKS (`kid`, firma, `iss`, `aud`, `exp`) antes de leer un solo
   claim, o se consulta `/userinfo` con el bearer (`umbral/docs/integration.md:80-85`).
   Falla cerrada: cualquier chequeo rechazado, no hay sesión.
3. **La app nunca guarda contraseñas de Umbral** ni mantiene un segundo
   directorio con una segunda contraseña: la identidad de la familia es el
   email, y duplicarla rompe la matriz (`umbral/docs/integration.md:107-119`).
4. **La app no crea personas en Umbral**; para eso está el alta delegada
   (`POST /api/v1/users`, que deja una invitación `pending` para que un humano
   la apruebe) (`umbral/docs/integration.md:231`).
5. **Los agentes no pasan por Umbral**: Umbral autentica **personas**. Un agente
   usa la `api_key`/`api_token` de la app contra la API de la app
   (`umbral/docs/integration.md:118-119`).
6. **No hay cookie compartida entre apps.** Cada app establece **su propia**
   sesión después de canjear el código, y su plug + su `on_mount` espejo siguen
   leyendo esa cookie (patrón `phoenix-session-mirror`); no se valida el token
   de Umbral en cada request del socket
   (`umbral/docs/integration.md:121-130`).
7. **Un `invalid_grant` se resuelve reautorizando**, nunca estirando la sesión
   local en silencio (`umbral/docs/integration.md:95-105`).

## Variables del consumidor

Propuesta del IdP en `umbral/docs/integration.md:34-47`; **la familia las fija
con estos nombres** (no inventes otros):

| Variable | Significado |
|---|---|
| `UMBRAL_BASE_URL` | issuer / base URL, **sin barra final** (ej. `https://umbral.example`) |
| `UMBRAL_CLIENT_ID` | de la app registrada |
| `UMBRAL_CLIENT_SECRET` | sólo clientes confidenciales; **omitir en clientes públicos (PKCE)** |
| `UMBRAL_REDIRECT_URI` | debe ser **exactamente** una URI registrada; default `<app>/auth/sso/callback` |
| `UMBRAL_SERVICE_CREDENTIAL` | opcional; sólo si se usa la API de provisión `/api/v1/*` |
| `UMBRAL_JWKS_TTL_MS` | TTL de la caché del JWKS (`/.well-known/jwks.json`) |
| `UMBRAL_SCOPE` | **ignorada**: existe sólo para no romper un entorno viejo |

**Sin `client_id` el SSO queda apagado** y la app conserva su login local
(`umbral/docs/integration.md:49`).

## SDK (monorepo, por path)

El cliente Elixir vive **dentro del repo de umbral** (no hay repo externo ni Hex;
publicarlo es decisión humana pendiente):

```elixir
{:umbral_ex, path: "../umbral/sdk/umbral_ex"}   # + req y jose
```

- Instalación y configuración explícita: `umbral/sdk/umbral_ex/README.md:11-35`.
- Módulos: `Umbral.Client`, `Umbral.Router`, `Umbral.Plug`, `Umbral.LiveAuth`
  (el pegamento Phoenix) y `UmbralEx.{OAuth,IdToken,Device,Service,LogoutToken,Jwks,Tokens,Error,Response}`.
- Ningún test toca la red: `req_options: [plug: {Req.Test, …}]`
  (`umbral/sdk/umbral_ex/README.md:175-193`).

## Wiring en Phoenix

Referencia: `umbral/sdk/umbral_ex/README.md:137-173` + `umbral/docs/integration.md:51-93`.

1. **Entrada de la app:** una request sin sesión va al `/auth/sso` **de la app**
   (no directo a Umbral) con `return_to`, para que el destino viva en su propio
   estado (`umbral/docs/integration.md:53-55`).
2. **Rutas:** `GET /auth/sso` → `Umbral.Router.login_redirect` y
   `GET /auth/sso/callback` → `Umbral.Router.callback_redirect`, en un scope con
   `pipe_through :browser` y `:fetch_session` (`umbral/sdk/umbral_ex/README.md:140-152`).
3. **`state` firmado de un solo uso** que lleva el `nonce` y el `return_to`, y
   también se guarda en la sesión de la app; el callback lo compara y **lo
   consume incluso si falla** (`umbral/docs/integration.md:56-59`).
4. **Identidad → perfil local:** upsert por `sub` (fallback `email`) con
   `provider: "sso"`, refrescando `name`, **sin contraseña**, y recién entonces
   la sesión de la app (`umbral/docs/integration.md:86-88`).
5. **Pipeline:** `plug Umbral.Plug, client: …` deja `current_user` en los
   assigns; **cada `live_session` privilegiada lleva su `on_mount` espejo**
   (`Umbral.LiveAuth, :require_user`) — el websocket no pasa por los plugs
   (`umbral/sdk/umbral_ex/README.md:154-165`, patrón `phoenix-session-mirror`).
6. **Logout:** destruye la sesión local **y** manda el navegador al `/logout` de
   Umbral (`umbral/docs/integration.md:89-93`).
7. **Revocación push (opcional):** con `backchannel_logout_url` registrada,
   Umbral hace `POST` form-encoded con `logout_token` (JWT RS256; `iss`, `aud`,
   `sub`, `jti`, `events`, sin `nonce`); la app responde **2xx** y cierra las
   sesiones de ese `sub`. Reintentos: 5, a un minuto, best-effort
   (`umbral/docs/integration.md:239-273`).

## Ciclo de vida del token

| Situación | Qué llega | Qué hacer |
|---|---|---|
| Refresh | nuevo access + refresh **rotado** | guardar el par nuevo; un refresh reusado revoca la cadena entera |
| Cadena revocada / persona suspendida | `400 invalid_grant`, `active: false` en `/oauth/introspect` | descartar la sesión local y reautorizar |
| Grant removido en el panel | `logout_token` al back-channel (si está registrado) | cerrar esa sesión local |
| Secreto rotado | `401 invalid_client` en el token endpoint | el operador actualiza el env y reinicia |

Nunca cachear una decisión negativa; el JWKS sí se cachea con TTL
(`umbral/docs/integration.md:95-105`).

## Operación del IdP (lo que la app puede asumir)

| Ruta | Qué es |
|---|---|
| `GET /health` | liveness: **200 sin tocar la base** — la misma regla que `SPEC-docker.md` |
| `GET /ready` | readiness real: `SELECT 1`; **es el probe que va al proxy** |
| `GET /.well-known/jwks.json` | llaves públicas, cacheables, indexadas por `kid` |
| `GET /.well-known/openid-configuration` | discovery (issuer, endpoints, flujos) |
| `GET /metrics` | Prometheus, **no público** (token `UMBRAL_METRICS_TOKEN`; sin token configurado, 404) |

Rotación de llaves sin downtime: `UMBRAL_SIGNING_KEYS` (JSON `[{"kid","pem"}]`),
la **primera** firma y las demás sólo verifican; `UMBRAL_SIGNING_KEY` (una sola)
sigue funcionando (`umbral/docs/integration.md:286-292`).

## Cómo se registra una app

- **Dev:** los seeds de Umbral ya dejan las tres apps de la familia con sus
  callbacks locales — Dran `:4001`, Stiva `:4003`, Skema `:4004`
  (`umbral/priv/repo/seeds.exs:28-31`). No registran `tokengate` ni `gorim`.
- **Producción:** se registra **en el panel** (no hay seeds de prod):
  `/admin/apps` con la `redirect_uri` **exacta** (sin comodines), `origins[]` si
  es cliente público en el browser, `launch_url` y branding; la persona × app se
  marca en `/admin/access` (deny-by-default); `/admin/apps/:id/credentials` sólo
  si la app usa `/api/v1/*` (`umbral/docs/integration.md:20-32`).

## Pendientes conocidos

| Pendiente | Ancla | Nota |
|---|---|---|
| Ninguna app integra el IdP | — | este spec es el contrato a seguir |
| Los seeds de Umbral son de **desarrollo** | `umbral/priv/repo/seeds.exs:28-31` | callbacks a `localhost:4001/4003/4004`; en producción cada app se registra en el panel con su URI real |
| Tokengate no está registrado en el IdP | `umbral/priv/repo/seeds.exs:28-31` | su puerto es 4000; se registra en el panel cuando se integre |

## Anti-patrones

- Conceder acceso por dominio: un dominio permitido **nunca** concede identidad
  ni acceso — la celda es la única decisión.
- Asumir un `scope` en el token o en la respuesta.
- Creer el `email` antes de verificar la firma, o aceptar un token cuyo `aud` sea
  de otra app.
- Poner el probe del proxy en `/health` de Umbral si hace falta readiness: para
  eso está `/ready`.
- Mandar agentes por el flujo de login.