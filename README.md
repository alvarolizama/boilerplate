# boilerplate

El estándar de la familia de apps (Dran, TokenGate, Gorim, Umbral, Stiva,
Skema), en dos piezas:

- **`DESIGN.md`** — el **Commons**: el estándar de UI completo (tema y tokens,
  layout y responsive, elementos y botones por contexto, cards, tablas, modales,
  buscadores, gráficas, estados, convenciones y shell). Secciones `## C1..C12` +
  Apéndices A/B.
- **Los specs + `skeleton/`** — la capa portátil de una app Phoenix: env vars,
  Dockerfile, entrypoint, healthcheck, aliases de `mix` y el esqueleto listo
  para materializar.

Este repo es **spec-first**: se leen los documentos y recién después se toca
código. Cualquier agente que llegue a una app de la familia empieza por acá.

## Orden de lectura

| # | Archivo | Qué resuelve |
|---|---|---|
| 1 | `README.md` (este) | qué es el repo, la regla de TokenGate, el mapa |
| 2 | `SPEC-design.md` | cómo se aplica el Commons al código y cómo se verifica |
| 3 | `SPEC-config.md` | env vars, sesión/cookies, settings en base de datos |
| 4 | `SPEC-docker.md` | Dockerfile, entrypoint, healthcheck, puertos |
| 5 | `VERSIONS.md` | versiones pinneadas (toolchain, imágenes, deps) |
| 6 | `BOOTSTRAP.md` | cómo nace una app, paso a paso |
| 7 | `skeleton/` | la capa portátil ya materializada, con placeholders |

Los specs citan `archivo:línea` de la implementación de referencia, con caminos
relativos a `~/Workspace/Repos/alvarolizama/`, y se verifican mecánicamente:

```bash
python3 scripts/check-spec-refs.py     # 0 referencias rotas
```

## La regla: TokenGate es la referencia, no la plantilla

**TokenGate es la versión canónica y está congelado como referencia read-only.**
No se modifica para servir de plantilla: cuando el estándar cambia, se cambia
**acá** y se porta a las apps.

La razón es concreta: TokenGate arrastra dominio que un esqueleto no debe
heredar. Copiarlo entero deja una app nueva que **no arranca** (`WEBHOOK_SECRET`
es `raise` en su `runtime.exs`) y con tablas particionadas que no necesita.

| Capa | Qué contiene | A dónde va |
|---|---|---|
| **Portátil** | Dockerfile sin dominio, `docker/entrypoint.sh`, `config/*.exs`, bloque de sesión del endpoint, `release.ex`, `/health` DB-free, `.dockerignore`, `.env.example`, alias de `mix` | `skeleton/` → app nueva |
| **Dominio TokenGate** | proxy + gzip, `WEBHOOK_SECRET`, `request_logs` particionada, Telegram, budgets, catálogo de providers, crons Oban | se queda en TokenGate |
| **Dominio Dran** | pgvector, inference (`DRAN_INFERENCE_*`), workers, `UPLOADS_DIR` | se queda en Dran |

## Dos ciclos distintos — no confundirlos

| Ciclo | Qué cambia | Cómo se propaga |
|---|---|---|
| **Commons** (`DESIGN.md`) | el estándar de UI, que evoluciona seguido | se edita aquí y se copia **byte-exacto** al `DESIGN.md` de cada app (más `## Custom — <App>`); nunca se edita en el repo de la app |
| **Esqueleto** (`skeleton/`) | la capa portátil, que cambia poco | se usa **al nacer** una app (`BOOTSTRAP.md`); las apps vivas no se re-sincronizan solas |

## Mapa del repo

```text
boilerplate/
├── DESIGN.md          # el Commons (estándar de UI) — fuente
├── README.md          # este índice
├── SPEC-design.md     # Commons → archivos → verificación → propagación
├── SPEC-config.md     # env vars, sesión, settings en BD
├── SPEC-docker.md     # contenedor, entrypoint, healthcheck, puertos
├── VERSIONS.md        # versiones pinneadas
├── BOOTSTRAP.md       # nacer una app (procedimiento mecánico)
├── skeleton/          # capa portátil con placeholders <app>/<App>/<APP>
└── scripts/           # check-spec-refs.py — el gate de los specs
```

## Arrancar una app (resumen)

```bash
bash skeleton/bootstrap.sh ~/Workspace/Repos/alvarolizama/<app>
```

`bootstrap.sh` materializa el esqueleto, reemplaza los placeholders y deja la
app compilando. El detalle, las trampas y el orden están en `BOOTSTRAP.md`.

## Cómo usar `DESIGN.md`

### Adoptarlo en una app

1. **Copiá `DESIGN.md` tal cual** a la raíz del repo de tu app.
2. **Añadí al final** tu sección con lo exclusivo de esa app:

   ```md
   ## Custom — <App>
   ```

   Cada bloque de tu Custom dice **por qué** no es compartible (marca la
   diferencia real, no el gusto).
3. **Aplicá lo que dice el doc** en el código: el tema en `app.css` (§C2), las
   primitivas en `CoreComponents` (§C4), el shell (§C12), etc. — el mapa a
   archivos está en `SPEC-design.md`.

### Mantenerlo cuando cambia el Commons

- El Commons se edita **aquí** (un PR en este repo), nunca en el repo de una
  app.
- Al fusionar, el cambio se propaga **copiando el bloque** a los `DESIGN.md`
  de las apps: no puede haber dos versiones vivas del mismo Commons.
- Si cambias el Commons, cámbialo en **todos** los `DESIGN.md`.

### Criterio de reparto

Todo lo que se pueda compartir va al **Commons**; **Custom** es la excepción.
Si dudas, va a Commons — así la próxima app lo hereda gratis.

### Regla de oro

El doc **refleja el código**: todo lo que afirma se puede señalar en
`lib/<app>_web/…` o `assets/css/app.css`. Si el código cambia, el doc cambia
con él.

## El tema

Una sola línea en `app.css` + `data-theme` en `root.html.heex`. Hoy la familia
corre daisyUI **`dim --default`** — los valores de referencia están en el
Apéndice A del doc. Cambiar de tema no toca las vistas.

## Verificar una implementación

El **Apéndice B** de `DESIGN.md` trae los greps de verificación (adaptá los
caminos a tu repo: por ejemplo `grep -rn 'table-zebra' lib/` debe dar 0). En
apps Phoenix, el gate es **`mix precommit`**.

## Índice del estándar

| Sección | Qué cubre |
|---|---|
| C1–C2 | Principios · tema y tokens · marca (logo y favicon) |
| C3 | Layout base y responsive (mobile-first) |
| C4 | Elementos básicos · **botones por contexto** |
| C5–C7 | Cards · tablas · modales (simple y de dos columnas) |
| C8 | Buscadores y selects: matriz de control + reglas duras |
| C9–C11 | Gráficas · estados · convenciones |
| C12 | Shell: sidebar, navegación y menús · **reglas duras** (fila del drawer, scroll) |
| Apéndices | A: valores del tema `dim` · B: verificación |

## Autoría

Álvaro Lizama. El Commons está destilado del estándar en producción de las apps
de la familia; la capa portátil, de TokenGate.