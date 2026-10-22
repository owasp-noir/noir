# NoirTechs catalog entry: ocelot.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  OCELOT = {
    :ocelot => {
      :format    => ["JSON"],
      :similar   => ["ocelot", "ocelot.json", "ocelot api gateway"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
