import Config

# Cache manifest con las versiones digeridas de los estáticos (lo genera
# `mix assets.deploy`, que corre antes de arrancar el server).
config :{{app}}, {{App}}Web.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# force_ssl es COMPILE-TIME en Phoenix: se decide al compilar la imagen. Para
# desplegar por HTTP plano (VPN/LAN sin terminador TLS) construí con
# DISABLE_FORCE_SSL=1 y poné PHX_SCHEME=http en runtime.
# (El default del esqueleto es HTTPS; ver SPEC-docker.md §Reglas duras.)
if System.get_env("DISABLE_FORCE_SSL") != "1" do
  config :{{app}}, {{App}}Web.Endpoint,
    force_ssl: [
      rewrite_on: [:x_forwarded_proto],
      exclude: [hosts: ["localhost", "127.0.0.1"]]
    ]
end

# Cliente HTTP de Swoosh.
config :swoosh, api_client: Swoosh.ApiClient.Req

# Swoosh no guarda correos en memoria en prod.
config :swoosh, local: false

# Sin ruido de debug en producción.
config :logger, level: :info

# La configuración de runtime (variables de entorno) vive en
# config/runtime.exs.