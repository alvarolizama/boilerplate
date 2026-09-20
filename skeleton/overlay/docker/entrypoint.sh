#!/bin/sh
# Entrypoint del contenedor de {{App}}.
#
# Corre {{App}}.Release.setup/0 (crear la base si falta → migrar → seed) antes
# de arrancar el release de Phoenix. En una base nueva crea el esquema; en los
# deploys siguientes saltea la parte ya hecha y sólo aplica migraciones
# pendientes. Una migración fallida aborta el boot — el deploy se revierte en
# lugar de servir código contra un esquema viejo.
#
# Variables:
#   SKIP_MIGRATIONS=1   saltea el setup (contenedores de tareas puntuales).
#
# Primera ejecución: si la app no bootstrapea un dueño en el seed, la instancia
# queda para el primero que llegue a la pantalla de primera ejecución. Cerrá esa
# ventana con la variable de la app (p. ej. {{APP}}_ADMIN_PASSWORD en su
# priv/repo/seeds_prod.exs) o desplegando detrás de la frontera de red.
set -e

if [ "$SKIP_MIGRATIONS" = "1" ]; then
  echo "[entrypoint] SKIP_MIGRATIONS=1, skipping setup."
else
  echo "[entrypoint] running setup (create DB → migrate → seed)..."
  bin/{{app}} eval "{{App}}.Release.setup"
fi

echo "[entrypoint] starting {{app}} release..."
exec bin/{{app}} start