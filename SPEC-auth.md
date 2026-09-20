# SPEC-auth.md — autenticación de una app (modos opcionales) + perfiles

## Alcance

Cómo entra la gente a una app **nacida de este boilerplate**. Hay **tres modos**
y la app elige — uno, o una combinación. Nada de esto se le aplica a Umbral: él
**es** el IdP, no un consumidor (su contrato de uso está en `SPEC-identity.md`).

## La regla de oro

**La app siempre tiene su propio perfil local y su propia sesión.** Los modos
cambian *cómo se prueba quién es la persona*, nunca dónde vive el perfil: la
identidad de la familia es el **email**, y un segundo directorio con una segunda
contraseña rompe todo (`umbral/docs/integration.md:107-119`).
La app **nunca** guarda contraseñas de un IdP.

| Modo | Cuándo | Qué agrega |
|---|---|---|
| **1 · Usuario y contraseña** | base de cualquier app; sin dependencias externas | tabla `users` con hash + rate limit + onboarding |
| **2 · Google (sin Umbral)** | la app quiere login social sin montar un IdP | `google_id`/`avatar_url` + OAuth propio |
| **3 · Umbral (SSO)** | una app más de la familia, gobernada por el IdP | `sub` como clave del perfil — ver `SPEC-identity.md` |

## Modo 1 — usuario y contraseña (canónico: TokenGate)

| Pieza | Referencia |
|---|---|
| Tabla `users`: `email`, `name`, `password_hash`, `status`, `timezone`, `locale`, `avatar_url` | `tokengate/lib/tokengate/accounts/user.ex:27-36` |
| Alta con hash bcrypt (`Bcrypt.hash_pwd_salt`) | `tokengate/lib/tokengate/accounts.ex:172`, `tokengate/lib/tokengate/accounts/user.ex:208-214` |
| Autenticación **timing-safe** (`Bcrypt.no_user_verify/0` si el email no existe) | `tokengate/lib/tokengate/accounts.ex:419-439` |
| Rate limit por IP del POST de login (10 intentos) | `tokengate/lib/tokengate_web/plugs/login_rate_limit.ex:22`, `:31`, `:52` |
| Controller de sesión: `renew: true`, auditoría, **error uniforme** | `tokengate/lib/tokengate_web/controllers/session_controller.ex:55-80` |
| Primera cuenta: `/onboarding` autodeshabilitante + `pg_advisory_xact_lock` | `tokengate/lib/tokengate_web/router.ex:85-86`, `tokengate/lib/tokengate/accounts.ex:241-250` |
| Rutas: `GET /login`, `DELETE /logout` | `tokengate/lib/tokengate_web/router.ex:71`, `:79` |
| Cambio de contraseña **exigiendo la actual** + auditoría | `tokengate/lib/tokengate_web/live/profile_modal.ex:51-69`, `tokengate/lib/tokengate/accounts/user.ex:228` |

**Reglas duras del modo:**

1. El error de login es **uniforme** (`Invalid credentials.`): distinguir
   "suspendido" de "no existe" convierte el form en un directorio de quién está
   registrado (`session_controller.ex:68-80`).
2. Toda verificación de contraseña pasa por bcrypt **con el camino timing-safe**
   cuando el email no existe.
3. La sesión se **renueva** al entrar (`configure_session(renew: true)`): un id de
   sesión nuevo evita la fijación.
4. El primer admin no viene de un seed: viene de `/onboarding`, que se apaga solo
   cuando ya hay una persona, y crea bajo un advisory lock para que dos submits
   en carrera no mienten dos admins.
5. Cambiar la contraseña exige la actual (re-autenticación), y el cambio se
   audita.

## Modo 2 — Google sin Umbral (canónico: TokenGate)

