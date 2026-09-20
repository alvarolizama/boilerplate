# SPEC-auth.md — app authentication (optional modes) + profiles

## Scope

How people get into an app **born from this boilerplate**. There are **three
modes** and the app chooses — one, or a combination. None of this applies to
Umbral: it **is** the IdP, not a consumer (its consumer contract is in
`SPEC-identity.md`).

## The golden rule

**The app always has its own local profile and its own session.** The modes
change *how the person is proven to be who they are*, never where the profile
lives: the identity of the family is the **email**, and a second directory with
a second password breaks everything. The app **never** stores an IdP's
passwords.

| Mode | When | What it adds |
|---|---|---|
| **1 · Username and password** | the base of any app; no external dependency | a `users` table with a hash + rate limit + onboarding |
| **2 · Google (without Umbral)** | the app wants social sign-in without running an IdP | `google_id`/`avatar_url` + its own OAuth |
| **3 · Umbral (SSO)** | one more app of the family, governed by the IdP | `sub` as the profile key — see `SPEC-identity.md` |

## Mode 1 — username and password

| Piece | What must exist |
|---|---|
| `users` table | `email`, `name`, `password_hash`, `status`, `timezone`, `locale`, `avatar_url` |
| Sign-up with a bcrypt hash | `Bcrypt.hash_pwd_salt/1` |
| **Timing-safe** authentication | `Bcrypt.no_user_verify/0` on the path where the email does not exist |
| Per-IP rate limit on the login POST | a plug in front of the session controller (e.g. 10 attempts) |
| Session controller | `renew: true`, an audit entry, and a **uniform error** |
| First account | `/onboarding`, self-disabling once a person exists, creating under `pg_advisory_xact_lock` so two racing submits do not mint two admins |
| Routes | `GET /login`, `DELETE /logout` |
| Password change | requires the current password (re-authentication) and is audited |

**Hard rules of the mode:**

1. The login error is **uniform** (`Invalid credentials.`): telling "suspended"
   apart from "does not exist" turns the form into a directory of who is
   registered.
2. Every password check goes through bcrypt, **with the timing-safe path** when
   the email does not exist.
3. The session is **renewed** on sign-in (`configure_session(renew: true)`): a
   new session id prevents fixation.
4. The first admin does not come from a seed: it comes from `/onboarding`, which
   turns itself off once there is a person, and it creates under an advisory
   lock.
5. Changing the password requires the current one, and the change is audited.

## Mode 2 — Google without Umbral

| Piece | What must exist |
|---|---|
| Variables | `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` / `_ALLOWED_DOMAINS` / `_REDIRECT_URI` (`SPEC-config.md`), read in `config/runtime.exs` |
| Provider client | `authorize_url/1`, `exchange_code/1`, `configured?/0` |
| Routes and controller | a `:request` and a `:callback` action in the browser scope |
| Link to the local profile | `google_id` and `avatar_url` fields on the profile |

Rules: **with no `client_id` the button is not rendered** (ask
`configured?/0` first); self-registration only for the domains in
`GOOGLE_OAUTH_ALLOWED_DOMAINS`; the person is linked to their profile **by
verified email** (no second profile is created); the app still issues *its own*
session after the callback.

The same contract appears more than once in the family — same pair of actions,
another copy. When porting a change, port it to every copy.

## Mode 3 — Umbral (optional SSO)

The complete contract (env, SDK, wiring, token lifecycle, app registration) is
in **`SPEC-identity.md`**. The essentials for choosing it: it turns on **only**
with `UMBRAL_CLIENT_ID`; the app keeps its local profile and its own session
(there is no shared cookie) and the profile is keyed by `sub`.

## Profiles

A local profile exists in **all three modes**. Typical content: `email`, `name`,
an avatar (or initials), and preferences such as `locale` and `timezone`.

**One single surface per app** — pick one and do not duplicate:

| Pattern | When |
|---|---|
| **Account modal** hanging off the avatar, with the password change inside | apps with a shell and many screens |
| **A section inside settings** (`profile_changeset`, a `save_profile` event) | apps whose configuration already lives in Settings |

Rules: profile changes are **audited**; the email is not edited on the same
surface as the name if changing the email has its own path; the name is the
visible identity (never the email address) and the role is **never** editable
from the profile.

## How they combine

- **Password + Google**: both paths coexist; the button appears only when there
  is a `client_id`, and the link is by verified email.
- **Local and then SSO**: the local table is kept as *profile*, it is not
  rewritten — the session is established after the code exchange.
- **SSO only**: the app has no credentials table; the profile is minimal and
  keyed by `sub`.

## Checklist

- [ ] Mode chosen and noted in the `## Custom — <App>` section of `DESIGN.md` if
      it changes the entry screen.
- [ ] Local profile with its table and its migration (`binary_id`,
      `utc_datetime_usec`).
- [ ] Mode 1: uniform error, timing-safe, rate limit, `renew: true`, first
      account through onboarding.
- [ ] Mode 2: `configured?/0` gates the button; allowed domains; link by
      verified email.
- [ ] Mode 3: the whole `SPEC-identity.md` (single-use `state`, token
      verification, upsert by `sub`, logout locally **and** at the IdP).
- [ ] One single profile surface, changes audited.

## Anti-patterns

- A second identity directory with a second password.
- Storing (or asking for) the IdP's password.
- Rendering the Google button when there is no `client_id`.
- Enumerating emails through the login error message.
- Allowing a password change without the current password.
- A duplicated profile: modal in the avatar **and** a section in Settings.
