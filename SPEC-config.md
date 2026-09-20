# SPEC-config.md — configuración de la app (env vars + settings)

## Alcance

Cómo se configura una app de la familia: qué **exige** el boot, qué es opcional
con qué default, dónde se lee cada variable, qué vive en **base de datos** y no
en entorno. Referencia canónica: **TokenGate** (`tokengate/config/runtime.exs`,
`tokengate/lib/tokengate_web/endpoint.ex`).

## Reglas duras

1. **El boot falla cerrado.** Si falta una variable requerida, `runtime.exs`
   **lanza** (`raise`) — nunca hay default silencioso ni contraseña de fallback.
2. **Las requeridas se exigen en `runtime.exs`, bajo `config_env() == :prod`**
   (`tokengate/config/runtime.exs:51`), y el endpoint se arranca con el gate
   `if config_env() == :prod or System.get_env("PHX_SERVER")`
   (`tokengate/config/runtime.exs:44`).
3. **Ningún secreto en el build**: los secretos entran por entorno en runtime,
   nunca como `ARG`/`ENV` del Dockerfile (`SPEC-docker.md` §Reglas duras).
4. **Los salts de sesión son dos y distintos**: `signing_salt` y
   `encryption_salt` no comparten valor (`tokengate/lib/tokengate_web/endpoint.ex:19-20`).
5. **Lo que se edita en la UI vive en la base de datos**, no en entorno
   (§Settings en base de datos).

## Requeridas en producción (sin ellas el boot muere)

| Var | Qué es | Dónde se exige |
|---|---|---|
| `DATABASE_URL` | conexión Postgres | `tokengate/config/runtime.exs:53` |
| `SECRET_KEY_BASE` | firma/cifra cookies y secretos | `tokengate/config/runtime.exs:94` |
| `PHX_HOST` | host público, **sin** esquema ni puerto | `tokengate/config/runtime.exs:101` |
| `SESSION_SIGNING_SALT` | salt de firma de sesión | `tokengate/config/runtime.exs:163` |
| `SESSION_ENCRYPTION_SALT` | salt de cifrado de sesión | `tokengate/config/runtime.exs:163` |

`WEBHOOK_SECRET` (`tokengate/config/runtime.exs:151`) es requerida **de
TokenGate**, no del estándar: es dominio (webhooks de observabilidad) y no se
porta al esqueleto.

## Comunes opcionales (default y dónde se lee)

| Var | Default | Qué ajusta | Dónde |
|---|---|---|---|
| `PORT` | `4000` | puerto de escucha (el proxy debe apuntar aquí) | `tokengate/config/runtime.exs:49` |
| `PHX_SCHEME` | `https` | esquema de las URLs generadas (`http` detrás de VPN) | `tokengate/config/runtime.exs:107` |
| `PHX_PORT` | `443` | puerto externo de las URLs generadas | `tokengate/config/runtime.exs:108` |
| `POOL_SIZE` | `10` | pool de conexiones | `tokengate/config/runtime.exs:82` |
| `ECTO_SSL` / `ECTO_SSL_VERIFY` | SSL sí, verificación no | TLS de la base | `tokengate/config/runtime.exs:66-86` |
| `ECTO_IPV6` | off | socket IPv6 contra la base | `tokengate/config/runtime.exs:59` |
| `CHECK_ORIGINS` | unset | origins permitidos para CSRF/WS (dual HTTPS+HTTP) | `tokengate/config/runtime.exs:123-147` |
| `SESSION_MAX_AGE_SECONDS` | `31536000` | vida de la cookie de sesión | `tokengate/lib/tokengate_web/endpoint.ex:28-29` |
| `SESSION_COOKIE_SECURE` | unset | fuerza/limpia el flag `Secure` | `tokengate/lib/tokengate_web/endpoint.ex:9-13` |
| `DNS_CLUSTER_QUERY` | unset | clustering Erlang distribuido | `tokengate/config/runtime.exs:110` |
| `DISABLE_FORCE_SSL` | build arg | apaga `force_ssl` (es **compile-time**, ver `SPEC-docker.md`) | `tokengate/config/prod.exs:14` |
| `SKIP_MIGRATIONS` | unset | el entrypoint no corre setup | `tokengate/docker/entrypoint.sh:23` |
| `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` / `_ALLOWED_DOMAINS` | unset | login con Google | `tokengate/config/runtime.exs:172-180` |

