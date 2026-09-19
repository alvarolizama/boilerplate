# design-system

El lenguaje visual de la familia de apps: un estándar de interfaz único que
vive en **[`DESIGN.md`](DESIGN.md)** — el **Commons** — más las reglas para
adoptarlo y mantenerlo.

## Contenido

- **`DESIGN.md`** — el estándar completo: tema y tokens, layout y responsive,
  elementos y botones por contexto, cards, tablas, modales, buscadores,
  gráficas, estados, convenciones y shell.

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
   primitivas en `CoreComponents` (§C4), el shell (§C12), etc.

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
| C12 | Shell: sidebar, navegación y menús |
| Apéndices | A: valores del tema `dim` · B: verificación |

## Autoría

Álvaro Lizama. Extraído del estándar en producción de las apps de la familia.
