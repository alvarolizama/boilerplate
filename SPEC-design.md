# SPEC-design.md — cómo se aplica el Commons

## Alcance

`DESIGN.md` de este repo **es** el estándar: ~34 KB, secciones `## C1..C12` +
`## Apéndice A` (valores del tema `dim`) + `## Apéndice B` (verificación). Este
spec no repite sus reglas: dice **qué archivo implementa cada regla**, cómo se
verifica y cómo se propaga a una app.

Un agente que va a tocar UI lee, en este orden: `DESIGN.md` (la sección que
aplica), este spec (el mapa a archivos) y el código de referencia de TokenGate.

## Reglas duras

1. **El Commons es byte-exacto.** El `DESIGN.md` de cada app empieza con el
   Commons copiado tal cual, y recién después `## Custom — <App>`.
2. **Una sola versión viva.** El Commons se edita **aquí**; nunca en el repo de
   una app. Si un app necesita algo distinto, es un cambio del Commons.
3. **El doc refleja el código** (regla de oro): toda afirmación del Commons se
   puede señalar en `lib/<app>_web/…` o `assets/css/app.css`.
4. **El Custom declara excepciones, no gustos**, y cada bloque dice *por qué* no
   es compartible. No duplica tablas del Commons (paleta de `dim`, botones por
   contexto): se apunta a §C2.1 / Apéndice A.
5. **Un solo tema `dim --default`**, sin `@apply` en CSS, sin `table-zebra`.

## Mapa regla → archivo (referencia: TokenGate)

| Regla | Dónde se implementa |
|---|---|
| §C2 Tema y tokens | `tokengate/assets/css/app.css:19-20` (`@plugin "../vendor/daisyui" { themes: dim --default; }`) y `tokengate/lib/tokengate_web/components/layouts/root.html.heex:2` (`data-theme="dim"`) |
| §C2 Iconos | `tokengate/assets/css/app.css:14` (`@plugin "../vendor/heroicons"`) |
| §C2.1 Marca | `tokengate/lib/tokengate_web/components/layouts/root.html.heex:7` (`<.live_title>`), rutas estáticas en `tokengate/lib/tokengate_web.ex:20` (`static_paths`) |
| §C4 Primitivas | `tokengate/lib/tokengate_web/components/core_components.ex:56` (`flash`), `:102` (`button`), `:192` (`input`) |
| §C6 Tablas | `tokengate/lib/tokengate_web/components/core_components.ex:402` (`table`) |
| §C7.1 Modal simple | `tokengate/lib/tokengate_web/components/core_components.ex:745` (`modal`): overlay + card, cierre por ✕, Escape (`phx-window-keydown`) y click-away — **LiveView puro, sin `<dialog>`**, sin estado interno |
| §C12 Shell | `tokengate/lib/tokengate_web/components/layouts.ex:47` (`app/1`), `:131` (raíz `drawer lg:drawer-open`), `:238` (`drawer-side`), `:417` y `:475` (`user_footer`) |
| §C12.5 Reglas duras del shell | Los comentarios que explican la regla viven con el código: `tokengate/lib/tokengate_web/components/layouts.ex:120-135` |

Para los combinados de §C8 (buscadores y selects) la mecánica LiveView se
trabaja con el skill `liveview-ui-wiring`; el Commons fija la matriz de control y
las reglas duras (`DESIGN.md` §C8, §Reglas duras de los combobox).

## Verificación

El Apéndice B de `DESIGN.md` (`DESIGN.md:677-694`) trae los greps; adaptá los
caminos a tu repo. Los tres que más rompen:

```bash
grep -n 'data-theme' lib/<app>_web/components/layouts/root.html.heex   # el tema declarado (§C2)
grep -n 'themes:' assets/css/app.css                                   # un solo tema --default (§C2)
grep -rn 'table-zebra\|@apply' lib/ assets/css/                        # 0 (§C2, §C6)
```

## Propagación a una app

1. Partí el `DESIGN.md` de referencia en el heading `## Custom —` (el Commons
   llega hasta ahí) y pegá el bloque de arriba en el `DESIGN.md` de la app.
2. Corregí las frases que nombran apps **dentro** del Commons (paths de
   `root.html.heex`, qué tema corre cada app): se corrigen, no se anotan.
3. Escribí `## Custom — <App>` con lo exclusivo (shell propio, rol de los
   tokens, marca, pantallas que no existen en otra app).
4. Verificá que el Commons quedó idéntico: el `DESIGN.md` de la app debe
   empezar con el Commons tal cual.
5. Commits atómicos en español, separando UI de docs.

## Anti-patrones

- **Custom que contradice el Commons** (p. ej. prescribir un topbar cuando §C12
  exige sidebar + gaveta). Manda el Commons.
- **Duplicar la tabla de `dim`** en el Custom: crea dos versiones vivas.
- **Citar §Custom desde el Commons**: los números del Commons no cambian al
  copiarlo; las referencias son §C12, §C12.3, §S4…
- **Editar el Commons en el repo de la app**: el cambio se pierde en la próxima
  propagación.