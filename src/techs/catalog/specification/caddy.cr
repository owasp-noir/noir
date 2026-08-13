# NoirTechs catalog entry: caddy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  CADDY = {
    :caddy => {
      :format    => ["CADDYFILE", "JSON"],
      :similar   => ["caddy", "caddyfile", "caddy.json"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