| Pieza | Referencia |
|---|---|
| Variables | `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` / `_ALLOWED_DOMAINS` / `_REDIRECT_URI` (`SPEC-config.md`) leídas en `tokengate/config/runtime.exs:172-180` |
| Cliente del proveedor: `authorize_url/1`, `exchange_code/1`, `configured?/0` | `tokengate/lib/tokengate_web/oauth/google.ex:6-7` |
| Rutas y controller (`:request`, `:callback`) | `tokengate/lib/tokengate_web/router.ex:95-96`, `tokengate/lib/tokengate_web/controllers/oauth_controller.ex:20`, `:39` |
| Vínculo con el perfil local | campos `google_id` y `avatar_url` (`tokengate/lib/tokengate/accounts/user.ex:35-36`) |

Reglas: **sin `client_id` no se muestra el botón** (se consulta `configured?/0`);
el auto-registro sólo para los dominios de `GOOGLE_OAUTH_ALLOWED_DOMAINS`; la
persona se vincula a su perfil **por email verificado** (no se crea un segundo
perfil); la app sigue emitiendo *su* sesión después del callback.

Dran implementa el mismo par — mismo contrato, otra copia:
`dran/lib/dran_web/controllers/oauth_controller.ex:13`, `:28` y
`dran/lib/dran_web/router.ex:444-445`.

## Modo 3 — Umbral (SSO opcional)

El contrato completo (env, SDK, wiring, ciclo de vida, registro de la app) está
en **`SPEC-identity.md`**. Lo esencial para elegirlo: se activa **sólo** con
`UMBRAL_CLIENT_ID`; la app conserva su perfil local y su sesión propia (no hay
cookie compartida) y el perfil se llavea por `sub`.

## Perfiles

Un perfil local existe en **los tres modos**. Contenido típico: `email`, `name`,
avatar (o iniciales), y preferencias como `locale` y `timezone`
(`tokengate/lib/tokengate/accounts/user.ex:27-36`).

**Una sola superficie por app** — elegí una y no dupliques:

| Patrón | Referencia | Cuándo |
|---|---|---|
| **Modal de cuenta** colgado del avatar, con cambio de contraseña | `tokengate/lib/tokengate_web/live/profile_modal.ex` (disparador en `tokengate/lib/tokengate_web/components/layouts.ex:482-486`) | apps con shell y muchas pantallas |
| **Sección dentro de ajustes** (`profile_changeset`, evento `save_profile`) | `dran/lib/dran_web/live/settings_live.ex:63`, `:323` | apps cuya configuración ya vive en Ajustes |

Reglas: los cambios de perfil se **auditan**; el email no se edita en la misma
superficie que el nombre si cambiar el email tiene su propio camino; el nombre es
la identidad visible (nunca el correo) y el rol **jamás** se edita desde el
perfil.

## Cómo se combinan

- **Contraseña + Google** (TokenGate hoy): los dos caminos coexisten; el botón
  aparece sólo si hay `client_id`, y el vínculo es por email verificado.
- **Local y después SSO** (Dran): la tabla local se conserva como *perfil*, no se
  reescribe — la sesión se establece tras el canje del código
  (`umbral/docs/integration.md:126-130`).
- **Sólo SSO**: la app no tiene tabla de credenciales; el perfil es mínimo y
  llaveado por `sub`.

## Checklist

- [ ] Modo elegido y anotado en el `## Custom — <App>` del `DESIGN.md` si cambia
      la pantalla de entrada.
- [ ] Perfil local con su tabla y su migración (`binary_id`, `utc_datetime_usec`).
- [ ] Modo 1: error uniforme, timing-safe, rate limit, `renew: true`, primera
      cuenta por onboarding.
- [ ] Modo 2: `configured?/0` gatea el botón; dominios permitidos; vínculo por
      email verificado.
- [ ] Modo 3: `SPEC-identity.md` completo (`state` de un solo uso, verificación
      de token, upsert por `sub`, logout local **y** del IdP).
- [ ] Una sola superficie de perfil, cambios auditados.

## Anti-patrones

- Un segundo directorio de identidad con una segunda contraseña.
- Guardar (o pedir) la contraseña del IdP.
- Mostrar el botón de Google cuando no hay `client_id`.
- Enumerar emails con el mensaje de error del login.
- Permitir cambiar la contraseña sin exigir la actual.
- Perfil duplicado: modal en el avatar **y** sección en Ajustes.