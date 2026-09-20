#!/bin/sh
# Container entrypoint for {{App}}.
#
# Runs {{App}}.Release.setup/0 (create the database if missing → migrate →
# seed) before starting the Phoenix release. On a new database it creates the
# schema; on later deploys it skips what is already done and applies only
# pending migrations. A failed migration aborts the boot — the deploy is rolled
# back instead of serving code against an old schema.
#
# Variables:
#   SKIP_MIGRATIONS=1   skips the setup (one-off task containers).
#
# First run: if the app does not bootstrap an owner in its seed, the instance
# is left to whoever reaches the first-run screen first. Close that window with
# the app's variable (e.g. {{APP}}_ADMIN_PASSWORD in its
# priv/repo/seeds_prod.exs) or by deploying behind a network boundary.
set -e

if [ "$SKIP_MIGRATIONS" = "1" ]; then
  echo "[entrypoint] SKIP_MIGRATIONS=1, skipping setup."
else
  echo "[entrypoint] running setup (create DB → migrate → seed)..."
  bin/{{app}} eval "{{App}}.Release.setup"
fi

echo "[entrypoint] starting {{app}} release..."
exec bin/{{app}} start