Plantilla lista para copiar (TokenGate **no** trae `.env.example`; Dran sí, y es
el mejor documento de la familia): `dran/.env.example`
(`:19` `PORT`, `:27` `PHX_HOST`, `:48` `SECRET_KEY_BASE`, `:53` `DATABASE_URL`,
`:57` `POOL_SIZE`, `:76-77` salts, `:123` `UPLOADS_DIR`,
`:137` `DRAN_INFERENCE_API_URL`).

## Variables propias de la app

El estándar no las fija; cada app declara las suyas en su `runtime.exs` con
default explícito. Patrón de referencia:

| App | Var | Para qué |
|---|---|---|
| Dran | `UPLOADS_DIR` | directorio de subidas — exige volumen persistente (`dran/.env.example:123`) |
| Dran | `DRAN_INFERENCE_API_URL` / `_API_KEY` | endpoint OpenAI-compatible (embeddings, chat, workers) (`dran/.env.example:137`) |
| Dran | `DRAN_RESET` | **destructivo**: borra el esquema en cada arranque mientras esté puesto (`dran/docker/entrypoint.sh:29-37`) |
| TokenGate | `TOKENGATE_ADMIN_PASSWORD` / `_EMAIL` | bootstrap del primer admin en el boot |
| TokenGate | `CIRCUIT_BREAKER_*`, `PROXY_RECEIVE_TIMEOUT_MS`, `ROUTING_SLOW_*` | comportamiento del proxy |

## Sesión y cookies (el bloque canónico)

Referencia: `tokengate/lib/tokengate_web/endpoint.ex:9-34`.

| Pieza | Valor canónico | Nota |
|---|---|---|
| `key` | `_<app>_key` | una cookie por app (`:18`) |
| `signing_salt` / `encryption_salt` | env, **dos distintos** | `:19-20`; en prod se exigen |
| `same_site` / `http_only` | `Lax` / `true` | `:21-22` |
| `renew: true` | sliding: la cookie se re-emite en cada request autenticado | `:27`; sin esto la vida es absoluta |
| `max_age` | `SESSION_MAX_AGE_SECONDS` (1 año) | `:28-29` |
| `secure` | según `SESSION_COOKIE_SECURE` | `:9-13` |
| `connect_info` del socket | `session` + `peer_data: true` + `user_agent: true` | `:32-34`; Dran hoy pasa sólo `session` (`dran/lib/dran_web/endpoint.ex:28-29`) |

**Pendiente en Dran** (diagnóstico, sin portar): comparte el **mismo** valor en
`signing_salt` y `encryption_salt` (`dran/lib/dran_web/endpoint.ex:19-20`), no
tiene `renew: true` (la cookie es de vida absoluta), y su `.env.example:83-84`
documenta 28800 s cuando el default real es 31536000
(`dran/lib/dran_web/endpoint.ex:24`).

## Settings en base de datos (no env)

Lo que se edita desde la UI **no** va a entorno. Dos patrones en la familia:

| Patrón | App | Implementación |
|---|---|---|
| Singleton con columnas | TokenGate | `tokengate/lib/tokengate/global_settings.ex:19-42` (`global_settings`, id 1, cap diario global) |
| Clave/valor + caché ETS | Dran | `dran/lib/dran/settings.ex:15-25` (defaults), `:45-56` (`get/1` cachea en ETS y cae a la tabla `settings`), `:70` (`put/2` con `on_conflict`) |

Regla: si el valor es un secreto editado desde la UI (p. ej. el token de
Telegram), se guarda **cifrado** en la base (`tokengate/lib/tokengate/notifications/secret_box.ex`),
no en claro y no en entorno.

## Checklist de instalación

1. `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, los dos salts: presentes y
   distintos entre sí.
2. `PORT` == puerto que el proxy expone; `PHX_SCHEME`/`PHX_PORT` == cómo se ve
   la app desde afuera.
3. Base de datos con SSL: dejá `ECTO_SSL_VERIFY` apagado salvo CA válida.
4. Si hay HTTP plano (VPN/LAN): build con `DISABLE_FORCE_SSL=1` **y**
   `PHX_SCHEME=http` en runtime.
5. Si la app se ve por dos orígenes: `CHECK_ORIGINS` con la lista completa
   (`scheme://host:port`, sin paths).
6. Para Dran: volumen persistente montado en `UPLOADS_DIR`.

## Anti-patrones

- Un default silencioso para una requerida (`System.get_env("SECRET_KEY_BASE", "algo")`).
- El mismo valor para `signing_salt` y `encryption_salt`.
- `secure: true` hardcodeado en la cookie: en HTTP el navegador la descarta y el
  login devuelve 403 sin log de controlador.
- Pedir en el boot una variable de dominio (el caso `WEBHOOK_SECRET`): una app
  nueva que herede eso no arranca.