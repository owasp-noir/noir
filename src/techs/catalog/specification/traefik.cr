# NoirTechs catalog entry: traefik.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  TRAEFIK = {
    :traefik => {
      :format    => ["YAML", "TOML"],
      :similar   => ["traefik", "traefik dynamic config", "ingressroute"],
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
